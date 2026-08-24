import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:parrot_app/data/service/impl/macos_openclaw_environment.dart';
import 'package:parrot_app/data/service/openclaw_installer_service.dart';

/// OpenClaw 安装服务（无状态，纯本机操作）
///
/// 职责：
/// - 确保 Node.js 可用（无则从 npmmirror 镜像下载二进制，免安装）
/// - 通过 npm（npmmirror 镜像源）安装 OpenClaw
/// - 流式输出安装进度（供 UI 进度条使用）
/// - 验证安装结果
///
/// 为什么不用官方 install.sh：
/// 官方脚本 macOS 依赖 Homebrew（brew install node），且装 Homebrew 需从
/// GitHub raw 拉取 —— 国内网络基本必挂。本实现改为全程国内镜像：
/// - Node：npmmirror.com/mirrors/node/ 下载 darwin 二进制，解压即用（免 brew、免系统安装）
/// - OpenClaw：npm install -g openclaw --registry=https://registry.npmmirror.com
///
/// 架构：无状态 Service，由 Repository 消费，不包含业务逻辑。
class MacOSOpenClawInstallerService implements OpenClawInstallerService {
  MacOSOpenClawInstallerService({Logger? logger})
    : _log = logger ?? Logger('MacOSOpenClawInstallerService');

  final Logger _log;

  /// Node 二进制镜像根（npmmirror 淘宝源）
  static const String nodeMirrorBase = 'https://npmmirror.com/mirrors/node';

  /// npm registry 镜像
  static const String npmRegistryMirror = 'https://registry.npmmirror.com';

  /// 安装后 Node 的本地目录（相对用户 home）
  static const String nodeInstallDir = '.parrot/node';

  /// OpenClaw npm 包名
  static const String openClawPackage = 'openclaw';

  /// 安装是否进行中
  bool _installing = false;

  @override
  bool get installing => _installing;

  /// 本地安装的 Node 目录（完整路径）
  @override
  String get nodeHomePath =>
      '${MacOSOpenClawEnvironment.homePath}/$nodeInstallDir';

  /// 本地安装的 node 可执行文件路径
  @override
  String get localNodeBin => '$nodeHomePath/bin/node';

  /// 本地安装的 npm 可执行文件路径
  String get localNpmBin => '$nodeHomePath/bin/npm';

  // ─────────────────────────────────────────────
  // MARK: - 公开 API
  // ─────────────────────────────────────────────

  /// 确保 Node.js 可用。
  ///
  /// 1. 系统已有 node 且版本受支持 → 直接用（返回系统 node 路径）
  /// 2. 系统无 node / 版本不支持 → 从 npmmirror 下载二进制到 ~/.parrot/node
  ///
  /// [onOutput] 每行输出回调（供 UI 显示进度）。
  /// 返回可用的 node 路径。
  @override
  Future<String> ensureNode({void Function(String line)? onOutput}) async {
    // 先看本地 ~/.parrot/node 是否已装过
    if (await _isFileExecutable(localNodeBin)) {
      _log.info('Using bundled node: $localNodeBin');
      onOutput?.call('检测到本地 Node: $localNodeBin');
      return localNodeBin;
    }

    // 再看系统 node 是否可用且版本受支持
    final sysNode = await _findSystemNode();
    if (sysNode != null) {
      _log.info('Using system node: $sysNode');
      onOutput?.call('检测到系统 Node: $sysNode');
      return sysNode;
    }

    // 都没有 → 下载
    _log.info('No usable Node found, downloading from mirror...');
    onOutput?.call('未检测到 Node.js，正在从国内镜像下载...');
    return _downloadNode(onOutput: onOutput);
  }

