import 'dart:async';
import 'package:logging/logging.dart';
import 'package:parrot_app/data/service/gateway_channel.dart';
import 'package:uuid/uuid.dart';
import 'package:parrot_app/util/device_identity.dart';

final _log = Logger('GatewayConnection');

// ─────────────────────────────────────────────
// MARK: - /openclaw/apps/shared/OpenClawKit/Sources/ChatGatewayRequest.swift
// ─────────────────────────────────────────────

enum GatewayAgentChannel {
  last,
  whatsapp,
  telegram,
  discord,
  googlechat,
  slack,
  signal,
  imessage,
  msteams,
  webchat;

  /// Mirrors Swift `init(raw:)`.
  static GatewayAgentChannel fromRaw(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    return GatewayAgentChannel.values.firstWhere(
      (e) => e.name == normalized,
      orElse: () => GatewayAgentChannel.last,
    );
  }

  /// Mirrors Swift `var isDeliverable`.
  bool get isDeliverable => this != GatewayAgentChannel.webchat;

  /// Mirrors Swift `func shouldDeliver`.
  bool shouldDeliver(bool deliver) => deliver && isDeliverable;
}

// ─────────────────────────────────────────────
// MARK: - GatewayAgentInvocation  (≈ Swift GatewayAgentInvocation)
// ─────────────────────────────────────────────

class GatewayAgentInvocation {
  final String message;
  final String sessionKey;
  final String? thinking;
  final bool deliver;
  final String? to;
  final GatewayAgentChannel channel;
  final int? timeoutSeconds;
  final String idempotencyKey;
  final String? voiceWakeTrigger;

  GatewayAgentInvocation({
    required this.message,
    this.sessionKey = 'main',
    this.thinking,
    this.deliver = false,
    this.to,
    this.channel = GatewayAgentChannel.last,
    this.timeoutSeconds,
    String? idempotencyKey,
    this.voiceWakeTrigger,
  }) : idempotencyKey = idempotencyKey ?? const Uuid().v4();
}

// ─────────────────────────────────────────────
// MARK: - Method enum  (≈ Swift GatewayConnection.Method)
// ─────────────────────────────────────────────

enum Method {
  agent,
  status,
  setHeartbeats('set-heartbeats'),
  systemEvent('system-event'),
  health,
  channelsStatus('channels.status'),
  configGet('config.get'),
  configSet('config.set'),
  configPatch('config.patch'),
  configSchema('config.schema'),
  configSchemaLookup('config.schema.lookup'),
  wizardStart('wizard.start'),
  wizardNext('wizard.next'),
  wizardCancel('wizard.cancel'),
  wizardStatus('wizard.status'),
  talkConfig('talk.config'),
  talkMode('talk.mode'),
  talkSpeak('talk.speak'),
  webLoginStart('web.login.start'),
  webLoginWait('web.login.wait'),
  channelsLogout('channels.logout'),
  modelsList('models.list'),
  chatHistory('chat.history'),
  sessionsPreview('sessions.preview'),
  sessionsPatch('sessions.patch'),
  chatSend('chat.send'),
  chatAbort('chat.abort'),
  skillsStatus('skills.status'),
  skillsInstall('skills.install'),
  skillsUpdate('skills.update'),
  voicewakeGet('voicewake.get'),
  voicewakeSet('voicewake.set'),
  nodePairApprove('node.pair.approve'),
  nodePairReject('node.pair.reject'),
  devicePairList('device.pair.list'),
  devicePairSetupCode('device.pair.setupCode'),
  devicePairApprove('device.pair.approve'),
  devicePairReject('device.pair.reject'),
  execApprovalResolve('exec.approval.resolve'),
  cronList('cron.list'),
  cronRuns('cron.runs'),
  cronRun('cron.run'),
  cronRemove('cron.remove'),
  cronUpdate('cron.update'),
  cronAdd('cron.add'),
  cronStatus('cron.status'),
  sessionsList('sessions.list'),
  sessionsCreate('sessions.create'),
  sessionsDelete('sessions.delete');

  final String? _raw;

  const Method([this._raw]);

  /// Mirrors Swift `Method.rawValue`.
  String get rawValue => _raw ?? name;
}

// ─────────────────────────────────────────────
// MARK: - GatewayConfig  (≈ Swift GatewayConfig in OpenClawMacCLI)
// ─────────────────────────────────────────────

class GatewayConfig {
  final String? mode;
  final String? bind;
  final int? port;
  final String? remoteUrl;
  final int? remotePort;
  final String? token;
  final String? password;
  final String? bootstrapToken;
  final String? remoteToken;
  final String? remotePassword;
  final String? remoteBootstrapToken;

  const GatewayConfig({
    this.mode,
    this.bind,
    this.port,
    this.remoteUrl,
    this.remotePort,
    this.token,
    this.password,
    this.bootstrapToken,
    this.remoteToken,
    this.remotePassword,
    this.remoteBootstrapToken,
  });
}

// ─────────────────────────────────────────────
// MARK: - GatewayEndpoint  (≈ Swift GatewayEndpoint in OpenClawMacCLI)
// ─────────────────────────────────────────────

class GatewayEndpoint {
  final String url;
  final String? token;
  final String? password;
  final String? bootstrapToken;
  final String mode;

  const GatewayEndpoint({
    required this.url,
    this.token,
    this.password,
    this.bootstrapToken,
    this.mode = 'remote',
  });

