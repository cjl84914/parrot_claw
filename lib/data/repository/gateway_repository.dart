import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:parrot_app/data/model/gateway_cron.dart';
import 'package:parrot_app/data/model/gateway_session_models.dart';
import 'package:parrot_app/data/model/gateway_skill.dart';
import 'package:parrot_app/data/model/message.dart';
import 'package:parrot_app/data/model/session_message.dart';
import 'package:parrot_app/data/service/gateway_connector.dart';
import 'package:parrot_app/data/service/openclaw_protocol.dart';
import 'package:parrot_app/util/parse.dart';
import 'package:parrot_app/util/string_util.dart';
import 'package:uuid/uuid.dart';

class GatewayRepository extends ChangeNotifier {
  final Logger _log = Logger('GatewayRepository');
  var uuid = const Uuid();

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

  final StreamController<GatewayPush> _pushes =
  StreamController<GatewayPush>.broadcast();

  /// 会话的原始推送流（snapshot / event）。
  ///
  /// 供需要自行等待某个网关事件的调用方使用 —— 例如引导页要等模型验证的
  /// `chat` final 事件，而它用的 idempotencyKey 不是本仓库的 `_runId`，
  /// 所以走不了 [pendingRunEvents]。日常 UI 状态请优先用具名事件流。
  Stream<GatewayPush> get pushes => _pushes.stream;

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

  String _runId = '';

  String get runId => _runId;

  // A run can contain multiple assistant replies. Keep a client-side ID for
  // the current cumulative streaming reply so later replies are appended.
  final Map<String, _StreamingMessageState> _streamingMessages = {};

  final bool _talkMode = false;

  bool get talkMode => _talkMode;

  /// 会话工厂：默认走真实 WebSocket，测试在这里注入假会话。
  final GatewaySessionFactory _sessionFactory;

  /// 当前正在使用的会话。
  ///
  /// 由本仓库直接持有并管理 —— 没有中间的 runtime 层，也没有进程级单例。
  /// 断线自愈完全交给 `GatewaySession` 自己的退避重连 + tick 看门狗，
  /// 仓库只负责把状态翻译给 UI。
  GatewaySession? _session;

  /// 正在握手、尚未接管的候选会话（见 [_ensureSession] 的「先连后拆」）。
  ///
  /// 它只在一次 [_ensureSession] 调用内存在，用来把「新配置能不能连上」和
  /// 「拆掉旧会话」分开，避免失败的新配置把可用的旧连接一起带走。
  GatewaySession? _pendingSession;

  /// 当前会话对应的连接配置，用于判断「是否同一配置」。
  GatewayConnectConfig? _gatewayConfig;

  /// 最近一次握手的 hello。
  ///
  /// `clawHubCanInstall` / `clawHubSkillsAvailable` 依赖它，而 `GatewaySession`
  /// 不暴露 `HelloOk`，所以在快照推送时自己缓存一份。
  HelloOk? _hello;

  /// 会话是否应当保持存活；手动断开时置 false。
  bool _shouldRun = false;

  String? disconnectReason;

  GatewayRepository({
    GatewaySessionFactory? sessionFactory,
  }) :
        _sessionFactory = sessionFactory ?? defaultGatewaySessionFactory{

  }


