import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:parrot_app/util/device_identity.dart';

enum GatewayAuthSource {
  deviceToken,
  sharedToken,
  bootstrapToken,
  password,
  none,
}

class StateVersion {
  final int presence;
  final int health;

  const StateVersion({required this.presence, required this.health});

  factory StateVersion.fromJson(Map<String, dynamic> json) => StateVersion(
    presence: json['presence'] as int? ?? 0,
    health: json['health'] as int? ?? 0,
  );
}

class GatewayConnectOptions {
  final String role;
  final List<String> scopes;
  final bool scopesAreExplicit;
  final List<String> caps;
  final List<String> commands;
  final Map<String, bool> permissions;
  final String clientId;
  final String clientMode;
  final String? clientDisplayName;
  final bool includeDeviceIdentity;

  const GatewayConnectOptions({
    required this.role,
    required this.scopes,
    this.scopesAreExplicit = false,
    required this.caps,
    required this.commands,
    required this.permissions,
    required this.clientId,
    required this.clientMode,
    this.clientDisplayName,
    this.includeDeviceIdentity = true,
  });
}

/// Operator scopes requested by the OpenClaw companion client by default.
const openClawOperatorScopes = <String>[
  'operator.admin',
  'operator.approvals',
  'operator.questions',
  'operator.read',
  'operator.talk.secrets',
  'operator.write',
];

/// 建立一条 operator 会话所需的连接设置（值对象，不可变）。
///
/// 这是「App 侧的连接意图」：一个 url + 一套凭据 + 一份角色/权限声明，
/// 由 [toGatewayOptions] 映射成握手用的 [GatewayConnectOptions]。
/// 原先叫 `OpenClawRuntimeConfig`，随 runtime 层一起并入本文件
/// —— 它本来就是 `GatewayConnectOptions` 的应用侧形态。
class GatewayConnectConfig {
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