  @override
  bool operator ==(Object other) =>
      other is GatewayEndpoint &&
      other.url == url &&
      other.token == token &&
      other.password == password &&
      other.bootstrapToken == bootstrapToken &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(url, token, password, bootstrapToken, mode);
}

// ─────────────────────────────────────────────
// MARK: - Error types  (≈ Swift GatewayErrors.swift)
// ─────────────────────────────────────────────

enum GatewayConnectAuthDetailCode {
  authRequired,
  authUnauthorized,
  authTokenMismatch,
  authBootstrapTokenInvalid,
  authDeviceTokenMismatch,
  authScopeMismatch,
  authTokenMissing,
  authTokenNotConfigured,
  authPasswordMissing,
  authPasswordMismatch,
  authPasswordNotConfigured,
  authRateLimited,
  authTailscaleIdentityMissing,
  authTailscaleProxyMissing,
  authTailscaleWhoisFailed,
  authTailscaleIdentityMismatch,
  pairingRequired,
  controlUiDeviceIdentityRequired,
  deviceIdentityRequired,
  deviceAuthInvalid,
  deviceAuthDeviceIdMismatch,
  deviceAuthSignatureExpired,
  deviceAuthNonceRequired,
  deviceAuthNonceMismatch,
  deviceAuthSignatureInvalid,
  deviceAuthPublicKeyInvalid;

  static const _rawValues = {
    'AUTH_REQUIRED': GatewayConnectAuthDetailCode.authRequired,
    'AUTH_UNAUTHORIZED': GatewayConnectAuthDetailCode.authUnauthorized,
    'AUTH_TOKEN_MISMATCH': GatewayConnectAuthDetailCode.authTokenMismatch,
    'AUTH_BOOTSTRAP_TOKEN_INVALID':
        GatewayConnectAuthDetailCode.authBootstrapTokenInvalid,
    'AUTH_DEVICE_TOKEN_MISMATCH':
        GatewayConnectAuthDetailCode.authDeviceTokenMismatch,
    'AUTH_SCOPE_MISMATCH': GatewayConnectAuthDetailCode.authScopeMismatch,
    'AUTH_TOKEN_MISSING': GatewayConnectAuthDetailCode.authTokenMissing,
    'AUTH_TOKEN_NOT_CONFIGURED':
        GatewayConnectAuthDetailCode.authTokenNotConfigured,
    'AUTH_PASSWORD_MISSING': GatewayConnectAuthDetailCode.authPasswordMissing,
    'AUTH_PASSWORD_MISMATCH': GatewayConnectAuthDetailCode.authPasswordMismatch,
    'AUTH_PASSWORD_NOT_CONFIGURED':
        GatewayConnectAuthDetailCode.authPasswordNotConfigured,
    'AUTH_RATE_LIMITED': GatewayConnectAuthDetailCode.authRateLimited,
    'AUTH_TAILSCALE_IDENTITY_MISSING':
        GatewayConnectAuthDetailCode.authTailscaleIdentityMissing,
    'AUTH_TAILSCALE_PROXY_MISSING':
        GatewayConnectAuthDetailCode.authTailscaleProxyMissing,
    'AUTH_TAILSCALE_WHOIS_FAILED':
        GatewayConnectAuthDetailCode.authTailscaleWhoisFailed,
    'AUTH_TAILSCALE_IDENTITY_MISMATCH':
        GatewayConnectAuthDetailCode.authTailscaleIdentityMismatch,
    'PAIRING_REQUIRED': GatewayConnectAuthDetailCode.pairingRequired,
    'CONTROL_UI_DEVICE_IDENTITY_REQUIRED':
        GatewayConnectAuthDetailCode.controlUiDeviceIdentityRequired,
    'DEVICE_IDENTITY_REQUIRED':
        GatewayConnectAuthDetailCode.deviceIdentityRequired,
    'DEVICE_AUTH_INVALID': GatewayConnectAuthDetailCode.deviceAuthInvalid,
    'DEVICE_AUTH_DEVICE_ID_MISMATCH':
        GatewayConnectAuthDetailCode.deviceAuthDeviceIdMismatch,
    'DEVICE_AUTH_SIGNATURE_EXPIRED':
        GatewayConnectAuthDetailCode.deviceAuthSignatureExpired,
    'DEVICE_AUTH_NONCE_REQUIRED':
        GatewayConnectAuthDetailCode.deviceAuthNonceRequired,
    'DEVICE_AUTH_NONCE_MISMATCH':
        GatewayConnectAuthDetailCode.deviceAuthNonceMismatch,
    'DEVICE_AUTH_SIGNATURE_INVALID':
        GatewayConnectAuthDetailCode.deviceAuthSignatureInvalid,
    'DEVICE_AUTH_PUBLIC_KEY_INVALID':
        GatewayConnectAuthDetailCode.deviceAuthPublicKeyInvalid,
  };

  static GatewayConnectAuthDetailCode? fromRaw(String? raw) =>
      raw == null ? null : _rawValues[raw];
}

enum GatewayConnectRecoveryNextStep {
  retryWithDeviceToken,
  updateAuthConfiguration,
  updateAuthCredentials,
  waitThenRetry,
  reviewAuthConfiguration;

