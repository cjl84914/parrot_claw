import 'dart:io';

import 'package:parrot_app/data/service/impl/macos_openclaw_environment.dart';
import 'package:parrot_app/data/service/impl/openclaw_model_service_impl.dart';

class MacOSOpenClawModelService extends OpenClawModelServiceImpl {
  MacOSOpenClawModelService()
      : super(
          configFilePath: MacOSOpenClawEnvironment.configFilePath,
          extensionDirectoriesLoader: _loadExtensionDirectories,
          pathJoiner: _joinPath,
        );

  static Future<List<Directory>> _loadExtensionDirectories() async {
    final root =
        Directory('${MacOSOpenClawEnvironment.homePath}/.openclaw/extensions');
    if (!await root.exists()) return const [];

    final directories = <Directory>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory) directories.add(entity);
    }
    return directories;
  }

  static String _joinPath(String parent, String child) => '$parent/$child';
}
