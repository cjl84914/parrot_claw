import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:parrot_app/data/service/impl/windows_openclaw_environment.dart';
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
class WindowsLocalGatewayService implements LocalGatewayService {
  WindowsLocalGatewayService({Logger? logger})
    : _log = logger ?? Logger('WindowsLocalGatewayService');

  final Logger _log;

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
      final environment = WindowsOpenClawEnvironment.openClawProcessEnvironment;
      // Always verify the exact executable that will be used by the app.
      // Do not rely on a separate `where openclaw` result: npm may install the
      // command beside the bundled Node rather than in %APPDATA%\\npm.
      final executable = await _resolveOpenClaw(environment);
      if (executable == null) return false;
      final nodePathResult = await Process.run(
        'where.exe',
        ['node.exe'],
        environment: environment,
        runInShell: true,
      );
      final nodePath = _firstPathLine(nodePathResult.stdout);
      final result = await Process.run(
        'cmd.exe',
        ['/d', '/s', '/c', executable, '--version'],
        environment: environment,
        runInShell: true,
      );
      final stdout = (result.stdout as String).trim();
      final stderr = (result.stderr as String).trim();
      final installed = result.exitCode == 0 && stdout.isNotEmpty;
      _log.fine(
        'isOpenClawInstalled: $installed '
        'openclawPath=$executable nodePath=$nodePath '
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
    try {
      await GatewayConnection.shared
          .configure(url: 'ws://$host:$port', token: token, password: password)
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

  /// 查询 Windows 受管 Gateway 服务状态。
  ///
  /// 该方法不做 WebSocket 握手，因此不会因 token 错误把 running 判成 stopped。
  @override
  Future<LocalGatewayServiceStatus> queryGatewayStatus() async {
    final cliStatus = await _queryGatewayStatusFromCli();
    if (cliStatus?.running == true) return cliStatus!;

    // CLI 可能只反映 Windows 服务未加载；如果端口已有 Gateway 进程监听，
    // 仍然应该显示 Gateway running。
    for (final port in commonGatewayPorts) {
      if (await _isTcpPortOpen(port)) {
        return LocalGatewayServiceStatus(
          state: LocalGatewayProcessState.running,
          port: port,
          address: '127.0.0.1:$port',
        );
      }
    }
    return cliStatus ??
        const LocalGatewayServiceStatus(state: LocalGatewayProcessState.stopped);
  }

  Future<LocalGatewayServiceStatus?> _queryGatewayStatusFromCli() async {
    try {
      final executable = await _requireOpenClaw();
      final result = await Process.run(
        'cmd.exe',
        ['/d', '/s', '/c', executable, 'gateway', 'status', '--json'],
        environment: WindowsOpenClawEnvironment.openClawProcessEnvironment,
        runInShell: true,
      );
      if (result.exitCode != 0) return null;
      return _parseGatewayStatusJson(result.stdout as String);
    } catch (e) {
      _log.fine('gateway status CLI failed: $e');
      return null;
    }
  }

  LocalGatewayServiceStatus? _parseGatewayStatusJson(String output) {
    try {
      final decoded = jsonDecode(output);
      if (decoded is! Map) return null;
      final json = Map<String, dynamic>.from(decoded);
      final nested = json['service'] is Map
          ? Map<String, dynamic>.from(json['service'] as Map)
          : <String, dynamic>{};
      final rawState = (json['status'] ?? json['state'] ?? nested['status'] ?? nested['state'])
          ?.toString().toLowerCase();
      final running = json['running'] == true || nested['running'] == true ||
          rawState == 'running' || rawState == 'active' || rawState == 'online';
      final stopped = json['running'] == false || nested['running'] == false ||
          rawState == 'stopped' || rawState == 'inactive' || rawState == 'offline';
      if (!running && !stopped) return null;
      final port = _portFromStatus(json, nested);
      return LocalGatewayServiceStatus(
        state: running ? LocalGatewayProcessState.running : LocalGatewayProcessState.stopped,
        port: port,
        address: port == null ? null : '127.0.0.1:$port',
      );
    } catch (_) {
      return null;
    }
  }

  int? _portFromStatus(Map<String, dynamic> json, Map<String, dynamic> nested) {
    final raw = json['port'] ?? nested['port'] ?? json['address'] ?? nested['address'] ??
        json['url'] ?? nested['url'];
    if (raw is num) return raw.toInt();
    final match = RegExp(r':(\d{1,5})(?:[/\s]|$)').firstMatch(raw?.toString() ?? '');
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Future<bool> _isTcpPortOpen(int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect('127.0.0.1', port, timeout: const Duration(seconds: 1));
      return true;
    } catch (_) {
      return false;
    } finally {
      await socket?.close();
    }
  }

  /// 按策略探测本机 gateway 端口
  @override
  Future<int?> detectGatewayPort() async {
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
      await WindowsOpenClawEnvironment.ensureGatewayTokenForLan();
      final executable = await _requireOpenClaw();
      final environment = WindowsOpenClawEnvironment.openClawProcessEnvironment;

      // `gateway restart` only reports the missing service and exits 0 on a
      // fresh Windows installation. Install the managed task first, then
      // restart it so the caller can wait for the real WebSocket readiness.
      final installExitCode = await _runGatewayCommand(
        executable,
        const ['gateway', 'install'],
        environment: environment,
        onOutput: onOutput,
      );
      if (installExitCode != 0) {
        _log.warning(
          'gateway install failed, exitCode=$installExitCode',
        );
        return installExitCode;
      }

      final restartExitCode = await _runGatewayCommand(
        executable,
        const ['gateway', 'restart'],
        environment: environment,
        onOutput: onOutput,
      );
      _log.info('gateway start finished, exitCode=$restartExitCode');
      return restartExitCode;
    } catch (e) {
      _log.warning('startGateway error: $e');
      rethrow;
    }
  }

  Future<int> _runGatewayCommand(
    String executable,
    List<String> args, {
    required Map<String, String> environment,
    void Function(String line)? onOutput,
  }) async {
    final process = await Process.start(
      'cmd.exe',
      ['/d', '/s', '/c', executable, ...args],
      environment: environment,
      runInShell: true,
    );
    _listenProcessOutput(process, onOutput);
    return process.exitCode;
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

  /// 停止本机 OpenClaw gateway service。
  @override
  Future<int> stopGateway({void Function(String line)? onOutput}) async {
    try {
      onOutput?.call('正在关闭 OpenClaw 网关...');
      final executable = await _requireOpenClaw();
      final environment = WindowsOpenClawEnvironment.openClawProcessEnvironment;
      final exitCode = await _runGatewayCommand(
        executable,
        const ['gateway', 'stop'],
        environment: environment,
        onOutput: onOutput,
      );
      _log.info('gateway stop finished, exitCode=$exitCode');
      return exitCode;
    } catch (e) {
      _log.warning('stopGateway error: $e');
      rethrow;
    }
  }

  /// 读取本机 OpenClaw gateway 凭据。
  ///
  /// 只读取字段，不输出实际凭据到日志。
  @override
  Future<LocalGatewayCredentials> readGatewayCredentials() async {
    final file = File(WindowsOpenClawEnvironment.configFilePath);
    if (!await file.exists()) {
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
        'cmd.exe',
        [
          '/d',
          '/s',
          '/c',
          await _requireOpenClaw(),
          'config',
          'get',
          'gateway.auth.token',
        ],
        environment: WindowsOpenClawEnvironment.openClawProcessEnvironment,
        runInShell: true,
      );
      if (result.exitCode != 0) return null;
      return _nonEmptyString(result.stdout);
    } catch (e) {
      _log.warning('Read gateway token through CLI failed: $e');
      return null;
    }
  }

  Future<String?> _resolveOpenClaw(Map<String, String> environment) async {
    final candidates = <String>[
      WindowsOpenClawEnvironment.openClawExecutable,
      '${WindowsOpenClawEnvironment.nodeHomePath}\\openclaw.cmd',
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) return candidate;
    }

    final result = await Process.run(
      'where.exe',
      ['openclaw.cmd'],
      environment: environment,
      runInShell: true,
    );
    if (result.exitCode != 0) return null;
    final path = _firstPathLine(result.stdout);
    return path.isEmpty ? null : path;
  }

  Future<String> _requireOpenClaw() async {
    final executable = await _resolveOpenClaw(
      WindowsOpenClawEnvironment.openClawProcessEnvironment,
    );
    if (executable == null) {
      throw Exception('未找到可执行的 openclaw.cmd');
    }
    return executable;
  }

  String? _nonEmptyString(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _firstPathLine(dynamic value) {
    if (value is! String) return '';
    for (final line in value.split(RegExp(r'[\r\n]+'))) {
      final path = line.trim();
      if (path.isNotEmpty) return path;
    }
    return '';
  }
}
