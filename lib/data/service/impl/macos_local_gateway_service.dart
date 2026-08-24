import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:parrot_app/data/service/impl/macos_openclaw_environment.dart';
import 'package:parrot_app/data/service/gateway_connection.dart';
import 'package:parrot_app/data/service/local_gateway_service.dart';

/// 本机 OpenClaw 网关检测服务（无状态，纯本机操作）
///
/// 职责：
/// - 判断本机是否安装了 openclaw CLI
/// - 探测本机 gateway 端口是否在线（用验证过的 [GatewayConnection] 真实握手）
/// - 生成网关 token
///
/// 设计原则（与项目 MVVM 架构一致）：
/// - 无状态，不持有数据
/// - 不包含业务逻辑，只做本机操作
/// - 由 LocalGatewayRepository 消费
///
/// 探测复用 [GatewayConnection]（server_edit_screen 连接测试同款）：
/// 它做的是真正的 gateway 握手 + 认证，能确认端口确实是 OpenClaw 网关，
/// 而非任意 TCP 服务；且探测通过 = 后续连接必通。
class MacOSLocalGatewayService implements LocalGatewayService {
  MacOSLocalGatewayService({Logger? logger})
    : _log = logger ?? Logger('MacOSLocalGatewayService');

  final Logger _log;

  // In isolated setup mode, do not accept a gateway that was started by
  // another environment. The flag becomes true only after this service
  // starts its own foreground process.
  bool _isolatedGatewayStarted = false;
  Process? _isolatedGatewayProcess;

  /// OpenClaw 默认网关端口
  static const int defaultGatewayPort = 18789;

  /// 常用网关端口（用户可能自定义端口）
  static const List<int> commonGatewayPorts = [
    18789, // 默认
    // 18889, // 常见变体
    // 18788, // 变体
    // 8080, // 常见自定义
    // 3000, // 常见开发端口
  ];

  /// 单端口探测超时
  static const Duration _probeTimeout = Duration(seconds: 4);

  /// 判断本机是否安装了 openclaw CLI
  ///
  /// 通过 `openclaw --version` 验证命令可执行。
  @override
  Future<bool> isOpenClawInstalled() async {
    try {
      final pathResult = await Process.run(
        'command',
        ['-v', 'openclaw'],
        environment: MacOSOpenClawEnvironment.openClawProcessEnvironment,
        runInShell: true,
      );
      final path = (pathResult.stdout as String).trim();
      final nodePathResult = await Process.run(
        'command',
        ['-v', 'node'],
        environment: MacOSOpenClawEnvironment.openClawProcessEnvironment,
        runInShell: true,
      );
      final nodePath = (nodePathResult.stdout as String).trim();
      final result = await Process.run(
        'openclaw',
        ['--version'],
        environment: MacOSOpenClawEnvironment.openClawProcessEnvironment,
        runInShell: true,
      );
      final stdout = (result.stdout as String).trim();
      final stderr = (result.stderr as String).trim();
      final installed = result.exitCode == 0 && stdout.isNotEmpty;
      _log.fine(
        'isOpenClawInstalled: $installed '
        'openclawPath=$path nodePath=$nodePath '
        'exitCode=${result.exitCode} stdout=$stdout stderr=$stderr',
      );
      return installed;
    } catch (e) {
      _log.warning('isOpenClawInstalled error: $e');
      return false;
    }
  }