  void _onServerChanged() {
    _log.info('Server configuration changed, auto connecting...');
    reconnect(); // 自动调用连接
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
  Future<void> connect(GatewayConnectConfig config) async {
    if (_connected && _gatewayConfig == config) {
      return;
    }
    await _doConnect(config);
  }

  Future<void> _doConnect(GatewayConnectConfig config, {
    bool reconnecting = false,
  }) async {
    _manualDisconnect = false;
    // 这里**不能**先把 `_gatewayConfig` 改成新配置：`_ensureSession` 就是靠
    // 「当前配置 == 目标配置吗」来判断「直接复用会话」还是「先建候选会话再拆
    // 旧的」。提前覆盖等于把每次切换都伪装成「同一个配置」，候选会话那条路
    // 永远走不到，切网关会变成在旧地址上重连。配置由 `_ensureSession` 在
    // 真正接管会话时才落库。
    _isConnecting = true;
    _connected = false;
    _isReconnecting = reconnecting;
    disconnectReason = reconnecting ? '正在重新连接网关…' : null;
    _runId = '';
    // _log.info('Switching to server: ${config.clientDisplayName}');

    try {
      notifyListeners();
      await _ensureSession(config);
      // _ensureSession() 只在认证握手完成后才返回。
      // 用它兜底：快照可能在本监听器挂上之前就推完了，或者快照里的 health
      // 载荷是另一种形状。
      if (!_connected && identical(_gatewayConfig, config)) {
        _markConnected(null);
      }
    } catch (e) {
      _log.warning('Connect failed in ViewModel: $e');
      // if (_session?.connected ?? false) {
        // 旧会话仍然健康：这次切换失败不该让 UI 掉到「未连接」——
        // 连接其实还在，只是新目标没连上。
        _isConnecting = false;
        _isReconnecting = false;
        _connected = true;
        disconnectReason = null;
        notifyListeners();
      // }
    }
  }

  /// 确保有一条连到 [config] 的可用会话。
  ///
  /// 三条路径：
  /// - 已经是同一配置 → 直接让现有会话重连（幂等，可反复调用）；
  /// - 换了配置 → 先建候选会话并完成握手，**成功后才**拆掉旧会话；
  /// - 握手失败 → 有健康旧会话就丢弃候选、什么都不动；否则把新配置落成
  ///   当前配置，交给候选会话自己的退避重连继续重试。
  Future<void> _ensureSession(GatewayConnectConfig config) async {
    _shouldRun = true;
    final current = _session;
    if (_gatewayConfig == config && current != null) {
      await current.connect();
      return;
    }

    late final GatewaySession candidate;
    candidate = _sessionFactory(
      config: config,
      onPush: (push) {
        if (_acceptsPush(candidate)) {
          _handlePush(push, pending: identical(_pendingSession, candidate));
        }
      },
      onDisconnect: (reason) {
        if (_acceptsDisconnect(candidate)) _handleDisconnect(reason);
      },
    );

    // 旧会话健康时才需要保护它：此时切换全程对外保持「已连接」。
    final protected = current != null && current.connected;
    _pendingSession = candidate;
    try {
      await candidate.connect();
    } catch (error) {
      _pendingSession = null;
      if (protected) {
        // 旧会话仍然可用：丢弃候选，配置 / 状态 / 自动重连全都不动。
        await _retireSession(candidate);
      } else {
        // 没有可用的旧会话（冷启动，或旧会话已断）：把新目标落成当前配置。
        // 候选会话在自己的 connect() 失败分支里已经排好了退避重连，所以这里
        // 只能接管它，**不能**把它拆掉，否则重试循环就没了。
        await _retireSession(current);
        _session = candidate;
        _gatewayConfig = config;
        _hello = null;
      }
      rethrow;
    }
    _pendingSession = null;

    if (!_shouldRun) {
      // 握手期间有人调用了 disconnect()/dispose()：不要在这里复活会话。
      await _retireSession(candidate);
      return;
    }

    // 握手成功后才切换：先换引用，再拆旧会话。反过来会让旧会话的 shutdown
    // 波及刚装上的新会话。
    _session = candidate;
    _gatewayConfig = config;
    if (current != null && !identical(current, candidate)) {
      await _retireSession(current);
    }
  }

  /// 构造连接某个网关所需的运行时配置。
  ///
  /// scopes 的决策只在这里做一次：扫码配对（受限 operator）加入的网关要复用
  /// 配对时实际授权的 scopes，否则按默认全量（含 admin/pairing）请求会触发
  /// scope-upgrade 审批。探测与正式连接共用它，"探测通过"才等于"连得上"。
  // Future<GatewayConnectConfig> _connectConfigFor(ServerConfig config) async {
  //   final storedScopes = await GatewayScopeStore.operatorScopes(config.wsUrl);
  //   return GatewayConnectConfig(
  //     url: config.wsUrl,
  //     token: config.isTokenAuth ? config.token : null,
  //     password: config.isPasswordAuth ? config.password : null,
  //     scopes: storedScopes ?? openClawOperatorScopes,
  //   );
  // }

  /// 用一条用完即弃的会话试连，**不会**触碰本仓库正在使用的会话。
  ///
  /// 见 [probeGateway]：探测与正式连接共用同一套 scopes 决策。
  Future<GatewayOperationResult<HelloOk>> probeServer(
      GatewayConnectConfig config,) async {
    final result = await probeGateway(config);
    if (!result.ok) {
      _log.warning('Gateway probe failed: ${result.error}');
    }
    return result;
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
    if (!(_session?.connected ?? false)) return;
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
      _sessionKey ??= await mainSessionKey();
      await beginHistoryLoad();
    } catch (error) {
      _log.warning('Failed to initialize main session: $error');
    }
  }

