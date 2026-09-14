import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:parrot_app/data/model/gateway_cron.dart';
import 'package:parrot_app/data/model/gateway_skill.dart';
import 'package:parrot_app/data/model/message.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/model/session_message.dart';
import 'package:parrot_app/data/repository/server_repository.dart';
import 'package:parrot_app/data/repository/setting_repository.dart';
import 'package:parrot_app/data/service/gateway_scope_store.dart';
import 'package:parrot_app/data/service/openclaw_protocol.dart';
import 'package:parrot_app/data/service/openclaw_runtime.dart';
import 'package:parrot_app/util/parse.dart';
import 'package:parrot_app/util/string_util.dart';
import 'package:uuid/uuid.dart';

class GatewayRepository extends ChangeNotifier {
  final Logger _log = Logger('GatewayRepository');
  var uuid = const Uuid();

  ServerConfig? _config;

  List<GatewaySessionEntry> _sessions = [];

  /// 获取当前服务器的会话列表。
  List<GatewaySessionEntry> get sessions => List.unmodifiable(_sessions);

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

  // A run can contain multiple assistant replies. Keep a client-side ID for
  // the current cumulative streaming reply so later replies are appended.
  final Map<String, _StreamingMessageState> _streamingMessages = {};

  final bool _talkMode = false;

  bool get talkMode => _talkMode;

  final ServerRepository _serverRepository;
  final OpenClawRuntime _runtime;
  StreamSubscription? _runtimeSub;
  StreamSubscription? _runtimeStateSub;
  String? disconnectReason;

  GatewayRepository({
    required SettingRepository settingRepository,
    required ServerRepository serverRepository,
    OpenClawRuntime? runtime,
  }) : _settingRepository = settingRepository,
       _serverRepository = serverRepository,
       _runtime = runtime ?? OpenClawRuntime.instance {
    _runtimeSub = _runtime.pushes.listen(_handleRuntimePush);
    _runtimeStateSub = _runtime.states.listen(_handleRuntimeState);
    _serverRepository.addListener(_onServerChanged);
  }


  void _onServerChanged() {
    _log.info('Server configuration changed, auto connecting...');
    connect(); // 自动调用连接
  }

  /// 主动断开标志：disconnect() 设置，避免断开事件被当作故障上报 UI
  bool _manualDisconnect = false;

  bool _isReconnecting = false;

  /// 是否正在自动重连（runtime 的守护重连或 socket 退避重连）。
  bool get isReconnecting => _isReconnecting;

  /// 连接服务器（串行化）
  ///
  /// ServerRepository 的每次变更都会触发本方法（添加/选择/更新/删除），
  /// 若不串行化，并发的 connect() 会互相取消订阅、configure 短路返回，
  /// 导致首次握手被提前标记成功或最终超时显示"连接失败"。
  Future<void> connect() async {
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
    await _doConnect(config);
  }

  Future<void> _doConnect(
    ServerConfig config, {
    bool reconnecting = false,
  }) async {
    _manualDisconnect = false;
    _config = config;
    _isConnecting = true;
    _connected = false;
    _isReconnecting = reconnecting;
    disconnectReason = reconnecting ? '正在重新连接网关…' : null;
    _runId = '';
    _log.info('Switching to server: ${config.name}');

    try {
      notifyListeners();
      // 扫码配对（受限 operator）加入的网关：重连时复用配对时实际授权的
      // scopes，避免按默认全量（含 admin/pairing）请求触发 scope-upgrade 审批。
      final storedScopes = await GatewayScopeStore.operatorScopes(config.wsUrl);
      final runtimeConfig = OpenClawRuntimeConfig(
        url: config.wsUrl,
        token: config.isTokenAuth ? config.token : null,
        password: config.isPasswordAuth ? config.password : null,
        scopes: storedScopes ?? openClawOperatorScopes,
      );
      await _runtime.configure(runtimeConfig);
      // configure() returns only after the authenticated WebSocket handshake.
      // Use it as a fallback when a snapshot was emitted before this listener
      // was attached or when the snapshot health payload has another shape.
      if (!_connected && identical(_config, config)) {
        _markConnected(null);
      }
    } catch (e) {
      _isConnecting = false;
      _connected = false;
      notifyListeners();
      _log.warning('Connect failed in ViewModel: $e');
      // runtime 会在后台继续重连，这里只把失败原因交给 UI。
      if (!_manualDisconnect) {
        disconnectReason = _describeConnectError(e);
        notifyListeners();
      }
    }
  }

