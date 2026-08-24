import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:parrot_app/util/device_identity.dart';

final _log = Logger('GatewayChannel');

// ─────────────────────────────────────────────
// MARK: - GatewayAuthSource  (≈ Swift GatewayAuthSource)
// ─────────────────────────────────────────────

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

// ─────────────────────────────────────────────
// MARK: - GatewayConnectOptions  (≈ Swift GatewayConnectOptions)
// ─────────────────────────────────────────────

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

// ─────────────────────────────────────────────
// MARK: - GatewayPush  (≈ Swift GatewayPush enum)
// ─────────────────────────────────────────────

abstract class GatewayPush {
  const GatewayPush();
}

class GatewayPushSnapshot extends GatewayPush {
  final HelloOk snapshot;

  const GatewayPushSnapshot(this.snapshot);
}

// ─────────────────────────────────────────────
// MARK: - HelloOk  (≈ Swift HelloOk decoded from connect response)
//
// Swift accesses: ok.policy["tickIntervalMs"], ok.auth, ok.server,
// ok.snapshot.sessiondefaults, ok.snapshot.configpath, ok.snapshot.statedir,
// ok.pluginsurfaceurls, ok.server["version"]
// ─────────────────────────────────────────────

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

Exception _gatewayError(String msg) => Exception('Gateway: $msg');

class GatewayResponseError implements Exception {
  final String method;
  final String code;
  final String message;
  final Map<String, dynamic> details;

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
       details = details ?? {};

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

// ─────────────────────────────────────────────
// MARK: - Internal RPC frame helpers
// ─────────────────────────────────────────────

class _RequestPayload {
  final String id;
  final String data;

  const _RequestPayload({required this.id, required this.data});
}

// ─────────────────────────────────────────────
// MARK: - GatewayChannelActor  (≈ Swift GatewayChannelActor)
//
// Dart single-threaded => no actor isolation needed; all methods run on the
// same event-loop microtask queue. Matches Swift actor semantics in practice.
// ─────────────────────────────────────────────

class GatewayChannelActor {
  // ── construction params ────────────────────
  final String _url;
  final String? _token;
  final String? _password;
  final String? _bootstrapToken;
  final void Function(GatewayPush push) _pushHandler;
  final void Function(String reason)? _disconnectHandler;
  final GatewayConnectOptions? connectOptions;

  // ── state  (mirrors Swift private vars) ────
  WebSocketChannel? _task;
  StreamSubscription? _taskSubscription;
  bool _connected = false;
  bool _isConnecting = false;

  bool get isConnecting => _isConnecting;

  bool get connected => _connected;

  /// Mirrors Swift `connectWaiters`.
  final List<Completer<void>> _connectWaiters = [];

  double _backoffMs = 500;
  bool _shouldReconnect = true;
  int? _lastSeq;
  DateTime? _lastTick;
  double _tickIntervalMs = 30000;
  GatewayAuthSource _lastAuthSource = GatewayAuthSource.none;

  // timeouts (mirrors Swift constants)
  static const double _connectTimeoutSeconds = 30;
  static const double _connectChallengeTimeoutSeconds = 6.0;
  static const double _keepaliveIntervalSeconds = 15.0;
  static const double _defaultRequestTimeoutMs = 15000;

  /// Mirrors Swift `pending: [String: CheckedContinuation<GatewayFrame, Error>]`.
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};

  // Background loop handles
  Timer? _watchdogTimer;
  Timer? _tickTask;
  Timer? _keepaliveTimer;
  Timer? _reconnectTimer; // 新增：用于去重和管理重连任务

  // Used during connect handshake
  Completer<String>? _challengeCompleter;
  bool _reconnectPausedForAuthFailure = false;

  GatewayChannelActor({
    required String url,
    required String? token,
    required String? password,
    String? bootstrapToken,
    required void Function(GatewayPush push) pushHandler,
    this.connectOptions,
    void Function(String reason)? disconnectHandler,
  }) : _url = url,
       _token = token,
       _password = password,
       _bootstrapToken = bootstrapToken,
       _pushHandler = pushHandler,
       _disconnectHandler = disconnectHandler {
    // Mirrors Swift: `Task { [weak self] in await self?.startWatchdog() }` in init.
    _startWatchdog();
  }

  // ── authSource  (≈ Swift public func authSource()) ─────────────────

  GatewayAuthSource authSource() => _lastAuthSource;

  // ── shutdown  (≈ Swift public func shutdown()) ──────────────────────