  /// 安装 OpenClaw（npm 全局安装，走 npmmirror 镜像）
  ///
  /// [nodeBin] 使用的 node 路径（来自 [ensureNode]）。
  /// [onOutput] 每行输出回调。
  /// 返回 exit code（0 = 成功）。
  @override
  Future<int> installOpenClaw({
    required String nodeBin,
    void Function(String line)? onOutput,
  }) async {
    if (_installing) {
      throw StateError('OpenClaw install already in progress');
    }
    _installing = true;
    _log.info('Installing OpenClaw via npm (mirror)');

    try {
      // npm 与 node 同目录
      final nodeDir = Directory(nodeBin).parent.path;
      final npmBin = '$nodeDir/npm';
      final resolvedNpm = await _resolvePath(npmBin);

      _log.info('Using npm: $resolvedNpm');
      onOutput?.call('正在通过 npm 安装 OpenClaw（国内镜像）...');

      final process = await Process.start(
        resolvedNpm,
        ['install', '-g', openClawPackage, '--registry=$npmRegistryMirror'],
        environment: {
          ...MacOSOpenClawEnvironment.processEnvironment,
          // 确保 npm 使用 node 同目录
          'PATH': MacOSOpenClawEnvironment.pathWithPrepended(nodeDir),
        },
        runInShell: true,
      );

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            _log.fine('[npm] $line');
            onOutput?.call(line);
          });

      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            _log.fine('[npm:err] $line');
            onOutput?.call(line);
          });

      final exitCode = await process.exitCode;
      _log.info('npm install finished, exitCode=$exitCode');
      return exitCode;
    } catch (e) {
      _log.severe('OpenClaw npm install failed: $e');
      rethrow;
    } finally {
      _installing = false;
    }
  }

  /// 验证 OpenClaw 是否安装成功
  ///
  /// 返回版本字符串；未安装返回 null。
  @override
  Future<String?> verifyInstall() async {
    try {
      final result = await Process.run(
        'openclaw',
        ['--version'],
        environment: MacOSOpenClawEnvironment.openClawProcessEnvironment,
        runInShell: true,
      );
      if (result.exitCode != 0) return null;
      final version = (result.stdout as String).trim();
      _log.info('OpenClaw version: $version');
      return version.isEmpty ? null : version;
    } catch (e) {
      _log.warning('verifyInstall failed: $e');
      return null;
    }
  }

  /// 判断是否已安装（便捷方法，供 Repository 使用）
  @override
  Future<bool> isInstalled() async => (await verifyInstall()) != null;

  // ─────────────────────────────────────────────
  // MARK: - 内部实现
  // ─────────────────────────────────────────────

  /// 查找系统可用的 node（版本需受支持）
  Future<String?> _findSystemNode() async {
    try {
      final result = await Process.run(
        'which',
        ['node'],
        environment: MacOSOpenClawEnvironment.openClawProcessEnvironment,
        runInShell: true,
      );
      if (result.exitCode != 0) return null;
      final path = (result.stdout as String).trim();
      if (path.isEmpty) return null;

      // 检查版本是否受支持
      final versionResult = await Process.run(
        'node',
        ['--version'],
        environment: MacOSOpenClawEnvironment.openClawProcessEnvironment,
        runInShell: true,
      );
      if (versionResult.exitCode != 0) return null;
      final version = (versionResult.stdout as String).trim();
      if (!_isSupportedNodeVersion(version)) {
        _log.warning('System node version unsupported: $version');
        return null;
      }
      return path;
    } catch (e) {
      _log.warning('findSystemNode failed: $e');
      return null;
    }
  }

  /// 判断 Node 版本是否受 OpenClaw 支持
  ///
  /// 支持：22.22.3+ / 24.15.0+ / 25.9.0+（Node 23 不支持）
  bool _isSupportedNodeVersion(String version) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(version.trim());
    if (match == null) return false;
    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    final patch = int.parse(match.group(3)!);

    bool versionAtLeast(int m, int mi, int p) {
      if (major != m) return major > m;
      if (minor != mi) return minor > mi;
      return patch >= p;
    }

    return versionAtLeast(22, 22, 3) ||
        versionAtLeast(24, 15, 0) ||
        versionAtLeast(25, 9, 0);
  }

  /// 从 npmmirror 下载 Node 二进制并解压到 ~/.parrot/node
  Future<String> _downloadNode({void Function(String line)? onOutput}) async {
    final arch = await _hostArch();
    final os =
        Platform.operatingSystem.toLowerCase().contains('mac')
            ? 'darwin'
            : 'linux';
    final nodeFileName = 'node-v24.18.1-$os-$arch.tar.gz';
    final downloadUrl = '$nodeMirrorBase/v24.18.1/$nodeFileName';

    _log.info('Downloading Node: $downloadUrl');
    onOutput?.call('正在下载 Node.js ($nodeFileName)...');

    // 建目录
    final installDir = Directory(nodeHomePath);
    if (!installDir.existsSync()) {
      await installDir.create(recursive: true);
    }

    // 下载到临时文件
    final tempDir = await Directory.systemTemp.createTemp('parrot_node');
    final tempFile = File('${tempDir.path}/$nodeFileName');

    final curlResult = await Process.run(
      'curl',
      ['-fsSL', '--retry', '3', downloadUrl, '-o', tempFile.path],
      environment: MacOSOpenClawEnvironment.openClawProcessEnvironment,
      runInShell: true,
    );
    if (curlResult.exitCode != 0) {
      _log.severe('Node download failed: ${curlResult.stderr}');
      throw Exception('Node.js 下载失败，请检查网络');
    }
    onOutput?.call('下载完成，正在解压...');

    // 解压（tar.gz）
    final tarResult = await Process.run(
      'tar',
      ['-xzf', tempFile.path, '-C', installDir.path, '--strip-components=1'],
      environment: MacOSOpenClawEnvironment.openClawProcessEnvironment,
      runInShell: true,
    );
    if (tarResult.exitCode != 0) {
      _log.severe('Node extract failed: ${tarResult.stderr}');
      throw Exception('Node.js 解压失败');
    }

    // 清理
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}

    // 验证
    final nodeBin = '$nodeHomePath/bin/node';
    if (!await _isFileExecutable(nodeBin)) {
      throw Exception('Node.js 安装失败：未找到可执行文件');
    }

    onOutput?.call('Node.js 安装完成: $nodeBin');
    _log.info('Node installed at $nodeBin');
    return nodeBin;
  }

  Future<String> _hostArch() async {
    try {
      final result = await Process.run(
        'uname',
        ['-m'],
        environment: MacOSOpenClawEnvironment.openClawProcessEnvironment,
        runInShell: true,
      );
      final machine = (result.stdout as String).trim().toLowerCase();
      if (machine == 'arm64' || machine == 'aarch64') return 'arm64';
    } catch (e) {
      _log.warning('host arch detection failed, fallback to x64: $e');
    }
    return 'x64';
  }

  Future<bool> _isFileExecutable(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return false;
      final result = await Process.run(
        path,
        ['--version'],
        environment: MacOSOpenClawEnvironment.openClawProcessEnvironment,
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 解析相对路径（如 ../npm）
  Future<String> _resolvePath(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) return file.path;
      // 尝试可执行文件（不带扩展名，Unix 风格）
      final execFile = File(path);
      if (execFile.existsSync()) return execFile.path;
    } catch (_) {}
    return path;
  }
}
