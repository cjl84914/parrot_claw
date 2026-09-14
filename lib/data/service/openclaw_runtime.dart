import 'dart:async';
import 'package:logging/logging.dart';
import 'package:parrot_app/data/service/gateway_session.dart';
import 'openclaw_protocol.dart';
export 'package:parrot_app/data/service/gateway_session.dart';

final _openClawLog = Logger('OpenClawRuntime');

/// Operator scopes used by the OpenClaw Android companion client.
const openClawOperatorScopes = <String>[
  'operator.admin',
  'operator.approvals',
  'operator.questions',
  'operator.read',
  'operator.talk.secrets',
  'operator.write',
];

/// Immutable connection settings for one operator session.
class OpenClawRuntimeConfig {
  final String url;
  final String? token;
  final String? password;
  final String? bootstrapToken;
  final String clientId;
  final String clientMode;
  final String role;
  final List<String> scopes;
  final List<String> caps;
  final List<String> commands;
  final Map<String, bool> permissions;
  final String? clientDisplayName;

  const OpenClawRuntimeConfig({
    required this.url,
    this.token,
    this.password,
    this.bootstrapToken,
    this.clientId = 'openclaw-android',
    this.clientMode = 'ui',
    this.role = 'operator',
    this.scopes = openClawOperatorScopes,
    this.caps = const <String>[],
    this.commands = const <String>[],
    this.permissions = const <String, bool>{},
    this.clientDisplayName = 'ParrotClaw',
  });

  GatewayConnectOptions toGatewayOptions() => GatewayConnectOptions(
    role: role,
    scopes: scopes,
    scopesAreExplicit: true,
    caps: caps,
    commands: commands,
    permissions: permissions,
    clientId: clientId,
    clientMode: clientMode,
    clientDisplayName: clientDisplayName,
  );