  /// 探测指定端口是否为本机 OpenClaw gateway
  ///
  /// 用 [GatewayConnection] 做真实握手（与 server_edit 连接测试同款）：
  /// - 能握手 + status() ok → 该端口确实是 OpenClaw gateway
  /// - 失败/超时 → 不是 gateway 或没在跑
  ///
  /// [token]/[password] 可选：传入则同时验证认证是否有效。
  @override
  Future<bool> isGatewayAt(
    int port, {
    String host = '127.0.0.1',
    String? token,
    String? password,
  }) async {
    final effectiveToken =
        MacOSOpenClawEnvironment.useIsolatedOpenClawSetupEnv &&
                _isolatedGatewayStarted
            ? MacOSOpenClawEnvironment.isolatedGatewayToken
            : token;
    try {
      await GatewayConnection.shared
          .configure(
            url: 'ws://$host:$port',
            token: effectiveToken,
            password: password,
          )
          .timeout(_probeTimeout);

      final result = await GatewayConnection.shared.status().timeout(
        _probeTimeout,
      );

      await _shutdownProbeConnection();

      final ok = result.ok;
      _log.fine('Gateway at $host:$port: ${ok ? 'online' : 'unreachable'}');
      return ok;
    } catch (e) {
      final isAuthChallenge =
          e is GatewayConnectAuthError ||
          e.toString().contains('gateway token missing') ||
          e.toString().contains('unauthorized');
      _log.fine(
        'Gateway at $host:$port ${isAuthChallenge ? 'requires auth' : 'not reachable'}: $e',
      );
      await _shutdownProbeConnection();
      return isAuthChallenge;
    }
  }

  Future<void> _shutdownProbeConnection() async {
    try {
      await GatewayConnection.shared.shutdown();
    } catch (e) {
      _log.fine('Gateway probe shutdown ignored: $e');
    }
  }

  /// 按策略探测本机 gateway 端口
  @override
  Future<int?> detectGatewayPort() async {
    if (MacOSOpenClawEnvironment.useIsolatedOpenClawSetupEnv &&
        !_isolatedGatewayStarted) {
      _log.info(
        'Isolated setup: ignoring gateways started outside this setup flow',
      );
      return null;
    }

    if (await isGatewayAt(defaultGatewayPort)) {
      _log.info('Gateway detected on default port: $defaultGatewayPort');
      return defaultGatewayPort;
    }

    for (final port in commonGatewayPorts) {
      if (port == defaultGatewayPort) continue;
      if (await isGatewayAt(port)) {
        _log.info('Gateway detected on port: $port');
        return port;
      }
    }

    _log.info('No gateway detected on common ports');
    return null;
  }

  /// 启动本机 OpenClaw gateway service
  ///
  /// 普通模式使用系统服务；隔离测试模式使用当前环境的前台进程，
  /// 避免误用真实用户的 LaunchAgent。
  @override
  Future<int> startGateway({void Function(String line)? onOutput}) async {
    try {
      onOutput?.call('正在启动 OpenClaw 网关...');
      if (MacOSOpenClawEnvironment.useIsolatedOpenClawSetupEnv) {
        return await _startIsolatedGateway(onOutput: onOutput);
      }

      final process = await Process.start(
        'openclaw',
        ['gateway', 'start'],
        environment: MacOSOpenClawEnvironment.openClawProcessEnvironment,
        runInShell: true,
      );

      _listenProcessOutput(process, onOutput);
      final exitCode = await process.exitCode;
      _log.info('gateway start finished, exitCode=$exitCode');
      return exitCode;
    } catch (e) {
      _log.warning('startGateway error: $e');
      rethrow;
    }
  }

  Future<int> _startIsolatedGateway({
    void Function(String line)? onOutput,
  }) async {
    if (_isolatedGatewayProcess != null) {
      onOutput?.call('隔离 OpenClaw 网关进程已存在');
      return _waitForIsolatedGateway(onOutput: onOutput);
    }

    final process = await Process.start(
      'openclaw',
      [
        'gateway',
        'run',
        '--dev',
        '--port',
        '$defaultGatewayPort',
        '--auth',
        'token',
        '--token',
        MacOSOpenClawEnvironment.isolatedGatewayToken,
      ],
      environment: MacOSOpenClawEnvironment.openClawProcessEnvironment,
      runInShell: true,
    );
    _isolatedGatewayProcess = process;
    _isolatedGatewayStarted = true;
    _listenProcessOutput(process, onOutput);
    process.exitCode.then((exitCode) {
      if (identical(_isolatedGatewayProcess, process)) {
        _isolatedGatewayProcess = null;
        _isolatedGatewayStarted = false;
      }
      _log.info('isolated gateway process exited: $exitCode');
    });
    return _waitForIsolatedGateway(onOutput: onOutput);
  }

