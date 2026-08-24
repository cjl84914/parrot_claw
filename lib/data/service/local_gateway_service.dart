/// Local OpenClaw Gateway credentials.
class LocalGatewayCredentials {
  final String? token;
  final String? password;

  const LocalGatewayCredentials({this.token, this.password});

  bool get hasToken => token?.trim().isNotEmpty == true;
  bool get hasPassword => password?.trim().isNotEmpty == true;
  bool get hasAny => hasToken || hasPassword;
  String get authMode => hasToken || !hasPassword ? 'token' : 'password';
}

/// 本机 OpenClaw Gateway 服务接口。
///
/// macOS/Windows 的命令、进程和文件路径由 impl 目录中的具体实现负责。
abstract interface class LocalGatewayService {
  Future<bool> isOpenClawInstalled();

  Future<bool> isGatewayAt(
    int port, {
    String host,
    String? token,
    String? password,
  });

  Future<int?> detectGatewayPort();

  Future<int> startGateway({void Function(String line)? onOutput});

  Future<LocalGatewayCredentials> readGatewayCredentials();
}
