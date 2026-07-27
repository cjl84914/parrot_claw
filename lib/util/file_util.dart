
import 'dart:io';
import 'dart:typed_data' hide Uint8List;
import 'package:flutter/services.dart' hide ByteData;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

Future<List<String>> getAllAssetFiles() async {
  final AssetManifest assetManifest = await AssetManifest.loadFromAssetBundle(
    rootBundle,
  );
  final List<String> assets = assetManifest.listAssets();
  return assets;
}

String stripLeadingDirectory(String src, {int n = 1}) {
  return p.joinAll(p.split(src).sublist(n));
}

Future<void> copyAllAssetFiles() async {
  final allFiles = await getAllAssetFiles();
  for (final src in allFiles) {
    final dst = stripLeadingDirectory(src);
    // 如果目标文件名为空（例如根目录下的资源），则跳过
    if (dst.isEmpty) {
      continue;
    }
    await copyAssetFile(src, dst);
  }
}

// Copy the asset file from src to dst.
// If dst already exists, then just skip the copy
Future<String> copyAssetFile(String src, [String? dst]) async {
  final Directory directory = await getApplicationSupportDirectory();
  if (dst == null) {
    dst = p.basename(src);
  }
  final target = p.join(directory.path, dst);

  // 安全检查：如果目标路径是一个已存在的目录，则跳过
  if (FileSystemEntity.isDirectorySync(target)) {
    return target;
  }

  bool exists = await File(target).exists();

  final data = await rootBundle.load(src);
  if (!exists || File(target).lengthSync() != data.lengthInBytes) {
    final List<int> bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    await (await File(target).create(recursive: true)).writeAsBytes(bytes);
  }

  return target;
}

Float32List convertBytesToFloat32(Uint8List bytes, [endian = Endian.little]) {
  final values = Float32List(bytes.length ~/ 2);

  final data = ByteData.view(bytes.buffer);

  for (var i = 0; i < bytes.length; i += 2) {
    int short = data.getInt16(i, endian);
    values[i ~/ 2] = short / 32768.0;
  }

  return values;
}