  const GatewayConnectConfig({
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

  GatewayConnectConfig copyWith({
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
    return GatewayConnectConfig(
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
      other is GatewayConnectConfig &&
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

String canonicalMobileClientId() {
  if (Platform.isAndroid) return 'openclaw-android';
  if (Platform.isIOS) return 'openclaw-ios';
  return 'node-host';
}

String? deviceFamilyForPlatform() {
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  return null;
}

abstract class GatewayPush {
  const GatewayPush();
}

class GatewayPushSnapshot extends GatewayPush {
  final HelloOk snapshot;

  const GatewayPushSnapshot(this.snapshot);
}

class HelloOk {
  final String type;
  final int protocol;
  final Map<String, dynamic> server;
  final Map<String, dynamic> features;
  final HelloSnapshot snapshot;
  final Map<String, dynamic>? pluginsurfaceurls;
  final Map<String, dynamic> auth;
  final Map<String, dynamic> policy;

  const HelloOk({
    required this.type,
    required this.protocol,
    required this.server,
    required this.features,
    required this.snapshot,
    this.pluginsurfaceurls,
    required this.auth,
    required this.policy,
  });

  factory HelloOk.fromJson(Map<String, dynamic> json) => HelloOk(
    type: json['type'] as String? ?? '',
    protocol: json['protocol'] as int? ?? 0,
    server: (json['server'] as Map?)?.cast<String, dynamic>() ?? {},
    features: (json['features'] as Map?)?.cast<String, dynamic>() ?? {},
    snapshot: HelloSnapshot.fromJson(
      (json['snapshot'] as Map?)?.cast<String, dynamic>() ?? {},
    ),
    pluginsurfaceurls:
        (json['pluginSurfaceUrls'] as Map?)?.cast<String, dynamic>(),
    auth: (json['auth'] as Map?)?.cast<String, dynamic>() ?? {},
    policy: (json['policy'] as Map?)?.cast<String, dynamic>() ?? {},
  );
}

class HelloSnapshot {
  final List<PresenceEntry> presence;
  final dynamic health;
  final StateVersion stateversion;
  final int uptimems;
  final String? configpath;
  final String? statedir;
  final Map<String, dynamic>? sessiondefaults;
  final dynamic authmode;
  final Map<String, dynamic>? updateavailable;

  const HelloSnapshot({
    required this.presence,
    required this.health,
    required this.stateversion,
    required this.uptimems,
    this.configpath,
    this.statedir,
    this.sessiondefaults,
    this.authmode,
    this.updateavailable,
  });

  factory HelloSnapshot.fromJson(Map<String, dynamic> json) => HelloSnapshot(
    presence:
        (json['presence'] as List? ?? [])
            .map(
              (e) => PresenceEntry.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList(),
    health: json['health'],
    stateversion: StateVersion.fromJson(
      (json['stateVersion'] as Map?)?.cast<String, dynamic>() ?? {},
    ),
    uptimems: json['uptimeMs'] as int? ?? 0,
    configpath: json['configPath'] as String?,
    statedir: json['stateDir'] as String?,
    sessiondefaults: (json['sessionDefaults'] as Map?)?.cast<String, dynamic>(),
    authmode: json['authMode'],
    updateavailable: (json['updateAvailable'] as Map?)?.cast<String, dynamic>(),
  );
}

class PresenceEntry {
  final String? host;
  final String? ip;
  final String? version;
  final String? platform;
  final String? devicefamily;
  final String? modelidentifier;
  final String? mode;
  final int? lastinputseconds;
  final String? reason;
  final List<String>? tags;
  final String? text;
  final int ts;
  final String? deviceid;
  final List<String>? roles;
  final List<String>? scopes;
  final String? instanceid;

  const PresenceEntry({
    this.host,
    this.ip,
    this.version,
    this.platform,
    this.devicefamily,
    this.modelidentifier,
    this.mode,
    this.lastinputseconds,
    this.reason,
    this.tags,
    this.text,
    required this.ts,
    this.deviceid,
    this.roles,
    this.scopes,
    this.instanceid,
  });

  factory PresenceEntry.fromJson(Map<String, dynamic> json) => PresenceEntry(
    host: json['host'] as String?,
    ip: json['ip'] as String?,
    version: json['version'] as String?,
    platform: json['platform'] as String?,
    devicefamily: json['deviceFamily'] as String?,
    modelidentifier: json['modelIdentifier'] as String?,
    mode: json['mode'] as String?,
    lastinputseconds: json['lastInputSeconds'] as int?,
    reason: json['reason'] as String?,
    tags: (json['tags'] as List?)?.cast<String>(),
    text: json['text'] as String?,
    ts: json['ts'] as int? ?? 0,
    deviceid: json['deviceId'] as String?,
    roles: (json['roles'] as List?)?.cast<String>(),
    scopes: (json['scopes'] as List?)?.cast<String>(),
    instanceid: json['instanceId'] as String?,
  );
}

class GatewayPushEvent extends GatewayPush {
  final String event;
  final dynamic payload;
  final int? seq;

  const GatewayPushEvent(this.event, this.payload, {this.seq});
}

class GatewayPushSeqGap extends GatewayPush {
  final int expected;
  final int received;

  const GatewayPushSeqGap({required this.expected, required this.received});
}

/// Structured error details returned by the gateway.
///
/// This mirrors Android's `GatewayErrorDetails` and intentionally keeps raw
/// protocol values instead of mapping them to the UI recovery enum.
class GatewayErrorDetails {
  final String? code;
  final bool canRetryWithDeviceToken;
  final String? recommendedNextStep;
  final bool? pauseReconnect;
  final String? reason;
  final String? requestId;
  final bool retryable;
  final int? clientMinProtocol;
  final int? clientMaxProtocol;
  final int? expectedProtocol;
  final int? minimumProbeProtocol;
  final String? clawhubWarning;
  final String? missingScope;
  final List<String> requiredScopes;

  const GatewayErrorDetails({
    required this.code,
    required this.canRetryWithDeviceToken,
    required this.recommendedNextStep,
    this.pauseReconnect,
    this.reason,
    this.requestId,
    this.retryable = false,
    this.clientMinProtocol,
    this.clientMaxProtocol,
    this.expectedProtocol,
    this.minimumProbeProtocol,
    this.clawhubWarning,
    this.missingScope,
    this.requiredScopes = const <String>[],
  });

  factory GatewayErrorDetails.fromJson(Map<String, dynamic> json) {
    return GatewayErrorDetails(
      code: _optionalString(json['code']),
      canRetryWithDeviceToken:
          _boolValue(json['canRetryWithDeviceToken']) ??
          _boolValue(json['can_retry_with_device_token']) ??
          false,
      recommendedNextStep: _optionalString(
        json['recommendedNextStep'] ?? json['recommended_next_step'],
      ),
      pauseReconnect: _boolValue(
        json['pauseReconnect'] ?? json['pause_reconnect'],
      ),
      reason: _optionalString(json['reason']),
      requestId: _optionalString(
        json['requestId'] ?? json['requestID'] ?? json['request_id'],
      ),
      retryable: _boolValue(json['retryable']) ?? false,
      clientMinProtocol: _intValue(
        json['clientMinProtocol'] ?? json['client_min_protocol'],
      ),
      clientMaxProtocol: _intValue(
        json['clientMaxProtocol'] ?? json['client_max_protocol'],
      ),
      expectedProtocol: _intValue(
        json['expectedProtocol'] ?? json['expected_protocol'],
      ),
      minimumProbeProtocol: _intValue(
        json['minimumProbeProtocol'] ?? json['minimum_probe_protocol'],
      ),
      clawhubWarning: _optionalString(
        json['clawhubWarning'] ?? json['clawhub_warning'] ?? json['warning'],
      ),
      missingScope: _optionalString(
        json['missingScope'] ?? json['missing_scope'],
      ),
      requiredScopes: _stringList(
        json['requiredScopes'] ?? json['required_scopes'],
      ),
    );
  }

  GatewayMissingScopeErrorDetails? missingScopeDetails() {
    final scope = missingScope?.trim() ?? '';
    final scopes = requiredScopes
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (code != 'MISSING_SCOPE' || scope.isEmpty || scopes.isEmpty) {
      return null;
    }
    return GatewayMissingScopeErrorDetails(
      missingScope: scope,
      requiredScopes: scopes,
    );
  }
}

/// Backwards-compatible alias for callers using the Android name.
class GatewayResponseError implements Exception {
  final String method;
  final String code;
  final String message;
  final Map<String, dynamic> details;
  final String? requestId;

  GatewayResponseError({
    required this.method,
    String? code,
    String? message,
    Map<String, dynamic>? details,
  }) : code = code!,
       message = message!,
       details = details ?? {},
       requestId = details?['requestId']?.toString();

  String? get detailsReason {
    final raw = details['reason'] as String?;
    final trimmed = raw?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  String toString() => message;
}

class GatewayDecodingError implements Exception {
  final String method;
  final String message;

  const GatewayDecodingError({required this.method, required this.message});

  @override
  String toString() => message;
}

enum GatewayErrorCode {
  pairingRequired,
  deviceNotPaired,
  deviceNotApproved,
  authRequired,
  authUnauthorized,
  authTokenMismatch,
  authBootstrapTokenInvalid,
  authDeviceTokenMismatch,
  authScopeMismatch,
  authRateLimited,
  protocolMismatch,
  deviceIdentityRequired,
  deviceAuthInvalid,
  networkUnavailable,
  connectTimeout,
  challengeTimeout,
  requestTimeout,
  connectionClosed,
  cancelled,
  serverError,
  unknown,
}

enum GatewayConnectionPhase {
  idle,
  connecting,
  connected,
  requesting,
  disconnected,
}

/// 把网关返回的原始错误码归类到 UI 可处理的恢复枚举。
///
/// 与 [GatewayErrorCode] 同处一个文件：调用方只需要协议层这一个 import，
/// 不必为此再去依赖 runtime。
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

class GatewayMissingScopeErrorDetails {
  final String missingScope;
  final List<String> requiredScopes;

  const GatewayMissingScopeErrorDetails({
    required this.missingScope,
    required this.requiredScopes,
  });

  @override
  bool operator ==(Object other) =>
      other is GatewayMissingScopeErrorDetails &&
      other.missingScope == missingScope &&
      _listEquals(other.requiredScopes, requiredScopes);

  @override
  int get hashCode => Object.hash(missingScope, Object.hashAll(requiredScopes));
}

bool _listEquals(List<String> a, List<String> b) {
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

class GatewayOperationResult<T> {
  final bool ok;
  final T? data;
  final GatewayResponseError? error;

  const GatewayOperationResult._({required this.ok, this.data, this.error});

  factory GatewayOperationResult.success({
    T? data,
    String? requestId,
    GatewayConnectionPhase phase = GatewayConnectionPhase.connected,
  }) => GatewayOperationResult<T>._(ok: true, data: data);

  factory GatewayOperationResult.failure({
    required GatewayResponseError error,
    GatewayConnectionPhase phase = GatewayConnectionPhase.disconnected,
  }) => GatewayOperationResult<T>._(ok: false, error: error);
}

String? _optionalString(Object? value) {
  final string = value?.toString().trim() ?? '';
  return string.isEmpty ? null : string;
}

bool? _boolValue(Object? value) {
  if (value is bool) return value;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
        return true;
      case 'false':
        return false;
    }
  }
  return null;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '');
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

final _sessionLog = Logger('GatewaySession');

/// JSON text that must remain a JSON string at the protocol boundary.
///
/// OpenClaw uses fields such as paramsJSON/payloadJSON whose values are JSON
/// documents encoded as strings. This type makes that boundary explicit and
/// prevents callers from accidentally decoding and re-encoding the document.
class RawJson {
  final String text;

  const RawJson(this.text);

  factory RawJson.fromValue(Object? value) => RawJson(jsonEncode(value));

  dynamic decode() => jsonDecode(text);

  String get value => text;

  @override
  String toString() => text;
}

abstract interface class GatewaySocket {
  Stream<dynamic> get stream;

  Future<void> get ready;

  void send(String data);

  Future<void> close();
}

abstract interface class GatewaySocketFactory {
  GatewaySocket connect(Uri uri, {required Duration timeout});
}

class IOWebSocketGatewaySocket implements GatewaySocket {
  final IOWebSocketChannel _channel;

  IOWebSocketGatewaySocket(this._channel);

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  Future<void> get ready => _channel.ready;

  @override
  void send(String data) => _channel.sink.add(data);

  @override
  Future<void> close() async {
    await _channel.sink.close();
  }
}

class DefaultGatewaySocketFactory implements GatewaySocketFactory {
  const DefaultGatewaySocketFactory();

  @override
  GatewaySocket connect(Uri uri, {required Duration timeout}) =>
      IOWebSocketGatewaySocket(
        IOWebSocketChannel.connect(uri, connectTimeout: timeout),
      );
}

enum GatewaySessionState {
  idle,
  connecting,
  authenticating,
  ready,
  disconnected,
  reconnecting,
  paused,
  shuttingDown,
}

class GatewayRetryPolicy {
  final Duration initialDelay;
  final double multiplier;
  final Duration maxDelay;

  const GatewayRetryPolicy({
    this.initialDelay = const Duration(seconds: 2),
    this.multiplier = 2,
    this.maxDelay = const Duration(seconds: 30),
  });
}

class GatewaySession {
  final String url;
  final String? token;
  final String? password;
  final String? bootstrapToken;
  final void Function(GatewayPush push) pushHandler;
  final void Function(String reason)? disconnectHandler;
  final GatewayConnectOptions? connectOptions;
  final GatewaySocketFactory socketFactory;
  final DateTime Function() clock;
  final String Function() idGenerator;
  final GatewayRetryPolicy retryPolicy;
  final Duration connectTimeout;
  final Duration challengeTimeout;
  final Duration defaultRequestTimeout;

  /// 关闭旧 socket 的等待上限。
  ///
  /// dart:io 的 `WebSocket.close()` 要等对端回一个 close 帧才算完成，对端已经
  /// 消失（进程被杀 / 掉线 / 休眠）时要靠它自己 5s 的收尾定时器才返回。这条
  /// 会话只关心「别再从这个 socket 收数据」，不该被这段等待拖住。
  static const Duration socketCloseTimeout = Duration(seconds: 2);

  GatewaySocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  final Map<String, _PendingRequest> _pending = {};
  final List<Completer<void>> _connectWaiters = [];
  Completer<String>? _challenge;
  Timer? _reconnectTimer;
  Timer? _tickTimer;
  int _generation = 0;
  int? _lastSeq;
  DateTime? _lastTick;
  Duration _backoff;
  GatewaySessionState _state = GatewaySessionState.idle;
  GatewayAuthSource _lastAuthSource = GatewayAuthSource.none;
  bool _shouldReconnect = true;
  bool _listening = false;
  bool _attemptInFlight = false;
  double _tickIntervalMs = 30000;

  final Logger _log = Logger('GatewaySession');

  GatewaySession({
    required this.url,
    required this.token,
    required this.password,
    this.bootstrapToken,
    required this.pushHandler,
    this.connectOptions,
    this.disconnectHandler,
    GatewaySocketFactory? socketFactory,
    DateTime Function()? clock,
    String Function()? idGenerator,
    this.retryPolicy = const GatewayRetryPolicy(),
    this.connectTimeout = const Duration(seconds: 30),
    this.challengeTimeout = const Duration(seconds: 6),
    this.defaultRequestTimeout = const Duration(seconds: 15),
  }) : socketFactory = socketFactory ?? const DefaultGatewaySocketFactory(),
       clock = clock ?? DateTime.now,
       idGenerator = idGenerator ?? const Uuid().v4,
       _backoff = retryPolicy.initialDelay;

  GatewaySessionState get state => _state;

  bool get connected => _state == GatewaySessionState.ready;

  /// Whether a connection attempt is actively in progress.
  ///
  /// 这里用「尝试是否在飞」而不是从 [_state] 推导：重连尝试期间 `_state` 是
  /// `reconnecting`（对 UI 有意义），按状态推导会得出 false，于是
  /// [_scheduleReconnect] 的定时器回调会误判「已经有尝试在跑」，并发的
  /// `connect()` 也不会合并成同一个 waiter。
  bool get isConnecting => _attemptInFlight;

  int get generation => _generation;

  int get pendingCount => _pending.length;

  GatewayAuthSource authSource() => _lastAuthSource;

  Future<void> connect() async {
    if (connected && _socket != null) return;
    if (_attemptInFlight) {
      final waiter = Completer<void>();
      _connectWaiters.add(waiter);
      return waiter.future;
    }

    final generation = ++_generation;
    _attemptInFlight = true;
    _state =
        _state == GatewaySessionState.disconnected ||
                _state == GatewaySessionState.reconnecting
            ? GatewaySessionState.reconnecting
            : GatewaySessionState.connecting;
    _shouldReconnect = true;
    _cancelReconnect();
    // 旧 socket 只摘不等：它的 close 可能要等好几秒，重连不该被拖住。
    await _disposeSocket(waitForClose: false);
    _challenge = Completer<String>();
    // 失败路径会在没人 await 的情况下用错误结束 challenge（例如握手前的
    // socket.ready 抛错）。挂一个空监听，避免变成未处理的异步异常。
    _challenge!.future.ignore();

    try {
      final hello = await () async {
        final socket = socketFactory.connect(
          Uri.parse(url),
          timeout: connectTimeout,
        );
        _socket = socket;
        _listen(socket, generation);
        await socket.ready;
        _state = GatewaySessionState.authenticating;
        return _sendConnect(generation);
      }().timeout(connectTimeout);

      if (!_isCurrent(generation)) return;
      // 顺序很关键：**先翻状态，再推 hello 快照**。
      // 订阅者（GatewayRepository）收到快照的那一刻就会读 `connected` 来判定
      // 「这次握手算不算连上」。若此时还是 authenticating，它会认为会话尚未
      // 就绪而丢弃这份 hello —— 于是断线之后 socket 明明自己连回来了，UI 却
      // 永远停在「正在自动重连」。首次连接因为 `_doConnect` 有兜底看不出来，
      // 只有自愈路径会踩到。
      _state = GatewaySessionState.ready;
      _backoff = retryPolicy.initialDelay;
      _lastSeq = null;
      _startTickWatchdog(generation);
      pushHandler(GatewayPushSnapshot(hello));
      _completeConnectWaiters();
    } catch (error, stack) {
      if (_isCurrent(generation)) {
        await _disposeSocket(waitForClose: false);
        _completeConnectWaiters(error, stack);
        disconnectHandler?.call(error.toString());
      }
      // 不管这次尝试还算不算「当前」，都不能让重连断档：
      // - generation 被 `_handleDisconnect` 顶掉时，它已经排过一次，这里被
      //   `_reconnectTimer?.isActive` 挡掉；
      // - 被 `shutdown()` 顶掉时 `_shouldReconnect` 已是 false，自然不排。
      _scheduleReconnect();
      Error.throwWithStackTrace(error, stack);
    } finally {
      _attemptInFlight = false;
    }
  }

  Future<void> shutdown() async {
    _shouldReconnect = false;
    _state = GatewaySessionState.shuttingDown;
    ++_generation;
    _cancelReconnect();
    _tickTimer?.cancel();
    _tickTimer = null;
    await _disposeSocket(shutdown: true);
    _completeConnectWaiters();
    _state = GatewaySessionState.idle;
  }

  /// Drops the current socket and immediately opens a fresh one.
  ///
  /// Unlike [connect] this never short-circuits on `connected`: a half-open
  /// socket keeps `_state == ready` long after the peer is gone, so the only
  /// way to recover from a stale connection is to tear the socket down first.
  /// Reconnect stays enabled, so a failed attempt falls back to the regular
  /// backoff loop.
  Future<void> forceReconnect() async {
    if (_state == GatewaySessionState.shuttingDown ||
        _state == GatewaySessionState.idle) {
      return;
    }
    _shouldReconnect = true;
    _cancelReconnect();
    _tickTimer?.cancel();
    _tickTimer = null;
    ++_generation;
    await _disposeSocket(waitForClose: false);
    _state = GatewaySessionState.disconnected;
    await connect();
  }

  Future<Map<String, dynamic>> request({
    required String method,
    Map<String, dynamic>? params,
    Duration? timeout,
  }) async {
    await connect();
    final socket = _socket;
    final generation = _generation;
    if (socket == null || !_isCurrent(generation) || !connected) {
      throw StateError('gateway socket unavailable');
    }

    final id = idGenerator();
    final completer = Completer<Map<String, dynamic>>();
    final pending = _PendingRequest(generation, completer);
    _pending[id] = pending;
    final timer = Timer(timeout ?? defaultRequestTimeout, () {
      final current = _pending[id];
      if (identical(current, pending)) {
        _pending.remove(id);
        if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException('gateway request timed out', timeout),
          );
        }
      }
    });
    pending.timer = timer;

    try {
      socket.send(_encodeRequest(id, method, params));
    } catch (error, stack) {
      timer.cancel();
      _pending.remove(id);
      if (!completer.isCompleted) Error.throwWithStackTrace(error, stack);
      rethrow;
    }

    return _finishResponse(method, completer.future);
  }

  Future<Map<String, dynamic>> _requestFrame({
    required String method,
    required Map<String, dynamic> params,
    required Duration timeout,
    required int generation,
    bool finishResponse = true,
  }) async {
    final socket = _socket;
    if (socket == null) throw StateError('gateway socket unavailable');
    final id = idGenerator();
    final completer = Completer<Map<String, dynamic>>();
    final pending = _PendingRequest(generation, completer);
    _pending[id] = pending;
    pending.timer = Timer(timeout, () {
      if (identical(_pending[id], pending)) {
        _pending.remove(id);
        if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException('gateway request timed out', timeout),
          );
        }
      }
    });
    try {
      socket.send(_encodeRequest(id, method, params));
    } catch (error, stack) {
      pending.timer?.cancel();
      _pending.remove(id);
      Error.throwWithStackTrace(error, stack);
    }
    final response = await completer.future;
    return finishResponse
        ? _finishResponse(method, Future.value(response))
        : response;
  }

  Future<Map<String, dynamic>> _finishResponse(
    String method,
    Future<Map<String, dynamic>> future,
  ) async {
    final response = await future;
    if (response['ok'] == false) {
      final error = (response['error'] as Map?)?.cast<String, dynamic>() ?? {};
      throw GatewayResponseError(
        method: method,
        code: error['code'] as String?,
        message: error['message'] as String?,
        details: (error['details'] as Map?)?.cast<String, dynamic>(),
      );
    }
    final payload = response['payload'];
    if (payload == null) return <String, dynamic>{};
    if (payload is String) {
      final decoded = jsonDecode(payload);
      if (decoded is Map) return decoded.cast<String, dynamic>();
      throw GatewayDecodingError(
        method: method,
        message: 'payload is not an object',
      );
    }
    if (payload is Map) return payload.cast<String, dynamic>();
    throw GatewayDecodingError(
      method: method,
      message: 'payload is not an object',
    );
  }

  Future<Map<String, dynamic>> requestRawJson({
    required String method,
    required Map<String, dynamic> params,
    Duration? timeout,
  }) => request(method: method, params: params, timeout: timeout);

  Future<Map<String, dynamic>> requestWithRawJson({
    required String method,
    required Map<String, dynamic> params,
    Duration? timeout,
  }) => requestRawJson(method: method, params: params, timeout: timeout);

  Future<void> send({
    required String method,
    Map<String, dynamic>? params,
  }) async {
    await connect();
    final socket = _socket;
    if (socket == null) throw StateError('gateway socket unavailable');
    socket.send(_encodeRequest(idGenerator(), method, params));
  }

  String _encodeRequest(
    String id,
    String method,
    Map<String, dynamic>? params,
  ) => jsonEncode({
    'type': 'req',
    'id': id,
    'method': method,
    if (params != null) 'params': params,
  });

  void _listen(GatewaySocket socket, int generation) {
    _listening = true;
    _subscription = socket.stream.listen(
      (raw) => _handleRaw(raw, generation),
      onError:
          (Object error, StackTrace stack) =>
              _handleDisconnect(error.toString(), generation),
      onDone: () => _handleDisconnect('closed', generation),
      cancelOnError: false,
    );
  }

  void _handleRaw(dynamic raw, int generation) {
    if (!_isCurrent(generation)) return;
    // 任何一帧都证明对端还活着，不只是 tick 事件。
    _lastTick = clock();
    final decoded = raw is String ? raw : utf8.decode(raw as List<int>);
    final frame = jsonDecode(decoded);
    if (frame is! Map) return;
    final map = frame.cast<String, dynamic>();
    switch (map['type']) {
      case 'res':
        final id = map['id'] as String?;
        final pending = id == null ? null : _pending.remove(id);
        if (pending != null && pending.generation == generation) {
          pending.timer?.cancel();
          pending.completer.complete(map);
        }
      case 'event':
        final event = map['event'] as String?;
        if (event == 'connect.challenge') {
          final nonce = (map['payload'] as Map?)?['nonce'] as String?;
          if (nonce != null && !(_challenge?.isCompleted ?? true))
            _challenge!.complete(nonce);
          return;
        }
        final seq = (map['seq'] as num?)?.toInt();
        if (seq != null) {
          final last = _lastSeq;
          if (last != null && seq > last + 1) {
            pushHandler(GatewayPushSeqGap(expected: last + 1, received: seq));
          }
          _lastSeq = seq;
        }
        if (event != null)
          pushHandler(GatewayPushEvent(event, map['payload'], seq: seq));
    }
  }

  Future<HelloOk> _sendConnect(int generation) async {
    final options =
        connectOptions ??
        const GatewayConnectOptions(
          role: 'operator',
          scopes: [
            'operator.admin',
            'operator.read',
            'operator.write',
            'operator.approvals',
            'operator.pairing',
          ],
          caps: [],
          commands: [],
          permissions: {},
          clientId: 'gateway-client',
          clientMode: 'ui',
          clientDisplayName: 'parrotClaw',
        );
    final nonce = await (_challenge?.future ??
            Future.error('challenge unavailable'))
        .timeout(challengeTimeout);
    if (!_isCurrent(generation)) throw StateError('stale gateway generation');

    DeviceIdentity? identity;
    String? signature;
    int? signedAtMs;
    if (options.includeDeviceIdentity) {
      identity = await DeviceIdentityManager.getOrCreate();
      signedAtMs = clock().millisecondsSinceEpoch;
      final payload = identity.buildAuthPayload(
        clientId: options.clientId,
        clientMode: options.clientMode,
        role: options.role,
        scopes: options.scopes,
        signedAtMs: signedAtMs,
        token: token ?? bootstrapToken,
        nonce: nonce,
        platform: Platform.operatingSystem,
        deviceFamily: deviceFamilyForPlatform(),
      );
      signature = identity.signPayload(payload);
    }
    final params = <String, dynamic>{
      'minProtocol': 4,
      'maxProtocol': 4,
      'client': {
        'id': options.clientId,
        'displayName': options.clientDisplayName ?? options.clientId,
        'version': '1.0.0',
        'platform': Platform.operatingSystem,
        'mode': options.clientMode,
        if (deviceFamilyForPlatform() != null)
          'deviceFamily': deviceFamilyForPlatform(),
      },
      'caps': options.caps,
      'locale': Platform.localeName,
      'userAgent': Platform.operatingSystemVersion,
      'role': options.role,
      'scopes': options.scopes,
      if (options.commands.isNotEmpty) 'commands': options.commands,
      if (options.permissions.isNotEmpty) 'permissions': options.permissions,
      if (token != null) 'auth': {'token': token},
      if (password != null) 'auth': {'password': password},
      if (bootstrapToken != null && token == null && password == null)
        'auth': {'bootstrapToken': bootstrapToken},
      if (identity != null)
        'device': {
          'id': identity.deviceId,
          'publicKey': identity.publicKey,
          'signature': signature,
          'signedAt': signedAtMs,
          'nonce': nonce,
        },
    };
    _lastAuthSource =
        token != null
            ? GatewayAuthSource.sharedToken
            : password != null
            ? GatewayAuthSource.password
            : bootstrapToken != null
            ? GatewayAuthSource.bootstrapToken
            : GatewayAuthSource.none;

    final response = await _requestFrame(
      method: 'connect',
      params: params,
      timeout: connectTimeout,
      generation: generation,
      finishResponse: false,
    );
    if (response['ok'] == false) {
      final error = (response['error'] as Map?)?.cast<String, dynamic>() ?? {};
      throw GatewayResponseError(
        method: 'connect',
        code: error['code'] as String?,
        message: error['message'] as String?,
        details: (error['details'] as Map?)?.cast<String, dynamic>(),
      );
    }
    final helloPayload = response['payload'];
    if (helloPayload is String) {
      final decoded = jsonDecode(helloPayload);
      if (decoded is Map) {
        response['payload'] = decoded;
      }
    }
    if (response['payload'] is! Map)
      throw StateError('connect failed (missing payload)');
    final hello = HelloOk.fromJson(
      (response['payload'] as Map).cast<String, dynamic>(),
    );
    final tick = hello.policy['tickIntervalMs'];
    if (tick is num && tick > 0) _tickIntervalMs = tick.toDouble();
    // 快照不在这里推：调用方要先翻到 ready，订阅者才认这份 hello。
    return hello;
  }

  /// tick 看门狗。
  ///
  /// 为什么需要它：TCP 半开（对端进程被杀、Wi-Fi 掉线、机器休眠）时 socket
  /// 既不会报错也不会 EOF，`_state` 会一直停在 ready —— 只要当下没有请求在
  /// 飞，App 就会永远显示「已连接」，也就谈不上自动重连。这里拿「对端静默
  /// 时长」当死亡判据：超过两个 tick 周期没有任何一帧到达，就判掉线，交给
  /// 退避重连把连接重开。
  ///
  /// 检查周期取 **一个** tick（而不是两个）：阈值既然是两个 tick，按两个
  /// tick 去查就总要等到第二个检查点才动手，判死时间被无谓地拉长一倍。
  void _startTickWatchdog(int generation) {
    _tickTimer?.cancel();
    _lastTick = clock();
    final tickMs = _tickIntervalMs > 0 ? _tickIntervalMs : 30000.0;
    final checkMs = tickMs < 1 ? 1 : tickMs.round();
    final deadlineMs = tickMs * 2;
    _tickTimer = Timer.periodic(Duration(milliseconds: checkMs), (_) {
      if (!_isCurrent(generation) || !connected) return;
      final last = _lastTick;
      if (last == null) return;
      if (clock().difference(last).inMilliseconds >= deadlineMs) {
        _handleDisconnect('gateway tick missed', generation);
      }
    });
  }

  void _handleDisconnect(String reason, int generation) {
    if (!_isCurrent(generation) ||
        _state == GatewaySessionState.shuttingDown ||
        _state == GatewaySessionState.idle)
      return;
    _generation++;
    _state = GatewaySessionState.disconnected;
    _listening = false;
    _tickTimer?.cancel();
    _tickTimer = null;
    _failPending(StateError('gateway connection closed: $reason'));
    // 立刻把旧 socket 摘掉。留着它的话，下一次 connect() 会在它的 close()
    // 上等（对端已消失时最长 5s），重连被白白推迟。
    unawaited(_disposeSocket(waitForClose: false));
    disconnectHandler?.call(reason);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect ||
        _state == GatewaySessionState.paused ||
        (_reconnectTimer?.isActive ?? false))
      return;
    final delay = _backoff;
    final nextDelay = Duration(
      milliseconds: (_backoff.inMilliseconds * retryPolicy.multiplier).round(),
    );
    _backoff = nextDelay.compareTo(retryPolicy.maxDelay) > 0
        ? retryPolicy.maxDelay
        : nextDelay;
    _state = GatewaySessionState.reconnecting;
    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      if (!_shouldReconnect || connected) return;
      // 不在这里判 `isConnecting` 并直接 return：万一真有一次尝试还在飞，
      // 直接返回会让重连就此断档。交给 connect() 自己合并成 waiter，
      // 那次尝试无论成败都会收尾并（失败时）再排一次。
      try {
        await connect();
      } catch (error) {
        _sessionLog.warning('gateway reconnect failed: $error');
      }
    });
  }