  // String buildMediaUrl(String sourcePath) {
  //   final encodedPath = Uri.encodeComponent(sourcePath);
  //   final url = '${_gatewayConfig!
  //       .url}/__openclaw__/assistant-media?token=${_gatewayConfig!
  //       .token}&source=$encodedPath';
  //   _log.info(url);
  //   return url;
  // }


  /// 处理来自会话的推送。
  ///
  /// [pending] 为 true 表示这条推送来自尚未接管的候选会话：只缓存 hello，
  /// 不上报「已连接」。否则切换网关时候选会话一握手成功就会触发
  /// `listSessions()`，而那一刻 `_session` 还指着旧会话，请求会打到错的地方。
  void _handlePush(GatewayPush push, {bool pending = false}) {
    if (push is GatewayPushSnapshot) {
      _hello = push.snapshot;
      if (!pending) _markConnected(push.snapshot.snapshot.health);
    } else if (push is GatewayPushEvent) {
      _handleGatewayEvent(push.event, push.payload);
    }
    if (!_pushes.isClosed) _pushes.add(push);
  }

  /// 会话掉线：UI 进入「正在自动重连」。
  ///
  /// 重连本身不在这里操心 —— `GatewaySession` 的退避循环与 tick 看门狗会自己
  /// 把连接拉回来，成功时推一份 snapshot，[_handlePush] 随即把状态翻回已连接。
  void _handleDisconnect(String reason) {
    if (_manualDisconnect) return;
    final wasConnected = _connected || _isConnecting;
    _isConnecting = false;
    _isReconnecting = true;
    _connected = false;
    if (wasConnected) {
      _sessionKey = null;
      _sessions = [];
    }
    disconnectReason = '与网关的连接已断开，正在自动重连…';
    _log.warning('Gateway session disconnected: $reason');
    notifyListeners();
  }

  /// 候选会话在接管之前也允许推送：握手时的那份 snapshot 正是 hello 的来源。
  bool _acceptsPush(GatewaySession session) =>
      identical(_session, session) || identical(_pendingSession, session);

  /// 只有当前会话的断开才算故障。
  ///
  /// 候选会话握手失败由 [_ensureSession] 的异常路径处理，不能被当成「连接断了」
  /// 上报给 UI —— 那正是「测试连接失败连累默认网关」的成因。
  bool _acceptsDisconnect(GatewaySession session) =>
      identical(_session, session);

  /// 拆掉一条已不属于本仓库的会话。
  ///
  /// 退役失败不能影响刚建立的新连接，所以这里只记日志。
  Future<void> _retireSession(GatewaySession? session) async {
    if (session == null) return;
    try {
      await session.shutdown();
    } catch (error) {
      _log.warning('Retiring superseded gateway session failed: $error');
    }
  }

  /// 关掉当前会话并清空连接状态（主动断开 / 释放仓库时用）。
  Future<void> _shutdownSession() async {
    final session = _session;
    _session = null;
    _pendingSession = null;
    _gatewayConfig = null;
    _hello = null;
    if (session == null) return;
    try {
      await session.shutdown();
    } catch (error) {
      _log.warning('Shutting down gateway session failed: $error');
    }
  }

