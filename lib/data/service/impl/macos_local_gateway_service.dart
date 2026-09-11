import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:parrot_app/data/service/impl/macos_openclaw_environment.dart';
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
class MacOSLocalGatewayService implements LocalGatewayService {
  MacOSLocalGatewayService({Logger? logger})
    : _log = logger ?? Logger('MacOSLocalGatewayService');

  final Logger _log;

  // In isolated setup mode, do not accept a gateway that was started by
  // another environment. The flag becomes true only after this service
  // starts its own foreground process.
  bool _isolatedGatewayStarted = false;
  Process? _isolatedGatewayProcess;
  String? _isolatedGatewayToken;

  /// 隔离网关 `gateway run` 控制台输出的就绪/失败信号。
  ///
  /// 与 [_isolatedGatewayProcess] 一一对应：进程启动时创建、退出时置空。
  _IsolatedGatewayConsoleSignal? _isolatedGatewaySignal;

  /// OpenClaw 默认网关端口
  static const int defaultGatewayPort = 18789;

  /// 常用网关端口（用户可能自定义端口）
  static const List<int> commonGatewayPorts = [18789];

  /// 单端口探测超时
  static const Duration _probeTimeout = Duration(seconds: 4);

  /// 等待隔离网关自报就绪的最长时间。
  static const Duration _isolatedGatewayReadyTimeout = Duration(seconds: 30);

  /// 控制台的优先窗口：这段时间内没打印就绪行就先做端口兜底探测。
  static const Duration _isolatedGatewayConsoleGrace = Duration(seconds: 6);

  /// `openclaw gateway run` 就绪时在控制台输出的标志行。
  ///
  /// 依据 openclaw 启动收尾日志 `log.info("gateway ready")`
  /// （`dist/server-startup-post-attach-*.mjs` 与 `dist/server-start-*.mjs`
  /// 两条启动路径都会输出）。用子串匹配而不是整行匹配，
  /// 这样时间戳、日志级别前缀、ANSI 着色都不会影响判定。
  static final RegExp _gatewayReadyLine = RegExp(
    r'gateway ready',
    caseSensitive: false,
  );

