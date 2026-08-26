import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:parrot_app/data/service/impl/windows_openclaw_environment.dart';
import 'package:parrot_app/data/service/openclaw_installer_service.dart';

/// OpenClaw 安装服务（无状态，纯本机操作）
///
/// 职责：
/// - 确保 Node.js 可用（无则从 npmmirror 镜像下载二进制，免安装）
/// - 通过 npm（npmmirror 镜像源）安装 OpenClaw
/// - 流式输出安装进度（供 UI 进度条使用）
/// - 验证安装结果
///
/// Windows 不调用 Unix 安装脚本，避免依赖 bash、Homebrew 或系统级安装器。
/// 本实现使用 Windows Node ZIP 和 npm.cmd，并通过国内镜像安装 OpenClaw：
/// - Node：npmmirror.com/mirrors/node/ 下载 Windows x64/arm64 ZIP，解压即用
/// - OpenClaw：npm install -g openclaw --registry=https://registry.npmmirror.com
///   npm 11.16+ / 12+ 还需显式授权 OpenClaw 的生命周期脚本。
///
/// 架构：无状态 Service，由 Repository 消费，不包含业务逻辑。
class WindowsOpenClawInstallerService implements OpenClawInstallerService {
  WindowsOpenClawInstallerService({Logger? logger})
    : _log = logger ?? Logger('WindowsOpenClawInstallerService');

  final Logger _log;

  /// Node 二进制镜像根（npmmirror 淘宝源）
  static const String nodeMirrorBase = 'https://npmmirror.com/mirrors/node';

  static const String npmRegistryMirror = 'https://registry.npmmirror.com';
  static const String nodeVersion = 'v24.18.1';
  static const String openClawPackage = 'openclaw';

  /// 安装是否进行中
  bool _installing = false;

  @override
  bool get installing => _installing;

  /// 本地安装的 Node 目录（完整路径）
  @override
  String get nodeHomePath => WindowsOpenClawEnvironment.nodeHomePath;

  /// 本地安装的 node 可执行文件路径
  @override
  String get localNodeBin => WindowsOpenClawEnvironment.nodeExecutable;

  /// 本地安装的 npm 可执行文件路径
  String get localNpmBin => WindowsOpenClawEnvironment.npmExecutable;

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
      final nodeDir = File(nodeBin).parent.path;
      final npmEnvironment = {
        ...WindowsOpenClawEnvironment.processEnvironment,
        'PATH': WindowsOpenClawEnvironment.pathWithPrepended(nodeDir),
      };
      final resolvedNpm = await _resolveNpm(nodeDir, npmEnvironment);
      if (resolvedNpm == null) {
        throw Exception('未找到与当前 Node 对应的 npm.cmd');
      }

      _log.info('Using npm: $resolvedNpm');
      onOutput?.call('正在通过 npm 安装 OpenClaw（国内镜像）...');

      final npmArgs = <String>[
        'install',
        '-g',
        openClawPackage,
        '--registry=$npmRegistryMirror',
      ];
      final npmVersion = await _readNpmVersion(resolvedNpm, npmEnvironment);
      if (_requiresScriptApproval(npmVersion)) {
        npmArgs.add(
          '--allow-scripts=openclaw,@google/genai,protobufjs,tree-sitter-bash',
        );
        onOutput?.call(
          '检测到 npm $npmVersion，已授权 OpenClaw 安装所需的生命周期脚本。',
        );
      } else if (npmVersion == null) {
        onOutput?.call('无法读取 npm 版本，将按当前 npm 默认策略安装。');
      }

      final process = await Process.start(
        'cmd.exe',
        ['/d', '/s', '/c', _cmdLine(resolvedNpm, npmArgs)],
        environment: npmEnvironment,
        runInShell: false,
      );