  // ==================== 会话请求通道 ====================
  //
  // 这一层刻意保持「薄」：不再为每个网关方法写一个命名包装。原先 runtime 层
  // 有 41 个这样的包装，而本仓库又把它们逐个包了一遍 —— 同一件事写两遍。
  // 现在调用方直接按方法名请求，由 OpenClawProtocolCatalog 兜住拼写错误。

  /// 向当前会话发起一次协议请求。
  ///
  /// 不在协议目录里的方法名会被本地拒绝，避免把拼错的请求打到网关。
  Future<Map<String, dynamic>> requestKnown(String method, {
    Map<String, dynamic>? params,
    Duration? timeout,
  }) {
    if (!OpenClawProtocolCatalog.supportsMethod(method)) {
      throw ArgumentError.value(
        method,
        'method',
        'Not in the OpenClaw protocol catalog',
      );
    }
    return _request(method, params: params, timeout: timeout);
  }

  Future<Map<String, dynamic>> _request(String method, {
    Map<String, dynamic>? params,
    Duration? timeout,
  }) {
    final session = _session;
    if (session == null) {
      throw StateError('OpenClaw Gateway is not configured');
    }
    return session.request(method: method, params: params, timeout: timeout);
  }

  /// 当前主会话的 key（`session.scope` 为 `global` 时是 `global`）。
  ///
  /// 优先用握手快照里的默认值，缺失时才回读一次 config。
  Future<String> mainSessionKey({Duration? timeout}) async {
    final cached =
    _hello?.snapshot.sessiondefaults?['mainSessionKey']?.toString();
    if (cached != null && cached
        .trim()
        .isNotEmpty) return cached;
    final data = await requestKnown('config.get', timeout: timeout);
    final scope = ((data['config'] as Map?)?['session'] as Map?)?['scope'];
    return scope?.toString().trim() == 'global' ? 'global' : 'main';
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
    final Map<String, dynamic> json = await requestKnown(
      'chat.history',
      params: {'sessionKey': sessionKey!},
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
                'msg_${DateTime
                    .now()
                    .microsecondsSinceEpoch}';
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

  /// 主动断开：关闭会话并停止自动重连。
  ///
  /// 与 [dispose] 的区别：这里只影响连接，不影响仓库自身；
  /// 之后任何 [connect] / [reconnect] 都能重新建立会话。
  Future<void> disconnect() async {
    _log.info('Disconnecting  server');
    _manualDisconnect = true;
    _sessionKey = null;
    _sessions = [];
    _connected = false;
    _isConnecting = false;
    _isReconnecting = false;
    disconnectReason = null;
    notifyListeners();
    await _shutdownSession();
  }

  /// 手动重连：走一次完整的连接，成功后 UI 会立刻恢复。
  ///
  /// 与 [connect] 的区别只是语义（带"正在重连"状态 + 失败原因），
  /// 底层复用同一条会话，因此不会额外建第二条连接。
  Future<void> reconnect() async {
    try {
      await _doConnect(_gatewayConfig!, reconnecting: true);
    } catch (error) {
      _log.warning('Manual reconnect failed: $error');
    }
    if (_connected) return;
    _isReconnecting = false;
    _isConnecting = false;
    disconnectReason ??= '重连失败，请确认 OpenClaw Gateway 正在运行';
    notifyListeners();
  }

  Future<void> sendChatMessage(String text, {
    List<OutgoingAttachment> attachments = const [],
  }) async {
    _log.info('sendMessage: $text');
    final message = text.trim();
    if (message.isEmpty && attachments.isEmpty) {
      return;
    }
    _runId =
    'chat_${DateTime
        .now()
        .millisecondsSinceEpoch}_${uuid.v4().substring(0, 8)}'; // 1. 准备数据
    notifyListeners();
    if (attachments.isEmpty) {
      // 2. 乐观更新：创建并显示用户消息
      final userMessage = ChatMessage(
        id: uuid.v4(),
        role: 'user',
        content: [ChatMessageContent(type: 'text', text: message)],
        timestamp: DateTime
            .now()
            .millisecondsSinceEpoch,
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
          timestamp: DateTime
              .now()
              .millisecondsSinceEpoch,
          idempotencyKey: _runId,
        );
        messageController.add(userMessage);
      }
    }

