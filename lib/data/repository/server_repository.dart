import 'package:flutter/foundation.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/service/storage_service.dart';

/// 服务器列表仓库
class ServerRepository extends ChangeNotifier {
  final StorageService _storage;
  
  List<ServerConfig> _servers = [];
  List<ServerConfig> get servers => _servers;
  
  ServerConfig? _selectedServer;
  ServerConfig? get selectedServer => _selectedServer;

  ServerRepository(this._storage) {
    _loadServers();
  }

  /// 获取默认服务器
  ServerConfig? get defaultServer {
    try {
      return _servers.firstWhere((s) => s.isDefault);
    } catch (_) {
      return _servers.isNotEmpty ? _servers.first : null;
    }
  }

  /// 加载服务器列表
  void _loadServers() {
    _servers = _storage.getServers();
    _selectedServer = defaultServer;
    notifyListeners();
  }

  /// 选择当前服务器
  void selectServer(ServerConfig? server) async{
    _selectedServer = server;
    setDefault(server!.id);
    notifyListeners();
  }

  /// 添加服务器
  Future<void> addServer(ServerConfig config) async {
    // 如果这是第一个服务器，设为默认
    final isFirst = _servers.isEmpty;
    final server = isFirst ? config.copyWith(isDefault: true) : config;
    
    await _storage.saveServer(server);
    _servers = [..._servers, server];
    notifyListeners();
  }

  /// 更新服务器
  Future<void> updateServer(String id, ServerConfig newConfig) async {
    await _storage.saveServer(newConfig);
    _servers = _servers.map((s) => s.id == id ? newConfig : s).toList();
    notifyListeners();
  }

  /// 删除服务器
  Future<void> deleteServer(String id) async {
    await _storage.deleteServer(id);
    _servers = _servers.where((s) => s.id != id).toList();
    
    // 如果删的是默认服务器，重新设置默认
    final remaining = _servers.where((s) => s.isDefault).toList();
    if (remaining.isEmpty && _servers.isNotEmpty) {
      await setDefault(_servers.first.id);
    } else {
      notifyListeners();
    }
  }

  /// 设置默认服务器
  Future<void> setDefault(String id) async {
    await _storage.setDefaultServer(id);
    _loadServers(); // 重新加载并通知
  }

  /// 调整服务器顺序
  Future<void> reorderServer(int oldIndex, int newIndex) async {
    final list = [..._servers];
    if (newIndex > oldIndex) newIndex--;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    await _storage.reorderServers(list);
    _servers = list;
    notifyListeners();
  }

  /// 刷新列表
  void refresh() {
    _loadServers();
  }

  /// 导出配置
  String exportConfig() {
    return _storage.exportConfig();
  }

  /// 导入配置
  Future<void> importConfig(String jsonString) async {
    await _storage.importConfig(jsonString);
    _loadServers();
  }
}