      process.stdout
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) {
            _log.fine('[npm] $line');
            onOutput?.call(line);
          });

      process.stderr
          .transform(const SystemEncoding().decoder)
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
      final environment = WindowsOpenClawEnvironment.openClawProcessEnvironment;
      final executable = await _resolveOpenClaw(environment);
      if (executable == null) return null;
      final result = await Process.run(
        'cmd.exe',
        ['/d', '/s', '/c', _cmdLine(executable, const ['--version'])],
        environment: environment,
        runInShell: false,
      );
      final stdout = (result.stdout as String).trim();
      final stderr = (result.stderr as String).trim();
      _log.info(
        'OpenClaw verify: path=$executable exitCode=${result.exitCode} '
        'stdout=$stdout stderr=$stderr',
      );
      if (result.exitCode != 0) return null;
      final version = _extractVersion(stdout);
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
        'where.exe',
        ['node.exe'],
        environment: WindowsOpenClawEnvironment.openClawProcessEnvironment,
        runInShell: true,
      );
      if (result.exitCode != 0) return null;
      final path = _firstPathLine(result.stdout);
      if (path.isEmpty) return null;

      // 检查版本是否受支持
      final versionResult = await Process.run(
        path,
        ['--version'],
        environment: WindowsOpenClawEnvironment.openClawProcessEnvironment,
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

    return switch (major) {
      22 => minor > 22 || (minor == 22 && patch >= 3),
      24 => minor > 15 || (minor == 15 && patch >= 0),
      25 => minor > 9 || (minor == 9 && patch >= 0),
      _ => false,
    };
  }

  /// 从 npmmirror 下载 Windows Node zip 并解压到用户目录。
  Future<String> _downloadNode({void Function(String line)? onOutput}) async {
    final arch = await _hostArch();
    final nodeFileName = 'node-$nodeVersion-win-$arch.zip';
    final downloadUrl = '$nodeMirrorBase/$nodeVersion/$nodeFileName';

    _log.info('Downloading Node: $downloadUrl');
    onOutput?.call('正在下载 Node.js ($nodeFileName)...');

    final installDir = Directory(nodeHomePath);
    if (!installDir.existsSync()) {
      await installDir.create(recursive: true);
    }

    final tempDir = await Directory.systemTemp.createTemp('parrot_node');
    final tempFile = File('${tempDir.path}\\$nodeFileName');
    try {
      final curlResult = await Process.run(
        'curl.exe',
        ['-fL', '--retry', '3', downloadUrl, '-o', tempFile.path],
        environment: WindowsOpenClawEnvironment.openClawProcessEnvironment,
        runInShell: true,
      );
      if (curlResult.exitCode != 0) {
        _log.severe('Node download failed: ${curlResult.stderr}');
        throw Exception('Node.js 下载失败，请检查网络');
      }
      onOutput?.call('下载完成，正在解压...');

      final extractRoot = Directory('${tempDir.path}\\extracted');
      await extractRoot.create(recursive: true);
      final powershellScript =
          r"Expand-Archive -LiteralPath $env:PARROT_NODE_ZIP -DestinationPath $env:PARROT_NODE_EXTRACT -Force";
      final extractResult = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          powershellScript,
        ],
        environment: {
          ...WindowsOpenClawEnvironment.openClawProcessEnvironment,
          'PARROT_NODE_ZIP': tempFile.path,
          'PARROT_NODE_EXTRACT': extractRoot.path,
        },
        runInShell: true,
      );
      if (extractResult.exitCode != 0) {
        _log.severe('Node extract failed: ${extractResult.stderr}');
        throw Exception('Node.js 解压失败');
      }

      var copied = false;
      await for (final entity in extractRoot.list(followLinks: false)) {
        if (entity is Directory) {
          final candidate = File('${entity.path}\\node.exe');
          if (candidate.existsSync()) {
            await _copyDirectoryContents(entity, installDir);
            copied = true;
            break;
          }
        }
      }

      if (!copied) {
        throw Exception('Node.js 安装失败：ZIP 中未找到 node.exe');
      }

      if (!await _isFileExecutable(WindowsOpenClawEnvironment.nodeExecutable)) {
        throw Exception('Node.js 安装失败：未找到 node.exe');
      }

      onOutput?.call(
        'Node.js 安装完成: ${WindowsOpenClawEnvironment.nodeExecutable}',
      );
      _log.info(
        'Node installed at ${WindowsOpenClawEnvironment.nodeExecutable}',
      );
      return WindowsOpenClawEnvironment.nodeExecutable;
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<String> _hostArch() async {
    final architecture =
        (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '').toLowerCase();
    final wowArchitecture =
        (Platform.environment['PROCESSOR_ARCHITEW6432'] ?? '').toLowerCase();
    final machine = wowArchitecture.isNotEmpty ? wowArchitecture : architecture;
    return machine.contains('arm64') || machine.contains('aarch64')
        ? 'arm64'
        : 'x64';
  }

  Future<void> _copyDirectoryContents(
    Directory source,
    Directory destination,
  ) async {
    await for (final entity in source.list(followLinks: false)) {
      final name = entity.path.split(RegExp(r'[\\\\/]')).last;
      final targetPath = '${destination.path}\\$name';
      if (entity is Directory) {
        final target = Directory(targetPath);
        await target.create(recursive: true);
        await _copyDirectoryContents(entity, target);
      } else if (entity is File) {
        await entity.copy(targetPath);
      }
    }
  }

  Future<bool> _isFileExecutable(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return false;
      final result = await Process.run(
        path,
        ['--version'],
        environment: WindowsOpenClawEnvironment.openClawProcessEnvironment,
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _resolveNpm(
    String nodeDir,
    Map<String, String> environment,
  ) async {
    final localNpm = File('$nodeDir\\npm.cmd');
    if (await localNpm.exists()) return localNpm.path;
    final result = await Process.run(
      'where.exe',
      ['npm.cmd'],
      environment: environment,
      runInShell: true,
    );
    if (result.exitCode != 0) return null;
    final path = _firstPathLine(result.stdout);
    return path.isEmpty ? null : path;
  }

  Future<String?> _resolveOpenClaw(Map<String, String> environment) async {
    final configured = File(WindowsOpenClawEnvironment.openClawExecutable);
    if (await configured.exists()) return configured.path;
    final result = await Process.run(
      'where.exe',
      ['openclaw.cmd'],
      environment: environment,
      runInShell: true,
    );
    if (result.exitCode != 0) return null;
    final path = _firstPathLine(result.stdout);
    return path.isEmpty ? null : path;
  }

  Future<String?> _readNpmVersion(
    String npmPath,
    Map<String, String> environment,
  ) async {
    final result = await Process.run(
      'cmd.exe',
      ['/d', '/s', '/c', _cmdLine(npmPath, const ['--version'])],
      environment: environment,
      runInShell: false,
    );
    return result.exitCode == 0 ? _firstPathLine(result.stdout) : null;
  }

  String _cmdLine(String executable, List<String> args) {
    final quotedExecutable = '"${executable.replaceAll('"', '\\"')}"';
    return [quotedExecutable, ...args.map(_quoteCmdArg)].join(' ');
  }

  String _quoteCmdArg(String arg) {
    if (arg.isEmpty || RegExp(r'[\s"]').hasMatch(arg)) {
      return '"${arg.replaceAll('"', '\\"')}"';
    }
    return arg;
  }

  String _extractVersion(String output) {
    final match = RegExp(r'v?\d+\.\d+\.\d+(?:[-+][^\s]+)?').firstMatch(output);
    return match?.group(0) ?? '';
  }

  bool _requiresScriptApproval(String? version) {
    final match = version == null
        ? null
        : RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version.trim());
    if (match == null) return false;
    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    return major >= 12 || (major == 11 && minor >= 16);
  }

  String _firstPathLine(dynamic value) {
    if (value is! String) return '';
    for (final line in value.split(RegExp(r'[\\r\\n]+'))) {
      final path = line.trim();
      if (path.isNotEmpty) return path;
    }
    return '';
  }
}