  Future<int> _waitForIsolatedGateway({
    void Function(String line)? onOutput,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (_isolatedGatewayProcess == null) return 1;
      if (await isGatewayAt(
        defaultGatewayPort,
        token: MacOSOpenClawEnvironment.isolatedGatewayToken,
      )) {
        onOutput?.call('隔离 OpenClaw 网关已完成鉴权并就绪');
        return 0;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    onOutput?.call('隔离 OpenClaw 网关启动超时');
    return 1;
  }

  void _listenProcessOutput(
    Process process,
    void Function(String line)? onOutput,
  ) {
    process.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
          _log.fine('[gateway:start] $line');
          onOutput?.call(line);
        });
    process.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
          _log.fine('[gateway:start:err] $line');
          onOutput?.call(line);
        });
  }

  /// 读取本机 OpenClaw gateway 凭据。
  ///
  /// 只读取字段，不输出实际凭据到日志。
  @override
  Future<LocalGatewayCredentials> readGatewayCredentials() async {
    if (MacOSOpenClawEnvironment.useIsolatedOpenClawSetupEnv &&
        _isolatedGatewayStarted) {
      return const LocalGatewayCredentials(
        token: MacOSOpenClawEnvironment.isolatedGatewayToken,
      );
    }

    final file = File(
      '${MacOSOpenClawEnvironment.homePath}/.openclaw/openclaw.json',
    );
    if (!await file.exists()) {
      if (MacOSOpenClawEnvironment.useIsolatedOpenClawSetupEnv &&
          _isolatedGatewayStarted) {
        return const LocalGatewayCredentials(
          token: MacOSOpenClawEnvironment.isolatedGatewayToken,
        );
      }
      final token = await _readGatewayTokenFromCli();
      if (token != null) {
        _log.info('Read gateway token through OpenClaw CLI');
        return LocalGatewayCredentials(token: token);
      }
      throw Exception('未找到 OpenClaw 配置文件，且无法读取 gateway token: ${file.path}');
    }

    final raw = await file.readAsString();
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) {
      throw Exception('OpenClaw 配置文件格式不正确');
    }

    final gateway = json['gateway'];
    final gatewayMap = gateway is Map<String, dynamic> ? gateway : null;
    final auth = gatewayMap?['auth'];
    final authMap = auth is Map<String, dynamic> ? auth : null;

    final token = _nonEmptyString(authMap?['token'] ?? gatewayMap?['token']);
    final password = _nonEmptyString(
      authMap?['password'] ?? gatewayMap?['password'],
    );

    final credentials = LocalGatewayCredentials(
      token: token,
      password: password,
    );
    if (!credentials.hasAny) {
      throw Exception('OpenClaw 配置中未找到 gateway token/password');
    }

    _log.info(
      'Read gateway credentials: mode=${credentials.authMode} '
      'tokenLength=${token?.length ?? 0} passwordLength=${password?.length ?? 0}',
    );
    return credentials;
  }

  Future<String?> _readGatewayTokenFromCli() async {
    try {
      final result = await Process.run(
        'openclaw',
        ['config', 'get', 'gateway.auth.token'],
        environment: MacOSOpenClawEnvironment.openClawProcessEnvironment,
        runInShell: true,
      );
      if (result.exitCode != 0) return null;
      return _nonEmptyString(result.stdout);
    } catch (e) {
      _log.warning('Read gateway token through CLI failed: $e');
      return null;
    }
  }

  String? _nonEmptyString(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