  static const _rawValues = {
    'retry_with_device_token':
        GatewayConnectRecoveryNextStep.retryWithDeviceToken,
    'update_auth_configuration':
        GatewayConnectRecoveryNextStep.updateAuthConfiguration,
    'update_auth_credentials':
        GatewayConnectRecoveryNextStep.updateAuthCredentials,
    'wait_then_retry': GatewayConnectRecoveryNextStep.waitThenRetry,
    'review_auth_configuration':
        GatewayConnectRecoveryNextStep.reviewAuthConfiguration,
  };

  static GatewayConnectRecoveryNextStep? fromRaw(String? raw) =>
      raw == null ? null : _rawValues[raw];
}

class GatewayConnectAuthError implements Exception {
  final String message;
  final String? detailCodeRaw;
  final String? recommendedNextStepRaw;
  final bool canRetryWithDeviceToken;
  final String? requestId;
  final String? detailsReason;
  final String? ownerRaw;
  final String? titleOverride;
  final String? userMessageOverride;
  final String? actionLabel;
  final String? actionCommand;
  final String? docsURLString;
  final bool? retryableOverride;
  final bool? pauseReconnectOverride;

  GatewayConnectAuthError({
    required String message,
    required this.canRetryWithDeviceToken,
    String? detailCodeRaw,
    String? recommendedNextStepRaw,
    this.requestId,
    this.detailsReason,
    this.ownerRaw,
    this.titleOverride,
    this.userMessageOverride,
    this.actionLabel,
    this.actionCommand,
    this.docsURLString,
    this.retryableOverride,
    this.pauseReconnectOverride,
  }) : message =
           message.trim().isEmpty ? 'gateway connect failed' : message.trim(),
       detailCodeRaw =
           detailCodeRaw?.trim().isEmpty == false
               ? detailCodeRaw!.trim()
               : null,
       recommendedNextStepRaw =
           recommendedNextStepRaw?.trim().isEmpty == false
               ? recommendedNextStepRaw!.trim()
               : null;

  GatewayConnectAuthDetailCode? get detail =>
      GatewayConnectAuthDetailCode.fromRaw(detailCodeRaw);

  GatewayConnectRecoveryNextStep? get recommendedNextStep =>
      GatewayConnectRecoveryNextStep.fromRaw(recommendedNextStepRaw);

  String? get detailCode => detailCodeRaw;

  String? get recommendedNextStepCode => recommendedNextStepRaw;

  bool get isNonRecoverable {
    switch (detail) {
      case GatewayConnectAuthDetailCode.authTokenMissing:
      case GatewayConnectAuthDetailCode.authBootstrapTokenInvalid:
      case GatewayConnectAuthDetailCode.authTokenNotConfigured:
      case GatewayConnectAuthDetailCode.authPasswordMissing:
      case GatewayConnectAuthDetailCode.authPasswordMismatch:
      case GatewayConnectAuthDetailCode.authPasswordNotConfigured:
      case GatewayConnectAuthDetailCode.authRateLimited:
      case GatewayConnectAuthDetailCode.authScopeMismatch:
      case GatewayConnectAuthDetailCode.pairingRequired:
      case GatewayConnectAuthDetailCode.controlUiDeviceIdentityRequired:
      case GatewayConnectAuthDetailCode.deviceIdentityRequired:
        return true;
      default:
        return false;
    }
  }

  @override
  String toString() => 'GatewayConnectAuthError: $message';
}

// ─────────────────────────────────────────────
// MARK: - GatewayConnection  (≈ Swift actor GatewayConnection)
// ─────────────────────────────────────────────

class GatewayConnection {
  /// Mirrors Swift `static let shared`.
  static final GatewayConnection shared = GatewayConnection._();

  GatewayConnection._();

  // ── config provider / client ───────────────
  // Mirrors Swift: `private let configProvider`, `private var client`
  // Future<GatewayEndpoint> Function()? _configProvider;
  GatewayChannelActor? _client;
  String? _configuredURL;
  String? _configuredToken;
  String? _configuredPassword;
  String? _configuredBootstrapToken;

  // ── subscribers / snapshot ─────────────────
  // Mirrors Swift `subscribers: [UUID: AsyncStream<GatewayPush>.Continuation]`
  final Map<String, StreamController<GatewayPush>> _subscribers = {};
  HelloOk? _lastSnapshot;
  Function(String)? onDisconnect;

  HelloOk? get lastSnapshot => _lastSnapshot;

  /// 当前连接代际：每次 shutdown/重建 client 时递增。
  /// 旧 client 的迟到断开事件（异步 onDone/onError）携带旧代际，一律忽略，
  /// 避免切换服务器后 UI 被残留事件错误拉回"已断开连接"。
  int _clientGeneration = 0;

  // GatewayChannelActor? get client => _client;

  Future<void> shutdown() async {
    _clientGeneration++; // 使所有在途断开事件失效
    await _client?.shutdown();
    _client = null;
    _configuredURL = null;
    _configuredToken = null;
    _configuredPassword = null;
    _configuredBootstrapToken = null;
    _lastSnapshot = null;
  }

  void _handleDisconnected(String reason, int generation) {
    if (generation != _clientGeneration) {
      // 来自已被替换/销毁的旧连接的断开事件，忽略
      return;
    }
    if (onDisconnect != null) {
      onDisconnect!(reason);
    }
  }

