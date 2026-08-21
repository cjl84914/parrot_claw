import 'dart:io';

import 'package:flutter/foundation.dart';

/// Local process environment used by OpenClaw setup.
///
/// Keep [enableIsolatedOpenClawSetupEnv] false for normal builds. Turn it on
/// only when testing the first-run Node/OpenClaw installation flow.
abstract final class LocalEnvConfig {
  static const bool enableIsolatedOpenClawSetupEnv = false;

  static const String isolatedHomePath = '/tmp/parrotclaw-openclaw-test-home';

  static const String isolatedPath = '/usr/bin:/bin:/usr/sbin:/sbin';

  // Debug-only credential used by the isolated foreground Gateway process.
  static const String isolatedGatewayToken =
      'parrotclaw-isolated-openclaw-test-token';

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

  static String get processPath => pathWithPrepended(localNodeBinPath);

  static Map<String, String> get openClawProcessEnvironment {
    return {...processEnvironment, 'PATH': processPath};
  }

  static String pathWithPrepended(String path) {
    final basePath = processEnvironment['PATH'] ?? '';
    if (basePath.isEmpty) return path;
    return '$path:$basePath';
  }
}
