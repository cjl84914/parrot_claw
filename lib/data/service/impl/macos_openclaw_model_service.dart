import 'dart:convert';
import 'dart:io';

import 'package:parrot_app/data/service/impl/macos_openclaw_environment.dart';
import 'package:parrot_app/data/model/openclaw_model.dart';
import 'package:parrot_app/data/service/openclaw_model_service.dart';

class MacOSOpenClawModelService implements OpenClawModelService {
  @override
  File get configFile =>
      File('${MacOSOpenClawEnvironment.homePath}/.openclaw/openclaw.json');

  @override
  Future<List<OpenClawModel>> loadModels() async {
    final config = await _readConfig();
    final rootModels = config['models'];
    if (rootModels is! Map) return const [];

    final providers = rootModels['providers'];
    if (providers is! Map) return const [];

    final models = <OpenClawModel>[];
    for (final providerEntry in providers.entries) {
      final provider = providerEntry.key.toString();
      final providerConfig = providerEntry.value;
      if (providerConfig is! Map) continue;

      final providerModels = providerConfig['models'];
      if (providerModels is List) {
        for (final modelConfig in providerModels) {
          if (modelConfig is Map) {
            final model = _parseModel(provider, modelConfig);
            if (model != null) models.add(model);
          }
        }
      } else if (providerModels is Map) {
        for (final modelEntry in providerModels.entries) {
          final modelConfig =
              modelEntry.value is Map
                  ? Map<String, dynamic>.from(modelEntry.value as Map)
                  : <String, dynamic>{};
          modelConfig.putIfAbsent('id', () => modelEntry.key.toString());
          final model = _parseModel(provider, modelConfig);
          if (model != null) models.add(model);
        }
      }
    }
    return models;
  }

  @override
  Future<void> addModel({
    required String provider,
    required String id,
    required String name,
    String? baseUrl,
    String? apiKey,
  }) async {
    final config = await _readConfig();
    final rootModels = _ensureMap(config, 'models');
    final providers = _ensureMap(rootModels, 'providers');
    final providerConfig = _ensureMap(providers, provider);
    final providerModels = providerConfig['models'];
    final modelList = <dynamic>[];

    if (providerModels is List) {
      modelList.addAll(providerModels);
    } else if (providerModels is Map) {
      for (final entry in providerModels.entries) {
        final model =
            entry.value is Map
                ? Map<String, dynamic>.from(entry.value as Map)
                : <String, dynamic>{};
        model.putIfAbsent('id', () => entry.key.toString());
        modelList.add(model);
      }
    }

    final newModel = <String, dynamic>{
      'id': id,
      'name': name.isEmpty ? id : name,
      'input': ['text'],
    };
    final existingIndex = modelList.indexWhere(
      (model) => model is Map && model['id']?.toString() == id,
    );
    if (existingIndex >= 0) {
      modelList[existingIndex] = {
        ...(modelList[existingIndex] as Map),
        ...newModel,
      };
    } else {
      modelList.add(newModel);
    }
    providerConfig['models'] = modelList;

    if (baseUrl?.trim().isNotEmpty == true) {
      providerConfig['baseUrl'] = baseUrl!.trim();
    }
    if (apiKey?.trim().isNotEmpty == true) {
      providerConfig['apiKey'] = apiKey!.trim();
    }

    await _writeConfig(config);
  }

  @override
  Future<void> deleteModel(OpenClawModel model) async {
    final config = await _readConfig();
    final rootModels = config['models'];
    final providers = rootModels is Map ? rootModels['providers'] : null;
    final providerConfig = providers is Map ? providers[model.provider] : null;
    if (providerConfig is! Map) return;

    final providerModels = providerConfig['models'];
    if (providerModels is List) {
      providerModels.removeWhere(
        (item) => item is Map && item['id']?.toString() == model.id,
      );
    } else if (providerModels is Map) {
      providerModels.remove(model.id);
    }
    await _writeConfig(config);
  }

  Future<void> _writeConfig(Map<String, dynamic> config) async {
    await configFile.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await configFile.writeAsString('${encoder.convert(config)}\n', flush: true);
  }

