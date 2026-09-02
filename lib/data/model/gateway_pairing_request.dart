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

  const GatewayPairingRequest({
    required this.host,
    required this.port,
    required this.useTLS,
    required this.bootstrapToken,
    this.token,
    this.password,
    this.contextPath,
    this.expiresAtMs,
  });

  String get wsUrl {
    final scheme = useTLS ? 'wss' : 'ws';
    return '$scheme://$host:$port${contextPath ?? ''}';
  }

  static GatewayPairingRequest? fromSetupCode(String input) {
    var value = input.trim();
    if (value.isEmpty) return null;

    const prefix = 'oc-pair://';
    if (value.toLowerCase().startsWith(prefix)) {
      value = value.substring(prefix.length);
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

      return GatewayPairingRequest(
        host: uri.host,
        port: port,
        useTLS: useTLS,
        bootstrapToken: bootstrapToken,
        token: _nonEmpty(json['token'] as String?),
        password: _nonEmpty(json['password'] as String?),
        contextPath: uri.path.isEmpty ? null : uri.path,
        expiresAtMs: expiresAtMs,
      );
    } catch (_) {
      return null;
    }
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
