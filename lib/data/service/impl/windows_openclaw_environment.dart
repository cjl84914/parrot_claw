import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Windows-specific process and filesystem configuration for OpenClaw.
abstract final class WindowsOpenClawEnvironment {
  static String get userHome =>
      Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;

  static String get appData =>
      Platform.environment['APPDATA'] ?? '$userHome\\AppData\\Roaming';

  static String get localAppData =>
      Platform.environment['LOCALAPPDATA'] ?? '$userHome\\AppData\\Local';

  static String get openClawHome => '$userHome\\.openclaw';

  static String get configFilePath {
    final configured = Platform.environment['OPENCLAW_CONFIG_PATH']?.trim();
    return configured == null || configured.isEmpty
        ? '$openClawHome\\openclaw.json'
        : configured;
  }
  static String get nodeHomePath => '$userHome\\.parrot\\node';
  static String get nodeBinPath => nodeHomePath;
  static String get nodeExecutable => '$nodeHomePath\\node.exe';
  static String get npmExecutable => '$nodeHomePath\\npm.cmd';

  static String get npmGlobalRoot => '$appData\\npm';
  static String get openClawExecutable => '$npmGlobalRoot\\openclaw.cmd';

  static String get pathSeparator => ';';

  static Map<String, String> get processEnvironment => Platform.environment;

  static Map<String, String> get openClawProcessEnvironment => {
    ...processEnvironment,
    'PATH': pathWithPrepended(nodeBinPath, includeGlobalNpm: true),
  };

  static String pathWithPrepended(
    String path, {
    bool includeGlobalNpm = false,
  }) {
    final entries = <String>[
      path,
      if (includeGlobalNpm) npmGlobalRoot,
      processEnvironment['PATH'] ?? '',
    ].where((value) => value.trim().isNotEmpty);
    return entries.join(pathSeparator);
  }

  /// Ensures local gateway configuration supports LAN mobile connections.
  /// Existing user config is preserved; only gateway auth and bind fields are
  /// initialized or repaired before OpenClaw restarts.
  static Future<String> ensureGatewayTokenForLan() async {
    final configFile = File(configFilePath);
    final config = await _readConfig(configFile);
    final gateway = _ensureMap(config, 'gateway');
    final auth = _ensureMap(gateway, 'auth');
    final configuredToken = _nonEmptyString(auth['token']);
    final token = configuredToken ?? _generateToken();

    final changed =
        gateway['mode'] != 'local' ||
        gateway['bind'] != 'lan' ||
        auth['mode'] != 'token' ||
        configuredToken == null;
    gateway['mode'] = 'local';
    gateway['bind'] = 'lan';
    auth['mode'] = 'token';
    auth['token'] = token;

    if (changed) {
      await configFile.parent.create(recursive: true);
      const encoder = JsonEncoder.withIndent('  ');
      await configFile.writeAsString(
        '${encoder.convert(config)}\n',
        flush: true,
      );
    }
    return token;
  }

  static Future<Map<String, dynamic>> _readConfig(File configFile) async {
    if (!await configFile.exists()) return <String, dynamic>{};
    final content = await configFile.readAsString();
    if (content.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw const FormatException('OpenClaw 配置文件格式不正确');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static Map<String, dynamic> _ensureMap(
    Map<String, dynamic> parent,
    String key,
  ) {
    final current = parent[key];
    if (current is Map<String, dynamic>) return current;
    if (current is Map) {
      final converted = Map<String, dynamic>.from(current);
      parent[key] = converted;
      return converted;
    }
    final created = <String, dynamic>{};
    parent[key] = created;
    return created;
  }

  static String? _nonEmptyString(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
