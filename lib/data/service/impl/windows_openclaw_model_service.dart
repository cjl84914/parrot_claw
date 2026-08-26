import 'dart:io';

import 'package:parrot_app/data/service/impl/openclaw_model_service_impl.dart';
import 'package:parrot_app/data/service/impl/windows_openclaw_environment.dart';

class WindowsOpenClawModelService extends OpenClawModelServiceImpl {
  WindowsOpenClawModelService()
      : super(
          configFilePath: WindowsOpenClawEnvironment.configFilePath,
          extensionDirectoriesLoader: _loadExtensionDirectories,
          pathJoiner: _joinPath,
        );

  static Future<List<Directory>> _loadExtensionDirectories() async {
    final roots = <Directory>[
      Directory('${WindowsOpenClawEnvironment.openClawHome}\\extensions'),
    ];

    final npmRoot = await _readNpmGlobalRoot();
    if (npmRoot != null) {
      roots.add(Directory('$npmRoot\\openclaw\\extensions'));
    }

    final directories = <Directory>[];
    final seen = <String>{};
    for (final root in roots) {
      if (!await root.exists()) continue;
      await for (final entity in root.list(followLinks: false)) {
        if (entity is Directory && seen.add(_normalizedPath(entity.path))) {
          directories.add(entity);
        }
      }
    }
    return directories;
  }

  static Future<String?> _readNpmGlobalRoot() async {
    try {
      final result = await Process.run(
        'cmd.exe',
        ['/c', 'npm.cmd', 'root', '-g'],
        environment: WindowsOpenClawEnvironment.openClawProcessEnvironment,
        runInShell: true,
      );
      if (result.exitCode != 0) return null;
      final root = _firstNonEmptyLine(result.stdout);
      return root.isEmpty ? null : root;
    } catch (_) {
      return null;
    }
  }

  static String _firstNonEmptyLine(dynamic value) {
    if (value is! String) return '';
    for (final line in value.split(RegExp(r'[\r\n]+'))) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  static String _normalizedPath(String value) =>
      value.replaceAll('/', '\\').toLowerCase();

  static String _joinPath(String parent, String child) => '$parent\\$child';
}