  OpenClawRuntimeConfig copyWith({
    String? url,
    String? token,
    String? password,
    String? bootstrapToken,
    String? clientId,
    String? clientMode,
    String? role,
    List<String>? scopes,
    List<String>? caps,
    List<String>? commands,
    Map<String, bool>? permissions,
    String? clientDisplayName,
  }) {
    return OpenClawRuntimeConfig(
      url: url ?? this.url,
      token: token ?? this.token,
      password: password ?? this.password,
      bootstrapToken: bootstrapToken ?? this.bootstrapToken,
      clientId: clientId ?? this.clientId,
      clientMode: clientMode ?? this.clientMode,
      role: role ?? this.role,
      scopes: scopes ?? this.scopes,
      caps: caps ?? this.caps,
      commands: commands ?? this.commands,
      permissions: permissions ?? this.permissions,
      clientDisplayName: clientDisplayName ?? this.clientDisplayName,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OpenClawRuntimeConfig &&
      other.url == url &&
      other.token == token &&
      other.password == password &&
      other.bootstrapToken == bootstrapToken &&
      other.clientId == clientId &&
      other.clientMode == clientMode &&
      other.role == role &&
      _listEquals(other.scopes, scopes) &&
      _listEquals(other.caps, caps) &&
      _listEquals(other.commands, commands) &&
      _mapEquals(other.permissions, permissions) &&
      other.clientDisplayName == clientDisplayName;

  @override
  int get hashCode => Object.hash(
    url,
    token,
    password,
    bootstrapToken,
    clientId,
    clientMode,
    role,
    Object.hashAll(scopes),
    Object.hashAll(caps),
    Object.hashAll(commands),
    Object.hashAllUnordered(
      permissions.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    clientDisplayName,
  );
}

/// A standalone OpenClaw operator runtime.
///
/// This class intentionally does not depend on existing screens, ViewModels or
/// GatewayConnection. It reuses the tested low-level GatewaySession for the
/// transport and owns the operator-facing protocol facade here.
///
/// The runtime is process-wide: [OpenClawRuntime.instance] is shared by every
/// ViewModel (connection, Skill, Cron), so the operator session is configured
/// once and all consumers talk to the same Gateway connection.
class OpenClawRuntime {
  /// The process-wide shared runtime.
  static final OpenClawRuntime instance = OpenClawRuntime._singleton();

  final GatewaySession Function({
    required OpenClawRuntimeConfig config,
    required void Function(GatewayPush push) onPush,
    required void Function(String reason) onDisconnect,
  })

  sessionFactory;

  /// Whether this runtime is the shared [instance].
  ///
  /// The shared runtime outlives individual ViewModels, so [dispose] only
  /// releases its session instead of tearing down the object permanently.
  final bool _isSingleton;

  final StreamController<GatewayPush> _pushes =
      StreamController<GatewayPush>.broadcast();
  final StreamController<OpenClawRuntimeState> _states =
      StreamController<OpenClawRuntimeState>.broadcast();

  GatewaySession? _session;
  OpenClawRuntimeConfig? _config;
  OpenClawRuntimeState _state = OpenClawRuntimeState.idle;
  HelloOk? _hello;
  Future<void>? _configureOperation;
  bool _disposed = false;

  /// Whether the operator session should be kept alive.
  ///
  /// Set by [configure], cleared by [shutdown]/[dispose]. Every automatic
  /// recovery path (reconnect supervisor + liveness probe) is gated on this so
  /// a deliberately closed runtime never fights the caller.
  bool _shouldRun = false;

  Timer? _supervisorTimer;
  Duration _supervisorBackoff = _supervisorInitialDelay;
  Timer? _livenessTimer;
  DateTime? _lastPushAt;
  bool _probeInFlight = false;

  /// First delay before the supervisor retries a dropped session.
  static const Duration _supervisorInitialDelay = Duration(seconds: 1);

  /// Upper bound for the supervisor backoff.
  ///
  /// Deliberately much shorter than [GatewayRetryPolicy.maxDelay]: a gateway
  /// restart is usually back within a couple of seconds, and waiting 30s for
  /// the next attempt is what makes the app look like it never reconnected.
  static const Duration _supervisorMaxDelay = Duration(seconds: 5);

  /// How often the runtime checks whether the session still looks alive.
  static const Duration _defaultLivenessInterval = Duration(seconds: 15);

  /// Silence on the push stream longer than this means the socket is suspect.
  static const Duration _defaultLivenessStaleAfter = Duration(seconds: 45);

  static const Duration _defaultLivenessTimeout = Duration(seconds: 6);

  /// How often the liveness probe runs. Overridable for tests.
  final Duration livenessInterval;

  /// How long the push stream may stay quiet before the probe runs.
  final Duration livenessStaleAfter;

  /// Timeout of a single liveness probe request.
  final Duration livenessTimeout;

  OpenClawRuntime({
    GatewaySession Function({
      required OpenClawRuntimeConfig config,
      required void Function(GatewayPush push) onPush,
      required void Function(String reason) onDisconnect,
    })?
    sessionFactory,
    this.livenessInterval = _defaultLivenessInterval,
    this.livenessStaleAfter = _defaultLivenessStaleAfter,
    this.livenessTimeout = _defaultLivenessTimeout,
  }) : sessionFactory = sessionFactory ?? _defaultSessionFactory,
       _isSingleton = false;

  OpenClawRuntime._singleton()
    : sessionFactory = _defaultSessionFactory,
      livenessInterval = _defaultLivenessInterval,
      livenessStaleAfter = _defaultLivenessStaleAfter,
      livenessTimeout = _defaultLivenessTimeout,
      _isSingleton = true;

  OpenClawRuntimeState get state => _state;

  bool get isReady => _state == OpenClawRuntimeState.ready;

  /// Whether the runtime has a configured session that is trying to come back.
  bool get isReconnecting => _state == OpenClawRuntimeState.reconnecting;

  OpenClawRuntimeConfig? get config => _config;

  HelloOk? get hello => _hello;

  GatewaySession? get session => _session;

  Stream<GatewayPush> get pushes => _pushes.stream;

  Stream<OpenClawRuntimeState> get states => _states.stream;

  Future<void> configure(OpenClawRuntimeConfig config) async {
    _ensureActive();
    final previous = _configureOperation;
    if (previous != null) {
      await previous;
    }
    final operation = Completer<void>();
    _configureOperation = operation.future;
    try {
      _shouldRun = true;
      _startLivenessWatch();
      if (_config == config && _session != null) {
        _supervisorBackoff = _supervisorInitialDelay;
        await _session!.connect();
        return;
      }
      await _shutdownSession();
      _config = config;
      _hello = null;
      _setState(OpenClawRuntimeState.connecting);

      final session = sessionFactory(
        config: config,
        onPush: _handlePush,
        onDisconnect: _handleDisconnect,
      );
      _session = session;
      await session.connect();
      if (identical(_session, session)) {
        _setState(OpenClawRuntimeState.ready);
      }
    } catch (error) {
      if (_session != null && !_session!.connected) {
        _setState(OpenClawRuntimeState.disconnected);
        // `configure` may be called while the gateway is still down (e.g. the
        // app starts before the local gateway finishes booting). Keep retrying
        // instead of leaving the caller to notice.
        _scheduleSupervisorReconnect();
      }
      rethrow;
    } finally {
      if (identical(_configureOperation, operation.future)) {
        _configureOperation = null;
      }
      if (!operation.isCompleted) operation.complete();
    }
  }

  Future<GatewayOperationResult<HelloOk>> configureResult(
    OpenClawRuntimeConfig config,
  ) async {
    try {
      await configure(config);
      return GatewayOperationResult.success(data: _hello);
    } catch (error) {
      if (error is GatewayResponseError) {
        return GatewayOperationResult.failure(error: error);
      }
      return GatewayOperationResult.failure(
        error: GatewayResponseError(
          code: 'UNAVAILABLE',
          message: 'request failed',
          method: 'Connect',
        ),
      );
    }
  }

  Future<void> reconnect() async {
    _ensureActive();
    final current = _config;
    if (current == null) throw StateError('OpenClaw Gateway is not configured');
    await configure(current);
  }

  /// Makes sure the shared session is up, reusing [config] when needed.
  ///
  /// Safe to call repeatedly: a healthy runtime returns immediately. Used by
  /// callers (repository / UI) that want a cheap "just reconnect" entry point.
  Future<void> ensureConnected() async {
    _ensureActive();
    if (_state == OpenClawRuntimeState.ready && (_session?.connected ?? false)) {
      return;
    }
    final current = _config;
    if (current == null) return;
    await configure(current);
  }

  Future<void> shutdown() async {
    if (_disposed) return;
    _shouldRun = false;
    _cancelSupervisor();
    _stopLivenessWatch();
    await _shutdownSession();
    _config = null;
    _hello = null;
    _setState(OpenClawRuntimeState.idle);
  }

  Future<Map<String, dynamic>> request(
    String method, {
    Map<String, dynamic>? params,
    Duration? timeout,
  }) async {
    _ensureActive();
    final session = _session;
    if (session == null) throw StateError('OpenClaw Gateway is not configured');
    return session.request(method: method, params: params, timeout: timeout);
  }

  Future<Map<String, dynamic>> requestKnown(
    String method, {
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
    return request(method, params: params, timeout: timeout);
  }

  Future<void> send(String method, {Map<String, dynamic>? params}) async {
    _ensureActive();
    final session = _session;
    if (session == null) throw StateError('OpenClaw Gateway is not configured');
    await session.send(method: method, params: params);
  }

  Future<Map<String, dynamic>> health({
    Duration timeout = const Duration(seconds: 8),
  }) => requestKnown('health', timeout: timeout);

  Future<Map<String, dynamic>> status({
    Duration timeout = const Duration(seconds: 15),
  }) => requestKnown('status', timeout: timeout);

  Future<Map<String, dynamic>> chatHistory({
    required String sessionKey,
    int? limit,
    Duration? timeout,
  }) => requestKnown(
    'chat.history',
    params: {'sessionKey': sessionKey, if (limit != null) 'limit': limit},
    timeout: timeout,
  );

  Future<Map<String, dynamic>> chatSend({
    required String sessionKey,
    required String message,
    String? idempotencyKey,
    String? agentId,
    List<Map<String, dynamic>> attachments = const [],
    Duration? timeout,
  }) => requestKnown(
    'chat.send',
    params: {
      'sessionKey': sessionKey,
      'message': message,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
      if (agentId != null) 'agentId': agentId,
      if (attachments.isNotEmpty) 'attachments': attachments,
    },
    timeout: timeout,
  );

  Future<String> mainSessionKey({Duration? timeout}) async {
    final cached =
        _hello?.snapshot.sessiondefaults?['mainSessionKey']?.toString();
    if (cached != null && cached.trim().isNotEmpty) return cached;
    final data = await configGet(timeout: timeout);
    final scope = ((data['config'] as Map?)?['session'] as Map?)?['scope'];
    return scope?.toString().trim() == 'global' ? 'global' : 'main';
  }

  Future<void> talkMode({
    required bool enabled,
    String? phase,
    Duration? timeout,
  }) async {
    await requestKnown(
      'talk.mode',
      params: {'enabled': enabled, if (phase != null) 'phase': phase},
      timeout: timeout,
    );
  }

  Future<Map<String, dynamic>> talkSpeak(String text, {Duration? timeout}) =>
      requestKnown('talk.speak', params: {'text': text}, timeout: timeout);

  Future<List<dynamic>> listModels({Duration? timeout}) async {
    final data = await modelsList(timeout: timeout);
    return data['models'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> chatAbort({
    required String sessionKey,
    String? runId,
    Duration? timeout,
  }) => requestKnown(
    'chat.abort',
    params: {'sessionKey': sessionKey, if (runId != null) 'runId': runId},
    timeout: timeout,
  );

  Future<Map<String, dynamic>> sessionsList({
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
    Duration? timeout,
  }) => requestKnown(
    'sessions.list',
    params: {
      'includeGlobal': includeGlobal,
      'includeUnknown': includeUnknown,
      if (limit != null) 'limit': limit,
      if (search?.trim().isNotEmpty == true) 'search': search!.trim(),
      if (archived) 'archived': true,
      if (agentId?.trim().isNotEmpty == true) 'agentId': agentId!.trim(),
      if (activeMinutes != null) 'activeMinutes': activeMinutes,
      if (spawnedBy?.trim().isNotEmpty == true) 'spawnedBy': spawnedBy!.trim(),
      if (offset != null) 'offset': offset,
      if (configuredAgentsOnly != null)
        'configuredAgentsOnly': configuredAgentsOnly,
    },
    timeout: timeout,
  );

  Future<Map<String, dynamic>> sessionsCreate({
    required String key,
    String? agentId,
    String? label,
    String? parentSessionKey,
    bool? worktree,
    String? worktreeBaseRef,
    Duration? timeout,
  }) => requestKnown(
    'sessions.create',
    params: {
      'key': key,
      if (agentId?.trim().isNotEmpty == true) 'agentId': agentId!.trim(),
      if (label != null) 'label': label,
      if (parentSessionKey != null) 'parentSessionKey': parentSessionKey,
      if (worktree != null) 'worktree': worktree,
      if (worktreeBaseRef?.trim().isNotEmpty == true)
        'worktreeBaseRef': worktreeBaseRef!.trim(),
    },
    timeout: timeout,
  );

  /// Applies the operator-facing session metadata patch used by the Android client.
  ///
  /// `clear*` takes precedence over the corresponding value and encodes an
  /// explicit JSON null. An empty patch is rejected locally. Archiving also
  /// requires [expectedSessionId] so a stale session entry cannot retire a
  /// newly-created session that reused the same key.
  Future<bool> patchSession({
    required String key,
    String? ownerAgentId,
    String? expectedSessionId,
    String? label,
    bool clearLabel = false,
    String? category,
    bool clearCategory = false,
    String? color,
    bool clearColor = false,
    bool? pinned,
    bool? archived,
    bool? unread,
    OpenClawSessionUnreadExpectation? unreadExpectation,
    Duration? timeout,
  }) async {
    final sessionKey = key.trim();
    if (sessionKey.isEmpty) return false;

    final normalizedOwner = ownerAgentId?.trim();
    final normalizedExpectedSessionId = expectedSessionId?.trim();
    final hasPatch =
        clearLabel ||
        label != null ||
        clearCategory ||
        category != null ||
        clearColor ||
        color != null ||
        pinned != null ||
        archived != null ||
        unread != null;
    if (!hasPatch) return false;
    if (archived != null &&
        (normalizedExpectedSessionId == null ||
            normalizedExpectedSessionId.isEmpty)) {
      _openClawLog.warning(
        'Session lifecycle action requires a durable session identity.',
      );
      return false;
    }

    final params = <String, dynamic>{
      'key': sessionKey,
      if (normalizedOwner != null && normalizedOwner.isNotEmpty)
        'agentId': normalizedOwner,
      if (normalizedExpectedSessionId != null &&
          normalizedExpectedSessionId.isNotEmpty)
        'expectedSessionId': normalizedExpectedSessionId,
      if (clearLabel) 'label': null else if (label != null) 'label': label,
      if (clearCategory)
        'category': null
      else if (category != null)
        'category': category,
      if (clearColor) 'color': null else if (color != null) 'color': color,
      if (pinned != null) 'pinned': pinned,
      if (archived != null) 'archived': archived,
      if (unread != null) 'unread': unread,
      if (unreadExpectation != null)
        'expectedMarkedUnreadAt': unreadExpectation.markedUnreadAt,
    };

    try {
      await requestKnown('sessions.patch', params: params, timeout: timeout);
      return true;
    } catch (error) {
      _openClawLog.warning('patchSession failed: $error');
      return false;
    }
  }

  Future<Map<String, dynamic>> sessionsPatch({
    required String sessionKey,
    required Map<String, dynamic> patch,
    Duration? timeout,
  }) => requestKnown(
    'sessions.patch',
    params: {'key': sessionKey, ...patch},
    timeout: timeout,
  );

  Future<Map<String, dynamic>> sessionsDelete({
    required String sessionKey,
    String? agentId,
    Duration? timeout,
  }) => requestKnown(
    'sessions.delete',
    params: {
      'key': sessionKey,
      if (agentId?.trim().isNotEmpty == true) 'agentId': agentId!.trim(),
      'deleteTranscript': true,
    },
    timeout: timeout,
  );

  Future<Map<String, dynamic>> questionList({Duration? timeout}) =>
      requestKnown('question.list', timeout: timeout);

  Future<Map<String, dynamic>> questionGet({
    required String id,
    Duration? timeout,
  }) => requestKnown('question.get', params: {'id': id}, timeout: timeout);

  Future<Map<String, dynamic>> questionResolve({
    required String id,
    required Map<String, List<String>> answers,
    Duration? timeout,
  }) => requestKnown(
    'question.resolve',
    params: {'id': id, 'answers': answers},
    timeout: timeout,
  );

  Future<Map<String, dynamic>> execApprovalList({Duration? timeout}) =>
      requestKnown('exec.approval.list', timeout: timeout);

  Future<Map<String, dynamic>> execApprovalResolve({
    required String id,
    required String decision,
    Duration? timeout,
  }) => requestKnown(
    'exec.approval.resolve',
    params: {'id': id, 'decision': decision},
    timeout: timeout,
  );

  Future<Map<String, dynamic>> cronList({
    bool includeDisabled = true,
    Duration? timeout,
  }) => requestKnown(
    'cron.list',
    params: {'includeDisabled': includeDisabled},
    timeout: timeout,
  );

  Future<Map<String, dynamic>> cronRun({
    required String id,
    bool force = true,
    Duration? timeout,
  }) => requestKnown(
    'cron.run',
    params: {'id': _requireJobId(id), 'force': force},
    timeout: timeout,
  );

  Future<Map<String, dynamic>> cronRuns({
    required String id,
    int limit = 200,
    Duration? timeout,
  }) => requestKnown(
    'cron.runs',
    params: {'id': _requireJobId(id), 'limit': limit},
    timeout: timeout,
  );

  Future<Map<String, dynamic>> cronAdd({
    required Map<String, dynamic> payload,
    Duration? timeout,
  }) {
    if (payload.isEmpty) {
      throw ArgumentError.value(payload, 'payload', '任务参数不能为空');
    }
    return requestKnown('cron.add', params: payload, timeout: timeout);
  }

  Future<Map<String, dynamic>> cronUpdate({
    required String id,
    required Map<String, dynamic> patch,
    Duration? timeout,
  }) {
    if (patch.isEmpty) {
      throw ArgumentError.value(patch, 'patch', '更新内容不能为空');
    }
    return requestKnown(
      'cron.update',
      params: {'id': _requireJobId(id), 'patch': patch},
      timeout: timeout,
    );
  }

  Future<Map<String, dynamic>> cronRemove({
    required String id,
    Duration? timeout,
  }) => requestKnown(
    'cron.remove',
    params: {'id': _requireJobId(id)},
    timeout: timeout,
  );

  Future<Map<String, dynamic>> cronStatus({Duration? timeout}) =>
      requestKnown('cron.status', timeout: timeout);

  Future<Map<String, dynamic>> skillsStatus({Duration? timeout}) =>
      requestKnown('skills.status', timeout: timeout);

  Future<Map<String, dynamic>> skillsInstall({
    required String name,
    required String installId,
    bool? dangerouslyForceUnsafeInstall,
    Duration? timeout,
  }) {
    final normalizedName = name.trim();
    final normalizedInstallId = installId.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Skill 名称不能为空');
    }
    if (normalizedInstallId.isEmpty) {
      throw ArgumentError.value(installId, 'installId', '安装方式不能为空');
    }
    return requestKnown(
      'skills.install',
      params: {
        'name': normalizedName,
        'installId': normalizedInstallId,
        if (dangerouslyForceUnsafeInstall != null)
          'dangerouslyForceUnsafeInstall': dangerouslyForceUnsafeInstall,
      },
      timeout: timeout,
    );
  }

  Future<Map<String, dynamic>> skillsUpdate({
    required String skillKey,
    bool? enabled,
    String? apiKey,
    Map<String, String>? env,
    Duration? timeout,
  }) {
    final normalizedKey = skillKey.trim();
    if (normalizedKey.isEmpty) {
      throw ArgumentError.value(skillKey, 'skillKey', 'Skill 标识不能为空');
    }
    return requestKnown(
      'skills.update',
      params: {
        'skillKey': normalizedKey,
        if (enabled != null) 'enabled': enabled,
        if (apiKey != null) 'apiKey': apiKey,
        if (env != null && env.isNotEmpty) 'env': env,
      },
      timeout: timeout,
    );
  }

  /// 搜索 ClawHub 技能。
  ///
  /// 网关的 `query` 是非空字符串（空串会被参数校验拒绝），所以关键字为空时
  /// 不传该字段，只带 limit —— 与 Android `clawHubSearchParams` 一致。
  Future<Map<String, dynamic>> skillsSearch({
    String? query,
    int limit = 25,
    Duration? timeout,
  }) {
    final normalized = query?.trim();
    return requestKnown(
      'skills.search',
      params: {
        if (normalized != null && normalized.isNotEmpty) 'query': normalized,
        'limit': limit,
      },
      timeout: timeout,
    );
  }

  /// 读取 ClawHub 技能详情，用于安装前的版本审核。
  ///
  /// 入参是 `skills.search` 给出的 reference（可能是 `@owner/slug`）：
  /// 网关的 `skills.detail` / `skills.install` 用同一套引用语法，
  /// 免得「审了一个发布者的卡片、装的是另一个发布者的包」。
  Future<Map<String, dynamic>> skillsDetail({
    required String slug,
    Duration? timeout,
  }) {
    final normalized = slug.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(slug, 'slug', 'ClawHub 技能引用不能为空');
    }
    return requestKnown(
      'skills.detail',
      params: {'slug': normalized},
      timeout: timeout,
    );
  }

  /// 从 ClawHub 安装技能（对应 Android `clawHubInstallParams`）。
  ///
  /// 与 [skillsInstall] 不是同一个入参形态：那条走网关自带的安装方式
  /// （`name` + `installId`），这条按 ClawHub 引用装，并且要指定具体版本，
  /// 让网关去校验的就是「审核时看到的那个版本」。
  ///
  /// 安装可能等很久（下载 + 校验），所以默认给 125s 超时。
  Future<Map<String, dynamic>> skillsInstallFromClawHub({
    required String slug,
    String? version,
    Duration? timeout,
  }) {
    final normalized = slug.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(slug, 'slug', 'ClawHub 技能引用不能为空');
    }
    final normalizedVersion = version?.trim();
    return requestKnown(
      'skills.install',
      params: {
        'source': 'clawhub',
        'slug': normalized,
        if (normalizedVersion != null && normalizedVersion.isNotEmpty)
          'version': normalizedVersion,
        'timeoutMs': 120000,
      },
      timeout: timeout ?? const Duration(milliseconds: 125000),
    );
  }

  Future<Map<String, dynamic>> modelsList({Duration? timeout}) =>
      requestKnown('models.list', timeout: timeout);

  Future<Map<String, dynamic>> devicePairList({Duration? timeout}) =>
      requestKnown('device.pair.list', timeout: timeout);

  Future<OpenClawDevicePairSetupCodeResponse> devicePairSetupCode({
    String? publicUrl,
    bool? preferRemoteUrl,
    bool includeQr = true,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final data = await requestKnown(
      'device.pair.setupCode',
      params: {
        if (publicUrl?.trim().isNotEmpty == true)
          'publicUrl': publicUrl!.trim(),
        if (preferRemoteUrl != null) 'preferRemoteUrl': preferRemoteUrl,
        'includeQr': includeQr,
      },
      timeout: timeout,
    );
    return OpenClawDevicePairSetupCodeResponse.fromJson(data);
  }

  Future<Map<String, dynamic>> nodeList({Duration? timeout}) =>
      requestKnown('node.list', timeout: timeout);

  Future<Map<String, dynamic>> configGet({Duration? timeout}) =>
      requestKnown('config.get', timeout: timeout);

  Future<Map<String, dynamic>> usersPrefsGet({
    List<String>? keys,
    Duration? timeout,
  }) => requestKnown(
    'users.prefs.get',
    params: {if (keys != null) 'keys': keys},
    timeout: timeout,
  );

  Future<Map<String, dynamic>> voicewakeGet({Duration? timeout}) =>
      requestKnown('voicewake.get', timeout: timeout);

  Future<Map<String, dynamic>> talkCatalog({Duration? timeout}) =>
      requestKnown('talk.catalog', timeout: timeout);

  Future<Map<String, dynamic>> rawKnownCall(
    String method, {
    Map<String, dynamic>? params,
    Duration? timeout,
  }) => requestKnown(method, params: params, timeout: timeout);

  Future<void> dispose() async {
    if (_disposed) return;
    if (_isSingleton) {
      // The shared runtime is reused by other ViewModels (Skill/Cron) and by
      // later connections, so only release the current session here.
      _shouldRun = false;
      _cancelSupervisor();
      _stopLivenessWatch();
      await _shutdownSession();
      _config = null;
      _hello = null;
      _setState(OpenClawRuntimeState.idle);
      return;
    }
    _disposed = true;
    _shouldRun = false;
    _cancelSupervisor();
    _stopLivenessWatch();
    await _shutdownSession();
    await _pushes.close();
    await _states.close();
  }

  void _handlePush(GatewayPush push) {
    _lastPushAt = DateTime.now();
    if (push is GatewayPushSnapshot) {
      _hello = push.snapshot;
      _supervisorBackoff = _supervisorInitialDelay;
      _cancelSupervisor();
      _setState(OpenClawRuntimeState.ready);
    }
    if (!_pushes.isClosed) _pushes.add(push);
  }

  void _handleDisconnect(String reason) {
    if (_disposed) return;
    _setState(OpenClawRuntimeState.disconnected);
    _openClawLog.warning('OpenClaw operator session disconnected: $reason');
    _scheduleSupervisorReconnect();
  }

  /// Retries the operator session on the runtime's own short backoff.
  ///
  /// `GatewaySession` already retries internally, but that loop only exists
  /// while the session object itself is alive: it is dropped by
  /// [shutdown]/[dispose], by a socket replaced under it, and by any path that
  /// bumps the session generation before the failure is observed. When that
  /// happens the app looks permanently disconnected even though the gateway is
  /// healthy again. This supervisor is the app-level safety net for exactly
  /// that case, and its cap (a few seconds) keeps recovery snappy after a
  /// gateway restart.
  void _scheduleSupervisorReconnect() {
    if (_disposed || !_shouldRun) return;
    if (_supervisorTimer?.isActive ?? false) return;
    if (_state == OpenClawRuntimeState.ready ||
        _state == OpenClawRuntimeState.connecting) {
      return;
    }
    _setState(OpenClawRuntimeState.reconnecting);
    final delay = _supervisorBackoff;
    final next = Duration(
      milliseconds: (_supervisorBackoff.inMilliseconds * 2).round(),
    );
    _supervisorBackoff = next.compareTo(_supervisorMaxDelay) > 0
        ? _supervisorMaxDelay
        : next;
    _supervisorTimer = Timer(delay, () async {
      _supervisorTimer = null;
      if (_disposed ||
          !_shouldRun ||
          _state == OpenClawRuntimeState.ready ||
          _state == OpenClawRuntimeState.connecting) {
        return;
      }
      final session = _session;
      if (session == null) {
        // The session was torn down (e.g. by a competing shutdown). Rebuild it
        // from the last known config so the connection comes back by itself.
        final current = _config;
        if (current == null) return;
        try {
          await configure(current);
        } catch (error) {
          _openClawLog.warning('Runtime rebuild failed: $error');
          _scheduleSupervisorReconnect();
        }
        return;
      }
      try {
        await session.connect();
      } catch (error) {
        _openClawLog.warning('Supervisor reconnect failed: $error');
        _scheduleSupervisorReconnect();
      }
    });
  }

  void _cancelSupervisor() {
    _supervisorTimer?.cancel();
    _supervisorTimer = null;
  }

  void _startLivenessWatch() {
    if (_livenessTimer != null) return;
    _lastPushAt = DateTime.now();
    _livenessTimer = Timer.periodic(livenessInterval, (_) => _probeLiveness());
  }

  void _stopLivenessWatch() {
    _livenessTimer?.cancel();
    _livenessTimer = null;
    _probeInFlight = false;
  }

  /// Detects a half-open socket: the peer is gone but no close frame arrived.
  ///
  /// Only runs once the push stream has been quiet for [_livenessStaleAfter],
  /// so a healthy (ticking) session costs no extra traffic. When the probe
  /// fails the socket is torn down and reopened immediately instead of waiting
  /// for the session's own tick watchdog.
  Future<void> _probeLiveness() async {
    if (_disposed || !_shouldRun || _probeInFlight) return;
    if (_state != OpenClawRuntimeState.ready) {
      _scheduleSupervisorReconnect();
      return;
    }
    final session = _session;
    if (session == null) {
      _scheduleSupervisorReconnect();
      return;
    }
    final last = _lastPushAt;
    if (last != null &&
        DateTime.now().difference(last) < livenessStaleAfter) {
      return;
    }
    _probeInFlight = true;
    try {
      await session.request(method: 'health', timeout: livenessTimeout);
    } catch (error) {
      _openClawLog.warning('Gateway liveness probe failed: $error');
      _setState(OpenClawRuntimeState.reconnecting);
      try {
        await session.forceReconnect();
      } catch (reconnectError) {
        _openClawLog.warning('Forced reconnect failed: $reconnectError');
        _scheduleSupervisorReconnect();
      }
    } finally {
      _probeInFlight = false;
    }
  }

  Future<void> _shutdownSession() async {
    final session = _session;
    _session = null;
    if (session != null) await session.shutdown();
  }

  void _setState(OpenClawRuntimeState value) {
    if (_state == value) return;
    _state = value;
    if (!_states.isClosed) _states.add(value);
  }

  void _ensureActive() {
    if (_disposed) throw StateError('OpenClaw Gateway has been disposed');
  }
}

enum OpenClawRuntimeState { idle, connecting, ready, reconnecting, disconnected }

GatewaySession _defaultSessionFactory({
  required OpenClawRuntimeConfig config,
  required void Function(GatewayPush push) onPush,
  required void Function(String reason) onDisconnect,
}) {
  return GatewaySession(
    url: config.url,
    token: _nonEmpty(config.token),
    password: _nonEmpty(config.password),
    bootstrapToken: _nonEmpty(config.bootstrapToken),
    pushHandler: onPush,
    disconnectHandler: onDisconnect,
    connectOptions: config.toGatewayOptions(),
  );
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String _requireJobId(String id) {
  final normalized = id.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(id, 'id', '任务 ID 不能为空');
  }
  return normalized;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// Conditional acknowledgement marker for a session unread patch.
class OpenClawSessionUnreadExpectation {
  final double? markedUnreadAt;

  const OpenClawSessionUnreadExpectation(this.markedUnreadAt);
}

class GatewaySessionEntry {
  final String key;
  final String? kind;
  final String? displayName;
  final String? derivedTitle;
  final String? classification;
  final String? agentId;
  final String? accountId;
  final String? peerKind;
  final bool? isMain;
  final bool? isBackground;
  final String? label;
  final String? category;
  final bool? pinned;
  final double? pinnedAt;
  final bool? archived;
  final double? archivedAt;
  final bool? unread;
  final GatewaySessionAgentStatus? agentStatus;
  final String? surface;
  final String? subject;
  final String? room;
  final String? space;
  final double? updatedAt;
  final double? lastReadAt;
  final double? markedUnreadAt;
  final double? lastInteractionAt;
  final double? lastActivityAt;
  final String? sessionId;
  final String? parentSessionKey;
  final String? spawnedBy;
  final List<String>? childSessions;
  final String? status;
  final String? lastRunError;
  final bool? hasActiveRun;
  final List<String>? activeRunIds;
  final bool? hasActiveSubagentRun;
  final String? subagentRunState;
  final String? swarmGroupId;
  final String? swarmPhase;
  final int? swarmPhaseRank;
  final String? swarmLog;
  final GatewaySessionWorktree? worktree;
  final double? startedAt;
  final double? endedAt;
  final double? runtimeMs;
  final GatewaySessionAgentRuntime? agentRuntime;
  final bool? systemSent;
  final bool? abortedLastRun;
  final String? thinkingLevel;
  final String? verboseLevel;
  final dynamic fastMode;
  final dynamic effectiveFastMode;
  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
  final bool? totalTokensFresh;
  final String? modelProvider;
  final String? model;
  final int? contextTokens;
  final List<GatewaySessionThinkingLevelOption>? thinkingLevels;
  final List<String>? thinkingOptions;
  final String? thinkingDefault;

  const GatewaySessionEntry({
    required this.key,
    this.kind,
    this.displayName,
    this.derivedTitle,
    this.classification,
    this.agentId,
    this.accountId,
    this.peerKind,
    this.isMain,
    this.isBackground,
    this.label,
    this.category,
    this.pinned,
    this.pinnedAt,
    this.archived,
    this.archivedAt,
    this.unread,
    this.agentStatus,
    this.surface,
    this.subject,
    this.room,
    this.space,
    this.updatedAt,
    this.lastReadAt,
    this.markedUnreadAt,
    this.lastInteractionAt,
    this.lastActivityAt,
    this.sessionId,
    this.parentSessionKey,
    this.spawnedBy,
    this.childSessions,
    this.status,
    this.lastRunError,
    this.hasActiveRun,
    this.activeRunIds,
    this.hasActiveSubagentRun,
    this.subagentRunState,
    this.swarmGroupId,
    this.swarmPhase,
    this.swarmPhaseRank,
    this.swarmLog,
    this.worktree,
    this.startedAt,
    this.endedAt,
    this.runtimeMs,
    this.agentRuntime,
    this.systemSent,
    this.abortedLastRun,
    this.thinkingLevel,
    this.verboseLevel,
    this.fastMode,
    this.effectiveFastMode,
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
    this.totalTokensFresh,
    this.modelProvider,
    this.model,
    this.contextTokens,
    this.thinkingLevels,
    this.thinkingOptions,
    this.thinkingDefault,
  });

  bool get isPinned => pinned == true;

  bool get isArchived => archived == true;

  factory GatewaySessionEntry.fromJson(Map<String, dynamic> json) =>
      GatewaySessionEntry(
        key: json['key'] as String? ?? '',
        kind: json['kind'] as String?,
        displayName: json['displayName'] as String?,
        derivedTitle: json['derivedTitle'] as String?,
        classification: json['classification'] as String?,
        agentId: json['agentId'] as String?,
        accountId: json['accountId'] as String?,
        peerKind: json['peerKind'] as String?,
        isMain: json['isMain'] as bool?,
        isBackground: json['isBackground'] as bool?,
        label: json['label'] as String?,
        category: json['category'] as String?,
        pinned: json['pinned'] as bool?,
        pinnedAt: (json['pinnedAt'] as num?)?.toDouble(),
        archived: json['archived'] as bool?,
        archivedAt: (json['archivedAt'] as num?)?.toDouble(),
        unread: json['unread'] as bool?,
        agentStatus: _mapValue(
          json['agentStatus'],
          GatewaySessionAgentStatus.fromJson,
        ),
        surface: json['surface'] as String?,
        subject: json['subject'] as String?,
        room: json['room'] as String?,
        space: json['space'] as String?,
        updatedAt: (json['updatedAt'] as num?)?.toDouble(),
        lastReadAt: (json['lastReadAt'] as num?)?.toDouble(),
        markedUnreadAt: (json['markedUnreadAt'] as num?)?.toDouble(),
        lastInteractionAt: (json['lastInteractionAt'] as num?)?.toDouble(),
        lastActivityAt: (json['lastActivityAt'] as num?)?.toDouble(),
        sessionId: json['sessionId'] as String?,
        parentSessionKey: json['parentSessionKey'] as String?,
        spawnedBy: json['spawnedBy'] as String?,
        childSessions: _stringList(json['childSessions']),
        status: json['status'] as String?,
        lastRunError: json['lastRunError'] as String?,
        hasActiveRun: json['hasActiveRun'] as bool?,
        activeRunIds: _stringList(json['activeRunIds']),
        hasActiveSubagentRun: json['hasActiveSubagentRun'] as bool?,
        subagentRunState: json['subagentRunState'] as String?,
        swarmGroupId: json['swarmGroupId'] as String?,
        swarmPhase: json['swarmPhase'] as String?,
        swarmPhaseRank: (json['swarmPhaseRank'] as num?)?.toInt(),
        swarmLog: json['swarmLog'] as String?,
        worktree: _mapValue(json['worktree'], GatewaySessionWorktree.fromJson),
        startedAt: (json['startedAt'] as num?)?.toDouble(),
        endedAt: (json['endedAt'] as num?)?.toDouble(),
        runtimeMs: (json['runtimeMs'] as num?)?.toDouble(),
        agentRuntime: _mapValue(
          json['agentRuntime'],
          GatewaySessionAgentRuntime.fromJson,
        ),
        systemSent: json['systemSent'] as bool?,
        abortedLastRun: json['abortedLastRun'] as bool?,
        thinkingLevel: json['thinkingLevel'] as String?,
        verboseLevel: json['verboseLevel'] as String?,
        fastMode: json['fastMode'],
        effectiveFastMode: json['effectiveFastMode'],
        inputTokens: (json['inputTokens'] as num?)?.toInt(),
        outputTokens: (json['outputTokens'] as num?)?.toInt(),
        totalTokens: (json['totalTokens'] as num?)?.toInt(),
        totalTokensFresh: json['totalTokensFresh'] as bool?,
        modelProvider: json['modelProvider'] as String?,
        model: json['model'] as String?,
        contextTokens: (json['contextTokens'] as num?)?.toInt(),
        thinkingLevels: _mapList(
          json['thinkingLevels'],
          GatewaySessionThinkingLevelOption.fromJson,
        ),
        thinkingOptions: _stringList(json['thinkingOptions']),
        thinkingDefault: json['thinkingDefault'] as String?,
      );
}

class GatewayCreateSessionResponse {
  final bool? ok;
  final String key;
  final String? sessionId;

  const GatewayCreateSessionResponse({
    required this.key,
    this.ok,
    this.sessionId,
  });

  factory GatewayCreateSessionResponse.fromJson(Map<String, dynamic> json) =>
      GatewayCreateSessionResponse(
        ok: json['ok'] as bool?,
        key: json['key'] as String? ?? '',
        sessionId: json['sessionId'] as String?,
      );
}

T? _mapValue<T>(dynamic value, T Function(Map<String, dynamic>) parser) {
  if (value is Map) return parser(value.cast<String, dynamic>());
  return null;
}

List<T>? _mapList<T>(dynamic value, T Function(Map<String, dynamic>) parser) {
  if (value is! List) return null;
  return value
      .whereType<Map>()
      .map((item) => parser(item.cast<String, dynamic>()))
      .toList();
}

List<String>? _stringList(dynamic value) {
  if (value is! List) return null;
  return value.whereType<String>().toList();
}

class GatewaySessionsListResponse {
  final double? ts;
  final String? path;
  final int? count;
  final int? totalCount;
  final int? offset;
  final int? nextOffset;
  final bool? hasMore;
  final Map<String, dynamic>? defaults;
  final List<GatewaySessionEntry> sessions;

  const GatewaySessionsListResponse({
    this.ts,
    this.path,
    this.count,
    this.totalCount,
    this.offset,
    this.nextOffset,
    this.hasMore,
    this.defaults,
    this.sessions = const [],
  });

  factory GatewaySessionsListResponse.fromJson(Map<String, dynamic> json) =>
      GatewaySessionsListResponse(
        ts: (json['ts'] as num?)?.toDouble(),
        path: json['path'] as String?,
        count: (json['count'] as num?)?.toInt(),
        totalCount: (json['totalCount'] as num?)?.toInt(),
        offset: (json['offset'] as num?)?.toInt(),
        nextOffset: (json['nextOffset'] as num?)?.toInt(),
        hasMore: json['hasMore'] as bool?,
        defaults: (json['defaults'] as Map?)?.cast<String, dynamic>(),
        sessions:
            _mapList(json['sessions'], GatewaySessionEntry.fromJson) ??
            const [],
      );
}

class GatewaySessionAgentStatus {
  final String note;
  final double expiresAt;
  final String? attention;

  const GatewaySessionAgentStatus({
    required this.note,
    required this.expiresAt,
    this.attention,
  });

  factory GatewaySessionAgentStatus.fromJson(Map<String, dynamic> json) =>
      GatewaySessionAgentStatus(
        note: json['note'] as String? ?? '',
        expiresAt: (json['expiresAt'] as num?)?.toDouble() ?? 0,
        attention: json['attention'] as String?,
      );
}

class GatewaySessionWorktree {
  final String? id;
  final String? branch;
  final String? repoRoot;

  const GatewaySessionWorktree({this.id, this.branch, this.repoRoot});

  factory GatewaySessionWorktree.fromJson(Map<String, dynamic> json) =>
      GatewaySessionWorktree(
        id: json['id'] as String?,
        branch: json['branch'] as String?,
        repoRoot: json['repoRoot'] as String?,
      );
}

GatewayErrorCode gatewayErrorCodeFromRaw(String code) {
  final normalized = code.toUpperCase();
  if (normalized.contains('PAIRING_REQUIRED')) {
    return GatewayErrorCode.pairingRequired;
  }
  if (normalized.contains('NOT_PAIRED')) {
    return GatewayErrorCode.deviceNotPaired;
  }
  if (normalized.contains('NOT_APPROVED') ||
      normalized.contains('NOT APPROVED')) {
    return GatewayErrorCode.deviceNotApproved;
  }
  if (normalized.contains('PROTOCOL')) return GatewayErrorCode.protocolMismatch;
  if (normalized.contains('RATE_LIMIT')) {
    return GatewayErrorCode.authRateLimited;
  }
  if (normalized.contains('BOOTSTRAP')) {
    return GatewayErrorCode.authBootstrapTokenInvalid;
  }
  if (normalized.contains('DEVICE_TOKEN')) {
    return GatewayErrorCode.authDeviceTokenMismatch;
  }
  if (normalized.contains('TOKEN_MISMATCH')) {
    return GatewayErrorCode.authTokenMismatch;
  }
  if (normalized.contains('SCOPE')) return GatewayErrorCode.authScopeMismatch;
  if (normalized.contains('UNAUTHORIZED') ||
      normalized.contains('AUTH_INVALID')) {
    return GatewayErrorCode.authUnauthorized;
  }
  if (normalized.contains('AUTH_REQUIRED') ||
      normalized.contains('TOKEN_MISSING')) {
    return GatewayErrorCode.authRequired;
  }
  if (normalized.contains('DEVICE_IDENTITY')) {
    return GatewayErrorCode.deviceIdentityRequired;
  }
  if (normalized.contains('DEVICE_AUTH')) {
    return GatewayErrorCode.deviceAuthInvalid;
  }
  return GatewayErrorCode.serverError;
}

class GatewaySessionAgentRuntime {
  final String id;
  final String? fallback;
  final String? source;

  const GatewaySessionAgentRuntime({
    required this.id,
    this.fallback,
    this.source,
  });

  factory GatewaySessionAgentRuntime.fromJson(Map<String, dynamic> json) =>
      GatewaySessionAgentRuntime(
        id: json['id'] as String? ?? '',
        fallback: json['fallback'] as String?,
        source: json['source'] as String?,
      );
}

class GatewaySessionThinkingLevelOption {
  final String id;
  final String label;

  const GatewaySessionThinkingLevelOption({
    required this.id,
    required this.label,
  });

  factory GatewaySessionThinkingLevelOption.fromJson(
    Map<String, dynamic> json,
  ) => GatewaySessionThinkingLevelOption(
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
  );
}
