import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:parrot_app/data/model/message.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/model/session_message.dart';
import 'package:parrot_app/data/repository/server_repository.dart';
import 'package:parrot_app/data/repository/setting_repository.dart';
import 'package:parrot_app/data/service/gateway_channel.dart';
import 'package:parrot_app/data/service/gateway_connection.dart';
import 'package:parrot_app/util/parse.dart';
import 'package:parrot_app/util/string_util.dart';
import 'package:uuid/uuid.dart';

class ConnViewModel extends ChangeNotifier {
  final Logger _log = Logger('ConnViewModel');
  var uuid = const Uuid();

  ServerConfig? _config;

  List<dynamic> _sessions = [];

  /// 获取当前服务器的会话列表
  List<dynamic> get sessions => _sessions;

  final messageController = StreamController<ChatMessage>.broadcast();

  Stream<ChatMessage>? get messageEvents => messageController.stream;

  final sessionUpdateController =
      StreamController<List<ChatMessage>>.broadcast();

  Stream<List<ChatMessage>>? get sessionUpdateEvents =>
      sessionUpdateController.stream;

  final messageFinalController = StreamController<String>.broadcast();

  Stream<String>? get pendingRunEvents => messageFinalController.stream;

  final voiceController = StreamController<dynamic>.broadcast();

  Stream<dynamic>? get voiceEvents => voiceController.stream;

  final StreamController<SessionMessage> _sessionMessageController =
      StreamController<SessionMessage>.broadcast();

  Stream<SessionMessage> get sessionMessageStream =>
      _sessionMessageController.stream;

  // Stream<String>? get thinkLevelEvents => _activeClient?.thinkLevelStream;

  List<dynamic> _thinkingOptions = [];

  List<dynamic> get thinkingOptions => _thinkingOptions;

  String _thinkingDefault = 'off';

  String get thinkingDefault => _thinkingDefault;

  String? _modelDefault = '';

  String? get model => _modelDefault;

  String? _sessionKey;

  String? get sessionKey => _sessionKey;

  bool _isConnecting = false;

  bool get isConnecting => _isConnecting;

  bool _connected = false;

  bool get connected => _connected;

  bool _isHistoryLoading = false;

  bool get isHistoryLoading => _isHistoryLoading;

  final SettingRepository _settingRepository;

  SettingRepository get settingRepository => _settingRepository;

  String _runId = '';

  String get runId => _runId;

  final bool _talkMode = false;

  bool get talkMode => _talkMode;

  final ServerRepository _serverRepository;
  StreamSubscription? _gatewaySub;

  String? disconnectReason;

  ConnViewModel({
    required SettingRepository settingRepository,
    required ServerRepository serverRepository,
  }) : _settingRepository = settingRepository,
       _serverRepository = serverRepository {
    _serverRepository.addListener(_onServerChanged);
  }

  void _onServerChanged() {
    _log.info('Server configuration changed, auto connecting...');
    connect(); // 自动调用连接
  }

  // Actions
  Future<void>? _pendingConnect;

  /// 主动断开标志：disconnect() 设置，避免断开事件被当作故障上报 UI
  bool _manualDisconnect = false;

  /// 连接服务器（串行化）
  ///
  /// ServerRepository 的每次变更都会触发本方法（添加/选择/更新/删除），
  /// 若不串行化，并发的 connect() 会互相取消订阅、configure 短路返回，
  /// 导致首次握手被提前标记成功或最终超时显示"连接失败"。
  Future<void> connect() async {
    // 等待上一次连接请求完成，避免并发竞态
    while (_pendingConnect != null) {
      try {
        await _pendingConnect;
      } catch (_) {
        // 上一次失败不影响本次重新连接
      }
    }
    final config = _serverRepository.selectedServer;
    if (config == null) {
      _isConnecting = false;
      _connected = false;
      notifyListeners();
      return;
    }
    if (_connected && _config == config) {
      return;
    }
    final completer = Completer<void>();
    _pendingConnect = completer.future;
    try {
      await _doConnect(config);
    } finally {
      _pendingConnect = null;
      completer.complete();
    }
  }

