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
  }) : code = (code?.trim().isEmpty == false) ? code!.trim() : 'GATEWAY_ERROR',
        message =
        (message?.trim().isEmpty == false)
            ? message!.trim()
            : 'gateway error',
        details = details ?? {},
        requestId = details?['requestId']?.toString() ??
            details?['requestID']?.toString() ??
            details?['request_id']?.toString();

  String? get detailsReason {
    final raw = details['reason'] as String?;
    final trimmed = raw?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  String toString() =>
      code == 'GATEWAY_ERROR'
          ? 'GatewayResponseError($method): $message'
          : 'GatewayResponseError($method): [$code] $message';
}

class GatewayDecodingError implements Exception {
  final String method;
  final String message;

  const GatewayDecodingError({required this.method, required this.message});

  @override
  String toString() => 'GatewayDecodingError($method): $message';
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

enum GatewayRecoveryAction {
  showPairingPage,
  retryWithDeviceToken,
  updateCredentials,
  retryAfterDelay,
  upgradeClient,
  scanAgain,
  manualActionRequired,
  none,
}

class GatewayErrorInfo {
  final GatewayErrorCode code;
  final String message;
  final String? reason;
  final String? requestId;
  final String? deviceId;
  final String? owner;
  final String? title;
  final String? userMessage;
  final String? actionLabel;
  final String? actionCommand;
  final String? docsUrl;
  final bool retryable;
  final bool pauseReconnect;
  final Map<String, dynamic> rawDetails;

  const GatewayErrorInfo({
    required this.code,
    required this.message,
    this.reason,
    this.requestId,
    this.deviceId,
    this.owner,
    this.title,
    this.userMessage,
    this.actionLabel,
    this.actionCommand,
    this.docsUrl,
    required this.retryable,
    required this.pauseReconnect,
    this.rawDetails = const <String, dynamic>{},
  });

  GatewayRecoveryAction get recoveryAction {
    switch (code) {
      case GatewayErrorCode.pairingRequired:
      case GatewayErrorCode.deviceNotPaired:
      case GatewayErrorCode.deviceNotApproved:
        return GatewayRecoveryAction.showPairingPage;
      case GatewayErrorCode.authTokenMismatch:
      case GatewayErrorCode.authDeviceTokenMismatch:
        return GatewayRecoveryAction.retryWithDeviceToken;
      case GatewayErrorCode.authUnauthorized:
      case GatewayErrorCode.authRequired:
      case GatewayErrorCode.authBootstrapTokenInvalid:
      case GatewayErrorCode.authScopeMismatch:
        return GatewayRecoveryAction.updateCredentials;
      case GatewayErrorCode.protocolMismatch:
        return GatewayRecoveryAction.upgradeClient;
      case GatewayErrorCode.authRateLimited:
        return GatewayRecoveryAction.retryAfterDelay;
      case GatewayErrorCode.networkUnavailable:
      case GatewayErrorCode.connectTimeout:
      case GatewayErrorCode.challengeTimeout:
      case GatewayErrorCode.requestTimeout:
      case GatewayErrorCode.connectionClosed:
        return GatewayRecoveryAction.scanAgain;
      case GatewayErrorCode.deviceIdentityRequired:
      case GatewayErrorCode.deviceAuthInvalid:
      case GatewayErrorCode.serverError:
      case GatewayErrorCode.cancelled:
      case GatewayErrorCode.unknown:
        return GatewayRecoveryAction.manualActionRequired;
    }
  }
}

class GatewayOperationResult<T> {
  final bool ok;
  final T? data;
  final GatewayErrorInfo? error;
  final String? requestId;
  final GatewayConnectionPhase phase;
  final bool retryable;
  final GatewayRecoveryAction recoveryAction;

  const GatewayOperationResult._({
    required this.ok,
    this.data,
    this.error,
    this.requestId,
    required this.phase,
    required this.retryable,
    required this.recoveryAction,
  });

  factory GatewayOperationResult.success({
    T? data,
    String? requestId,
    GatewayConnectionPhase phase = GatewayConnectionPhase.connected,
  }) => GatewayOperationResult<T>._(
    ok: true,
    data: data,
    requestId: requestId,
    phase: phase,
    retryable: false,
    recoveryAction: GatewayRecoveryAction.none,
  );

