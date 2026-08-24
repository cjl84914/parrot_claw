import 'dart:io';

import 'package:flutter/foundation.dart';

/// macOS-only process and filesystem configuration for OpenClaw setup.
///
/// Windows will provide its own implementation-specific environment later.
abstract final class MacOSOpenClawEnvironment {
  /// Enable only when testing the first-run isolated installation flow.
  static const bool enableIsolatedOpenClawSetupEnv = false;

  static const String isolatedHomePath = '/tmp/parrotclaw-openclaw-test-home';
  static const String isolatedPath = '/usr/bin:/bin:/usr/sbin:/sbin';
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

  static Map<String, String> get openClawProcessEnvironment => {
    ...processEnvironment,
    'PATH': processPath,
  };

  static String pathWithPrepended(String path) {
    final basePath = processEnvironment['PATH'] ?? '';
    if (basePath.isEmpty) return path;
    return '$path:$basePath';
  }
}