  Future<Map<String, dynamic>> _readConfig() async {
    if (!await configFile.exists()) return <String, dynamic>{};
    final content = await configFile.readAsString();
    if (content.trim().isEmpty) return <String, dynamic>{};

    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw const FormatException('OpenClaw 配置文件格式不正确');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Map<String, dynamic> _ensureMap(Map<String, dynamic> parent, String key) {
    final current = parent[key];
    if (current is Map<String, dynamic>) return current;
    if (current is Map) {
      final converted = Map<String, dynamic>.from(current);
      parent[key] = converted;
      return converted;
    }
    final created = <String, dynamic>{};
    parent[key] = created;
    return created;
  }

  OpenClawModel? _parseModel(String provider, Map modelConfig) {
    final id = modelConfig['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;

    final input =
        modelConfig['input'] is List
            ? (modelConfig['input'] as List)
                .map((item) => item.toString())
                .toList(growable: false)
            : const <String>[];
    return OpenClawModel(
      provider: provider,
      id: id,
      name: modelConfig['name']?.toString() ?? id,
      reasoning: modelConfig['reasoning'] == true,
      input: input,
    );
  }

  /// 读取 OpenClaw 已安装 Provider 插件声明的完整候选列表。
  ///
  /// 不使用 models.list，因为它只返回当前 Gateway 可见/已配置的模型。
  /// Provider 插件元数据位于 OpenClaw 安装目录的 extensions/*/openclaw.plugin.json。
  @override
  Future<List<OpenClawProvider>> fetchAvailableProviders() async {
    final providers = <String, Set<String>>{};
    _mergeProviderUrls(providers, await _readConfiguredProviderUrls());
    _mergeProviderUrls(providers, await _readInstalledPluginProviderUrls());

    final result =
        providers.entries
            .map(
              (entry) => OpenClawProvider(
                id: entry.key,
                baseUrls: entry.value.toList(growable: false),
              ),
            )
            .toList();
    result.sort((a, b) => a.id.compareTo(b.id));
    return result;
  }

  void _mergeProviderUrls(
    Map<String, Set<String>> target,
    Map<String, Set<String>> source,
  ) {
    for (final entry in source.entries) {
      target.putIfAbsent(entry.key, () => <String>{}).addAll(entry.value);
    }
  }

  Future<Map<String, Set<String>>> _readConfiguredProviderUrls() async {
    final result = <String, Set<String>>{};
    try {
      final config = await _readConfig();
      final models = config['models'];
      final configured = models is Map ? models['providers'] : null;
      if (configured is! Map) return result;
      for (final entry in configured.entries) {
        final provider = entry.key.toString().trim();
        if (provider.isEmpty) continue;
        final urls = _extractUrls(entry.value is Map ? entry.value : null);
        result[provider] = urls;
      }
    } catch (_) {}
    return result;
  }

  Future<Map<String, Set<String>>> _readInstalledPluginProviderUrls() async {
    final result = <String, Set<String>>{};
    for (final directory in await _openClawExtensionDirectories()) {
      final metadataFile = File('${directory.path}/openclaw.plugin.json');
      if (!await metadataFile.exists()) continue;
      try {
        final decoded = jsonDecode(await metadataFile.readAsString());
        if (decoded is! Map) continue;
        _collectProviderMetadata(decoded, result);
      } catch (_) {}
    }
    return result;
  }

  Set<String> _extractUrls(Map? value) {
    final urls = <String>{};
    void add(dynamic raw) {
      if (raw is String && raw.trim().isNotEmpty) urls.add(raw.trim());
    }

    add(value?['baseUrl']);
    final baseUrls = value?['baseUrls'];
    if (baseUrls is List) {
      for (final url in baseUrls) {
        add(url);
      }
    }
    return urls;
  }

  Future<List<Directory>> _openClawExtensionDirectories() async {
    final roots = <Directory>[
      Directory('${MacOSOpenClawEnvironment.homePath}/.openclaw/extensions'),
      Directory(
        '${MacOSOpenClawEnvironment.homePath}/.openclaw/node_modules/openclaw/extensions',
      ),
      Directory('/usr/local/lib/node_modules/openclaw/extensions'),
      Directory('/opt/homebrew/lib/node_modules/openclaw/extensions'),
      Directory('/Users/alexcai/workspace/openclaw/extensions'),
    ];
    final directories = <Directory>[];
    final seen = <String>{};
    for (final root in roots) {
      if (!await root.exists()) continue;
      await for (final entity in root.list(followLinks: false)) {
        if (entity is Directory && seen.add(entity.path)) {
          directories.add(entity);
        }
      }
    }
    return directories;
  }

  void _collectProviderMetadata(Map metadata, Map<String, Set<String>> output) {
    void add(String? provider, Set<String> urls) {
      final id = provider?.trim() ?? '';
      if (id.isEmpty) return;
      output.putIfAbsent(id, () => <String>{}).addAll(urls);
    }

    final modelCatalog = metadata['modelCatalog'];
    final catalogProviders =
        modelCatalog is Map ? modelCatalog['providers'] : null;
    if (catalogProviders is Map) {
      for (final entry in catalogProviders.entries) {
        add(
          entry.key.toString(),
          _extractUrls(entry.value is Map ? entry.value : null),
        );
      }
    }

    final providers = metadata['providers'];
    if (providers is List) {
      for (final provider in providers) {
        add(provider is String ? provider : null, const <String>{});
      }
    }

    final setup = metadata['setup'];
    final setupProviders = setup is Map ? setup['providers'] : null;
    if (setupProviders is List) {
      for (final entry in setupProviders) {
        if (entry is Map) add(entry['id']?.toString(), const <String>{});
      }
    }

    final authChoices = metadata['providerAuthChoices'];
    if (authChoices is List) {
      for (final entry in authChoices) {
        if (entry is Map) add(entry['provider']?.toString(), const <String>{});
      }
    }
  }
}
