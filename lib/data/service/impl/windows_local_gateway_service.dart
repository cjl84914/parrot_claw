import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:parrot_app/data/service/impl/windows_openclaw_environment.dart';
import 'package:parrot_app/data/service/gateway_connection.dart';
import 'package:parrot_app/data/service/local_gateway_service.dart';
import 'package:parrot_app/data/service/openclaw_runtime.dart';

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

  /// `openclaw gateway run` 在前台跑到就绪时会打印的标志行。
  ///
  /// 与 macOS 侧同一份判定：openclaw 启动收尾日志 `log.info("gateway ready")`。
  /// Windows 正常流程由托管服务负责，这一行通常不会出现在 CLI 输出里；
  /// 保留它是为了 `gateway run` 前台模式（以及日志格式变化）时行为一致。
  static final RegExp _gatewayReadyLine = RegExp(
    r'gateway ready',
    caseSensitive: false,
  );

  /// 启动失败标志，必须先于 [_gatewayReadyLine] 判断：
  /// `refusing to report the gateway ready` 同样包含 `gateway ready`。
  ///
  /// 后几条是 Windows 上 `gateway restart` 失败时 CLI 的真实输出
  /// （见 openclaw dist 的 lifecycle / schtasks 模块），命中就能给出确定原因，
  /// 而不是只把一个 exit code 抛给调用方。
  static final RegExp _gatewayStartupFailureLine = RegExp(
    r'refusing to report the gateway ready'
    r'|Gateway restart timed out after'
    r'|No verified gateway process is listening'
    r'|multiple gateway processes are listening'
    r'|is not a verified gateway process'
    r'|already listening on'
    r'|EADDRINUSE',
    caseSensitive: false,
  );

  /// 最近一次 CLI 调用中识别到的失败原因（只由启动流程消费）。
  String? _lastCliFailure;

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
      final config = OpenClawRuntimeConfig(
        url: 'ws://$host:$port',
        token: token,
        password: password,
      );
      // 探测必须用独立的 runtime 实例，绝不能碰 OpenClawRuntime.instance，
      // 否则会把 App 正在用的共享会话一起关掉（并停掉它的自动重连）。
      final probe = OpenClawRuntime();
      _probeRuntime = probe;
      final result = await probe.configureResult(config);
      await _shutdownProbeConnection();
      final ok = result.ok;
      _log.fine('Gateway at $host:$port: ${ok ? 'online' : 'unreachable'}');
      return ok;
    } catch (e) {
      await _shutdownProbeConnection();
      return false;
    }
  }

  OpenClawRuntime? _probeRuntime;

  Future<void> _shutdownProbeConnection() async {
    final probe = _probeRuntime;
    _probeRuntime = null;
    if (probe == null) return;
    try {
      await probe.dispose();
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
        const LocalGatewayServiceStatus(
          state: LocalGatewayProcessState.stopped,
        );
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
      final nested =
          json['service'] is Map
              ? Map<String, dynamic>.from(json['service'] as Map)
              : <String, dynamic>{};
      final rawState =
          (json['status'] ??
                  json['state'] ??
                  nested['status'] ??
                  nested['state'])
              ?.toString()
              .toLowerCase();
      final running =
          json['running'] == true ||
          nested['running'] == true ||
          rawState == 'running' ||
          rawState == 'active' ||
          rawState == 'online';
      final stopped =
          json['running'] == false ||
          nested['running'] == false ||
          rawState == 'stopped' ||
          rawState == 'inactive' ||
          rawState == 'offline';
      if (!running && !stopped) return null;
      final port = _portFromStatus(json, nested);
      return LocalGatewayServiceStatus(
        state:
            running
                ? LocalGatewayProcessState.running
                : LocalGatewayProcessState.stopped,
        port: port,
        address: port == null ? null : '127.0.0.1:$port',
      );
    } catch (_) {
      return null;
    }
  }

  int? _portFromStatus(Map<String, dynamic> json, Map<String, dynamic> nested) {
    final raw =
        json['port'] ??
        nested['port'] ??
        json['address'] ??
        nested['address'] ??
        json['url'] ??
        nested['url'];
    if (raw is num) return raw.toInt();
    final match = RegExp(
      r':(\d{1,5})(?:[/\s]|$)',
    ).firstMatch(raw?.toString() ?? '');
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Future<bool> _isTcpPortOpen(int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: const Duration(seconds: 1),
      );
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
      _lastCliFailure = null;
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
        _log.warning('gateway install failed, exitCode=$installExitCode');
        _reportGatewayStartFailure(installExitCode, onOutput);
        return installExitCode;
      }

      final restartExitCode = await _runGatewayCommand(
        executable,
        const ['gateway', 'restart'],
        environment: environment,
        onOutput: onOutput,
      );
      _log.info('gateway start finished, exitCode=$restartExitCode');
      if (restartExitCode != 0) {
        _reportGatewayStartFailure(restartExitCode, onOutput);
      }
      return restartExitCode;
    } catch (e) {
      _log.warning('startGateway error: $e');
      rethrow;
    }
  }

  /// 把 CLI 控制台的行分类为就绪/失败信号，与 macOS 侧共用同一套判定。
  ///
  /// Windows 的就绪等待由 `gateway restart` 自己完成（CLI 会在退出前
  /// 校验网关监听健康度，失败时打印 `Gateway restart timed out after ...`），
  /// 所以这里不做等待，只负责把原因提取出来。
  void _classifyGatewayStartupLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    if (_gatewayStartupFailureLine.hasMatch(trimmed)) {
      _lastCliFailure ??= trimmed;
      return;
    }
    if (_gatewayReadyLine.hasMatch(trimmed)) {
      _log.info('gateway reported ready through console output');
    }
  }

  /// 启动失败时把 CLI 给出的具体原因补进 UI 日志。
  ///
  /// 否则调用方只拿到一个退出码，界面上只能显示"启动失败"而无从解释。
  void _reportGatewayStartFailure(
    int exitCode,
    void Function(String line)? onOutput,
  ) {
    final reason = _lastCliFailure;
    onOutput?.call(
      reason == null
          ? '网关启动失败（exit code $exitCode），CLI 输出中未识别到具体原因'
          : '网关启动失败：$reason',
    );
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
    _listenProcessOutput(
      process,
      onOutput,
      onLine: _classifyGatewayStartupLine,
    );
    return process.exitCode;
  }

  void _listenProcessOutput(
    Process process,
    void Function(String line)? onOutput, {
    void Function(String line)? onLine,
  }) {
    process.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
          _log.fine('[gateway:start] $line');
          onOutput?.call(line);
          onLine?.call(line);
        });
    process.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
          _log.fine('[gateway:start:err] $line');
          onOutput?.call(line);
          onLine?.call(line);
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