  Future<void> _doConnect(ServerConfig config) async {
    _manualDisconnect = false;
    _gatewaySub?.cancel();
    _config = config;
    _isConnecting = true;
    _connected = false;
    disconnectReason = null;
    _log.info('Switching to server: ${config.name}');

    _gatewaySub = GatewayConnection.shared.subscribe().listen((d) {
      if (d is GatewayPushSnapshot) {
        _markConnected(d.snapshot.snapshot.health);
      } else if (d is GatewayPushEvent) {
        // _log.info('${d.event}\n ${d.payload}');
        _handleGatewayEvent(d.event, d.payload);
      }
    });

    GatewayConnection.shared.onDisconnect = (reason) {
      if (_manualDisconnect) {
        // 主动断开（切换服务器/退出页面）不当作故障上报，避免
        // 与新连接的竞态把 UI 错误拉回"已断开连接"。
        _manualDisconnect = false;
        return;
      }
      _sessionKey = null; //断连时清空残留 sessionKey
      _sessions = [];
      _isConnecting = false;
      _connected = false;
      // _log.warning('onDisconnect: $reason');
      disconnectReason = reason;
      notifyListeners();
    };
    try {
      notifyListeners();
      await GatewayConnection.shared.configure(
        url: config.wsUrl,
        token: config.token,
        password: config.password,
      );
      // configure() returns only after the authenticated WebSocket handshake.
      // Use it as a fallback when a snapshot was emitted before this listener
      // was attached or when the snapshot health payload has another shape.
      if (!_connected && identical(_config, config)) {
        _markConnected(null);
      }
    } catch (e) {
      _isConnecting = false;
      _connected = false;
      disconnectReason = e.toString();
      notifyListeners();
      _log.warning('Connect failed in ViewModel: $e');
    }
  }

  void _markConnected(dynamic health) {
    if (_connected && !_isConnecting) return;
    _isConnecting = false;
    _connected = true;
    disconnectReason = null; // 连接成功时清空断开原因，避免 UI 残留"已断开连接"
    _sessionKey = GatewayConnection.shared.cachedMainSessionKey();
    if (health is Map) {
      final sessions = health['sessions'];
      if (sessions is Map && sessions['recent'] is List) {
        _sessions = sessions['recent'] as List<dynamic>;
      }
    }
    _isHistoryLoading = false;
    notifyListeners();
    unawaited(_initializeSessionData());
    unawaited(listModels());
  }

  Future<void> _initializeSessionData() async {
    try {
      _sessionKey ??= await GatewayConnection.shared.mainSessionKey();
      await beginHistoryLoad();
    } catch (error) {
      _log.warning('Failed to initialize main session: $error');
    }
  }

  String buildMediaUrl(String srcUrl) {
    return _config!.buildMediaUrl(srcUrl);
  }

  void _handleGatewayEvent(String event, dynamic payload) {
    _log.info(event);
    switch (event) {
      case 'tick':
        break;
      case 'health':
        break;
      case 'chat':
        if (payload != null) _handleChatEvent(payload);
        break;
      case 'agent':
        if (payload != null) _handleAgentEvent(payload);
        break;
      case 'presence':
        break;
      case 'session.message':
        if (payload != null) _handleSessionMessageEvent(payload);
      default:
    }
  }

  void _handleChatEvent(dynamic payload) {
    if (payload == null) return;
    final runId = payload['runId'] as String?;
    final state = payload['state'] as String?;
    switch (state) {
      case 'delta':
        break;
      case 'final':
        if (_runId == runId) {
          _log.info(payload);
          _runId = '';
          notifyListeners();
          if (payload['message'] != null) {
            final ChatMessage message = ChatMessage.fromJson(
              payload['message'],
            );
            if (message.content.first.type == 'text') {
              messageFinalController.add(
                StringUtil.cleanTextForTts(message.content.first.text!),
              );
            }
          }
        }
        break;
      case 'aborted':
      case 'error':
        if (_runId == runId) {
          _log.warning('Chat run $runId ended with state=$state: $payload');
          _runId = '';
          notifyListeners();
        }
        break;
    }
  }

  void subscribeSessionMessage() async {
    // await GatewayConnection.shared.request(
    //   method: 'sessions.messages.subscribe',
    //   params: {'key': _sessionKey},
    //   timeoutMs: 10000,
    // );
  }

  void unsubscribeSessionMessage() async {
    // await GatewayConnection.shared.request(
    //   method: 'sessions.messages.unsubscribe',
    //   params: {'key': _sessionKey},
    //   timeoutMs: 10000,
    // );
  }

