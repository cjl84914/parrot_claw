import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/repository/server_repository.dart';
import 'package:parrot_app/data/service/local_gateway_service.dart';
import 'package:parrot_app/data/service/openclaw_installer_service.dart';
import 'package:parrot_app/util/result.dart';

/// 本地网关检测结果
class LocalGatewayStatus {
  /// 本机是否安装了 openclaw CLI
  final bool installed;

  /// 本机 gateway 是否在线（探测到端口）
  final bool online;

  /// 命中的网关端口（online 时为非空）
  final int? port;

  const LocalGatewayStatus({
    required this.installed,
    required this.online,
    this.port,
  });

  bool get needsInstall => !installed;

  bool get needsStart => installed && !online;

  bool get ready => online;
}

/// 本地 OpenClaw 网关仓库（唯一数据源）
///
/// 职责：
/// - 检测本机 OpenClaw 状态（装没装、gateway 活没活、端口）
/// - 安装 OpenClaw（装 Node → npm 装 OpenClaw）
/// - 把本地服务器加入服务器列表（host+port 去重）
///
/// 架构（遵循 MVVM + 单向数据流）：
/// - 消费 [LocalGatewayService]（检测）/ [OpenClawInstallerService]（安装）
/// - 通过 [ServerRepository] 写入服务器列表（唯一改数据入口）
/// - 返回 [Result] 给 ViewModel
class LocalGatewayRepository extends ChangeNotifier {
  LocalGatewayRepository({
    required LocalGatewayService service,
    required OpenClawInstallerService installerService,
    required ServerRepository serverRepository,
    Logger? logger,
  }) : _service = service,
       _installerService = installerService,
       _serverRepository = serverRepository,
       _log = logger ?? Logger('LocalGatewayRepository');

  final LocalGatewayService _service;
  final OpenClawInstallerService _installerService;
  final ServerRepository _serverRepository;
  final Logger _log;

  /// 上次检测结果缓存
  LocalGatewayStatus? _lastStatus;

  LocalGatewayStatus? get lastStatus => _lastStatus;

  /// 检测本机 OpenClaw 状态
  ///
  /// 流程：
  /// 1. 是否安装 openclaw CLI
  /// 2. 探测 gateway 端口（默认 → 常用集合）
  Future<Result<LocalGatewayStatus>> detectLocal() async {
    try {
      final installed = await _service.isOpenClawInstalled();

      int? port;
      if (installed) {
        port = await _service.detectGatewayPort();
      }

      final status = LocalGatewayStatus(
        installed: installed,
        online: port != null,
        port: port,
      );
      _lastStatus = status;
      _log.info(
        'detectLocal: installed=$installed online=${status.online} port=$port',
      );
      notifyListeners();
      return Result.ok(status);
    } on Exception catch (e) {
      _log.warning('detectLocal failed: $e');
      return Result.error(e);
    }
  }

