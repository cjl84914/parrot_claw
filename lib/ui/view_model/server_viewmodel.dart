import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/repository/server_repository.dart';

class ServerViewModel extends ChangeNotifier {
  final Logger _log = Logger('ServerViewModel');
  final ServerRepository _serverRepository;

  ServerViewModel({
    required ServerRepository serverRepository,
  }) : _serverRepository = serverRepository {
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
}