    final resolvedSessionKey = sessionKey ?? await mainSessionKey();
    _sessionKey = resolvedSessionKey;
    try {
      await requestKnown(
        'chat.send',
        params: {
          'sessionKey': resolvedSessionKey,
          'message': message,
          'idempotencyKey': _runId,
          if (attachments.isNotEmpty)
            'attachments':
            attachments
                .map(
                  (a) =>
              {
                'type': a.type,
                'content': a.base64,
                'mimeType': a.mimeType,
                'fileName': a.fileName,
              },
            )
                .toList(),
        },
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
    await requestKnown('talk.mode', params: {'enabled': talkMode});
  }

  Future<void> sendTalkSpeak(String text) async {
    if (text.isEmpty) {
      return;
    }
    final Map<String, dynamic> payload = await requestKnown(
      'talk.speak',
      params: {'text': text},
    );
    if (payload.containsKey('audioBase64')) {
      voiceController.add(payload['audioBase64']);
    }
  }

  Future<void> abortMessage() async {
    if (_runId != '') {
      await requestKnown(
        'chat.abort',
        params: {'sessionKey': sessionKey!, 'runId': _runId},
      );
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
      await requestKnown(
        'sessions.list',
        params: {
          'includeGlobal': includeGlobal,
          'includeUnknown': includeUnknown,
          if (limit != null) 'limit': limit,
          if (search
              ?.trim()
              .isNotEmpty == true) 'search': search!.trim(),
          if (archived) 'archived': true,
          if (agentId
              ?.trim()
              .isNotEmpty == true) 'agentId': agentId!.trim(),
          if (activeMinutes != null) 'activeMinutes': activeMinutes,
          if (spawnedBy
              ?.trim()
              .isNotEmpty == true)
            'spawnedBy': spawnedBy!.trim(),
          if (offset != null) 'offset': offset,
          if (configuredAgentsOnly != null)
            'configuredAgentsOnly': configuredAgentsOnly,
        },
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
      await requestKnown(
        'sessions.create',
        params: {
          'key': key,
          if (agentId
              ?.trim()
              .isNotEmpty == true) 'agentId': agentId!.trim(),
          if (label != null) 'label': label,
          if (parentSessionKey != null) 'parentSessionKey': parentSessionKey,
          if (worktree != null) 'worktree': worktree,
          if (worktreeBaseRef
              ?.trim()
              .isNotEmpty == true)
            'worktreeBaseRef': worktreeBaseRef!.trim(),
        },
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
    final success = await _patchSessionLabel(
      sessionKey: sessionKey,
      agentId: agentId ?? session?.agentId,
      label: normalizedLabel,
    );
    if (!success) {
      throw StateError('更新会话标签失败');
    }
    await listSessions();
  }

  /// 写入会话标签。
  ///
  /// 失败只记日志并返回 false，由调用方决定文案 —— 会话标签是「尽力而为」的
  /// 元数据，不值得为它中断上层流程。
  Future<bool> _patchSessionLabel({
    required String sessionKey,
    required String label,
    String? agentId,
  }) async {
    try {
      await requestKnown(
        'sessions.patch',
        params: {
          'key': sessionKey,
          if (agentId
              ?.trim()
              .isNotEmpty == true) 'agentId': agentId!.trim(),
          'label': label,
        },
      );
      return true;
    } catch (error) {
      _log.warning('patchSession failed: $error');
      return false;
    }
  }

  /// 删除会话及其 transcript，并清理本地状态。
  Future<void> deleteSession({
    required String sessionKey,
    String? agentId,
  }) async {
    await requestKnown(
      'sessions.delete',
      params: {
        'key': sessionKey,
        if (agentId
            ?.trim()
            .isNotEmpty == true) 'agentId': agentId!.trim(),
        'deleteTranscript': true,
      },
    );
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
              final fileName = url
                  .split('/')
                  .last;
              final String type = _mediaType(url);
              contentList.add(
                ChatMessageContent(
                  type: type,
                  text: url,
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
            base64: b64
                .trim()
                .isEmpty ? null : b64,
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
            final fileName = mediaUrl
                .split('/')
                .last;
            final type = _mediaType(mediaUrl);
            final message = ChatMessage(
              id: uuid.v4(),
              role: 'assistant',
              content: [
                ChatMessageContent(
                  type: type,
                  text: mediaUrl,
                  fileName: fileName,
                ),
              ],
              timestamp: DateTime
                  .now()
                  .millisecondsSinceEpoch,
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
    final extension = '.${mediaUrl
        .split('.')
        .last
        .toLowerCase()}';
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
      timestamp: DateTime
          .now()
          .millisecondsSinceEpoch,
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
      final data = await requestKnown('models.list');
      _rawModels = data['models'] as List? ?? const [];
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
      final Map<String, dynamic> json = await requestKnown(
        'sessions.patch',
        params: {'key': _sessionKey!, ...patch},
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
    // 注意：这里把 publicUrl 真的透传下去了。原实现声明了这个入参却直接丢弃，
    // 属于「签名承诺了、实现没做」——调用方目前都不传，所以行为不变。
    return OpenClawDevicePairSetupCodeResponse.fromJson(
      await requestKnown(
        'device.pair.setupCode',
        params: {
          if (publicUrl
              ?.trim()
              .isNotEmpty == true)
            'publicUrl': publicUrl!.trim(),
          'includeQr': true,
        },
        timeout: const Duration(seconds: 15),
      ),
    );
  }

  // 说明：上层只通过带状态的方法访问网关（listSessions / createSession /
  // updateSessionLabel / deleteSession / setSessionConfig / abortMessage 等）。
  // 需要新能力时，请在仓库里按「请求 + 解析 + 更新状态 + notifyListeners」的
  // 模式新增，而不要再为每个网关方法加一层纯转发包装 —— 那正是刚被删掉的
  // runtime 层做过的事。

  // ==================== Skill 管理 ====================
  //
  // Skill 的状态与操作都收敛在这里（复用本仓库持有的会话），
  // SkillViewModel 只做转发，不再自己持有状态或直连连接。

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
      final normalizedName = name.trim();
      final normalizedInstallId = installId.trim();
      if (normalizedName.isEmpty) {
        throw ArgumentError.value(name, 'name', 'Skill 名称不能为空');
      }
      if (normalizedInstallId.isEmpty) {
        throw ArgumentError.value(installId, 'installId', '安装方式不能为空');
      }
      await requestKnown(
        'skills.install',
        params: {
          'name': normalizedName,
          'installId': normalizedInstallId,
          if (dangerouslyForceUnsafeInstall != null)
            'dangerouslyForceUnsafeInstall': dangerouslyForceUnsafeInstall,
        },
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
      final normalizedKey = skillKey.trim();
      if (normalizedKey.isEmpty) {
        throw ArgumentError.value(skillKey, 'skillKey', 'Skill 标识不能为空');
      }
      await requestKnown(
        'skills.update',
        params: {
          'skillKey': normalizedKey,
          if (enabled != null) 'enabled': enabled,
          if (apiKey != null) 'apiKey': apiKey,
          if (env != null && env.isNotEmpty) 'env': env,
        },
      );
      await _reloadSkills();
    });
  }

  Future<void> _reloadSkills() async {
    _skills =
        GatewaySkillsStatus
            .fromJson(
          await requestKnown('skills.status'),
        )
            .skills;
  }

  Future<bool> _runSkillOperation(String operation,
      Future<void> Function() action,) async {
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
    final scopes = _hello?.auth['scopes'];
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
    final methods = _hello?.features['methods'];
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
      final response = await requestKnown(
        'skills.search',
        params: {
          if (normalized.isNotEmpty) 'query': normalized,
          'limit': 25,
        },
      );
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
      GatewayClawHubSkillSummary skill,) async {
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
      final response = await requestKnown(
        'skills.detail',
        params: {'slug': reference},
      );
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
      // 与「网关自带安装方式」不是同一个入参形态：这条按 ClawHub 引用装，
      // 并且要指定具体版本，让网关校验的就是「审核时看到的那个版本」。
      // 安装可能等很久（下载 + 校验），所以给 125s 超时。
      final response = await requestKnown(
        'skills.install',
        params: {
          'source': 'clawhub',
          'slug': normalized,
          if (attemptedVersion != null) 'version': attemptedVersion,
          'timeoutMs': 120000,
        },
        timeout: const Duration(milliseconds: 125000),
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
      if (await _refreshAndConfirmClawHubInstall(
          normalized, attemptedVersion)) {
        _clawHubMessage = '已安装 $normalized';
        return true;
      }
      _clawHubError =
      '$normalized 的安装结果未知。请重新连接、刷新技能列表后重试；'
          '网关会安全地接续仍在进行的同一次安装。';
      return false;
    } on GatewayResponseError catch (error) {
      if (await _refreshAndConfirmClawHubInstall(
          normalized, attemptedVersion)) {
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
  Future<bool> _refreshAndConfirmClawHubInstall(String slug,
      String? version,) async {
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

  static String _formatClawHubInstallMessage(String message,
      String? warning,) =>
      (warning == null || warning.isEmpty) ? message : '$message\n\n$warning';

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
          GatewayCronList
              .fromJson(
            await requestKnown(
              'cron.list',
              params: {'includeDisabled': includeDisabled},
            ),
          )
              .jobs;
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
          GatewayCronRuns
              .fromJson(
            await requestKnown(
              'cron.runs',
              params: {'id': _requireJobId(jobId), 'limit': limit},
            ),
          )
              .entries;
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
        await requestKnown(
          'cron.run',
          params: {'id': _requireJobId(jobId), 'force': force},
        );
      });

  Future<bool> addCronJob(Map<String, dynamic> payload) =>
      _runCronOperation('add', () async {
        if (payload.isEmpty) {
          throw ArgumentError.value(payload, 'payload', '任务参数不能为空');
        }
        await requestKnown('cron.add', params: payload);
        await _reloadCronJobs();
      });

  Future<bool> updateCronJob(String jobId, Map<String, dynamic> patch) =>
      _runCronOperation('update', () async {
        if (patch.isEmpty) {
          throw ArgumentError.value(patch, 'patch', '更新内容不能为空');
        }
        await requestKnown(
          'cron.update',
          params: {'id': _requireJobId(jobId), 'patch': patch},
        );
        await _reloadCronJobs();
      });

  /// 删除任务：本地直接摘掉对应条目，避免多打一次列表请求。
  Future<bool> removeCronJob(String jobId) =>
      _runCronOperation('remove', () async {
        await requestKnown(
          'cron.remove',
          params: {'id': _requireJobId(jobId)},
        );
        _cronJobs = _cronJobs
            .where((job) => job.id != jobId.trim())
            .toList(growable: false);
      });

  Future<void> _reloadCronJobs() async {
    _cronJobs = GatewayCronList
        .fromJson(
      await requestKnown('cron.list'),
    )
        .jobs;
  }

  /// 任务 ID 不能为空 —— 空 ID 打到网关只会换来一个含糊的服务端错误。
  static String _requireJobId(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(id, 'id', '任务 ID 不能为空');
    }
    return normalized;
  }

  Future<bool> _runCronOperation(String operation,
      Future<void> Function() action,) async {
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
    // GatewaySession.shutdown() 会把它的 _shouldReconnect 一起停掉，
    // 否则退避重连会留着一个已经没人消费的连接继续重试。
    _shouldRun = false;
    unawaited(_shutdownSession());
    messageController.close();
    sessionUpdateController.close();
    messageFinalController.close();
    voiceController.close();
    _pushes.close();
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