  /// 把底层异常转成用户能看懂的一行原因。
  String _describeConnectError(Object error) {
    final text = error.toString();
    if (error is GatewayResponseError) {
      return '${error.code}: ${error.message}';
    }
    if (text.contains('Connection refused') ||
        text.contains('SocketException')) {
      return '无法连接到网关，请确认 OpenClaw Gateway 正在运行';
    }
    if (text.contains('TimeoutException') || text.contains('timed out')) {
      return '连接网关超时';
    }
    return text;
  }

  void _markConnected(dynamic health) {
    if (_runtime.state != OpenClawRuntimeState.ready) return;
    if (_connected && !_isConnecting) return;
    _isConnecting = false;
    _isReconnecting = false;
    _connected = true;
    disconnectReason = null; // 连接成功时清空断开原因，避免 UI 残留"已断开连接"
    _isHistoryLoading = false;
    notifyListeners();
    unawaited(_initializeSessionData());
    unawaited(listSessions());
    unawaited(listModels());
  }

  Future<void> _initializeSessionData() async {
    try {
      _sessionKey ??= await _runtime.mainSessionKey();
      await beginHistoryLoad();
    } catch (error) {
      _log.warning('Failed to initialize main session: $error');
    }
  }

  String buildMediaUrl(String srcUrl) {
    return _config!.buildMediaUrl(srcUrl);
  }

  void _handleRuntimePush(GatewayPush push) {
    if (push is GatewayPushSnapshot) {
      _markConnected(push.snapshot.snapshot.health);
    } else if (push is GatewayPushEvent) {
      _handleGatewayEvent(push.event, push.payload);
    }
  }

  void _handleRuntimeState(OpenClawRuntimeState state) {
    if (_manualDisconnect) return;
    switch (state) {
      case OpenClawRuntimeState.ready:
        // 正常路径由 snapshot 触发 _markConnected；这里兜底，避免 push 丢失
        // （或监听器晚挂）时 UI 永远停在"已断开"。
        _markConnected(null);
      case OpenClawRuntimeState.disconnected:
      case OpenClawRuntimeState.reconnecting:
        final wasConnected = _connected || _isConnecting;
        _isReconnecting = true;
        _isConnecting = false;
        if (wasConnected) {
          _sessionKey = null;
          _sessions = [];
        }
        _connected = false;
        disconnectReason = '与网关的连接已断开，正在自动重连…';
        notifyListeners();
      case OpenClawRuntimeState.idle:
      case OpenClawRuntimeState.connecting:
        break;
    }
  }

