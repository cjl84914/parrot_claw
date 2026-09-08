import 'dart:async';

import 'package:logging/logging.dart';
import 'package:parrot_app/data/service/gateway_session.dart';
import 'openclaw_protocol.dart';

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
class OpenClawRuntime {
  final GatewaySession Function({
    required OpenClawRuntimeConfig config,
    required void Function(GatewayPush push) onPush,
    required void Function(String reason) onDisconnect,
  }) sessionFactory;

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

  OpenClawRuntime({
    GatewaySession Function({
      required OpenClawRuntimeConfig config,
      required void Function(GatewayPush push) onPush,
      required void Function(String reason) onDisconnect,
    })? sessionFactory,
  }) : sessionFactory = sessionFactory ?? _defaultSessionFactory;

  OpenClawRuntimeState get state => _state;
  bool get isReady => _state == OpenClawRuntimeState.ready;
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
      if (_config == config && _session != null) {
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
      }
      rethrow;
    } finally {
      if (identical(_configureOperation, operation.future)) {
        _configureOperation = null;
      }
      if (!operation.isCompleted) operation.complete();
    }
  }

  Future<void> reconnect() async {
    _ensureActive();
    final current = _config;
    if (current == null) throw StateError('OpenClaw runtime is not configured');
    await configure(current);
  }

  Future<void> shutdown() async {
    if (_disposed) return;
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
    if (session == null) throw StateError('OpenClaw runtime is not configured');
    return session.request(method: method, params: params, timeout: timeout);
  }

  Future<Map<String, dynamic>> requestKnown(
    String method, {
    Map<String, dynamic>? params,
    Duration? timeout,
  }) {
    if (!OpenClawProtocolCatalog.supportsMethod(method)) {
      throw ArgumentError.value(method, 'method', 'Not in the OpenClaw protocol catalog');
    }
    return request(method, params: params, timeout: timeout);
  }

  Future<void> send(String method, {Map<String, dynamic>? params}) async {
    _ensureActive();
    final session = _session;
    if (session == null) throw StateError('OpenClaw runtime is not configured');
    await session.send(method: method, params: params);
  }

  Future<Map<String, dynamic>> health({Duration timeout = const Duration(seconds: 8)}) =>
      requestKnown('health', timeout: timeout);

  Future<Map<String, dynamic>> status({Duration timeout = const Duration(seconds: 15)}) =>
      requestKnown('status', timeout: timeout);

  Future<Map<String, dynamic>> chatHistory({
    required String sessionKey,
    int? limit,
    Duration? timeout,
  }) =>
      requestKnown(
        'chat.history',
        params: {
          'sessionKey': sessionKey,
          if (limit != null) 'limit': limit,
        },
        timeout: timeout,
      );

  Future<Map<String, dynamic>> chatSend({
    required String sessionKey,
    required String message,
    String? idempotencyKey,
    String? agentId,
    Duration? timeout,
  }) =>
      requestKnown(
        'chat.send',
        params: {
          'sessionKey': sessionKey,
          'message': message,
          if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
          if (agentId != null) 'agentId': agentId,
        },
        timeout: timeout,
      );

  Future<Map<String, dynamic>> chatAbort({
    required String sessionKey,
    String? runId,
    Duration? timeout,
  }) =>
      requestKnown(
        'chat.abort',
        params: {
          'sessionKey': sessionKey,
          if (runId != null) 'runId': runId,
        },
        timeout: timeout,
      );

  Future<Map<String, dynamic>> sessionsList({
    int? limit,
    int? offset,
    Duration? timeout,
  }) =>
      requestKnown(
        'sessions.list',
        params: {
          if (limit != null) 'limit': limit,
          if (offset != null) 'offset': offset,
        },
        timeout: timeout,
      );

  Future<Map<String, dynamic>> sessionsCreate({
    String? sessionKey,
    String? agentId,
    Duration? timeout,
  }) =>
      requestKnown(
        'sessions.create',
        params: {
          if (sessionKey != null) 'sessionKey': sessionKey,
          if (agentId != null) 'agentId': agentId,
        },
        timeout: timeout,
      );

  Future<Map<String, dynamic>> sessionsPatch({
    required String sessionKey,
    required Map<String, dynamic> patch,
    Duration? timeout,
  }) =>
      requestKnown(
        'sessions.patch',
        params: {'sessionKey': sessionKey, 'patch': patch},
        timeout: timeout,
      );

  Future<Map<String, dynamic>> sessionsDelete({
    required String sessionKey,
    Duration? timeout,
  }) =>
      requestKnown(
        'sessions.delete',
        params: {'sessionKey': sessionKey},
        timeout: timeout,
      );

  Future<Map<String, dynamic>> questionList({Duration? timeout}) =>
      requestKnown('question.list', timeout: timeout);

  Future<Map<String, dynamic>> questionGet({
    required String id,
    Duration? timeout,
  }) =>
      requestKnown('question.get', params: {'id': id}, timeout: timeout);

  Future<Map<String, dynamic>> questionResolve({
    required String id,
    required Map<String, List<String>> answers,
    Duration? timeout,
  }) =>
      requestKnown(
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
  }) =>
      requestKnown(
        'exec.approval.resolve',
        params: {'id': id, 'decision': decision},
        timeout: timeout,
      );

  Future<Map<String, dynamic>> cronList({
    bool includeDisabled = true,
    Duration? timeout,
  }) =>
      requestKnown(
        'cron.list',
        params: {'includeDisabled': includeDisabled},
        timeout: timeout,
      );

  Future<Map<String, dynamic>> cronRun({
    required String id,
    bool force = true,
    Duration? timeout,
  }) =>
      requestKnown(
        'cron.run',
        params: {'id': id, 'force': force},
        timeout: timeout,
      );

  Future<Map<String, dynamic>> skillsStatus({Duration? timeout}) =>
      requestKnown('skills.status', timeout: timeout);

  Future<Map<String, dynamic>> skillsSearch({
    required String query,
    Duration? timeout,
  }) =>
      requestKnown('skills.search', params: {'query': query}, timeout: timeout);

  Future<Map<String, dynamic>> modelsList({Duration? timeout}) =>
      requestKnown('models.list', timeout: timeout);

  Future<Map<String, dynamic>> devicePairList({Duration? timeout}) =>
      requestKnown('device.pair.list', timeout: timeout);

  Future<Map<String, dynamic>> nodeList({Duration? timeout}) =>
      requestKnown('node.list', timeout: timeout);

  Future<Map<String, dynamic>> configGet({Duration? timeout}) =>
      requestKnown('config.get', timeout: timeout);

  Future<Map<String, dynamic>> usersPrefsGet({
    List<String>? keys,
    Duration? timeout,
  }) =>
      requestKnown(
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
  }) =>
      requestKnown(method, params: params, timeout: timeout);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _shutdownSession();
    await _pushes.close();
    await _states.close();
  }

  void _handlePush(GatewayPush push) {
    if (push is GatewayPushSnapshot) {
      _hello = push.snapshot;
      _setState(OpenClawRuntimeState.ready);
    }
    if (!_pushes.isClosed) _pushes.add(push);
  }

  void _handleDisconnect(String reason) {
    if (_disposed) return;
    _setState(OpenClawRuntimeState.disconnected);
    _openClawLog.warning('OpenClaw operator session disconnected: $reason');
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
    if (_disposed) throw StateError('OpenClaw runtime has been disposed');
  }
}

enum OpenClawRuntimeState {
  idle,
  connecting,
  ready,
  disconnected,
}

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