  Future<void> beginHistoryLoad() async {
    if (!_connected || _isHistoryLoading || sessionKey == null) {
      return;
    }
    _isHistoryLoading = true;
    notifyListeners();
    final Map<String, dynamic> json = await GatewayConnection.shared
        .chatHistory(sessionKey!);

    final sessionInfo = json['sessionInfo'];
    _thinkingOptions = sessionInfo['thinkingOptions'];
    _modelDefault = sessionInfo['model'];
    _log.info(json);

    final messagesList = json['messages'] as List<dynamic>? ?? [];
    final List<ChatMessage> messages = [];
    for (final item in messagesList) {
      final obj = item as Map<String, dynamic>;
      final role = obj['role'] as String? ?? 'user';
      if (role != 'user' && role != 'assistant') {
        continue;
      }

      final contentList = _parseChatMessageContents(obj);
      if (contentList.isNotEmpty) {
        final ts = obj['timestamp'] as int?;
        // 提取 ID (参考 Kotlin 和原有逻辑)
        final openclaw = obj['__openclaw'] as Map<String, dynamic>?;
        final id =
            obj['id'] as String? ??
            openclaw?['id']?.toString() ??
            'msg_${DateTime.now().microsecondsSinceEpoch}';
        messages.add(
          ChatMessage(
            id: id,
            role: role,
            content: contentList,
            timestamp: ts,
            idempotencyKey: obj['idempotencyKey'] as String?,
          ),
        );
      }
    }

    sessionUpdateController.add(messages);
    _isHistoryLoading = false;
    notifyListeners();
  }

  void disconnect() {
    _manualDisconnect = true;
    _sessionKey = null; // 🌟 修复点 2：主动断开时清空残留 sessionKey
    _sessions = [];
    _connected = false;
    _isConnecting = false;
    GatewayConnection.shared.shutdown();
  }

  Future<void> reconnect() async {
    _log.info('Reconnecting to server: ${_config?.name} (${_config?.id})');
    return connect();
  }

  Future<void> sendChatMessage(
    String text, {
    List<OutgoingAttachment> attachments = const [],
  }) async {
    _log.info('sendMessage: $text');
    final message = text.trim();
    if (message.isEmpty && attachments.isEmpty) {
      return;
    }

    _runId =
        'chat_${DateTime.now().millisecondsSinceEpoch}_${uuid.v4().substring(0, 8)}'; // 1. 准备数据
    notifyListeners();
    if (attachments.isEmpty) {
      // 2. 乐观更新：创建并显示用户消息
      final userMessage = ChatMessage(
        id: uuid.v4(),
        role: 'user',
        content: [ChatMessageContent(type: 'text', text: message)],
        timestamp: DateTime.now().millisecondsSinceEpoch,
        idempotencyKey: _runId,
      );
      messageController.add(userMessage);
    } else {
      for (dynamic a in attachments) {
        // 2. 乐观更新：创建并显示用户消息
        final userMessage = ChatMessage(
          id: uuid.v4(),
          role: 'user',
          content: [
            ChatMessageContent(
              // base64: a.base64,
              text: message,
              type: a.type, // 或根据 mimeType 判断
              mimeType: a.mimeType,
              fileName: a.fileName,
            ),
          ],
          timestamp: DateTime.now().millisecondsSinceEpoch,
          idempotencyKey: _runId,
        );
        messageController.add(userMessage);
      }
    }

    final resolvedSessionKey =
        sessionKey ?? await GatewayConnection.shared.mainSessionKey();
    _sessionKey = resolvedSessionKey;
    try {
      await GatewayConnection.shared.chatSend(
        sessionKey: resolvedSessionKey,
        message: message,
        idempotencyKey: _runId,
        attachments:
            attachments
                .map(
                  (a) => {
                    'type': a.type,
                    'content': a.base64,
                    'mimeType': a.mimeType,
                    'fileName': a.fileName,
                  },
                )
                .toList(),
      );
    } catch (error) {
      if (_runId.isNotEmpty) {
        _runId = '';
        notifyListeners();
      }
      _log.warning('chat.send failed: $error');
      rethrow;
    }
  }

  void switchTalkMode(bool talModel) {
    GatewayConnection.shared.talkMode(enabled: talModel);
  }

  Future<void> sendTalkSpeak(String text) async {
    if (text.isEmpty) {
      return;
    }
    final Map<String, dynamic> payload = await GatewayConnection.shared
        .requestRaw(Method.talkSpeak, params: {'text': text});
    if (payload.containsKey('audioBase64')) {
      voiceController.add(payload['audioBase64']);
    }
  }