  Future<void> shutdown() async {
    _shouldReconnect = false;
    _connected = false;

    _watchdogTimer?.cancel();
    _watchdogTimer = null;

    _tickTask?.cancel();
    _tickTask = null;

    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;

    _reconnectTimer?.cancel(); // 新增
    _reconnectTimer = null; // 新增

    await _taskSubscription?.cancel();
    _taskSubscription = null;
    _task?.sink.close();
    _task = null;

    _clearPendingOnShutdown();

    final waiters = List.of(_connectWaiters);
    _connectWaiters.clear();
    for (final w in waiters) {
      if (!w.isCompleted) {
        w.complete();
      }
    }
  }

  // ── startWatchdog  (≈ Swift private func startWatchdog()) ───────────

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    // Mirrors Swift `watchdogLoop`: 30 s cadence, nudges reconnect if stalled.
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_shouldReconnect) return;
      if (_reconnectPausedForAuthFailure) return;
      if (_connected) return;
      try {
        await connect();
      } catch (e) {
        _log.warning('gateway watchdog reconnect failed: $e');
      }
    });
  }

  // ── connect  (≈ Swift public func connect()) ────────────────────────

  Future<void> connect() async {
    if (_connected && _task != null) return;
    if (_isConnecting) {
      // Mirrors Swift: append to connectWaiters, await.
      final waiter = Completer<void>();
      _connectWaiters.add(waiter);
      return waiter.future;
    }
    _isConnecting = true;

    try {
      _task?.sink.close();
      await _taskSubscription?.cancel();
      _taskSubscription = null;
      _task = null;

      final channel = IOWebSocketChannel.connect(
        Uri.parse(_url),
        connectTimeout: const Duration(seconds: _connectTimeoutSeconds ~/ 1),
      );
      _task = channel;

      _challengeCompleter = Completer<String>();

      // Set up listen (recursive callback, mirrors Swift `self.listen()`)
      _listen();

      // 等待连接就绪。这对于在 try-catch 块中捕获异步连接错误（如 SocketException）至关重要。
      await channel.ready;

      // 修改建议
      final sendConnectFuture = _sendConnect();
      await sendConnectFuture.timeout(
        const Duration(seconds: _connectTimeoutSeconds ~/ 1),
        onTimeout: () => throw _gatewayError('connect timed out'),
      );

      // 增加这一行，防止 sendConnectFuture 在超时后抛出的错误变成 Unhandled
      sendConnectFuture.catchError((e) {
        _log.fine('Gateway: suppressed late error from _sendConnect: $e');
      });
    } catch (e) {
      _connected = false;
      // 必须先取消订阅再 close sink，否则 close 会触发迟到的 onDone，
      // 二次调用 disconnectHandler 并意外调度底层自动重连。
      await _taskSubscription?.cancel();
      _taskSubscription = null;
      _task?.sink.close();
      _task = null;
      _disconnectHandler?.call('connect failed: $e');

      final waiters = List.of(_connectWaiters);
      _connectWaiters.clear();
      for (final w in waiters) {
        if (!w.isCompleted) w.completeError(e);
      }
      _log.warning('gateway ws connect failed: $e @ $_url');
      rethrow;
    } finally {
      _isConnecting = false;
    }

    // Success path (mirrors Swift post-sendConnect)
    _listen(); // already started above; _listen() is idempotent via subscription guard
    _connected = true;
    _reconnectPausedForAuthFailure = false;
    _backoffMs = 500;
    _lastSeq = null;
    _reconnectTimer?.cancel(); // 新增
    _reconnectTimer = null; // 新增

    _startKeepalive();

    final waiters = List.of(_connectWaiters);
    _connectWaiters.clear();
    for (final w in waiters) {
      if (!w.isCompleted) w.resume();
    }
  }

  // ── startKeepalive  (≈ Swift private func startKeepalive()) ─────────

  void _startKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(
      Duration(milliseconds: (_keepaliveIntervalSeconds * 1000).toInt()),
      (_) {
        if (!_shouldReconnect) return;
        if (!_connected || _task == null) return;
        // Best-effort ping: IOWebSocketChannel does not expose sendPing directly;
        // the underlying socket keepalive + tick monitor handles liveness.
        // (Mirrors Swift where a failed ping is silently swallowed.)
      },
    );
  }

  // ── listen  (≈ Swift private func listen()) ─────────────────────────
  // Swift uses recursive callback: task.receive { result in ... self.listen() }
  // Dart: subscribe once; re-subscribe is handled by the stream itself.

  bool _listening = false;

  void _listen() {
    if (_listening) return;
    final channel = _task;
    if (channel == null) return;
    _listening = true;
    _taskSubscription = channel.stream.listen(
      (raw) => _handleRawMessage(raw),
      onError: (e) => _handleReceiveFailure(e.toString()),
      onDone: () {
        _listening = false;
        _handleReceiveFailure(
          (_task as IOWebSocketChannel?)?.closeReason ?? 'closed',
        );
      },
      cancelOnError: false,
    );
  }

  // ── handle receive failure  (≈ Swift private func handleReceiveFailure) ─

  void _handleReceiveFailure(String reason) {
    _log.warning('gateway ws receive failed: $reason');
    _connected = false;
    _listening = false;
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    _disconnectHandler?.call('receive failed: $reason');
    _failPending(_gatewayError('receive failed: $reason'));
    _scheduleReconnect();
  }

  // ── handle raw message  (≈ Swift private func handle(_ msg:)) ────────

  void _handleRawMessage(dynamic raw) {
    final Map<String, dynamic> frame;
    try {
      frame = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      _log.severe('gateway decode failed');
      return;
    }

    final type = frame['type'] as String?;

    if (type == 'res') {
      // Mirrors Swift: `if let waiter = pending.removeValue(forKey: id)`
      final id = frame['id'] as String?;
      if (id == null) return;
      final waiter = _pending.remove(id);
      waiter?.complete(frame);
    } else if (type == 'event') {
      final event = frame['event'] as String?;

      // Mirrors Swift: `if evt.event == "connect.challenge" { return }`
      if (event == 'connect.challenge') {
        final payload = frame['payload'];
        String? nonce;
        if (payload is Map) {
          nonce = payload['nonce'] as String?;
        }

        final completer = _challengeCompleter;
        if (nonce != null && completer != null && !completer.isCompleted) {
          _log.fine('Gateway: received connect.challenge');
          completer.complete(nonce);
        } else if (nonce == null) {
          _log.severe('Gateway: connect.challenge missing nonce in payload');
        }
        return;
      }

      // seq gap detection
      final seq = frame['seq'] as int?;
      if (seq != null) {
        final last = _lastSeq;
        if (last != null && seq > last + 1) {
          _pushHandler(GatewayPushSeqGap(expected: last + 1, received: seq));
        }
        _lastSeq = seq;
      }

      // tick liveness
      if (event == 'tick') _lastTick = DateTime.now();

      if (event != null) {
        _pushHandler(GatewayPushEvent(event, frame['payload'], seq: seq));
      }
    }
  }

  // ── waitForConnectChallenge  (≈ Swift private func waitForConnectChallenge) ─

  Future<String> _waitForConnectChallenge() async {
    if (_task == null) throw _gatewayError('connect.challenge: no task');

    // 如果连接过程中 completer 还没被 connect() 创建（防御性编程）
    _challengeCompleter ??= Completer<String>();

    try {
      return await _challengeCompleter!.future.timeout(
        Duration(seconds: _connectChallengeTimeoutSeconds.toInt()),
      );
    } on TimeoutException {
      _log.warning('Gateway: connect.challenge timed out');
      throw _gatewayError('connect.challenge timed out');
    } catch (e) {
      // 可能是连接断开导致的 _failPending 触发了错误
      rethrow;
    } finally {
      // 保持 completer 状态，直到 connect 流程彻底结束
    }
  }

  // ── waitForConnectResponse  (≈ Swift private func waitForConnectResponse) ─

  Future<Map<String, dynamic>> _waitForConnectResponse(String reqId) async {
    final completer = Completer<Map<String, dynamic>>();
    _pending[reqId] = completer;
    return completer.future;
  }

  // ── sendConnect  (≈ Swift private func sendConnect()) ───────────────

  Future<void> _sendConnect() async {
    final identity = await DeviceIdentityManager.getOrCreate();
    final signedAtMs = DateTime.now().millisecondsSinceEpoch;

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
        );

    final clientId = options.clientId;
    final clientMode = options.clientMode;
    final clientDisplayName = options.clientDisplayName ?? clientId;
    final role = options.role;
    final scopes = options.scopes;
    final platform = Platform.operatingSystem;

    // Step 1: wait for connect.challenge (nonce)
    final connectNonce = await _waitForConnectChallenge();

    // Build device auth payload (mirrors Swift GatewayDeviceAuthPayload.buildV3)
    final authPayload = identity.buildAuthPayload(
      clientId: clientId,
      clientMode: clientMode,
      role: role,
      scopes: scopes,
      signedAtMs: signedAtMs,
      token: _token,
      nonce: connectNonce,
    );
    final signature = identity.signPayload(authPayload);

    final reqId = const Uuid().v4();

    // Build client dict
    final clientDict = <String, dynamic>{
      'id': clientId,
      'displayName': clientDisplayName,
      'version': '1.0.0',
      'platform': platform,
      'mode': clientMode,
    };

    // Build params (mirrors Swift var params: [String: ProtoAnyCodable])
    final params = <String, dynamic>{
      'minProtocol': 4,
      'maxProtocol': 4,
      'client': clientDict,
      'caps': options.caps,
      'locale': Platform.localeName,
      'userAgent': Platform.operatingSystemVersion,
      'role': role,
      'scopes': scopes,
    };
    if (options.commands.isNotEmpty) {
      params['commands'] = options.commands;
    }
    if (options.permissions.isNotEmpty) {
      params['permissions'] = options.permissions;
    }

    // Auth block (mirrors Swift auth selection)
    if (_token != null) {
      params['auth'] = {'token': _token};
      _lastAuthSource = GatewayAuthSource.sharedToken;
    } else if (_password != null) {
      params['auth'] = {'password': _password};
      _lastAuthSource = GatewayAuthSource.password;
    } else if (_bootstrapToken != null) {
      params['auth'] = {'bootstrapToken': _bootstrapToken};
      _lastAuthSource = GatewayAuthSource.bootstrapToken;
    } else {
      _lastAuthSource = GatewayAuthSource.none;
    }

    // Device identity block (mirrors Swift params["device"] = ...)
    if (options.includeDeviceIdentity) {
      params['device'] = {
        'id': identity.deviceId,
        'publicKey': identity.publicKey,
        'signature': signature,
        'signedAt': signedAtMs,
        'nonce': connectNonce,
      };
    }

    // Step 2: send connect request
    final payload = _encodeRequest(
      method: 'connect',
      params: params,
      id: reqId,
    );
    _task!.sink.add(payload.data);

    // Step 3: wait for connect response (mirrors Swift waitForConnectResponse)
    final responseFuture = _waitForConnectResponse(reqId);
    final res = await responseFuture.timeout(
      const Duration(seconds: _connectTimeoutSeconds ~/ 1),
      onTimeout: () {
        _pending.remove(reqId);
        throw _gatewayError('connect response timed out');
      },
    );

    await _handleConnectResponse(res);
  }

  // ── handleConnectResponse  (≈ Swift private func handleConnectResponse) ─

  Future<void> _handleConnectResponse(Map<String, dynamic> res) async {
    if (res['ok'] == false) {
      final error = res['error'] as Map?;
      final msg = error?['message'] as String? ?? 'gateway connect failed';
      throw _gatewayError(msg);
    }

    final rawPayload = res['payload'];
    if (rawPayload == null) {
      throw _gatewayError('connect failed (missing payload)');
    }

    final payloadMap =
        rawPayload is String
            ? (jsonDecode(rawPayload) as Map).cast<String, dynamic>()
            : (rawPayload as Map).cast<String, dynamic>();

    final ok = HelloOk.fromJson(payloadMap);

    // tickIntervalMs (mirrors Swift `if let tick = ok.policy["tickIntervalMs"]`)
    final tickRaw = ok.policy['tickIntervalMs'];
    if (tickRaw is num) {
      _tickIntervalMs = tickRaw.toDouble();
    }

    _lastTick = DateTime.now();

    // Start tick watchdog (mirrors Swift `self.tickTask = Task { await self.watchTicks() }`)
    _tickTask?.cancel();
    _tickTask = Timer.periodic(
      Duration(milliseconds: (_tickIntervalMs * 2).toInt()),
      (_) {
        if (!_connected) return;
        final last = _lastTick;
        if (last == null) return;
        final delta = DateTime.now().difference(last).inMilliseconds;
        final tolerance = _tickIntervalMs * 2;
        if (delta > tolerance) {
          _log.severe('gateway tick missed; reconnecting');
          _connected = false;
          _failPending(_gatewayError('gateway tick missed; reconnecting'));
          _scheduleReconnect();
        }
      },
    );

    // Emit snapshot (mirrors Swift `Task { await pushHandler(.snapshot(ok)) }`)
    _pushHandler(GatewayPushSnapshot(ok));
  }

  // ── scheduleReconnect  (≈ Swift private func scheduleReconnect()) ───

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    if (_reconnectPausedForAuthFailure) return;
    // 如果已经连接、正在连接、或者已经有一个重连定时器在跑了，就什么都不做
    if (_connected || _isConnecting || (_reconnectTimer?.isActive ?? false)) {
      return;
    }
    final delay = _backoffMs;
    _backoffMs = (_backoffMs * 2).clamp(0, 30000);
    _reconnectTimer = Timer(Duration(milliseconds: delay.toInt()), () async {
      _reconnectTimer = null; // 定时器触发，清除句柄

      // 触发时刻再次检查状态（防止定时器等待期间状态已变化）
      if (!_shouldReconnect || _connected || _isConnecting) return;

      try {
        await connect();
      } catch (e) {
        _log.warning('gateway reconnect failed: $e');
        _scheduleReconnect(); // 失败了由它负责发起下一次带退避的调度
      }
    });
  }

  // ── failPending  (≈ Swift private func failPending()) ───────────────

  void _failPending(Exception error) {
    final waiters = Map.of(_pending);
    _pending.clear();
    for (final c in waiters.values) {
      if (!c.isCompleted) c.completeError(error);
    }

    // 同时失败 challengeCompleter，防止 _waitForConnectChallenge 一直等待
    if (_challengeCompleter != null && !_challengeCompleter!.isCompleted) {
      _challengeCompleter!.completeError(error);
    }
  }

  void _clearPendingOnShutdown() {
    _pending.clear();
    if (_challengeCompleter != null && !_challengeCompleter!.isCompleted) {
      _challengeCompleter!.complete('');
    }
    _challengeCompleter = null;
  }

  // ── timeoutRequest  (≈ Swift private func timeoutRequest) ───────────

  void _timeoutRequest(String id, double timeoutMs) {
    final waiter = _pending.remove(id);
    if (waiter == null || waiter.isCompleted) return;
    waiter.completeError(
      _gatewayError('gateway request timed out after ${timeoutMs.toInt()}ms'),
    );
  }

  // ── connectOrThrow  (≈ Swift private func connectOrThrow) ───────────

  Future<void> _connectOrThrow() async {
    try {
      await connect();
    } catch (e) {
      rethrow;
    }
  }

  // ── encodeRequest  (≈ Swift private func encodeRequest) ─────────────

  _RequestPayload _encodeRequest({
    required String method,
    required dynamic params,
    String? id,
  }) {
    final reqId = id ?? const Uuid().v4();
    final data = jsonEncode({
      'type': 'req',
      'id': reqId,
      'method': method,
      if (params != null) 'params': params,
    });
    return _RequestPayload(id: reqId, data: data);
  }

  // ── request  (≈ Swift public func request(method:params:timeoutMs:)) ─

  Future<Map<String, dynamic>> request({
    required String method,
    Map<String, dynamic>? params,
    double? timeoutMs,
  }) async {
    await _connectOrThrow();

    final effectiveTimeout = timeoutMs ?? _defaultRequestTimeoutMs;
    final payload = _encodeRequest(method: method, params: params);

    final completer = Completer<Map<String, dynamic>>();
    _pending[payload.id] = completer;

    // Timeout task (mirrors Swift `Task { try? await Task.sleep ... ; timeoutRequest }`)
    Timer(Duration(milliseconds: effectiveTimeout.toInt()), () {
      _timeoutRequest(payload.id, effectiveTimeout);
    });

    // Send (mirrors Swift `Task { try await self.task?.send(.data(payload.data)) }`)
    try {
      _task!.sink.add(payload.data);
    } catch (e) {
      _pending.remove(payload.id);
      if (!completer.isCompleted) completer.completeError(e);
      _connected = false;
      _task?.sink.close();
      _scheduleReconnect();
    }

    final res = await completer.future;

    if (res['ok'] == false) {
      final err = res['error'] as Map?;
      final code = err?['code'] as String?;
      final msg = err?['message'] as String?;
      final details = (err?['details'] as Map?)?.cast<String, dynamic>() ?? {};
      throw GatewayResponseError(
        method: method,
        code: code,
        message: msg,
        details: details,
      );
    }

    final rawPayload = res['payload'];
    if (rawPayload == null) return {};
    // Re-encode payload to canonical JSON bytes (mirrors Swift encoder.encode(payload))
    return rawPayload is Map ? rawPayload.cast<String, dynamic>() : {};
  }

  // ── send  (≈ Swift public func send(method:params:)) ─────────────────

  Future<void> send({
    required String method,
    Map<String, dynamic>? params,
  }) async {
    await _connectOrThrow();
    final payload = _encodeRequest(method: method, params: params);
    if (_task == null) throw _gatewayError('gateway socket unavailable');
    try {
      _task!.sink.add(payload.data);
    } catch (e) {
      _connected = false;
      _task?.sink.close();
      _scheduleReconnect();
      rethrow;
    }
  }
}

// ─────────────────────────────────────────────
// MARK: - Completer helper
// ─────────────────────────────────────────────

extension on Completer<void> {
  void resume() {
    if (!isCompleted) complete();
  }
}
