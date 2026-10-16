import 'dart:convert';

/// OpenClaw setup code 的一次性内存凭据。
/// bootstrapToken 只用于首次握手，不参与 ServerConfig 持久化。
class GatewayPairingRequest {
  final String host;
  final int port;
  final bool useTLS;
  final String bootstrapToken;
  final String? token;
  final String? password;
  final String? contextPath;
  final int? expiresAtMs;

  /// payload 里 `urls[]` 广告的备用地址（已规范化成 ws/wss，并去掉与主地址重复的）。
  ///
  /// 官方只在 `gateway.bind=lan` 且探测到持久 Tailscale Serve HTTPS 根时才附这一项
  /// （`docs/cli/qr.md`：「Current iOS clients probe the advertised routes in order
  /// and save the first reachable one」）。主地址（[wsUrl]）不通时按顺序回退。
  final List<String> fallbackUrls;

  /// 网关 TLS 证书指纹：小写十六进制 SHA-256（64 字符）。
  ///
  /// 官方只在直连本地 TLS（`gateway.bind=`）或 `gateway.remote.url` 带指纹时才下发。
  /// 语义与官方客户端一致：对 **DER 编码证书**取 SHA-256
  /// （Android 侧 `X509Certificate.encoded.toByteString().sha256().hex()`）。
  final String? tlsFingerprint;

  const GatewayPairingRequest({
    required this.host,
    required this.port,
    required this.useTLS,
    required this.bootstrapToken,
    this.token,
    this.password,
    this.contextPath,
    this.expiresAtMs,
    this.fallbackUrls = const <String>[],
    this.tlsFingerprint,
  });

  String get wsUrl {
    final scheme = useTLS ? 'wss' : 'ws';
    return '$scheme://$host:$port${contextPath ?? ''}';
  }

  /// 按顺序尝试的候选地址：主地址在前，其后是 [fallbackUrls]。
  ///
  /// 探测与正式连接都按这个顺序走，「第一个握手成功的」就是最终落配置的地址。
  List<String> get candidateUrls => <String>[wsUrl, ...fallbackUrls];

  static const int _maxFallbackUrls = 8;

  static const String _setupCodePrefix = 'oc-pair://';

  static final RegExp _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

  static final RegExp _sha256Colon = RegExp(r'^[0-9a-f]{2}(:[0-9a-f]{2}){31}$');

  static GatewayPairingRequest? fromSetupCode(String input) {
    var value = input.trim();
    if (value.isEmpty) return null;

    if (value.toLowerCase().startsWith(_setupCodePrefix)) {
      value = value.substring(_setupCodePrefix.length);
    }

    final direct = _decodeJson(value);
    if (direct != null) return direct;

    final decoded = _decodeBase64Url(value);
    if (decoded != null) {
      final request = _decodeJson(decoded);
      if (request != null) return request;
    }

    for (final candidate in _candidates(value)) {
      if (candidate == value) continue;
      final candidateJson = _decodeBase64Url(candidate);
      if (candidateJson == null) continue;
      final request = _decodeJson(candidateJson);
      if (request != null) return request;
    }

    return null;
  }

