import 'dart:io';

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
}