  Future<String?> canvasPluginSurfaceUrl() async {
    final snapshot = _lastSnapshot;
    if (snapshot == null) return null;
    final raw = snapshot.pluginsurfaceurls?['canvas'] as String?;
    final trimmed = raw?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<String?> controlUiAutoAuthToken(GatewayEndpoint config) async {
    final token = config.token?.trim();
    if (token != null && token.isNotEmpty) return token;

    final deviceToken = _lastSnapshot?.auth['deviceToken'] as String?;
    final trimmed = deviceToken?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;

    // Mirrors Swift: DeviceIdentityStore.loadOrCreate()
    await DeviceIdentityManager.getOrCreate();

    // Note: DeviceAuthStore equivalent missing in Dart currently.
    return null;
  }

  String? cachedMainSessionKey() {
    final snapshot = _lastSnapshot;
    if (snapshot == null) return null;
    final trimmed = _sessionDefaultString(
      snapshot.snapshot.sessiondefaults,
      key: 'mainSessionKey',
    );
    return trimmed.isEmpty ? null : trimmed;
  }

  String? cachedGatewayVersion() {
    final snapshot = _lastSnapshot;
    if (snapshot == null) return null;
    final raw = snapshot.server['version'] as String?;
    final trimmed = raw?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  ({String? configPath, String? stateDir}) snapshotPaths() {
    final snapshot = _lastSnapshot;
    if (snapshot == null) return (configPath: null, stateDir: null);
    final configPath = snapshot.snapshot.configpath?.trim();
    final stateDir = snapshot.snapshot.statedir?.trim();
    return (
      configPath: configPath?.isNotEmpty == true ? configPath : null,
      stateDir: stateDir?.isNotEmpty == true ? stateDir : null,
    );
  }

  // ─────────────────────────────────────────────
  // MARK: - Low-level request  (≈ Swift func request(method:params:timeoutMs:))
  // ─────────────────────────────────────────────

  Future<Map<String, dynamic>> request({
    required String method,
    Map<String, dynamic>? params,
    double? timeoutMs,
  }) async {
    await _refreshConfig();
    final client = _client;
    if (client == null) {
      throw Exception('gateway not configured');
    }
    return client.request(method: method, params: params, timeoutMs: timeoutMs);
  }

  /// Mirrors Swift `func requestRaw(method: Method, ...)`.
  Future<Map<String, dynamic>> requestRaw(
    Method method, {
    Map<String, dynamic>? params,
    double? timeoutMs,
  }) async {
    return request(
      method: method.rawValue,
      params: params,
      timeoutMs: timeoutMs,
    );
  }

  /// Mirrors Swift `func requestRaw(method: String, ...)`.
  Future<Map<String, dynamic>> requestRawString(
    String method, {
    Map<String, dynamic>? params,
    double? timeoutMs,
  }) async {
    return request(method: method, params: params, timeoutMs: timeoutMs);
  }

  /// Mirrors Swift `func requestDecoded<T: Decodable>(method:params:timeoutMs:)`.
  Future<T> requestDecoded<T>(
    Method method,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? params,
    double? timeoutMs,
  }) async {
    final data = await requestRaw(method, params: params, timeoutMs: timeoutMs);
    try {
      return fromJson(data);
    } catch (e) {
      throw GatewayDecodingError(
        method: method.rawValue,
        message: e.toString(),
      );
    }
  }

  /// Mirrors Swift `func requestVoid(method:params:timeoutMs:)`.
  Future<void> requestVoid(
    Method method, {
    Map<String, dynamic>? params,
    double? timeoutMs,
  }) async {
    await requestRaw(method, params: params, timeoutMs: timeoutMs);
  }

  // ─────────────────────────────────────────────
  // MARK: - refresh  (≈ Swift func refresh())
  // ─────────────────────────────────────────────

  Future<void> refresh() async {
    await _refreshConfig();
  }

  // ─────────────────────────────────────────────
  // MARK: - authSource  (≈ Swift func authSource())
  // ─────────────────────────────────────────────

  GatewayAuthSource? authSource() => _client?.authSource();

  // ─────────────────────────────────────────────
  // MARK: - subscribe  (≈ Swift func subscribe(bufferingNewest:))
  // ─────────────────────────────────────────────

  /// Returns a broadcast stream of [GatewayPush] events.
  /// Immediately emits the cached snapshot if available (mirrors Swift behaviour).
  Stream<GatewayPush> subscribe() {
    final id = const Uuid().v4();
    final controller = StreamController<GatewayPush>.broadcast();
    _subscribers[id] = controller;

    // Emit cached snapshot immediately (mirrors Swift `if let snapshot { continuation.yield(.snapshot(snapshot)) }`)
    final snapshot = _lastSnapshot;
    if (snapshot != null) {
      controller.add(GatewayPushSnapshot(snapshot));
    }

    controller.onCancel = () => _removeSubscriber(id);
    return controller.stream;
  }

  void _removeSubscriber(String id) {
    _subscribers.remove(id);
  }

  // ─────────────────────────────────────────────
  // MARK: - configure  (≈ Swift private func configure(url:token:password:))
  // ─────────────────────────────────────────────

  Future<void> configure({
    required String url,
    String? token,
    String? password,
    String? bootstrapToken,
    GatewayConnectOptions? connectOptions,
  }) async {
    final normalizedToken = _nonEmptyCredential(token);
    final normalizedPassword = _nonEmptyCredential(password);
    final normalizedBootstrapToken = _nonEmptyCredential(bootstrapToken);
    if (_client != null &&
        _configuredURL == url &&
        _configuredToken == normalizedToken &&
        _configuredPassword == normalizedPassword &&
        _configuredBootstrapToken == normalizedBootstrapToken) {
      // 同配置复用现有连接；若仍在连接中，connect() 内部会排队等待
      // 握手完成后再返回，避免调用方误以为连接已就绪。
      if (!_client!.connected) {
        await _client!.connect();
      }
      return;
    }
    if (_client != null) {
      await shutdown();
    }
    _lastSnapshot = null;
    final generation = _clientGeneration;
    _client = GatewayChannelActor(
      url: url,
      token: normalizedToken,
      password: normalizedPassword,
      bootstrapToken: normalizedBootstrapToken,
      pushHandler: (push) => _handle(push),
      disconnectHandler: (reason) => _handleDisconnected(reason, generation),
      connectOptions: connectOptions,
    );
    _configuredURL = url;
    _configuredToken = normalizedToken;
    _configuredPassword = normalizedPassword;
    _configuredBootstrapToken = normalizedBootstrapToken;
    await _client!.connect();
  }

  // ─────────────────────────────────────────────
  // MARK: - handle / broadcast  (≈ Swift private func handle / broadcast)
  // ─────────────────────────────────────────────

  void _handle(GatewayPush push) => _broadcast(push);

  void _broadcast(GatewayPush push) {
    if (push is GatewayPushSnapshot) {
      _lastSnapshot = push.snapshot;
    }
    for (final ctrl in _subscribers.values) {
      ctrl.add(push);
    }
  }

  // ─────────────────────────────────────────────
  // MARK: - canonicalizeSessionKey  (≈ Swift private func canonicalizeSessionKey)
  // ─────────────────────────────────────────────

  String canonicalizeSessionKey(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;
    final defaults = _lastSnapshot?.snapshot.sessiondefaults;
    if (defaults == null) return trimmed;
    final mainSessionKey = _sessionDefaultString(
      defaults,
      key: 'mainSessionKey',
    );
    if (mainSessionKey.isEmpty) return trimmed;
    final mainKey = _sessionDefaultString(defaults, key: 'mainKey');
    final defaultAgentId = _sessionDefaultString(
      defaults,
      key: 'defaultAgentId',
    );
    final isMainAlias =
        trimmed == 'main' ||
        (mainKey.isNotEmpty && trimmed == mainKey) ||
        trimmed == mainSessionKey ||
        (defaultAgentId.isNotEmpty &&
            (trimmed == 'agent:$defaultAgentId:main' ||
                (mainKey.isNotEmpty &&
                    trimmed == 'agent:$defaultAgentId:$mainKey')));
    return isMainAlias ? mainSessionKey : trimmed;
  }

  // ─────────────────────────────────────────────
  // MARK: - helpers
  // ─────────────────────────────────────────────

  String _sessionDefaultString(
    Map<String, dynamic>? defaults, {
    required String key,
  }) {
    final raw = defaults?[key] as String?;
    return (raw ?? '').trim();
  }

  String? _nonEmptyCredential(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _refreshConfig() async {
    if (_configuredURL != null) {
      await configure(
        url: _configuredURL!,
        token: _configuredToken,
        password: _configuredPassword,
        bootstrapToken: _configuredBootstrapToken,
      );
    }
  }

  /// Set a config provider function (mirrors Swift `configProvider` init param).
  // void setConfigProvider(Future<GatewayEndpoint> Function() provider) {
  //   _configProvider = provider;
  // }
}

String? _nonEmptyString(String? value, {bool trim = true}) {
  final normalized = trim ? value?.trim() : value;
  return normalized?.isNotEmpty == true ? normalized : null;
}

class DevicePairSetupCodeResponse {
  final String setupCode;
  final String gatewayUrl;
  final String auth;
  final String urlSource;
  final String? setupId;
  final String? joinUrl;
  final String? qrDataUrl;
  final List<String>? gatewayUrls;
  final String? access;
  final bool? accessDowngraded;
  final int? expiresAtMs;

  const DevicePairSetupCodeResponse({
    required this.setupCode,
    required this.gatewayUrl,
    required this.auth,
    required this.urlSource,
    this.setupId,
    this.joinUrl,
    this.qrDataUrl,
    this.gatewayUrls,
    this.access,
    this.accessDowngraded,
    this.expiresAtMs,
  });

  factory DevicePairSetupCodeResponse.fromJson(Map<String, dynamic> json) {
    final setupCode = json['setupCode'] as String?;
    final gatewayUrl = json['gatewayUrl'] as String?;
    final auth = json['auth'] as String?;
    final urlSource = json['urlSource'] as String?;
    if (setupCode == null || setupCode.trim().isEmpty) {
      throw const FormatException('device.pair.setupCode response missing setupCode');
    }
    if (gatewayUrl == null || gatewayUrl.trim().isEmpty) {
      throw const FormatException('device.pair.setupCode response missing gatewayUrl');
    }
    if (auth == null || auth.trim().isEmpty) {
      throw const FormatException('device.pair.setupCode response missing auth');
    }
    if (urlSource == null || urlSource.trim().isEmpty) {
      throw const FormatException('device.pair.setupCode response missing urlSource');
    }
    return DevicePairSetupCodeResponse(
      setupCode: setupCode,
      gatewayUrl: gatewayUrl,
      auth: auth,
      urlSource: urlSource,
      setupId: json['setupId'] as String?,
      joinUrl: json['joinUrl'] as String?,
      qrDataUrl: json['qrDataUrl'] as String?,
      gatewayUrls: (json['gatewayUrls'] as List?)?.whereType<String>().toList(),
      access: json['access'] as String?,
      accessDowngraded: json['accessDowngraded'] as bool?,
      expiresAtMs: (json['expiresAtMs'] as num?)?.toInt(),
    );
  }
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

  const GatewaySessionThinkingLevelOption({required this.id, required this.label});

  factory GatewaySessionThinkingLevelOption.fromJson(Map<String, dynamic> json) =>
      GatewaySessionThinkingLevelOption(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
      );
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
        agentStatus: _mapValue(json['agentStatus'], GatewaySessionAgentStatus.fromJson),
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
        agentRuntime: _mapValue(json['agentRuntime'], GatewaySessionAgentRuntime.fromJson),
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
        thinkingLevels: _mapList(json['thinkingLevels'], GatewaySessionThinkingLevelOption.fromJson),
        thinkingOptions: _stringList(json['thinkingOptions']),
        thinkingDefault: json['thinkingDefault'] as String?,
      );
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
        sessions: _mapList(json['sessions'], GatewaySessionEntry.fromJson) ?? const [],
      );
}