  factory GatewayOperationResult.failure({
    required GatewayErrorInfo error,
    GatewayConnectionPhase phase = GatewayConnectionPhase.disconnected,
  }) => GatewayOperationResult<T>._(
    ok: false,
    error: error,
    requestId: error.requestId,
    phase: phase,
    retryable: error.retryable,
    recoveryAction: error.recoveryAction,
  );
}

GatewayErrorInfo gatewayErrorInfoFrom(Object error, {String? method}) {
  if (error is GatewayResponseError) {
    final details = Map<String, dynamic>.from(error.details);
    final rawCode = error.code.toUpperCase();
    final code = _gatewayErrorCodeFromRaw(rawCode, error.message, details);
    return GatewayErrorInfo(
      code: code,
      message: error.message,
      reason: error.detailsReason,
      requestId: error.requestId,
      deviceId: _firstString(details, const [
        'deviceId',
        'device_id',
        'requestId',
        'requestID',
        'request_id',
      ]),
      owner: _firstString(details, const ['owner']),
      title: _firstString(details, const ['title']),
      userMessage: _firstString(details, const ['userMessage', 'user_message']),
      actionLabel: _firstString(details, const ['actionLabel', 'action_label']),
      actionCommand: _firstString(details, const ['actionCommand', 'action_command']),
      docsUrl: _firstString(details, const ['docsUrl', 'docs_url']),
      retryable: _retryableFor(code),
      pauseReconnect: _pauseReconnectFor(code),
      rawDetails: details,
    );
  }

  final message = error.toString();
  final code = error is TimeoutException
      ? (method == 'connect'
      ? GatewayErrorCode.connectTimeout
      : GatewayErrorCode.requestTimeout)
      : error is SocketException
      ? GatewayErrorCode.networkUnavailable
      : GatewayErrorCode.unknown;
  return GatewayErrorInfo(
    code: code,
    message: message,
    retryable: code != GatewayErrorCode.unknown,
    pauseReconnect: false,
  );
}

String? _firstString(Map<String, dynamic> details, List<String> keys) {
  for (final key in keys) {
    final value = details[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

GatewayErrorCode _gatewayErrorCodeFromRaw(
    String raw,
    String message,
    Map<String, dynamic> details,
    ) {
  final detailCode = _firstString(details, const ['code', 'detailCode']);
  final normalized = '$raw ${detailCode ?? ''} ${message.toUpperCase()}'.toUpperCase();
  if (normalized.contains('PAIRING_REQUIRED')) {
    return GatewayErrorCode.pairingRequired;
  }
  if (normalized.contains('NOT_PAIRED')) return GatewayErrorCode.deviceNotPaired;
  if (normalized.contains('NOT_APPROVED') ||
      normalized.contains('NOT APPROVED')) {
    return GatewayErrorCode.deviceNotApproved;
  }
  if (normalized.contains('PROTOCOL')) return GatewayErrorCode.protocolMismatch;
  if (normalized.contains('RATE_LIMIT')) return GatewayErrorCode.authRateLimited;
  if (normalized.contains('BOOTSTRAP')) return GatewayErrorCode.authBootstrapTokenInvalid;
  if (normalized.contains('DEVICE_TOKEN')) return GatewayErrorCode.authDeviceTokenMismatch;
  if (normalized.contains('TOKEN_MISMATCH')) return GatewayErrorCode.authTokenMismatch;
  if (normalized.contains('SCOPE')) return GatewayErrorCode.authScopeMismatch;
  if (normalized.contains('UNAUTHORIZED') || normalized.contains('AUTH_INVALID')) {
    return GatewayErrorCode.authUnauthorized;
  }
  if (normalized.contains('AUTH_REQUIRED') || normalized.contains('TOKEN_MISSING')) {
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

bool _retryableFor(GatewayErrorCode code) => switch (code) {
  GatewayErrorCode.networkUnavailable ||
  GatewayErrorCode.connectTimeout ||
  GatewayErrorCode.challengeTimeout ||
  GatewayErrorCode.requestTimeout ||
  GatewayErrorCode.connectionClosed ||
  GatewayErrorCode.serverError ||
  GatewayErrorCode.authRateLimited => true,
  _ => false,
};

bool _pauseReconnectFor(GatewayErrorCode code) => switch (code) {
  GatewayErrorCode.pairingRequired ||
  GatewayErrorCode.deviceNotPaired ||
  GatewayErrorCode.deviceNotApproved ||
  GatewayErrorCode.authUnauthorized ||
  GatewayErrorCode.authTokenMismatch ||
  GatewayErrorCode.authBootstrapTokenInvalid ||
  GatewayErrorCode.authDeviceTokenMismatch ||
  GatewayErrorCode.authScopeMismatch ||
  GatewayErrorCode.protocolMismatch ||
  GatewayErrorCode.deviceIdentityRequired ||
  GatewayErrorCode.deviceAuthInvalid => true,
  _ => false,
};

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
    this.initialDelay = const Duration(milliseconds: 350),
    this.multiplier = 1.7,
    this.maxDelay = const Duration(seconds: 8),
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
  double _tickIntervalMs = 30000;

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
  /// `reconnecting` is only a scheduled state, not an active attempt. It must
  /// not be included here, otherwise the timer callback in `_scheduleReconnect`
  /// calls `connect()` and gets queued as a waiter forever instead of starting
  /// the next socket attempt.
  bool get isConnecting =>
      _state == GatewaySessionState.connecting ||
      _state == GatewaySessionState.authenticating;
  int get generation => _generation;
  int get pendingCount => _pending.length;
  GatewayAuthSource authSource() => _lastAuthSource;

  Future<void> connect() async {
    if (connected && _socket != null) return;
    if (isConnecting) {
      final waiter = Completer<void>();
      _connectWaiters.add(waiter);
      return waiter.future;
    }

    final generation = ++_generation;
    _state = _state == GatewaySessionState.disconnected ||
            _state == GatewaySessionState.reconnecting
        ? GatewaySessionState.reconnecting
        : GatewaySessionState.connecting;
    _shouldReconnect = true;
    _cancelReconnect();
    await _disposeSocket(failPending: true);
    _challenge = Completer<String>();

    try {
      await () async {
        final socket = socketFactory.connect(Uri.parse(url), timeout: connectTimeout);
        _socket = socket;
        _listen(socket, generation);
        await socket.ready;
        _state = GatewaySessionState.authenticating;
        await _sendConnect(generation);
      }().timeout(connectTimeout);

      if (!_isCurrent(generation)) return;
      _state = GatewaySessionState.ready;
      _backoff = retryPolicy.initialDelay;
      _lastSeq = null;
      _startTickWatchdog(generation);
      _completeConnectWaiters();
    } catch (error, stack) {
      if (_isCurrent(generation)) {
        final errorInfo = gatewayErrorInfoFrom(error, method: 'connect');
        if (errorInfo.pauseReconnect) {
          _state = GatewaySessionState.paused;
        } else {
          _state = GatewaySessionState.disconnected;
        }
        await _disposeSocket(failPending: true);
        _completeConnectWaiters(error, stack);
        disconnectHandler?.call(error.toString());
        if (_state != GatewaySessionState.paused) {
          _scheduleReconnect();
        }
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> shutdown() async {
    _shouldReconnect = false;
    _state = GatewaySessionState.shuttingDown;
    ++_generation;
    _cancelReconnect();
    _tickTimer?.cancel();
    _tickTimer = null;
    await _disposeSocket(failPending: true, shutdown: true);
    _completeConnectWaiters();
    _state = GatewaySessionState.idle;
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
          completer.completeError(TimeoutException('gateway request timed out', timeout));
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
    return finishResponse ? _finishResponse(method, Future.value(response)) : response;
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
      throw GatewayDecodingError(method: method, message: 'payload is not an object');
    }
    if (payload is Map) return payload.cast<String, dynamic>();
    throw GatewayDecodingError(method: method, message: 'payload is not an object');
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

  Future<void> send({required String method, Map<String, dynamic>? params}) async {
    await connect();
    final socket = _socket;
    if (socket == null) throw StateError('gateway socket unavailable');
    socket.send(_encodeRequest(idGenerator(), method, params));
  }

  String _encodeRequest(String id, String method, Map<String, dynamic>? params) =>
      jsonEncode({
        'type': 'req',
        'id': id,
        'method': method,
        if (params != null) 'params': params,
      });

  void _listen(GatewaySocket socket, int generation) {
    _listening = true;
    _subscription = socket.stream.listen(
      (raw) => _handleRaw(raw, generation),
      onError: (Object error, StackTrace stack) => _handleDisconnect(error.toString(), generation),
      onDone: () => _handleDisconnect('closed', generation),
      cancelOnError: false,
    );
  }

  void _handleRaw(dynamic raw, int generation) {
    if (!_isCurrent(generation)) return;
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
          if (nonce != null && !(_challenge?.isCompleted ?? true)) _challenge!.complete(nonce);
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
        if (event == 'tick') _lastTick = clock();
        if (event != null) pushHandler(GatewayPushEvent(event, map['payload'], seq: seq));
    }
  }

  Future<void> _sendConnect(int generation) async {
    final options = connectOptions ?? const GatewayConnectOptions(
      role: 'operator',
      scopes: ['operator.admin', 'operator.read', 'operator.write', 'operator.approvals', 'operator.pairing'],
      caps: [], commands: [], permissions: {}, clientId: 'gateway-client', clientMode: 'ui', clientDisplayName: 'parrotClaw',
    );
    final nonce = await (_challenge?.future ?? Future.error('challenge unavailable')).timeout(challengeTimeout);
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
        if (deviceFamilyForPlatform() != null) 'deviceFamily': deviceFamilyForPlatform(),
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
      if (bootstrapToken != null && token == null && password == null) 'auth': {'bootstrapToken': bootstrapToken},
      if (identity != null) 'device': {
        'id': identity.deviceId,
        'publicKey': identity.publicKey,
        'signature': signature,
        'signedAt': signedAtMs,
        'nonce': nonce,
      },
    };
    _lastAuthSource = token != null
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
    if (response['payload'] is! Map) throw StateError('connect failed (missing payload)');
    final hello = HelloOk.fromJson((response['payload'] as Map).cast<String, dynamic>());
    final tick = hello.policy['tickIntervalMs'];
    if (tick is num) _tickIntervalMs = tick.toDouble();
    _lastTick = clock();
    pushHandler(GatewayPushSnapshot(hello));
  }

  void _startTickWatchdog(int generation) {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(Duration(milliseconds: (_tickIntervalMs * 2).toInt()), (_) {
      if (!_isCurrent(generation) || !connected || _lastTick == null) return;
      if (clock().difference(_lastTick!).inMilliseconds > _tickIntervalMs * 2) {
        _handleDisconnect('gateway tick missed', generation);
      }
    });
  }

  void _handleDisconnect(String reason, int generation) {
    if (!_isCurrent(generation) || _state == GatewaySessionState.shuttingDown || _state == GatewaySessionState.idle) return;
    _generation++;
    _state = GatewaySessionState.disconnected;
    _listening = false;
    _tickTimer?.cancel();
    _tickTimer = null;
    _failPending(StateError('gateway connection closed: $reason'));
    disconnectHandler?.call(reason);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || _state == GatewaySessionState.paused || (_reconnectTimer?.isActive ?? false)) return;
    final delay = _backoff;
    _backoff = Duration(milliseconds: (_backoff.inMilliseconds * retryPolicy.multiplier).round()).compareTo(retryPolicy.maxDelay) > 0
        ? retryPolicy.maxDelay
        : Duration(milliseconds: (_backoff.inMilliseconds * retryPolicy.multiplier).round());
    _state = GatewaySessionState.reconnecting;
    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      if (!_shouldReconnect || connected || isConnecting) return;
      try {
        await connect();
      } catch (error) {
        _sessionLog.warning('gateway reconnect failed: $error');
      }
    });
  }

  Future<void> _disposeSocket({required bool failPending, bool shutdown = false}) async {
    await _subscription?.cancel();
    _subscription = null;
    _listening = false;
    if (failPending) _failPending(StateError(shutdown ? 'gateway session shutdown' : 'gateway socket replaced'));
    final socket = _socket;
    _socket = null;
    if (socket != null) await socket.close();
  }

  void _failPending(Object error) {
    final entries = List<_PendingRequest>.from(_pending.values);
    _pending.clear();
    for (final pending in entries) {
      pending.timer?.cancel();
      if (!pending.completer.isCompleted) pending.completer.completeError(error);
    }
    final challenge = _challenge;
    if (challenge != null && !challenge.isCompleted) challenge.completeError(error);
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
