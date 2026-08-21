import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/repository/local_gateway_repository.dart';
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

/// 本地 OpenClaw 引导 ViewModel
///
/// 管理"检测本机 → 连接/安装"引导流程的 UI 状态。
/// 遵循项目现有风格：ChangeNotifier + 状态字段 + async 方法。
class SetupViewModel extends ChangeNotifier {
  SetupViewModel({required LocalGatewayRepository repository, Logger? logger})
    : _repository = repository,
      _log = logger ?? Logger('LocalSetupViewModel');

  final LocalGatewayRepository _repository;
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

  /// 是否正在忙（检测/安装中）
  bool get isBusy =>
      _phase == LocalSetupPhase.detecting ||
      _phase == LocalSetupPhase.installing ||
      _phase == LocalSetupPhase.starting;

  /// 初始化：进入界面时自动触发检测
  Future<void> init() async {
    await detect();
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

  /// 把本地服务器加入列表并选中
  ///
  /// 返回添加的服务器；失败返回 null。
  Future<ServerConfig?> connectLocal() async {
    _errorMessage = null;
    final result = await _repository.ensureLocalServerAdded();
    if (result is Error<ServerConfig?>) {
      _errorMessage = result.error.toString();
      _setPhase(LocalSetupPhase.error);
      return null;
    }
    final server = (result as Ok<ServerConfig?>).value;
    if (server != null) {
      _addLog('已添加本机服务器: ${server.name} (${server.displayAddress})');
    }
    return server;
  }

  /// 启动本机 gateway
  Future<bool> startGateway() async {
    _setPhase(LocalSetupPhase.starting);
    _errorMessage = null;
    _addLog('正在启动 OpenClaw 网关...');

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
