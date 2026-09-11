import 'dart:async';
import 'package:flutter/material.dart';
import 'package:parrot_app/data/model/message.dart';
import 'package:parrot_app/data/repository/gateway_repository.dart';
import 'package:parrot_app/data/service/openclaw_runtime.dart';

class SessionViewModel extends ChangeNotifier {
  /// 获取当前服务器的会话列表。
  List<GatewaySessionEntry> get sessions => _gatewayRepository.sessions;

  Stream<ChatMessage>? get messageEvents => _gatewayRepository.messageController.stream;

  String? get sessionKey => _gatewayRepository.sessionKey;

  bool get connected => _gatewayRepository.connected;

  bool get isReconnecting => _gatewayRepository.isReconnecting;

  final GatewayRepository _gatewayRepository;

  SessionViewModel({
    required GatewayRepository gatewayRepository,
  }) :
        _gatewayRepository = gatewayRepository {
    _gatewayRepository.addListener(_notify);
  }

  void _notify(){
    notifyListeners();
  }

  Future<void> switchSession(String key) async {
    await _gatewayRepository.switchSession(key);
  }

  /// 从 Gateway 获取完整会话列表，并同步更新 ViewModel 状态。
  Future<GatewaySessionsListResponse> listSessions({
    int? limit,
    String? search,
    bool archived = false,
    String? agentId,
    bool includeGlobal = true,
    bool includeUnknown = false,
    int? activeMinutes,
    String? spawnedBy,
    int? offset,
    bool? configuredAgentsOnly,
  }) async {
    return await _gatewayRepository.listSessions(
      limit: limit,
      search: search,
      archived: archived,
      agentId: agentId,
      includeGlobal: includeGlobal,
      includeUnknown: includeUnknown,
      activeMinutes: activeMinutes,
      spawnedBy: spawnedBy,
      offset: offset,
      configuredAgentsOnly: configuredAgentsOnly,
    );
  }

  /// 创建会话，并把新会话加入本地列表。
  Future<GatewayCreateSessionResponse> createSession({
    required String key,
    String? agentId,
    String? label,
    String? parentSessionKey,
    bool? worktree,
    String? worktreeBaseRef,
  }) async {
    return await _gatewayRepository.createSession(
      key: key,
      agentId: agentId,
      label: label,
      parentSessionKey: parentSessionKey,
      worktree: worktree,
      worktreeBaseRef: worktreeBaseRef,
    );
  }

  /// 更新会话显示标签，并同步刷新会话列表。
  Future<void> updateSessionLabel({
    required String sessionKey,
    required String label,
    String? agentId,
  }) async {
    await _gatewayRepository.updateSessionLabel(
      sessionKey: sessionKey,
      label: label,
      agentId: agentId,
    );
  }

  /// 删除会话及其 transcript，并清理本地状态。
  Future<void> deleteSession({
    required String sessionKey,
    String? agentId,
  }) async {
    await _gatewayRepository.deleteSession(
      sessionKey: sessionKey,
      agentId: agentId,
    );
  }

  @override
  void dispose() {
    // GatewayRepository 由根级 Provider 持有，本 ViewModel 只是消费者，
    // 不能在这里 dispose，否则会连带拆掉共享连接。
    _gatewayRepository.removeListener(_notify);
    super.dispose();
  }
}