  Future<void> abortMessage() async {
    if (_runId != '') {
      GatewayConnection.shared.chatAbort(sessionKey!, _runId);
      _runId = '';
      notifyListeners();
    }
  }

  Future<void> switchSession(String key) async {
    _sessionKey = key;
    beginHistoryLoad();
  }

  Future<void> refresh() async {
    GatewayConnection.shared.refresh();
  }

  bool isOpenclawTTS() {
    return _settingRepository.isOpenclawTTS;
  }

  bool isTTSAbort() {
    return _settingRepository.isTTSAbort;
  }

  List<ChatMessageContent> _parseChatMessageContents(Map<String, dynamic> obj) {
    final content = obj['content'];
    if (content is List) {
      final List<ChatMessageContent> contentList = [];
      for (var e in content) {
        final ChatMessageContent? chatMessageContent = _parseChatMessageContent(
          e,
        );
        if (chatMessageContent != null) {
          if (obj['role'] == 'assistant') {
            final SplitMediaResult result = splitMediaFromOutput(
              chatMessageContent.text!,
            );
            final List<String> mediaUrls = result.mediaUrls ?? [];
            for (String url in mediaUrls) {
              final fileName = url.split('/').last;
              final String type = _mediaType(url);
              contentList.add(
                ChatMessageContent(
                  type: type,
                  text: _config!.buildMediaUrl(url),
                  fileName: fileName,
                ),
              );
            }
          }
          contentList.add(chatMessageContent);
        }
      }
      return contentList;
    }

    if (content is String && content.isNotEmpty) {
      if ('${obj['MediaType'] ?? ''}'.startsWith('image')) {
        return [
          ChatMessageContent(type: 'image', text: content),
          ChatMessageContent(type: 'text', text: content),
        ];
      }

      return [ChatMessageContent(type: 'text', text: content)];
    }

    final text = obj['text'] as String?;
    if (text != null && text.isNotEmpty) {
      return [ChatMessageContent(type: 'text', text: text)];
    }

    return [];
  }

  ChatMessageContent? _parseChatMessageContent(dynamic el) {
    if (el is! Map<String, dynamic>) return null;
    final type = el['type'] as String? ?? 'text';
    switch (type) {
      case 'text':
      case 'input_text':
      case 'output_text':
        return ChatMessageContent(
          type: 'text',
          text: el['text'] as String? ?? el['content'] as String?,
        );
      case 'image':
        final b64 = el['content'] as String? ?? el['base64'] as String?;
        if (b64 != null) {
          return ChatMessageContent(
            type: 'image',
            mimeType: el['mimeType'] as String?,
            fileName: el['fileName'] as String?,
            base64: b64.trim().isEmpty ? null : b64,
          );
        } else {
          return ChatMessageContent(type: 'text', text: el['url'] as String?);
        }

      default:
        return null;
    }
  }

  Future<void> _handleAgentEvent(dynamic payload) async {
    if (payload == null) return;
    _log.info(payload);
    final stream = payload['stream'] as String?;
    final data = payload['data'];
    final runId = payload['runId'] as String?;
    switch (stream) {
      case 'assistant':
        // 2. 处理助手文本流 (不再直接创建 ChatMessage，而是更新流式文本)
        final text = data?['text'] as String?;
        if (text != null && text.isNotEmpty) {
          _pushStreamingMessage(text, runId);
        }
        final mediaUrlsRaw = data['mediaUrls'] as List<dynamic>?;
        if (mediaUrlsRaw != null && mediaUrlsRaw.isNotEmpty) {
          for (String mediaUrl in mediaUrlsRaw) {
            final fileName = mediaUrl.split('/').last;
            final type = _mediaType(mediaUrl);
            final message = ChatMessage(
              id: runId!,
              role: 'assistant',
              content: [
                ChatMessageContent(
                  type: type,
                  text: _config!.buildMediaUrl(mediaUrl),
                  fileName: fileName,
                ),
              ],
              timestamp: DateTime.now().millisecondsSinceEpoch,
            );
            messageController.add(message);
          }
        }
        break;
      case 'tool':
        // 3. 处理工具调用状态 (start/result)
        final phase = data?['phase'] as String?;
        final name = data?['name'] as String?;
        final toolCallId = data?['toolCallId'] as String?;
        if (phase == null || name == null || toolCallId == null) return;
        if (phase == 'start') {
          _log.info('Tool call started: $name ($toolCallId)');
          // _pushStreamingMessage('Tool call', runId);
          // 可在此发送事件通知 UI 显示“正在执行 $name”
        } else if (phase == 'result') {
          _log.info('Tool call finished: $name ($toolCallId)');
          // _pushStreamingMessage("Tool output", runId);
          // 可在此发送事件通知 UI 移除工具执行状态
        }
        break;
      // case 'item':
      //   final message = ChatMessage(
      //     id: runId!,
      //     role: 'assistant',
      //     content: [
      //       ChatMessageContent(
      //         type: 'toolCall',
      //         text: data?['data'] as String?,
      //       ),
      //     ],
      //     timestamp: DateTime.now().millisecondsSinceEpoch,
      //   );
      //   messageController.add(message);
      case 'error':
        break;
    }
  }

