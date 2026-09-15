import 'dart:async';
import 'package:flutter/material.dart';
import 'package:parrot_app/data/model/message.dart';
import 'package:parrot_app/data/repository/gateway_repository.dart';
import 'package:parrot_app/data/repository/setting_repository.dart';

class ChatViewModel extends ChangeNotifier {

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

  ChatViewModel({
    required SettingRepository settingRepository,
    required GatewayRepository gatewayRepository,
  }) : _settingRepository = settingRepository,
        _gatewayRepository = gatewayRepository {
    _gatewayRepository.addListener(_notify);
  }

  void _notify(){
    notifyListeners();
  }

  void subscribeSessionMessage() {}

  void unsubscribeSessionMessage() {}

  Future<void> beginHistoryLoad() async {
    await _gatewayRepository.beginHistoryLoad();
  }

  Future<void> sendChatMessage(
    String text, {
    List<OutgoingAttachment> attachments = const [],
  }) async {
    await _gatewayRepository.sendChatMessage(text, attachments: attachments);
  }

  Future<void> switchTalkMode(bool talkMode) =>
      _gatewayRepository.switchTalkMode(talkMode);

  Future<void> sendTalkSpeak(String text) async {
    await _gatewayRepository.sendTalkSpeak(text);
  }

  Future<void> abortMessage() async {
    await _gatewayRepository.abortMessage();
  }

  List<dynamic>? get rawModels => _gatewayRepository.rawModels;

  /// 更新会话使用的模型和思考深度。
  ///
  /// 只会把非 null 的字段写入请求，因此可以单独更新其中一项，
  /// 也可以在一次 sessions.patch 请求中同时更新两项。
  Future<void> setSessionConfig({String? model, String? thinkingLevel}) async {
    await _gatewayRepository.setSessionConfig(
      model: model,
      thinkingLevel: thinkingLevel,
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