  /// 启动失败标志，必须先于 [_gatewayReadyLine] 判断：
  /// `refusing to report the gateway ready` 同样包含 `gateway ready`。
  static final RegExp _gatewayStartupFailureLine = RegExp(
    r'refusing to report the gateway ready'
    r'|already listening on'
    r'|multiple gateway processes are listening'
    r'|EADDRINUSE',
    caseSensitive: false,
  );

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
            ? _isolatedGatewayToken
            : token;
    try {
      final config = OpenClawRuntimeConfig(
        url: 'ws://$host:$port',
        token: effectiveToken,
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
      // final isAuthChallenge =
      //     e is GatewayConnectAuthError ||
      //     e.toString().contains('gateway token missing') ||
      //     e.toString().contains('unauthorized');
      // _log.fine(
      //   'Gateway at $host:$port ${isAuthChallenge ? 'requires auth' : 'not reachable'}: $e',
      // );
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

  /// 查询本机 Gateway 服务状态，不要求 WebSocket 鉴权成功。
  @override
  Future<LocalGatewayServiceStatus> queryGatewayStatus() async {
    // final cliStatus = await _queryGatewayStatusFromCli();
    // if (cliStatus?.running == true) return cliStatus!;

    // LaunchAgent 未加载不等于 Gateway 没有进程。CLI 可能报告 stopped，
    // 但已有手动启动的 openclaw-gateway 正在监听端口，此时应以端口为准。
    for (final port in commonGatewayPorts) {
      if (await _isTcpPortOpen(port)) {
        return LocalGatewayServiceStatus(
          state: LocalGatewayProcessState.running,
          port: port,
          address: '127.0.0.1:$port',
        );
      }
    }
    return const LocalGatewayServiceStatus(
      state: LocalGatewayProcessState.stopped,
    );
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
        ['gateway', 'restart'],
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

  /// 停止本机 OpenClaw gateway service。
  @override
  Future<int> stopGateway({void Function(String line)? onOutput}) async {
    try {
      onOutput?.call('正在关闭 OpenClaw 网关...');
      if (MacOSOpenClawEnvironment.useIsolatedOpenClawSetupEnv &&
          _isolatedGatewayProcess != null) {
        _isolatedGatewayProcess!.kill(ProcessSignal.sigterm);
        _isolatedGatewayProcess = null;
        _isolatedGatewayStarted = false;
        _isolatedGatewayToken = null;
        _isolatedGatewaySignal = null;
        onOutput?.call('隔离 OpenClaw 网关已关闭');
        return 0;
      }

      final process = await Process.start(
        'openclaw',
        ['gateway', 'stop'],
        environment: MacOSOpenClawEnvironment.openClawProcessEnvironment,
        runInShell: true,
      );
      _listenProcessOutput(process, onOutput);
      final exitCode = await process.exitCode;
      _log.info('gateway stop finished, exitCode=$exitCode');
      return exitCode;
    } catch (e) {
      _log.warning('stopGateway error: $e');
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

    final token = await MacOSOpenClawEnvironment.ensureIsolatedGatewayToken();
    _isolatedGatewayToken = token;
    final signal = _IsolatedGatewayConsoleSignal();
    _isolatedGatewaySignal = signal;

    final process = await Process.start(
      'openclaw',
      [
        'gateway',
        'run',
        '--bind',
        'lan',
        '--port',
        '$defaultGatewayPort',
        '--auth',
        'token',
        '--token',
        token,
      ],
      environment: MacOSOpenClawEnvironment.openClawProcessEnvironment,
      runInShell: true,
    );
    _isolatedGatewayProcess = process;
    _isolatedGatewayStarted = true;
    _listenProcessOutput(
      process,
      onOutput,
      onLine: (line) => _handleIsolatedGatewayLine(signal, line),
    );
    process.exitCode.then((exitCode) {
      if (identical(_isolatedGatewayProcess, process)) {
        _isolatedGatewayProcess = null;
        _isolatedGatewayStarted = false;
        _isolatedGatewayToken = null;
        _isolatedGatewaySignal = null;
      }
      // 进程提前退出时唤醒等待方，否则只能白等到超时。
      signal.failed('进程已退出，exitCode=$exitCode');
      _log.info('isolated gateway process exited: $exitCode');
    });
    return _waitForIsolatedGateway(onOutput: onOutput);
  }

  /// 把 `gateway run` 的控制台输出翻译成就绪/失败信号。
  ///
  /// 就绪判定只依赖 gateway 自己打印的 `gateway ready`，
  /// 不再用 WebSocket 握手轮询：握手探测每次都要建连接 + 走鉴权，
  /// 在启动窗口期既昂贵又只会得到无意义的失败结果。
  void _handleIsolatedGatewayLine(
    _IsolatedGatewayConsoleSignal signal,
    String line,
  ) {
    if (signal.isCompleted) return;
    if (_gatewayStartupFailureLine.hasMatch(line)) {
      signal.failed(line.trim());
      return;
    }
    if (_gatewayReadyLine.hasMatch(line)) {
      signal.ready();
    }
  }

  Future<int> _waitForIsolatedGateway({
    void Function(String line)? onOutput,
  }) async {
    if (_isolatedGatewayProcess == null) return 1;

    final signal = _isolatedGatewaySignal ??= _IsolatedGatewayConsoleSignal();

    // 判定顺序：控制台优先窗口 → 端口探测兜底 → 剩余时间继续等控制台 → 再兜底一次。
    // 兜底只做两次最便宜的 TCP 探测（不握手、不轮询），
    // 目的是"那一行 gateway ready 没打印出来"时不要白等到总超时。
    final early = await _awaitIsolatedGatewaySignal(
      signal,
      _isolatedGatewayConsoleGrace,
    );
    if (early != null) return _reportIsolatedGatewayOutcome(early, onOutput);

    final probe = await _confirmIsolatedGatewayPort(onOutput);
    if (probe != null) return probe;

    final late = await _awaitIsolatedGatewaySignal(
      signal,
      _isolatedGatewayReadyTimeout - _isolatedGatewayConsoleGrace,
    );
    if (late != null) return _reportIsolatedGatewayOutcome(late, onOutput);

    final finalProbe = await _confirmIsolatedGatewayPort(onOutput);
    if (finalProbe != null) return finalProbe;

    onOutput?.call('隔离 OpenClaw 网关启动超时');
    return 1;
  }

  Future<_IsolatedGatewayOutcome?> _awaitIsolatedGatewaySignal(
    _IsolatedGatewayConsoleSignal signal,
    Duration timeout,
  ) async {
    if (timeout <= Duration.zero) return null;
    try {
      return await signal.future.timeout(timeout);
    } on TimeoutException {
      return null;
    }
  }

  int _reportIsolatedGatewayOutcome(
    _IsolatedGatewayOutcome outcome,
    void Function(String line)? onOutput,
  ) {
    switch (outcome.status) {
      case _IsolatedGatewayStatus.ready:
        onOutput?.call('隔离 OpenClaw 网关已就绪');
        return 0;
      case _IsolatedGatewayStatus.failed:
        onOutput?.call('隔离 OpenClaw 网关启动失败：${outcome.reason}');
        return 1;
    }
  }

  /// 控制台没给出就绪信号时的兜底：确认端口已在监听即视为就绪。
  ///
  /// 只做一次 TCP 连接（毫秒级、无鉴权），不做 WebSocket 握手也不轮询。
  Future<int?> _confirmIsolatedGatewayPort(
    void Function(String line)? onOutput,
  ) async {
    final status = await queryGatewayStatus();
    if (!status.running) return null;
    onOutput?.call(
      '未捕获到 "gateway ready" 控制台输出，但端口 ${status.port} 已在监听，按已就绪处理',
    );
    return 0;
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

  /// 读取本机 OpenClaw gateway 凭据。
  ///
  /// 只读取字段，不输出实际凭据到日志。
  @override
  Future<LocalGatewayCredentials> readGatewayCredentials() async {
    if (MacOSOpenClawEnvironment.useIsolatedOpenClawSetupEnv &&
        _isolatedGatewayStarted) {
      return LocalGatewayCredentials(token: _isolatedGatewayToken);
    }

    final file = File(
      '${MacOSOpenClawEnvironment.homePath}/.openclaw/openclaw.json',
    );
    if (!await file.exists()) {
      if (MacOSOpenClawEnvironment.useIsolatedOpenClawSetupEnv &&
          _isolatedGatewayStarted) {
        return LocalGatewayCredentials(token: _isolatedGatewayToken);
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

/// 隔离网关等待结果。
enum _IsolatedGatewayStatus { ready, failed }

class _IsolatedGatewayOutcome {
  final _IsolatedGatewayStatus status;
  final String? reason;

  const _IsolatedGatewayOutcome.ready()
    : status = _IsolatedGatewayStatus.ready,
      reason = null;

  const _IsolatedGatewayOutcome.failed(this.reason)
    : status = _IsolatedGatewayStatus.failed;
}

/// 单向信号：就绪或失败，先到者生效，重复上报被忽略。
class _IsolatedGatewayConsoleSignal {
  final Completer<_IsolatedGatewayOutcome> _completer =
      Completer<_IsolatedGatewayOutcome>();

  Future<_IsolatedGatewayOutcome> get future => _completer.future;

  bool get isCompleted => _completer.isCompleted;

  void ready() {
    if (!_completer.isCompleted) {
      _completer.complete(const _IsolatedGatewayOutcome.ready());
    }
  }

  void failed(String reason) {
    if (!_completer.isCompleted) {
      _completer.complete(_IsolatedGatewayOutcome.failed(reason));
    }
  }
}
