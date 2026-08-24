/// OpenClaw 安装服务接口。
///
/// macOS/Windows 的 Node 下载、解压、命令和环境变量由 impl 目录中的
/// 具体实现负责。
abstract interface class OpenClawInstallerService {
  bool get installing;

  String get nodeHomePath;

  String get localNodeBin;

  Future<String> ensureNode({void Function(String line)? onOutput});

  Future<int> installOpenClaw({
    required String nodeBin,
    void Function(String line)? onOutput,
  });

  Future<String?> verifyInstall();

  Future<bool> isInstalled();
}
