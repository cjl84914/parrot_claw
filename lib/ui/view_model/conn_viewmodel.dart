import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:parrot_app/data/model/message.dart';
import 'package:parrot_app/data/repository/gateway_repository.dart';
import 'package:parrot_app/data/repository/setting_repository.dart';
import 'package:parrot_app/data/service/openclaw_protocol.dart';
import 'package:parrot_app/data/service/openclaw_runtime.dart';

class ConnViewModel extends ChangeNotifier {
  final Logger _log = Logger('ConnViewModel');

  /// 获取当前服务器的会话列表。
  List<GatewaySessionEntry> get sessions => _gatewayRepository.sessions;

  Stream<ChatMessage>? get messageEvents => _gatewayRepository.messageController.stream;


  Stream<List<ChatMessage>>? get sessionUpdateEvents =>
      _gatewayRepository.sessionUpdateController.stream;


  Stream<String>? get pendingRunEvents => _gatewayRepository.messageFinalController.stream;

  Stream<dynamic>? get voiceEvents => _gatewayRepository.voiceController.stream;

  // Stream<String>? get thinkLevelEvents => _activeClient?.thinkLevelStream;

  List<dynamic> get thinkingOptions => _gatewayRepository.thinkingOptions;

  String get thinkingDefault => _gatewayRepository.thinkingDefault;

  String? get model => _gatewayRepository.model;

  String? get sessionKey => _gatewayRepository.sessionKey;

  bool get isConnecting => _gatewayRepository.isConnecting;

  bool get connected => _gatewayRepository.connected;

  bool get isReconnecting => _gatewayRepository.isReconnecting;

  bool get isHistoryLoading => _gatewayRepository.isHistoryLoading;

  final SettingRepository _settingRepository;

  SettingRepository get settingRepository => _settingRepository;

  String get runId => _gatewayRepository.runId;

  bool get talkMode => _gatewayRepository.talkMode;

  bool isOpenclawTTS() => _settingRepository.isOpenclawTTS;

  bool isTTSAbort() => _settingRepository.isTTSAbort;

  final GatewayRepository _gatewayRepository;

  String? get disconnectReason => _gatewayRepository.disconnectReason;

  ConnViewModel({
    required SettingRepository settingRepository,
    required GatewayRepository gatewayRepository,
  }) : _settingRepository = settingRepository,
        _gatewayRepository = gatewayRepository {
    _gatewayRepository.addListener(_notify);
  }

  void _notify(){
    notifyListeners();
  }

  /// 连接服务器（串行化）
  ///
  /// ServerRepository 的每次变更都会触发本方法（添加/选择/更新/删除），
  /// 若不串行化，并发的 connect() 会互相取消订阅、configure 短路返回，
  /// 导致首次握手被提前标记成功或最终超时显示"连接失败"。
  Future<void> connect() async {
    _gatewayRepository.connect();
  }

  String buildMediaUrl(String srcUrl) {
    return _gatewayRepository.buildMediaUrl(srcUrl);
  }

  void subscribeSessionMessage() {}

  void unsubscribeSessionMessage() {}

  Future<void> beginHistoryLoad() async {
    _gatewayRepository.beginHistoryLoad();
  }

  /// 主动断开连接（保留服务器配置，可随时重新连接）。
  Future<void> disconnect() async {
    await _gatewayRepository.disconnect();
  }

  Future<void> reconnect() async {
    await _gatewayRepository.reconnect();
  }

  Future<void> sendChatMessage(
    String text, {
    List<OutgoingAttachment> attachments = const [],
  }) async {
    _gatewayRepository.sendChatMessage(text, attachments: attachments);
  }

  Future<void> switchTalkMode(bool talkMode) =>
      _gatewayRepository.switchTalkMode(talkMode);

  Future<void> sendTalkSpeak(String text) async {
    await _gatewayRepository.sendChatMessage(text);
  }

  Future<void> abortMessage() async {
    await _gatewayRepository.abortMessage();
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
    _gatewayRepository.updateSessionLabel(
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
    _gatewayRepository.deleteSession(sessionKey: sessionKey, agentId: agentId);
  }

  Future<void> refresh() async {
    _gatewayRepository.refresh();
  }


  List<dynamic>? get rawModels => _gatewayRepository.rawModels;

  Future listModels() async {
    _gatewayRepository.listModels();
  }

  /// 更新会话使用的模型和思考深度。
  ///
  /// 只会把非 null 的字段写入请求，因此可以单独更新其中一项，
  /// 也可以在一次 sessions.patch 请求中同时更新两项。
  Future<void> setSessionConfig({String? model, String? thinkingLevel}) async {
    _gatewayRepository.setSessionConfig(model: model, thinkingLevel: thinkingLevel);
  }

  Future<OpenClawDevicePairSetupCodeResponse> devicePairSetupCode({
    String? publicUrl,
  }) async {
    return _gatewayRepository.devicePairSetupCode();
  }

  @override
  void dispose() {
    // GatewayRepository 由根级 Provider 持有，本 ViewModel 只是消费者，
    // 不能在这里 dispose，否则会连带拆掉共享连接。
    _gatewayRepository.removeListener(_notify);
    super.dispose();
  }
}
