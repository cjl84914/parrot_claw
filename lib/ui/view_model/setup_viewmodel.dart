import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/repository/local_gateway_repository.dart';
import 'package:parrot_app/data/service/openclaw_model_service.dart';
import 'package:parrot_app/util/result.dart';

/// 本地网关引导流程状态
enum LocalSetupPhase {
  /// 检测中
  detecting,

  /// 已检测：本机有 gateway 在线（可连接）
  ready,

  /// 已检测：装了 openclaw 但 gateway 没跑
  needsStart,

  /// 正在启动 gateway
  starting,

  /// 已检测：没装 openclaw（需安装）
  needsInstall,

  /// 安装中
  installing,

  /// 安装完成
  installed,

  /// 出错
  error,
}

/// [SetupViewModel.connectLocal] 的结果状态。
enum LocalConnectStatus {
  /// 本机服务器已加入列表并设为默认，可以进门了
  saved,

  /// 网关未在线，服务器没有加入列表（需要先启动/安装）
  gatewayOffline,

  /// 服务器已加入列表，但模型配置读取失败
  failed,
}

/// 保存本机服务器的结果。
///
/// 取代原来的可空记录：失败时 [errorMessage] 一定非空且可直接展示，
/// 调用方不必再靠 null 去猜是哪一步出的问题。
class LocalConnectResult {
  final LocalConnectStatus status;

  /// 加入/更新的本机服务器；[LocalConnectStatus.gatewayOffline] 时为 null。
  final ServerConfig? server;

  /// 是否已有可用模型；仅 [LocalConnectStatus.saved] 时有意义。
  final bool hasModel;

  /// 失败原因，可直接展示给用户。
  final String? errorMessage;

  const LocalConnectResult({
    required this.status,
    this.server,
    this.hasModel = false,
    this.errorMessage,
  });

  bool get isSaved => status == LocalConnectStatus.saved;

  /// 网关没在线：服务器没被加入列表，需要先启动。
  bool get needsGatewayStart => status == LocalConnectStatus.gatewayOffline;

  @override
  String toString() =>
      'LocalConnectResult(${status.name}'
      '${errorMessage == null ? '' : ', $errorMessage'})';
}

/// 本地 OpenClaw 引导 ViewModel
///
/// 管理"检测本机 → 连接/安装"引导流程的 UI 状态。
/// 遵循项目现有风格：ChangeNotifier + 状态字段 + async 方法。
class SetupViewModel extends ChangeNotifier {
  SetupViewModel({
    required LocalGatewayRepository repository,
    required OpenClawModelService modelService,
    Logger? logger,
  }) : _repository = repository,
       _modelService = modelService,
       _log = logger ?? Logger('LocalSetupViewModel');

  final LocalGatewayRepository _repository;
  final OpenClawModelService _modelService;
  final Logger _log;

  LocalSetupPhase _phase = LocalSetupPhase.detecting;
  LocalSetupPhase get phase => _phase;

  /// 检测到的端口
  int? _port;
  int? get port => _port;

  /// 安装/操作输出日志（供界面滚动显示）
  final List<String> _outputLogs = [];
  List<String> get outputLogs => List.unmodifiable(_outputLogs);

  /// 错误信息
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// OpenClaw 版本（安装后）
  String? _version;
  String? get version => _version;

  // 页面可能因路由重定向或依赖更新而重建；初始化检测只允许执行一次。
  Future<void>? _initFuture;

  /// 是否正在忙（检测/安装中）
  bool get isBusy =>
      _phase == LocalSetupPhase.detecting ||
      _phase == LocalSetupPhase.installing ||
      _phase == LocalSetupPhase.starting;

  /// 初始化：进入界面时自动触发检测。
  ///
  /// 允许多个页面实例同时调用，但同一轮初始化实际检测只执行一次。
  Future<void> init() async {
    final running = _initFuture;
    if (running != null) {
      await running;
      return;
    }

    final future = detect();
    _initFuture = future;
    try {
      await future;
    } finally {
      if (identical(_initFuture, future)) _initFuture = null;
    }
  }

  /// 检测本机 OpenClaw 状态
  Future<void> detect() async {
    _setPhase(LocalSetupPhase.detecting);
    _errorMessage = null;
    _outputLogs.clear();
    _addLog('正在检测本机 OpenClaw...');

    final result = await _repository.detectLocal();
    if (result is Error<LocalGatewayStatus>) {
      _errorMessage = result.error.toString();
      _setPhase(LocalSetupPhase.error);
      return;
    }

    final status = (result as Ok<LocalGatewayStatus>).value;
    _port = status.port;

    if (status.online) {
      _addLog('已检测到本机网关（端口 ${status.port}）');
      _setPhase(LocalSetupPhase.ready);
    } else if (status.installed) {
      _addLog('已安装 OpenClaw，但网关未运行');
      _setPhase(LocalSetupPhase.needsStart);
    } else {
      _addLog('未检测到 OpenClaw，需要安装');
      _setPhase(LocalSetupPhase.needsInstall);
    }
  }