  void _handleGatewayEvent(String event, dynamic payload) {
    // _log.info(event);
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
          _clearStreamingMessages(runId);
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
          _clearStreamingMessages(runId);
          _runId = '';
          notifyListeners();
        }
        break;
    }
  }

  void subscribeSessionMessage() {}

  void unsubscribeSessionMessage() {}

  Future<void> beginHistoryLoad() async {
    if (!_connected || _isHistoryLoading || sessionKey == null) {
      return;
    }
    _isHistoryLoading = true;
    notifyListeners();
    final Map<String, dynamic> json = await _runtime.chatHistory(
      sessionKey: sessionKey!,
    );

    final sessionInfo = json['sessionInfo'];
    final sessionInfoMap =
        sessionInfo is Map
            ? sessionInfo.cast<String, dynamic>()
            : const <String, dynamic>{};
    _thinkingOptions = sessionInfoMap['thinkingOptions'] as List? ?? const [];
    _modelDefault = sessionInfoMap['model'] as String?;
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

  // Future<void> disconnect() async {
  //   _log.info('shutdown sessionKey: $_sessionKey');
  //   _manualDisconnect = true;
  //   _sessionKey = null;
  //   _sessions = [];
  //   _connected = false;
  //   _isConnecting = false;
  //   _config = null;
  //   disconnectReason = null;
  //   notifyListeners();
  //   await _runtime.shutdown();
  // }

  /// 主动断开：关闭共享会话并停止自动重连。
  ///
  /// 与 [dispose] 的区别：这里只影响连接，不影响仓库自身；
  /// 之后任何 [connect] / [reconnect] 都能重新建立会话。
  Future<void> disconnect() async {
    _log.info('Disconnecting from server: ${_config?.name} (${_config?.id})');
    _manualDisconnect = true;
    _sessionKey = null;
    _sessions = [];
    _connected = false;
    _isConnecting = false;
    _isReconnecting = false;
    disconnectReason = null;
    notifyListeners();
    await _runtime.shutdown();
  }

  /// 手动重连：走一次完整的 configure，成功后 UI 会立刻恢复。
  ///
  /// 与 [connect] 的区别只是语义（带"正在重连"状态 + 失败原因），
  /// 底层同样是 runtime 的共享会话，因此不会额外建第二条连接。
  Future<void> reconnect() async {
    final config = _serverRepository.selectedServer ?? _config;
    if (config == null) {
      _log.warning('Reconnect skipped: no server selected');
      return;
    }
    _log.info('Reconnecting to server: ${config.name} (${config.id})');
    try {
      await _doConnect(config, reconnecting: true);
    } catch (error) {
      _log.warning('Manual reconnect failed: $error');
    }
    if (_connected) return;
    _isReconnecting = false;
    _isConnecting = false;
    disconnectReason ??= '重连失败，请确认 OpenClaw Gateway 正在运行';
    notifyListeners();
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

    final resolvedSessionKey = sessionKey ?? await _runtime.mainSessionKey();
    _sessionKey = resolvedSessionKey;
    try {
      await _runtime.chatSend(
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

  Future<void> switchTalkMode(bool talkMode) async {
    _runtime.talkMode(enabled: talkMode);
  }

  Future<void> sendTalkSpeak(String text) async {
    if (text.isEmpty) {
      return;
    }
    final Map<String, dynamic> payload = await _runtime.talkSpeak(text);
    if (payload.containsKey('audioBase64')) {
      voiceController.add(payload['audioBase64']);
    }
  }

  Future<void> abortMessage() async {
    if (_runId != '') {
      await _runtime.chatAbort(sessionKey: sessionKey!, runId: _runId);
      _runId = '';
      notifyListeners();
    }
  }

  Future<void> switchSession(String key) async {
    _sessionKey = key;
    await beginHistoryLoad();
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
    final response = GatewaySessionsListResponse.fromJson(
      await _runtime.sessionsList(
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
      ),
    );
    _sessions = response.sessions;
    notifyListeners();
    return response;
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
    final response = GatewayCreateSessionResponse.fromJson(
      await _runtime.sessionsCreate(
        key: key,
        agentId: agentId,
        label: label,
        parentSessionKey: parentSessionKey,
        worktree: worktree,
        worktreeBaseRef: worktreeBaseRef,
      ),
    );
    try {
      await listSessions();
    } catch (error) {
      _log.warning('Failed to refresh sessions after creation: $error');
    }
    return response;
  }

  /// 更新会话显示标签，并同步刷新会话列表。
  Future<void> updateSessionLabel({
    required String sessionKey,
    required String label,
    String? agentId,
  }) async {
    final normalizedLabel = label.trim();
    if (normalizedLabel.isEmpty) {
      throw ArgumentError.value(label, 'label', '标签不能为空');
    }
    final session = _sessions.cast<GatewaySessionEntry?>().firstWhere(
      (item) => item?.key == sessionKey,
      orElse: () => null,
    );
    final success = await _runtime.patchSession(
      key: sessionKey,
      ownerAgentId: agentId ?? session?.agentId,
      label: normalizedLabel,
    );
    if (!success) {
      throw StateError('更新会话标签失败');
    }
    await listSessions();
  }

  /// 删除会话及其 transcript，并清理本地状态。
  Future<void> deleteSession({
    required String sessionKey,
    String? agentId,
  }) async {
    await _runtime.sessionsDelete(sessionKey: sessionKey, agentId: agentId);
    _sessions =
        _sessions.where((session) => session.key != sessionKey).toList();
    if (_sessionKey == sessionKey) {
      _sessionKey = null;
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_connected) await listSessions();
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
              id: uuid.v4(),
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

  /// Push a cumulative streaming reply, or start a new reply when the text
  /// no longer belongs to the current reply in the same run.
  void _pushStreamingMessage(String text, String? runId) {
    if (text.isEmpty) return;

    final key = runId ?? 'streaming_assistant';
    final previous = _streamingMessages[key];
    final isContinuation =
        previous != null &&
        (text == previous.text || text.startsWith(previous.text));
    final state =
        isContinuation
            ? previous
            : _StreamingMessageState(id: uuid.v4(), text: text);

    _streamingMessages[key] = state.copyWith(text: text);
    final message = ChatMessage(
      id: state.id,
      role: 'assistant',
      content: [ChatMessageContent(type: 'text', text: text)],
      timestamp: DateTime.now().millisecondsSinceEpoch,
      idempotencyKey: runId,
    );
    messageController.add(message);
  }

  void _clearStreamingMessages(String? runId) {
    if (runId == null) {
      _streamingMessages.clear();
    } else {
      _streamingMessages.remove(runId);
    }
  }

  List<dynamic>? _rawModels;

  List<dynamic>? get rawModels => _rawModels;

  Future listModels() async {
    if (!_connected) return; // 防止未连接时的无效底请求
    try {
      final rawModels = await _runtime.listModels();
      _rawModels = rawModels;
      notifyListeners();
    } catch (e) {
      _log.warning('listModels failed: $e');
    }
    notifyListeners();
  }

  /// 更新会话使用的模型和思考深度。
  ///
  /// 只会把非 null 的字段写入请求，因此可以单独更新其中一项，
  /// 也可以在一次 sessions.patch 请求中同时更新两项。
  Future<void> setSessionConfig({String? model, String? thinkingLevel}) async {
    if (model == null && thinkingLevel == null) {
      return;
    }

    try {
      if (_sessionKey == null) return;
      final patch = <String, dynamic>{
        if (model != null) 'model': model,
        if (thinkingLevel != null) 'thinkingLevel': thinkingLevel,
      };
      final Map<String, dynamic> json = await _runtime.sessionsPatch(
        sessionKey: _sessionKey!,
        patch: patch,
        timeout: const Duration(seconds: 15),
      );
      _log.info(json);

      if (model != null) {
        _modelDefault = model;
      }
      if (thinkingLevel != null) {
        _thinkingDefault = thinkingLevel;
      }
      notifyListeners();

      _log.info(
        'Successfully updated session config: '
        'model=$model, thinkingLevel=$thinkingLevel',
      );
    } catch (e) {
      _log.warning('setSessionConfig failed: $e');
      rethrow;
    }
  }

  Future<OpenClawDevicePairSetupCodeResponse> devicePairSetupCode({
    String? publicUrl,
  }) async {
    return _runtime.devicePairSetupCode();
  }

  // 说明：这里曾有一批 runtime 原样透传方法（mainSessionKey / configure /
  // chatHistory / talkSpeak / chatAbort / sessionsList / sessionsCreate /
  // patchSession / sessionsPatch / sessionsDelete）。它们没有任何调用方
  // （上层走的是 listSessions / createSession / updateSessionLabel /
  // deleteSession / setSessionConfig / abortMessage 这些带状态的方法），
  // 且 sessionsPatch 与 chatAbort 会静默忽略自己的入参，容易误用，故删除。
  // 需要新能力时，请在仓库里按「解析 + 更新状态 + notifyListeners」的模式新增。

  // ==================== Skill 管理 ====================
  //
  // Skill 的状态与操作都收敛在这里（复用共享的 _runtime 会话），
  // SkillViewModel 只做转发，不再自己持有状态或直连 runtime。

  List<GatewaySkill> _skills = const [];

  /// 当前网关上的 Skill 列表。
  List<GatewaySkill> get skills => List.unmodifiable(_skills);

  bool _skillsLoading = false;

  /// Skill 列表加载或 Skill 操作是否进行中（用于去重与 loading 态）。
  bool get skillsLoading => _skillsLoading;

  String? _skillsError;

  /// 最近一次 Skill 操作失败的原因。
  String? get skillsError => _skillsError;

  String? _lastSkillOperation;

  /// 最近一次成功的 Skill 操作名（install / update）。
  String? get lastSkillOperation => _lastSkillOperation;

  /// 拉取 Skill 列表。已在进行中时直接返回 false，避免并发请求互相覆盖状态。
  Future<bool> loadSkills() async {
    if (_skillsLoading) return false;
    _skillsLoading = true;
    _skillsError = null;
    notifyListeners();
    try {
      await _reloadSkills();
      return true;
    } catch (error) {
      _skillsError = error.toString();
      return false;
    } finally {
      _skillsLoading = false;
      notifyListeners();
    }
  }

  /// 安装 Skill，成功后刷新列表。
  Future<bool> installSkill({
    required String name,
    required String installId,
    bool? dangerouslyForceUnsafeInstall,
  }) async {
    if (_skillsLoading) return false;
    return _runSkillOperation('install', () async {
      await _runtime.skillsInstall(
        name: name,
        installId: installId,
        dangerouslyForceUnsafeInstall: dangerouslyForceUnsafeInstall,
      );
      await _reloadSkills();
    });
  }

  /// 更新 Skill（启用状态 / apiKey / env），成功后刷新列表。
  Future<bool> updateSkill({
    required String skillKey,
    bool? enabled,
    String? apiKey,
    Map<String, String>? env,
  }) async {
    if (_skillsLoading) return false;
    return _runSkillOperation('update', () async {
      await _runtime.skillsUpdate(
        skillKey: skillKey,
        enabled: enabled,
        apiKey: apiKey,
        env: env,
      );
      await _reloadSkills();
    });
  }

  Future<void> _reloadSkills() async {
    _skills =
        GatewaySkillsStatus.fromJson(await _runtime.skillsStatus()).skills;
  }

  Future<bool> _runSkillOperation(
    String operation,
    Future<void> Function() action,
  ) async {
    _skillsLoading = true;
    _skillsError = null;
    _lastSkillOperation = null;
    notifyListeners();
    try {
      await action();
      _lastSkillOperation = operation;
      return true;
    } catch (error) {
      _skillsError = error.toString();
      return false;
    } finally {
      _skillsLoading = false;
      notifyListeners();
    }
  }

  // ==================== ClawHub 技能搜索 / 安装审核 ====================
  //
  // 对应 Android `NodeRuntime.searchClawHubSkillsFromGateway` 与
  // `reviewClawHubSkillInstallFromGateway`：搜索与审核共用一套状态，
  // 放在这里，上层只做转发。与 Skill 列表是两套状态，互不影响。

  /// ClawHub 技能管理所需的网关方法族（Android 的 CLAWHUB_SKILL_GATEWAY_METHODS）。
  static const _clawHubGatewayMethods = <String>[
    'skills.search',
    'skills.detail',
    'skills.install',
  ];

  List<GatewayClawHubSkillSummary> _clawHubResults = const [];

  /// 最近一次 ClawHub 搜索的结果。
  List<GatewayClawHubSkillSummary> get clawHubResults =>
      List.unmodifiable(_clawHubResults);

  String _clawHubQuery = '';

  /// 最近一次搜索用的关键字。
  String get clawHubQuery => _clawHubQuery;

  bool _clawHubSearching = false;

  /// 是否正在搜索 ClawHub。
  bool get clawHubSearching => _clawHubSearching;

  String? _clawHubError;

  /// 最近一次搜索或审核失败的原因。
  String? get clawHubError => _clawHubError;

  String? _clawHubMessage;

  /// 搜索成功但无结果时的提示。
  String? get clawHubMessage => _clawHubMessage;

  String? _clawHubReviewingSlug;

  /// 正在读取详情的技能引用（用于该行的 loading 态）。
  String? get clawHubReviewingSlug => _clawHubReviewingSlug;

  GatewayClawHubInstallReview? _clawHubInstallReview;

  /// 已加载的安装审核信息，null 表示没有待确认的安装。
  GatewayClawHubInstallReview? get clawHubInstallReview =>
      _clawHubInstallReview;

  final Set<String> _clawHubInstallingSlugs = <String>{};

  /// 正在安装的 ClawHub 引用（用于把对应那行的按钮置为「安装中」并去重）。
  Set<String> get clawHubInstallingSlugs =>
      Set.unmodifiable(_clawHubInstallingSlugs);

  /// 当前连接是否拿到 `operator.admin`。
  ///
  /// 安装 ClawHub 技能需要写权限，与 Android `operatorAdminScopeAvailable` 同源：
  /// 读 hello 里 `auth.scopes`（网关没返回时视为没有，由调用方提示）。
  bool get clawHubCanInstall {
    final scopes = _runtime.hello?.auth['scopes'];
    if (scopes is! List) return false;
    return scopes
        .whereType<String>()
        .any((scope) => scope.trim() == 'operator.admin');
  }

  /// 搜索序号：只让最新一次搜索的结果落地，旧响应直接丢弃。
  int _clawHubSearchSeq = 0;

  /// 审核序号：新的搜索 / 审核会让在途的详情响应作废。
  int _clawHubReviewSeq = 0;

  /// 网关是否宣告了完整的 ClawHub 方法族（hello 的 `features.methods`）。
  ///
  /// 与 Android 一致：网关没宣告（含旧网关不返回 methods）时视为不支持，
  /// 由调用方提示用户升级 Gateway。
  bool get clawHubSkillsAvailable {
    final methods = _runtime.hello?.features['methods'];
    if (methods is! List) return false;
    final advertised = methods
        .whereType<String>()
        .map((method) => method.trim())
        .toSet();
    return _clawHubGatewayMethods.every(advertised.contains);
  }

  /// 搜索 ClawHub 技能，结果与状态写入本仓库。
  Future<bool> searchClawHubSkillsFromGateway(String query) async {
    final normalized = query.trim();
    final searchSeq = ++_clawHubSearchSeq;
    // 新的搜索会作废在途的详情请求与待确认的审核。
    _clawHubReviewSeq++;
    if (!_connected) {
      _clawHubQuery = normalized;
      _clawHubSearching = false;
      _clawHubResults = const [];
      _clawHubReviewingSlug = null;
      _clawHubInstallReview = null;
      _clawHubError = '请先连接网关，再搜索 ClawHub 技能';
      _clawHubMessage = null;
      notifyListeners();
      return false;
    }
    if (!clawHubSkillsAvailable) {
      _clawHubQuery = normalized;
      _clawHubSearching = false;
      _clawHubResults = const [];
      _clawHubReviewingSlug = null;
      _clawHubInstallReview = null;
      _clawHubError = '当前网关不支持 ClawHub 技能搜索，请升级 Gateway 后重试';
      _clawHubMessage = null;
      notifyListeners();
      return false;
    }
    _clawHubQuery = normalized;
    _clawHubSearching = true;
    _clawHubResults = const [];
    _clawHubReviewingSlug = null;
    _clawHubInstallReview = null;
    _clawHubError = null;
    _clawHubMessage = null;
    notifyListeners();
    try {
      final response = await _runtime.skillsSearch(query: normalized);
      final results = GatewayClawHubSkillSummary.listFromSearchResponse(
        response,
      );
      if (searchSeq != _clawHubSearchSeq) return false;
      _clawHubResults = results;
      _clawHubMessage = results.isEmpty ? '没有匹配的 ClawHub 技能' : null;
      return true;
    } catch (error) {
      if (searchSeq != _clawHubSearchSeq) return false;
      _clawHubError = '搜索 ClawHub 技能失败：$error';
      return false;
    } finally {
      if (searchSeq == _clawHubSearchSeq) {
        _clawHubSearching = false;
        notifyListeners();
      }
    }
  }

  /// 读取安装前的版本审核信息，成功后 [clawHubInstallReview] 就是待确认的版本。
  ///
  /// 对应 Android `reviewClawHubSkillInstallFromGateway`：用搜索结果自带的
  /// reference 去读详情，所以「审核的发布者」与「安装的发布者」是同一个。
  Future<bool> reviewClawHubSkillInstallFromGateway(
    GatewayClawHubSkillSummary skill,
  ) async {
    final reference = skill.reference;
    final reviewSeq = ++_clawHubReviewSeq;
    if (!_connected) {
      _clawHubError = '请先连接网关，再查看 ClawHub 技能详情';
      notifyListeners();
      return false;
    }
    if (!clawHubSkillsAvailable) {
      _clawHubError = '当前网关不支持 ClawHub 技能搜索，请升级 Gateway 后重试';
      notifyListeners();
      return false;
    }
    _clawHubReviewingSlug = reference;
    _clawHubInstallReview = null;
    _clawHubError = null;
    _clawHubMessage = null;
    notifyListeners();
    try {
      final response = await _runtime.skillsDetail(slug: reference);
      final review = GatewayClawHubInstallReview.fromDetailResponse(
        response,
        fallback: skill,
      );
      if (reviewSeq != _clawHubReviewSeq) return false;
      _clawHubReviewingSlug = null;
      _clawHubInstallReview = review;
      _clawHubError = review == null
          ? 'ClawHub 没有为 $reference 返回可安装的版本'
          : null;
      return review != null;
    } catch (error) {
      if (reviewSeq != _clawHubReviewSeq) return false;
      _clawHubReviewingSlug = null;
      _clawHubError = '加载 $reference 的 ClawHub 详情失败：$error';
      return false;
    } finally {
      if (reviewSeq == _clawHubReviewSeq) notifyListeners();
    }
  }

  /// 关掉待确认的安装（弹窗「取消」）。
  ///
  /// 同时自增审核序号：在途的详情响应落地时会被丢弃，不会又把弹窗顶回来。
  void dismissClawHubSkillInstallReview() {
    _clawHubReviewSeq++;
    _clawHubReviewingSlug = null;
    _clawHubInstallReview = null;
    notifyListeners();
  }

  /// 安装一条 ClawHub 搜索结果，成功后刷新 Skill 列表。
  ///
  /// 对应 Android `installClawHubSkillFromGateway`。入参是审核确认过的
  /// `slug` + `version` —— 装的必须就是审核时看到的那个版本。
  ///
  /// 失败路径都先回读一次列表再定性：超时或被拒时网关其实可能已经装上了，
  /// 直接报「失败」会让用户重复安装。
  Future<bool> installClawHubSkillFromGateway({
    required String slug,
    String? version,
  }) async {
    final normalized = slug.trim();
    if (normalized.isEmpty) return false;
    if (!_connected) {
      _clawHubError = '请先连接网关，再安装 ClawHub 技能';
      notifyListeners();
      return false;
    }
    if (!clawHubSkillsAvailable) {
      _clawHubError = '当前网关不支持 ClawHub 技能搜索，请升级 Gateway 后重试';
      notifyListeners();
      return false;
    }
    if (!clawHubCanInstall) {
      _clawHubError = '当前连接缺少 operator.admin 权限，无法安装 ClawHub 技能';
      notifyListeners();
      return false;
    }
    // 同一条结果重复点击直接吞掉，别打两次网关。
    if (!_clawHubInstallingSlugs.add(normalized)) return false;
    final trimmedVersion = version?.trim();
    final attemptedVersion = (trimmedVersion == null || trimmedVersion.isEmpty)
        ? null
        : trimmedVersion;
    _clawHubInstallReview = null;
    _clawHubError = null;
    _clawHubMessage = null;
    notifyListeners();
    try {
      final response = await _runtime.skillsInstallFromClawHub(
        slug: normalized,
        version: attemptedVersion,
      );
      final refreshed = await _refreshSkillsQuietly();
      _clawHubMessage = _formatClawHubInstallMessage(
        _nonEmptyText(response['message']) ?? '已安装 $normalized',
        [
          _nonEmptyText(response['warning']),
          if (!refreshed) '已安装，但技能列表刷新失败，请下拉刷新',
        ].whereType<String>().join('\n'),
      );
      return true;
    } on TimeoutException {
      if (await _refreshAndConfirmClawHubInstall(normalized, attemptedVersion)) {
        _clawHubMessage = '已安装 $normalized';
        return true;
      }
      _clawHubError =
          '$normalized 的安装结果未知。请重新连接、刷新技能列表后重试；'
          '网关会安全地接续仍在进行的同一次安装。';
      return false;
    } on GatewayResponseError catch (error) {
      if (await _refreshAndConfirmClawHubInstall(normalized, attemptedVersion)) {
        _clawHubMessage = '已安装 $normalized';
        return true;
      }
      _clawHubError = _formatClawHubInstallMessage(
        _nonEmptyText(error.message) ?? '网关拒绝了这个 ClawHub 安装请求',
        _nonEmptyText(error.details['clawhubWarning']),
      );
      return false;
    } catch (error) {
      _clawHubError = '从 ClawHub 安装 $normalized 失败：$error';
      return false;
    } finally {
      _clawHubInstallingSlugs.remove(normalized);
      notifyListeners();
    }
  }

  /// 回读列表并确认安装结果。
  ///
  /// 带版本时要求引用与版本都对上；不带版本说明来源是「只能直接安装」的，
  /// 只能按网关记录的原始引用比对。
  Future<bool> _refreshAndConfirmClawHubInstall(
    String slug,
    String? version,
  ) async {
    if (!await _refreshSkillsQuietly()) return false;
    final skills = _skills;
    if (version != null) {
      return isClawHubSkillInstalledAtVersion(skills, slug, version);
    }
    return isClawHubSkillInstalledByReference(skills, slug);
  }

  /// 重新拉取 Skill 列表；失败返回 false，不写 [_skillsError]（调用方自己决定文案）。
  Future<bool> _refreshSkillsQuietly() async {
    try {
      await _reloadSkills();
      return true;
    } catch (_) {
      return false;
    }
  }

  static String? _nonEmptyText(Object? value) {
    final text = value?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  static String _formatClawHubInstallMessage(
    String message,
    String? warning,
  ) => (warning == null || warning.isEmpty) ? message : '$message\n\n$warning';

  // ==================== Cron 管理 ====================
  //
  // 与 Skill 同一套分层：状态与操作在仓库，CronViewModel 只做转发。

  List<GatewayCronJob> _cronJobs = const [];

  /// 当前网关上的定时任务列表。
  List<GatewayCronJob> get cronJobs => List.unmodifiable(_cronJobs);

  List<Map<String, dynamic>> _cronRuns = const [];

  /// 最近一次 [loadCronRuns] 拉取到的运行记录。
  List<Map<String, dynamic>> get cronRuns => List.unmodifiable(_cronRuns);

  bool _cronLoading = false;

  /// Cron 列表加载或任务操作是否进行中（用于去重与 loading 态）。
  bool get cronLoading => _cronLoading;

  String? _cronError;

  /// 最近一次 Cron 操作失败的原因。
  String? get cronError => _cronError;

  String? _lastCronOperation;

  /// 最近一次成功的 Cron 操作名（run / add / update / remove）。
  String? get lastCronOperation => _lastCronOperation;

  /// 拉取定时任务列表。已在进行中时直接返回 false。
  Future<bool> loadCronJobs({bool includeDisabled = true}) async {
    if (_cronLoading) return false;
    _cronLoading = true;
    _cronError = null;
    notifyListeners();
    try {
      _cronJobs =
          GatewayCronList.fromJson(
            await _runtime.cronList(includeDisabled: includeDisabled),
          ).jobs;
      return true;
    } catch (error) {
      _cronError = error.toString();
      return false;
    } finally {
      _cronLoading = false;
      notifyListeners();
    }
  }

  /// 拉取某个任务的运行记录。已在进行中时直接返回 false。
  Future<bool> loadCronRuns(String jobId, {int limit = 200}) async {
    if (_cronLoading) return false;
    _cronLoading = true;
    _cronError = null;
    notifyListeners();
    try {
      _cronRuns =
          GatewayCronRuns.fromJson(
            await _runtime.cronRuns(id: jobId, limit: limit),
          ).entries;
      return true;
    } catch (error) {
      _cronError = error.toString();
      return false;
    } finally {
      _cronLoading = false;
      notifyListeners();
    }
  }

  /// 立即执行一次任务（不改变任务配置，因此不刷新列表）。
  Future<bool> runCronJob(String jobId, {bool force = true}) =>
      _runCronOperation('run', () async {
        await _runtime.cronRun(id: jobId, force: force);
      });

  Future<bool> addCronJob(Map<String, dynamic> payload) =>
      _runCronOperation('add', () async {
        await _runtime.cronAdd(payload: payload);
        await _reloadCronJobs();
      });

  Future<bool> updateCronJob(String jobId, Map<String, dynamic> patch) =>
      _runCronOperation('update', () async {
        await _runtime.cronUpdate(id: jobId, patch: patch);
        await _reloadCronJobs();
      });

  /// 删除任务：本地直接摘掉对应条目，避免多打一次列表请求。
  Future<bool> removeCronJob(String jobId) =>
      _runCronOperation('remove', () async {
        await _runtime.cronRemove(id: jobId);
        _cronJobs = _cronJobs
            .where((job) => job.id != jobId.trim())
            .toList(growable: false);
      });

  Future<void> _reloadCronJobs() async {
    _cronJobs = GatewayCronList.fromJson(await _runtime.cronList()).jobs;
  }

  Future<bool> _runCronOperation(
    String operation,
    Future<void> Function() action,
  ) async {
    if (_cronLoading) return false;
    _cronLoading = true;
    _cronError = null;
    _lastCronOperation = null;
    notifyListeners();
    try {
      await action();
      _lastCronOperation = operation;
      return true;
    } catch (error) {
      _cronError = error.toString();
      return false;
    } finally {
      _cronLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _serverRepository.removeListener(_onServerChanged); // 🌟 修复点 6：反注册监听器
    _runtimeSub?.cancel();
    _runtimeStateSub?.cancel();
    // OpenClawRuntime 是进程级共享单例（Skill / Cron 等 ViewModel 也在用），
    // 这里只能解除订阅，不能 dispose：否则会把共享会话一起关掉，并把
    // session 的 _shouldReconnect 置为 false，导致之后网关重启再也不自动重连。
    messageController.close();
    sessionUpdateController.close();
    messageFinalController.close();
    voiceController.close();
    _sessionMessageController.close();
    super.dispose();
  }
}

class _StreamingMessageState {
  final String id;
  final String text;

  const _StreamingMessageState({required this.id, required this.text});

  _StreamingMessageState copyWith({String? text}) {
    return _StreamingMessageState(id: id, text: text ?? this.text);
  }
}