class GatewayCreateSessionResponse {
  final bool? ok;
  final String key;
  final String? sessionId;

  const GatewayCreateSessionResponse({required this.key, this.ok, this.sessionId});

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
  return value.whereType<Map>().map((item) => parser(item.cast<String, dynamic>())).toList();
}

List<String>? _stringList(dynamic value) {
  if (value is! List) return null;
  return value.whereType<String>().toList();
}

// ─────────────────────────────────────────────
// MARK: - Typed gateway API  (≈ Swift extension GatewayConnection)
// ─────────────────────────────────────────────

extension GatewayConnectionApi on GatewayConnection {
  // ── mainSessionKey  (≈ Swift func mainSessionKey(timeoutMs:)) ────────

  Future<String> mainSessionKey({double timeoutMs = 15000}) async {
    if (cachedMainSessionKey() case final cached?) return cached;
    try {
      final data = await requestRawString('config.get', timeoutMs: timeoutMs);
      final scope =
          ((data['config'] as Map?)?['session'] as Map?)?['scope'] as String?;
      return scope?.trim() == 'global' ? 'global' : 'main';
    } catch (_) {
      return 'main';
    }
  }

  // ── status  (≈ Swift func status()) ─────────────────────────────────

  Future<({bool ok, Object? error})> status() async {
    try {
      await requestRaw(Method.status);
      return (ok: true, error: null);
    } catch (e) {
      // 保留原始异常，配对流程需要从异常 details/requestId 中提取设备 ID。
      return (ok: false, error: e);
    }
  }