  /// 保存本机服务器并设为默认，**不在这里建立连接**。
  ///
  /// 连接由首页（index）的连接流程负责；这里只做三件事：
  /// 写进服务器列表（`ensureLocalServerAdded` 内部会 setDefault）、
  /// 读一次本地模型配置决定下一步去哪、
  /// 把结果和原因返回给界面。
  ///
  /// 返回值永远非空：调用方用 [LocalConnectResult.isSaved] 判断成功，
  /// 用 [LocalConnectResult.errorMessage] 拿到可直接展示的失败原因。
  Future<LocalConnectResult> connectLocal() async {
    _errorMessage = null;

    final Result<ServerConfig?> addResult;
    try {
      addResult = await _repository.ensureLocalServerAdded();
    } catch (error) {
      _log.warning('connectLocal: ensureLocalServerAdded threw: $error');
      return _failed('添加本机服务器失败：$error');
    }

    if (addResult is Error<ServerConfig?>) {
      return _failed(addResult.error.toString());
    }

    final server = (addResult as Ok<ServerConfig?>).value;
    if (server == null) {
      // 仓库只在 gateway 未在线（或端口未知）时返回 null。
      _errorMessage = _describeGatewayOffline();
      _setPhase(LocalSetupPhase.needsStart);
      return LocalConnectResult(
        status: LocalConnectStatus.gatewayOffline,
        errorMessage: _errorMessage,
      );
    }

    _addLog('已添加本机网关: ${server.name} (${server.displayAddress})');

    final bool hasModel;
    try {
      final models = await _modelService.loadModels();
      hasModel = models.isNotEmpty;
      _addLog(
        hasModel ? '检测到已配置模型 ${models.length} 个' : '未检测到已配置模型，需要完成模型配置',
      );
    } catch (error) {
      _log.warning('connectLocal: loadModels failed: $error');
      return _failed('已保存本机网关，但读取模型配置失败：$error', server: server);
    }

    _setPhase(LocalSetupPhase.ready);
    return LocalConnectResult(
      status: LocalConnectStatus.saved,
      server: server,
      hasModel: hasModel,
    );
  }

  LocalConnectResult _failed(String message, {ServerConfig? server}) {
    _errorMessage = message;
    _setPhase(LocalSetupPhase.error);
    return LocalConnectResult(
      status: LocalConnectStatus.failed,
      server: server,
      errorMessage: message,
    );
  }

  /// 拼出"网关未在线"的具体原因，避免只给一句无从下手的提示。
  ///
  /// 三种情况要区分开：CLI 没装上 / 装上了但端口没探测到 / 探测到了却没在跑。
  String _describeGatewayOffline() {
    final status = _repository.lastStatus;
    if (status == null) return '本机网关未在线（尚无检测结果），请先启动网关再连接';

    final detail = status.installed
        ? '已安装 OpenClaw，端口探测结果：${status.port ?? '未发现在监听的网关端口'}'
        : '未检测到 OpenClaw CLI（openclaw --version 执行失败）';
    return '本机网关未在线：$detail';
  }

  /// 启动本机 gateway
  Future<bool> startGateway() async {
    _setPhase(LocalSetupPhase.starting);
    _errorMessage = null;
    // _addLog('正在启动 OpenClaw 网关...');

    final result = await _repository.startGateway(onOutput: _addLog);
    if (result is Error<LocalGatewayStatus>) {
      _errorMessage = result.error.toString();
      _setPhase(LocalSetupPhase.error);
      return false;
    }

    final status = (result as Ok<LocalGatewayStatus>).value;
    _port = status.port;
    if (status.online) {
      _addLog('OpenClaw 网关已启动（端口 ${status.port}）');
      _setPhase(LocalSetupPhase.ready);
      return true;
    }

    _errorMessage = '网关启动后仍无法连接，请稍后重试';
    _setPhase(LocalSetupPhase.error);
    return false;
  }

  /// 安装 OpenClaw
  Future<bool> install() async {
    _setPhase(LocalSetupPhase.installing);
    _errorMessage = null;
    _addLog('开始安装 OpenClaw...');

    final result = await _repository.installOpenClaw(onOutput: _addLog);
    if (result is Error<String>) {
      _errorMessage = result.error.toString();
      _setPhase(LocalSetupPhase.error);
      return false;
    }

    _version = (result as Ok<String>).value;
    _addLog('OpenClaw $_version 安装完成');
    _setPhase(LocalSetupPhase.installed);
    return true;
  }

  /// 安装完成后重新检测（进入连接阶段）
  Future<void> detectAfterInstall() async {
    await detect();
  }

  /// 清空错误，回到检测
  Future<void> retry() async {
    await detect();
  }

  // ── 内部 ──

  void _setPhase(LocalSetupPhase phase) {
    _phase = phase;
    notifyListeners();
  }

  void _addLog(String line) {
    _outputLogs.add(line);
    _log.fine('[local-setup] $line');
    notifyListeners();
  }
}
