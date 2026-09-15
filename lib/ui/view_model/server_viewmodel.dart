import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/repository/gateway_repository.dart';
import 'package:parrot_app/data/repository/server_repository.dart';
import 'package:parrot_app/data/service/gateway_session.dart';

class ServerViewModel extends ChangeNotifier {
  final Logger _log = Logger('ServerViewModel');
  final ServerRepository _serverRepository;
  final GatewayRepository _gatewayRepository;

  ServerViewModel({
    required ServerRepository serverRepository,
    required GatewayRepository gatewayRepository,
  }) : _serverRepository = serverRepository,
       _gatewayRepository = gatewayRepository {
    _serverRepository.addListener(_onRepositoryChanged);
  }

  @override
  void dispose() {
    _serverRepository.removeListener(_onRepositoryChanged);
    super.dispose();
  }

  void _onRepositoryChanged() {
    notifyListeners();
  }

  // Getters
  List<ServerConfig> get servers => _serverRepository.servers;

  ServerConfig? get selectedServer => _serverRepository.selectedServer;

  ServerConfig? get defaultServer => _serverRepository.defaultServer;

  // Actions
  void selectServer(ServerConfig? server) {
    _log.info('Selected server: ${server?.name ?? 'null'}');
    _serverRepository.selectServer(server);
    notifyListeners();
  }

  Future<void> addServer(ServerConfig config) async {
    _log.info('Adding server: ${config.name}');
    await _serverRepository.addServer(config);
  }

  Future<void> updateServer(String id, ServerConfig newConfig) async {
    _log.info('Updating server: $id');
    await _serverRepository.updateServer(id, newConfig);
  }

  Future<void> deleteServer(String id) async {
    _log.info('Deleting server: $id');
    await _serverRepository.deleteServer(id);
  }

  // Future<void> setDefault(String id) async {
  //   _log.info('Setting default server: $id');
  //   await _serverRepository.setDefault(id);
  // }

  Future<void> reorderServer(int oldIndex, int newIndex) async {
    _log.info('Reordering servers from $oldIndex to $newIndex');
    await _serverRepository.reorderServer(oldIndex, newIndex);
  }

  void refresh() {
    _log.info('Refreshing servers');
    _serverRepository.refresh();
  }

  String exportConfig() {
    _log.info('Exporting server config');
    return _serverRepository.exportConfig();
  }

  Future<void> importConfig(String jsonString) async {
    _log.info('Importing server config');
    await _serverRepository.importConfig(jsonString);
  }

  /// 试连一个（可能尚未保存的）网关配置。
  ///
  /// 走一次性的独立 runtime，不触碰当前共享会话：失败时当前连接、当前配置和
  /// 自动重连都不会被影响。只有返回 ok 才应该保存并切换过去。
  Future<GatewayOperationResult<HelloOk>> probeServer(
    ServerConfig config,
  ) async {
    return _gatewayRepository.probeServer(
      GatewayConnectConfig(
        url: config.wsUrl,
        token: config.isTokenAuth ? config.token : null,
        password: config.isPasswordAuth ? config.password : null,
      ),
    );
  }
}