  // ── setHeartbeatsEnabled  (≈ Swift func setHeartbeatsEnabled) ────────

  Future<bool> setHeartbeatsEnabled(bool enabled) async {
    try {
      await requestVoid(Method.setHeartbeats, params: {'enabled': enabled});
      return true;
    } catch (e) {
      _log.severe('setHeartbeatsEnabled failed: $e');
      return false;
    }
  }

  // ── sendAgent  (≈ Swift func sendAgent(_ invocation:)) ───────────────

  Future<({bool ok, String? error})> sendAgent(
    GatewayAgentInvocation invocation,
  ) async {
    final trimmed = invocation.message.trim();
    if (trimmed.isEmpty) return (ok: false, error: 'message empty');
    final sessionKey = canonicalizeSessionKey(invocation.sessionKey);

    final params = <String, dynamic>{
      'message': trimmed,
      'sessionKey': sessionKey,
      'deliver': invocation.deliver,
      'to': invocation.to ?? '',
      'channel': invocation.channel.name,
      'idempotencyKey': invocation.idempotencyKey,
    };
    if (invocation.thinking?.trim().isNotEmpty == true) {
      params['thinking'] = invocation.thinking!.trim();
    }
    if (invocation.timeoutSeconds != null) {
      params['timeout'] = invocation.timeoutSeconds;
    }
    if (invocation.voiceWakeTrigger?.trim().isNotEmpty == true) {
      params['voiceWakeTrigger'] = invocation.voiceWakeTrigger!.trim();
    }

    try {
      await requestVoid(Method.agent, params: params);
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  /// Mirrors Swift convenience overload of `sendAgent`.
  Future<({bool ok, String? error})> sendAgentMessage({
    required String message,
    String? thinking,
    required String sessionKey,
    required bool deliver,
    String? to,
    GatewayAgentChannel channel = GatewayAgentChannel.last,
    int? timeoutSeconds,
    String? idempotencyKey,
  }) => sendAgent(
    GatewayAgentInvocation(
      message: message,
      sessionKey: sessionKey,
      thinking: thinking,
      deliver: deliver,
      to: to,
      channel: channel,
      timeoutSeconds: timeoutSeconds,
      idempotencyKey: idempotencyKey,
    ),
  );

  // ── sendSystemEvent  (≈ Swift func sendSystemEvent) ──────────────────

  Future<void> sendSystemEvent(Map<String, dynamic> params) async {
    try {
      await requestVoid(Method.systemEvent, params: params);
    } catch (_) {
      // best-effort
    }
  }

  // ── health ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> healthSnapshot({double? timeoutMs}) =>
      requestRaw(Method.health, timeoutMs: timeoutMs);

  Future<bool> healthOK({double timeoutMs = 8000}) async {
    try {
      final data = await requestRaw(Method.health, timeoutMs: timeoutMs);
      return data['ok'] as bool? ?? true;
    } catch (_) {
      return false;
    }
  }

  // ── skills ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> skillsStatus() =>
      requestRaw(Method.skillsStatus);

  Future<Map<String, dynamic>> skillsInstall({
    required String name,
    required String installId,
    bool? dangerouslyForceUnsafeInstall,
    int? timeoutMs,
  }) {
    final params = <String, dynamic>{
      'name': name,
      'installId': installId,
      if (dangerouslyForceUnsafeInstall != null)
        'dangerouslyForceUnsafeInstall': dangerouslyForceUnsafeInstall,
      if (timeoutMs != null) 'timeoutMs': timeoutMs,
    };
    return requestRaw(Method.skillsInstall, params: params);
  }

  Future<Map<String, dynamic>> skillsUpdate({
    required String skillKey,
    bool? enabled,
    String? apiKey,
    Map<String, String>? env,
  }) {
    final params = <String, dynamic>{
      'skillKey': skillKey,
      if (enabled != null) 'enabled': enabled,
      if (apiKey != null) 'apiKey': apiKey,
      if (env != null && env.isNotEmpty) 'env': env,
    };
    return requestRaw(Method.skillsUpdate, params: params);
  }

  // ── sessions ──────────────────────────────────────────────────────────

  Future<GatewaySessionsListResponse> sessionsList({
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
    double timeoutMs = 15000,
  }) async {
    final params = <String, dynamic>{
      'includeGlobal': includeGlobal,
      'includeUnknown': includeUnknown,
      if (_nonEmptyString(agentId) case final value?) 'agentId': value,
      if (limit != null) 'limit': limit,
      if (activeMinutes != null) 'activeMinutes': activeMinutes,
      if (_nonEmptyString(spawnedBy) case final value?) 'spawnedBy': value,
      if (offset != null) 'offset': offset,
      if (configuredAgentsOnly != null)
        'configuredAgentsOnly': configuredAgentsOnly,
      if (_nonEmptyString(search) case final value?) 'search': value,
      if (archived) 'archived': true,
    };
    return GatewaySessionsListResponse.fromJson(
      await requestRaw(Method.sessionsList, params: params, timeoutMs: timeoutMs),
    );
  }

  Future<GatewayCreateSessionResponse> sessionsCreate({
    required String key,
    String? agentId,
    String? label,
    String? parentSessionKey,
    bool? worktree,
    String? worktreeBaseRef,
    double timeoutMs = 15000,
  }) async {
    final params = <String, dynamic>{
      'key': key,
      if (_nonEmptyString(agentId) case final value?) 'agentId': value,
      if (label != null) 'label': label,
      if (parentSessionKey != null) 'parentSessionKey': parentSessionKey,
      if (worktree != null) 'worktree': worktree,
      if (_nonEmptyString(worktreeBaseRef) case final value?)
        'worktreeBaseRef': value,
    };
    return GatewayCreateSessionResponse.fromJson(
      await requestRaw(Method.sessionsCreate, params: params, timeoutMs: timeoutMs),
    );
  }

  Future<void> sessionsDelete({
    required String sessionKey,
    String? agentId,
    double timeoutMs = 15000,
  }) async {
    final params = <String, dynamic>{
      'key': sessionKey,
      if (_nonEmptyString(agentId) case final value?) 'agentId': value,
      'deleteTranscript': true,
    };
    await requestVoid(Method.sessionsDelete, params: params, timeoutMs: timeoutMs);
  }

  // ── sessionsPreview ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> sessionsPreview({
    required List<String> keys,
    int? limit,
    int? maxChars,
    int? timeoutMs,
  }) {
    final resolvedKeys =
        keys.map(canonicalizeSessionKey).where((k) => k.isNotEmpty).toList();
    if (resolvedKeys.isEmpty) return Future.value({'ts': 0, 'previews': []});
    final params = <String, dynamic>{
      'keys': resolvedKeys,
      if (limit != null) 'limit': limit,
      if (maxChars != null) 'maxChars': maxChars,
    };
    return requestRaw(
      Method.sessionsPreview,
      params: params,
      timeoutMs: timeoutMs?.toDouble(),
    );
  }