  /// 摘掉当前 socket。
  ///
  /// [waitForClose] 默认 true（主动 shutdown 时用）；**重连路径一律传 false**：
  /// 取消订阅之后旧 socket 已经不会再投递任何东西，没必要等它的 close 完成。
  Future<void> _disposeSocket({
    bool failPending = true,
    bool waitForClose = true,
    bool shutdown = false,
  }) async {
    final subscription = _subscription;
    _subscription = null;
    _listening = false;
    if (failPending) {
      _failPending(
        StateError(
          shutdown ? 'gateway session shutdown' : 'gateway socket replaced',
        ),
      );
    }
    final socket = _socket;
    _socket = null;
    await subscription?.cancel();
    if (socket == null) return;
    final closing = _closeSocket(socket);
    if (waitForClose) await closing;
  }

  /// 关闭一条已经不属于本会话的 socket，超时与报错一律吞掉。
  Future<void> _closeSocket(GatewaySocket socket) async {
    try {
      await socket.close().timeout(socketCloseTimeout);
    } catch (error) {
      _log.fine('gateway socket close ignored: $error');
    }
  }

  void _failPending(Object error) {
    final entries = List<_PendingRequest>.from(_pending.values);
    _pending.clear();
    for (final pending in entries) {
      pending.timer?.cancel();
      if (!pending.completer.isCompleted)
        pending.completer.completeError(error);
    }
    final challenge = _challenge;
    if (challenge != null && !challenge.isCompleted)
      challenge.completeError(error);
  }

  bool _isCurrent(int generation) => generation == _generation;

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _completeConnectWaiters([Object? error, StackTrace? stack]) {
    final waiters = List<Completer<void>>.from(_connectWaiters);
    _connectWaiters.clear();
    for (final waiter in waiters) {
      if (waiter.isCompleted) continue;
      if (error == null) {
        waiter.complete();
      } else if (stack != null) {
        waiter.completeError(error, stack);
      } else {
        waiter.completeError(error);
      }
    }
  }
}

class _PendingRequest {
  final int generation;
  final Completer<Map<String, dynamic>> completer;
  Timer? timer;

  _PendingRequest(this.generation, this.completer);
}