  void _handleSessionMessageEvent(dynamic data) {
    if (data is! Map) {
      return;
    }
    // _log.info(data);
    final rawMessage = data['message'];
    if (rawMessage is! Map) {
      return;
    }

    try {
      final message = SessionMessage.fromJson(
        Map<String, dynamic>.from(rawMessage),
      );

      _sessionMessageController.add(message);
    } catch (error, stackTrace) {
      debugPrint('Failed to parse session message: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  String _mediaType(String mediaUrl) {
    final extension = '.${mediaUrl.split('.').last.toLowerCase()}';
    const imageExts = {
      '.png',
      '.jpg',
      '.jpeg',
      '.webp',
      '.gif',
      '.heic',
      '.heif',
    };
    const audioExts = {'.mp3', '.wav', '.ogg', '.opus', '.m4a'};
    const videoExts = {'.mp4', '.mov', '.webm'};
    String type;
    if (imageExts.contains(extension)) {
      type = 'image';
    } else if (audioExts.contains(extension)) {
      type = 'audio';
    } else if (videoExts.contains(extension)) {
      type = 'video';
    } else {
      type = 'file';
    }
    return type;
  }

  /// 封装流式消息并回传到流控制器，同时更新本地消息列表
  void _pushStreamingMessage(String text, String? runId) {
    if (text.isEmpty) return;
    final messageId = runId ?? 'streaming_assistant';
    final message = ChatMessage(
      id: messageId,
      role: 'assistant',
      content: [ChatMessageContent(type: 'text', text: text)],
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    messageController.add(message);
  }

  List<dynamic>? _rawModels;

  List<dynamic>? get rawModels => _rawModels;

  Future listModels() async {
    if (!_connected) return; // 防止未连接时的无效底请求
    try {
      final rawModels = await GatewayConnection.shared.listModels();
      _rawModels = rawModels;
      notifyListeners();
    } catch (e) {
      _log.warning('listModels failed: $e');
    }
    notifyListeners();
  }

  /// 设置会话使用的模型 (参考 Swift WebChatSwiftUI.swift 的 setSessionModel)
  Future<void> setSessionModel(String? model) async {
    try {
      final Map<String, dynamic> params = {
        'key': _sessionKey,
        'model': model, // Dart 中 null 会被转为 JSON 的 null
      };

      final Map<String, dynamic> json = await GatewayConnection.shared.request(
        method: Method.sessionsPatch.rawValue,
        params: params,
        timeoutMs: 15000,
      );
      _log.info(json);
      _modelDefault = model;
      notifyListeners();

      _log.info('Successfully updated session model to: $model');
    } catch (e) {
      _log.warning('setSessionModel failed: $e');
      rethrow;
    }
  }

  /// 设置会话的思考深度 (参考 Swift WebChatSwiftUI.swift 的 setSessionThinking)
  Future<void> setSessionThinking(String thinkingLevel) async {
    try {
      final Map<String, dynamic> params = {
        'key': _sessionKey,
        'thinkingLevel': thinkingLevel,
      };

      final Map<String, dynamic> json = await GatewayConnection.shared.request(
        method: Method.sessionsPatch.rawValue,
        params: params,
        timeoutMs: 15000,
      );

      _log.info(json);
      // 同时更新本地状态
      _thinkingDefault = thinkingLevel;
      notifyListeners();

      _log.info(
        'Successfully updated session thinkingLevel to: $thinkingLevel',
      );
    } catch (e) {
      _log.warning('setSessionThinking failed: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _serverRepository.removeListener(_onServerChanged); // 🌟 修复点 6：反注册监听器
    _gatewaySub?.cancel();
    messageController.close();
    sessionUpdateController.close();
    messageFinalController.close();
    voiceController.close();
    _sessionMessageController.close();
    super.dispose();
  }
}
