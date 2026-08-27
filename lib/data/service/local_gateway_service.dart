/// 本机 Gateway 进程状态。
enum LocalGatewayProcessState { running, stopped, unknown }

/// 不依赖 WebSocket 鉴权的本机 Gateway 服务状态。
class LocalGatewayServiceStatus {
  final LocalGatewayProcessState state;
  final int? port;
  final String? address;

  const LocalGatewayServiceStatus({
    required this.state,
    this.port,
    this.address,
  });

  bool get running => state == LocalGatewayProcessState.running;
}

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

  /// 查询本机 Gateway 服务状态，不要求 WebSocket 鉴权成功。
  Future<LocalGatewayServiceStatus> queryGatewayStatus();

  Future<int> startGateway({void Function(String line)? onOutput});

  Future<int> stopGateway({void Function(String line)? onOutput});

  Future<LocalGatewayCredentials> readGatewayCredentials();
}
