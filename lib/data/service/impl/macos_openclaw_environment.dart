import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// macOS-only process and filesystem configuration for OpenClaw setup.
///
/// Windows will provide its own implementation-specific environment later.
abstract final class MacOSOpenClawEnvironment {
  /// Enable only when testing the first-run isolated installation flow.
  // 隔离环境仅用于自动化回归，不能在正常桌面应用中启用；否则
  // App 会使用 /tmp 下的 HOME 和配置，与用户在终端执行的 openclaw
  // 使用的真实 Gateway 不是同一个实例。
  static const bool enableIsolatedOpenClawSetupEnv = true;

  static const String isolatedHomePath = '/tmp/parrotclaw-openclaw-test-home';
  static const String isolatedPath = '/usr/bin:/bin:/usr/sbin:/sbin';

  static bool get useIsolatedOpenClawSetupEnv =>
      kDebugMode && enableIsolatedOpenClawSetupEnv;

  static String get homePath =>
      useIsolatedOpenClawSetupEnv
          ? isolatedHomePath
          : Platform.environment['HOME'] ?? '.';

  static Map<String, String> get processEnvironment {
    if (!useIsolatedOpenClawSetupEnv) {
      return Platform.environment;
    }
    return {
      ...Platform.environment,
      'HOME': isolatedHomePath,
      'PATH': isolatedPath,
    };
  }

  static String get localNodeBinPath => '$homePath/.parrot/node/bin';

  static String get configFilePath => '$homePath/.openclaw/openclaw.json';

  static String get processPath => pathWithPrepended(localNodeBinPath);

  static Map<String, String> get openClawProcessEnvironment => {
    ...processEnvironment,
    'PATH': processPath,
  };

  static String pathWithPrepended(String path) {
    final basePath = processEnvironment['PATH'] ?? '';
    if (basePath.isEmpty) return path;
    return '$path:$basePath';
  }

  /// Persists token auth before an isolated cold-start gateway launches.
  /// Real user credentials remain managed by OpenClaw itself.
  static Future<String> ensureIsolatedGatewayToken() async {
    if (!useIsolatedOpenClawSetupEnv) {
      throw StateError('隔离测试环境未启用');
    }

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