  /// 确保本地服务器已加入列表（去重）
  ///
  /// 仅在 gateway 在线时添加。按 host+port 去重，已存在则更新本机凭据。
  /// 添加或更新后设为默认服务器。
  ///
  /// 返回添加/更新的服务器；未在线返回 null。
  Future<Result<ServerConfig?>> ensureLocalServerAdded() async {
    try {
      // 先确保有最新状态
      var status = _lastStatus;
      if (status == null) {
        final result = await detectLocal();
        if (result is Error<LocalGatewayStatus>) {
          return Result.error(result.error);
        }
        status = (result as Ok<LocalGatewayStatus>).value;
      }

      if (!status.online || status.port == null) {
        _log.fine('ensureLocalServerAdded: gateway not online, skip');
        return const Result.ok(null);
      }

      const host = '127.0.0.1';
      final port = status.port!;

      final credentials = await _service.readGatewayCredentials();
      final token = credentials.hasToken ? credentials.token! : '';
      final password = credentials.hasPassword ? credentials.password! : '';
      final authMode = credentials.authMode;

      // host+port 去重；本机配置存在时更新凭据，避免旧 token 继续 mismatch。
      final existing = _serverRepository.servers.where(
        (s) => s.host == host && s.port == port,
      );
      if (existing.isNotEmpty) {
        final server = existing.first.copyWith(
          name: '本机服务器',
          token: token,
          password: password,
          authMode: authMode,
          useTLS: false,
        );
        await _serverRepository.updateServer(server.id, server);
        await _serverRepository.setDefault(server.id);
        _log.info(
          'ensureLocalServerAdded: updated local server credentials '
          '(host=$host port=$port mode=$authMode)',
        );
        return Result.ok(server);
      }

      final localServer = ServerConfig(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: '本机服务器',
        host: host,
        port: port,
        token: token,
        password: password,
        authMode: authMode,
        useTLS: false,
      );

      await _serverRepository.addServer(localServer);
      _log.info(
        'ensureLocalServerAdded: added local server on port $port mode=$authMode',
      );
      return Result.ok(localServer);
    } on Exception catch (e) {
      _log.warning('ensureLocalServerAdded failed: $e');
      return Result.error(e);
    }
  }

  /// 启动本机 gateway 服务
  ///
  /// 成功后自动重新检测状态。
  Future<Result<LocalGatewayStatus>> startGateway({
    void Function(String line)? onOutput,
  }) async {
    try {
      final exitCode = await _service.startGateway(onOutput: onOutput);
      if (exitCode != 0) {
        throw Exception('OpenClaw 网关启动失败（exit code $exitCode）');
      }

      // gateway start 返回时进程可能刚拉起，端口和握手还没 ready。
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      LocalGatewayStatus? lastStatus;
      while (DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(seconds: 1));
        final result = await detectLocal();
        if (result is Error<LocalGatewayStatus>) {
          return result;
        }
        lastStatus = (result as Ok<LocalGatewayStatus>).value;
        if (lastStatus.online) {
          return Result.ok(lastStatus);
        }
      }

      return Result.ok(
        lastStatus ?? const LocalGatewayStatus(installed: true, online: false),
      );
    } on Exception catch (e) {
      _log.warning('startGateway failed: $e');
      return Result.error(e);
    }
  }

  /// 安装 OpenClaw（装 Node → npm 装 OpenClaw → 验证）
  ///
  /// [onOutput] 安装进度回调（供 UI 显示）。
  /// 成功后自动重新检测状态。
  /// 返回安装后的 OpenClaw 版本；失败返回 Error。
  Future<Result<String>> installOpenClaw({
    void Function(String line)? onOutput,
  }) async {
    try {
      _log.info('installOpenClaw: starting');
      onOutput?.call('开始安装...');

      // 1. 确保 Node
      final nodeBin = await _installerService.ensureNode(onOutput: onOutput);

      // 2. npm 安装 OpenClaw
      final exitCode = await _installerService.installOpenClaw(
        nodeBin: nodeBin,
        onOutput: onOutput,
      );
      if (exitCode != 0) {
        throw Exception('OpenClaw 安装失败（exit code $exitCode）');
      }

      // 3. 验证
      final version = await _installerService.verifyInstall();
      if (version == null) {
        onOutput?.call(
          '安装命令已结束，但 openclaw --version 未能成功执行。请检查上方 npm 输出中的错误或 allow-scripts 提示。',
        );
        throw Exception('OpenClaw 安装后验证失败');
      }

      _log.info('installOpenClaw: success, version=$version');
      onOutput?.call('OpenClaw $version 安装成功！');

      // 4. 重新检测
      await detectLocal();
      return Result.ok(version);
    } on Exception catch (e) {
      _log.warning('installOpenClaw failed: $e');
      return Result.error(e);
    }
  }

  /// 刷新检测结果
  Future<Result<LocalGatewayStatus>> refresh() => detectLocal();
}
