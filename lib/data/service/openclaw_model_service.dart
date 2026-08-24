import 'dart:io';

import 'package:parrot_app/data/model/openclaw_model.dart';

class OpenClawProvider {
  final String id;
  final List<String> baseUrls;

  const OpenClawProvider({required this.id, this.baseUrls = const []});

  String? get defaultBaseUrl => baseUrls.isEmpty ? null : baseUrls.first;
}

/// OpenClaw 模型配置服务接口。
///
/// macOS/Windows 的配置文件路径和插件目录由 impl 目录中的具体实现负责；
/// 两端共用相同的 OpenClaw JSON 配置结构。
abstract interface class OpenClawModelService {
  File get configFile;

  Future<List<OpenClawModel>> loadModels();

  Future<void> addModel({
    required String provider,
    required String id,
    required String name,
    String? baseUrl,
    String? apiKey,
  });

  Future<void> deleteModel(OpenClawModel model);

  Future<List<OpenClawProvider>> fetchAvailableProviders();
}