  // ── chat ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> chatHistory(
    String sessionKey, {
    int? limit,
    int? maxChars,
    int? timeoutMs,
  }) {
    final resolvedKey = canonicalizeSessionKey(sessionKey);
    final params = <String, dynamic>{
      'sessionKey': resolvedKey,
      if (limit != null) 'limit': limit,
      if (maxChars != null) 'maxChars': maxChars,
    };
    return requestRaw(
      Method.chatHistory,
      params: params,
      timeoutMs: timeoutMs?.toDouble(),
    );
  }

  Future<Map<String, dynamic>> chatSend({
    required String sessionKey,
    required String message,
    String? thinking,
    required String idempotencyKey,
    List<Map<String, dynamic>> attachments = const [],
    int timeoutMs = 30000,
  }) {
    final resolvedKey = canonicalizeSessionKey(sessionKey);
    final params = <String, dynamic>{
      'sessionKey': resolvedKey,
      'message': message,
      'idempotencyKey': idempotencyKey,
      'timeoutMs': timeoutMs,
    };
    if (thinking?.trim().isNotEmpty == true) {
      params['thinking'] = thinking!.trim();
    }
    if (attachments.isNotEmpty) {
      params['attachments'] =
          attachments
              .map(
                (att) => {
                  'type': att['type'],
                  'mimeType': att['mimeType'],
                  'fileName': att['fileName'],
                  'content': att['content'],
                },
              )
              .toList();
    }
    return requestRaw(
      Method.chatSend,
      params: params,
      timeoutMs: timeoutMs.toDouble(),
    );
  }

  Future<bool> chatAbort(String sessionKey, String runId) async {
    final resolvedKey = canonicalizeSessionKey(sessionKey);
    final res = await requestRaw(
      Method.chatAbort,
      params: {'sessionKey': resolvedKey, 'runId': runId},
    );
    return res['aborted'] as bool? ?? false;
  }

  Future<void> talkMode({required bool enabled, String? phase}) {
    final params = <String, dynamic>{
      'enabled': enabled,
      if (phase != null) 'phase': phase,
    };
    return requestVoid(Method.talkMode, params: params);
  }

  // ── voicewake ─────────────────────────────────────────────────────────

  Future<List<String>> voiceWakeGetTriggers() async {
    final data = await requestRaw(Method.voicewakeGet);
    return List<String>.from(data['triggers'] as List? ?? []);
  }

  Future<void> voiceWakeSetTriggers(List<String> triggers) async {
    try {
      await requestVoid(
        Method.voicewakeSet,
        params: {'triggers': triggers},
        timeoutMs: 10000,
      );
    } catch (_) {
      // best-effort
    }
  }

  // ── node pairing ──────────────────────────────────────────────────────

  Future<void> nodePairApprove(String requestId) => requestVoid(
    Method.nodePairApprove,
    params: {'requestId': requestId},
    timeoutMs: 10000,
  );

  Future<void> nodePairReject(String requestId) => requestVoid(
    Method.nodePairReject,
    params: {'requestId': requestId},
    timeoutMs: 10000,
  );

  // ── device pairing ────────────────────────────────────────────────────

  /// Requests a short-lived device pairing setup code and optional QR image.
  ///
  /// The gateway returns [qrDataUrl] as a PNG data URL when [includeQr] is
  /// true (the default). The setup code itself is a Base64URL payload and
  /// should be treated as a bearer credential until [expiresAtMs].
  Future<DevicePairSetupCodeResponse> devicePairSetupCode({
    String? publicUrl,
    bool? preferRemoteUrl,
    bool includeQr = true,
    String? bootstrapProfile,
    bool joinUrl = false,
    double timeoutMs = 15000,
  }) async {
    if (bootstrapProfile != null &&
        bootstrapProfile != 'limited' &&
        bootstrapProfile != 'node') {
      throw ArgumentError.value(
        bootstrapProfile,
        'bootstrapProfile',
        'must be limited or node',
      );
    }
    if (joinUrl && bootstrapProfile != null && bootstrapProfile != 'node') {
      throw ArgumentError('joinUrl requires bootstrapProfile=node');
    }

    final params = <String, dynamic>{
      if (publicUrl?.trim().isNotEmpty == true) 'publicUrl': publicUrl!.trim(),
      if (preferRemoteUrl != null) 'preferRemoteUrl': preferRemoteUrl,
      'includeQr': includeQr,
      if (bootstrapProfile != null) 'bootstrapProfile': bootstrapProfile,
      if (joinUrl) 'joinUrl': true,
    };
    return DevicePairSetupCodeResponse.fromJson(
      await requestRaw(
        Method.devicePairSetupCode,
        params: params,
        timeoutMs: timeoutMs,
      ),
    );
  }

  Future<void> devicePairApprove(String requestId) => requestVoid(
    Method.devicePairApprove,
    params: {'requestId': requestId},
    timeoutMs: 10000,
  );

  Future<void> devicePairReject(String requestId) => requestVoid(
    Method.devicePairReject,
    params: {'requestId': requestId},
    timeoutMs: 10000,
  );

  // ── cron ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> cronStatus() => requestRaw(Method.cronStatus);

  Future<List<dynamic>> cronList({bool includeDisabled = true}) async {
    final data = await requestRaw(
      Method.cronList,
      params: {'includeDisabled': includeDisabled},
    );
    return data['jobs'] as List? ?? [];
  }

  Future<List<dynamic>> cronRuns(String jobId, {int limit = 200}) async {
    final data = await requestRaw(
      Method.cronRuns,
      params: {'id': jobId, 'limit': limit},
    );
    return data['entries'] as List? ?? [];
  }

  Future<void> cronRun(String jobId, {bool force = true}) => requestVoid(
    Method.cronRun,
    params: {'id': jobId, 'mode': force ? 'force' : 'due'},
    timeoutMs: 20000,
  );

  Future<void> cronRemove(String jobId) =>
      requestVoid(Method.cronRemove, params: {'id': jobId});

  Future<void> cronUpdate(String jobId, Map<String, dynamic> patch) =>
      requestVoid(Method.cronUpdate, params: {'id': jobId, 'patch': patch});

  Future<void> cronAdd(Map<String, dynamic> payload) =>
      requestVoid(Method.cronAdd, params: payload);

  Future<List<dynamic>> listModels({double timeoutMs = 15000}) async {
    try {
      final data = await requestRaw(Method.modelsList, timeoutMs: timeoutMs);
      _log.info(data);
      return data['models'] as List? ?? [];
    } catch (e) {
      _log.warning('models.list failed: $e');
      return [];
    }
  }
}