  static GatewayPairingRequest? _decodeJson(String value) {
    try {
      final json = jsonDecode(value);
      if (json is! Map) return null;

      final rawUrl = (json['url'] as String?)?.trim();
      if (rawUrl == null || rawUrl.isEmpty) return null;

      final uri = Uri.tryParse(rawUrl);
      if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
        return null;
      }
      if (uri.query.isNotEmpty || uri.fragment.isNotEmpty) return null;

      final scheme = uri.scheme.toLowerCase();
      if (scheme != 'ws' && scheme != 'wss' &&
          scheme != 'http' && scheme != 'https') {
        return null;
      }

      final useTLS = scheme == 'wss' || scheme == 'https';
      if (!useTLS && !_isLocalNetworkHost(uri.host)) return null;

      final port = uri.hasPort ? uri.port : (useTLS ? 443 : 18789);
      if (port < 1 || port > 65535) return null;

      final bootstrapToken = (json['bootstrapToken'] as String?)?.trim() ?? '';
      if (bootstrapToken.isEmpty) return null;

      final expiresAtMs = (json['expiresAtMs'] as num?)?.toInt();
      if (expiresAtMs != null &&
          expiresAtMs <= DateTime.now().millisecondsSinceEpoch) {
        return null;
      }

      // 与官方一致：`urls` **存在但非法** → 整条 payload 无效，而不是悄悄忽略
      // （官方 `decodePairingSetupCode` 对这些字段是抛错语义）。
      final fallbackUrls = _parseFallbackUrls(json['urls'], rawUrl);
      if (fallbackUrls == null) return null;

      final rawFingerprint = json['tlsFingerprint'];
      final tlsFingerprint = _normalizeTlsFingerprint(rawFingerprint);
      if (rawFingerprint != null && tlsFingerprint == null) return null;

      return GatewayPairingRequest(
        host: uri.host,
        port: port,
        useTLS: useTLS,
        bootstrapToken: bootstrapToken,
        token: _nonEmpty(json['token'] as String?),
        password: _nonEmpty(json['password'] as String?),
        contextPath: uri.path.isEmpty ? null : uri.path,
        expiresAtMs: expiresAtMs,
        fallbackUrls: fallbackUrls,
        tlsFingerprint: tlsFingerprint,
      );
    } catch (_) {
      return null;
    }
  }

  /// 解析 `urls[]`。返回 null 表示「字段存在但不合法」。
  static List<String>? _parseFallbackUrls(Object? raw, String primaryUrl) {
    if (raw == null) return const <String>[];
    if (raw is! List || raw.isEmpty || raw.length > _maxFallbackUrls) return null;

    final primary = _normalizeWsUrl(primaryUrl);
    final urls = <String>[];
    for (final candidate in raw) {
      if (candidate is! String) return null;
      final normalized = _normalizeWsUrl(candidate);
      if (normalized == null) return null;
      if (normalized == primary || urls.contains(normalized)) continue;
      urls.add(normalized);
    }
    return urls;
  }

  /// 把一条网关地址规范化成 `ws`/`wss` 形式（`http`→`ws`、`https`→`wss`）。
  ///
  /// 候选地址必须能直接喂给 `IOWebSocketChannel.connect`，所以这里统一 scheme；
  /// 不规范化就会拿 `https://` 去连 WebSocket，必然失败。
  static String? _normalizeWsUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
    if (uri.query.isNotEmpty || uri.fragment.isNotEmpty) return null;

    final String wsScheme;
    switch (uri.scheme.toLowerCase()) {
      case 'ws':
      case 'http':
        wsScheme = 'ws';
      case 'wss':
      case 'https':
        wsScheme = 'wss';
      default:
        return null;
    }

    final port = uri.hasPort ? uri.port : (wsScheme == 'wss' ? 443 : 18789);
    if (port < 1 || port > 65535) return null;

    return '$wsScheme://${uri.host}:$port${uri.path == '/' ? '' : uri.path}';
  }

  /// 归一化 TLS 证书指纹：去 `sha256:` 前缀、去冒号分隔、转小写。
  ///
  /// 与官方 `normalizeTlsFingerprint` 接受的形式一致（裸 hex / 冒号分隔 / 带前缀）。
  static String? _normalizeTlsFingerprint(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim().replaceFirst(
      RegExp(r'^sha256:', caseSensitive: false),
      '',
    );
    final lower = value.toLowerCase();
    if (_sha256Hex.hasMatch(lower)) return lower;
    if (_sha256Colon.hasMatch(lower)) return lower.replaceAll(':', '');
    return null;
  }

  static String? _decodeBase64Url(String value) {
    try {
      return utf8.decode(base64Url.decode(base64Url.normalize(value)));
    } catch (_) {
      return null;
    }
  }

  static Iterable<String> _candidates(String input) sync* {
    final punctuation = RegExp(
      r'''^[`'"“”‘’()\[\]{}<>.,;:]+|[`'"“”‘’()\[\]{}<>.,;:]+$''',
    );
    for (final part in input.split(RegExp(r'\s+'))) {
      final candidate = part.replaceAll(punctuation, '');
      if (candidate.length >= 24 &&
          RegExp(r'^[A-Za-z0-9_-]+={0,2}$').hasMatch(candidate)) {
        yield candidate;
      }
    }
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool _isLocalNetworkHost(String host) {
    final value = host.toLowerCase();
    if (value == 'localhost' || value == '127.0.0.1' ||
        value == '::1' || value.endsWith('.local')) {
      return true;
    }
    final parts = value.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any(
      (part) => part == null || part! < 0 || part > 255,
    )) {
      return false;
    }
    final a = octets[0]!;
    final b = octets[1]!;
    return a == 10 || (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }
}
