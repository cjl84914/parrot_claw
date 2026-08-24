import 'dart:io';

import 'package:parrot_app/data/service/impl/macos_local_gateway_service.dart';
import 'package:parrot_app/data/service/impl/macos_openclaw_installer_service.dart';
import 'package:parrot_app/data/service/impl/macos_openclaw_model_service.dart';
import 'package:parrot_app/data/service/impl/windows_local_gateway_service.dart';
import 'package:parrot_app/data/service/impl/windows_openclaw_installer_service.dart';
import 'package:parrot_app/data/service/impl/windows_openclaw_model_service.dart';
import 'package:parrot_app/data/service/local_gateway_service.dart';
import 'package:parrot_app/data/service/openclaw_installer_service.dart';
import 'package:parrot_app/data/service/openclaw_model_service.dart';

class OpenClawServices {
  final LocalGatewayService gateway;
  final OpenClawInstallerService installer;
  final OpenClawModelService model;

  const OpenClawServices({
    required this.gateway,
    required this.installer,
    required this.model,
  });
}

abstract final class OpenClawServiceFactory {
  static OpenClawServices create() {
    if (Platform.isWindows) {
      return OpenClawServices(
        gateway: WindowsLocalGatewayService(),
        installer: WindowsOpenClawInstallerService(),
        model: WindowsOpenClawModelService(),
      );
    }

    return OpenClawServices(
      gateway: MacOSLocalGatewayService(),
      installer: MacOSOpenClawInstallerService(),
      model: MacOSOpenClawModelService(),
    );
  }
}
