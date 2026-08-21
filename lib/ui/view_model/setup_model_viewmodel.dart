import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/repository/server_repository.dart';
import 'package:parrot_app/data/service/gateway_channel.dart';
import 'package:parrot_app/data/service/gateway_connection.dart';
import 'package:uuid/uuid.dart';

class SetupModelOption {
  final String id;
  final String name;

  const SetupModelOption({required this.id, required this.name});
}

class SetupProviderOption {
  final String id;
  final String name;
  final String? defaultBaseUrl;
  final List<SetupModelOption> models;

  const SetupProviderOption({
    required this.id,
    required this.name,
    this.defaultBaseUrl,
    required this.models,
  });
}

class SetupModelConfig {
  final String provider;
  final String baseUrl;
  final String model;
  final String apiKey;

  const SetupModelConfig({
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });
}

enum SetupModelPhase { idle, saving, validating, success, error }

class SetupModelViewModel extends ChangeNotifier {
  SetupModelViewModel({
    required ServerRepository serverRepository,
    Logger? logger,
  }) : _serverRepository = serverRepository,
       _log = logger ?? Logger('SetupModelViewModel');

  static const List<SetupProviderOption> providerOptions = [
    SetupProviderOption(
      id: 'opencode-zen',
      name: 'OpenCode Zen',
      models: [
        SetupModelOption(id: 'gpt-5.5', name: 'GPT-5.5'),
        SetupModelOption(id: 'claude-sonnet-4-6', name: 'Claude Sonnet 4.6'),
        SetupModelOption(id: 'deepseek-v4-pro', name: 'DeepSeek V4 Pro'),
        SetupModelOption(id: 'qwen3.6-plus', name: 'Qwen3.6 Plus'),
        SetupModelOption(id: 'kimi-k2.6', name: 'Kimi K2.6'),
      ],
    ),
    SetupProviderOption(
      id: 'openai',
      name: 'OpenAI',
      defaultBaseUrl: 'https://api.openai.com/v1',
      models: [SetupModelOption(id: 'gpt-5.5', name: 'GPT-5.5')],
    ),
    SetupProviderOption(
      id: 'deepseek',
      name: 'DeepSeek',
      defaultBaseUrl: 'https://api.deepseek.com',
      models: [SetupModelOption(id: 'deepseek-chat', name: 'DeepSeek Chat')],
    ),
    SetupProviderOption(
      id: 'qwen',
      name: 'Qwen',
      defaultBaseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      models: [SetupModelOption(id: 'qwen-plus', name: 'Qwen Plus')],
    ),
    SetupProviderOption(
      id: 'moonshot',
      name: 'Kimi',
      defaultBaseUrl: 'https://api.moonshot.cn/v1',
      models: [SetupModelOption(id: 'kimi-k2.6', name: 'Kimi K2.6')],
    ),
  ];

  final ServerRepository _serverRepository;
  final Logger _log;

  SetupModelPhase _phase = SetupModelPhase.idle;
  SetupModelPhase get phase => _phase;
  bool get busy =>
      _phase == SetupModelPhase.saving || _phase == SetupModelPhase.validating;
  bool get configured => _phase == SetupModelPhase.success;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  SetupProviderOption _selectedProvider = providerOptions.first;
  SetupProviderOption get selectedProvider => _selectedProvider;

  SetupModelOption _selectedModel = providerOptions.first.models.first;
  SetupModelOption get selectedModel => _selectedModel;

  ServerConfig? get selectedServer => _serverRepository.selectedServer;

  void selectProvider(SetupProviderOption provider) {
    _selectedProvider = provider;
    _selectedModel = provider.models.first;
    _resetFeedback();
  }

  void selectModel(SetupModelOption model) {
    _selectedModel = model;
    _resetFeedback();
  }

  Future<bool> saveModelConfig(SetupModelConfig config) async {
    final server = selectedServer;
    final provider = config.provider.trim();
    final baseUrl = _normalizeBaseUrl(config.baseUrl);
    final model = config.model.trim();
    final apiKey = config.apiKey.trim();

    if (server == null) return _fail('未找到当前服务器，请先手动配置服务器');
    if (provider.isEmpty) return _fail('请选择供应商');
    if (baseUrl.isEmpty) return _fail('请输入 Base URL');
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return _fail('Base URL 格式不正确');
    }
    if (model.isEmpty) return _fail('请选择模型');
    if (apiKey.isEmpty) return _fail('请输入 API Key');

    _phase = SetupModelPhase.saving;
    _errorMessage = null;
    notifyListeners();

    try {
      await _configureGateway(server);
      final patch = {
        'agents': {
          'defaults': {
            'model': {
              'primary': '$provider/$model',
            },
          },
        },
        'models': {
          'providers': {
            provider: {
              'baseUrl': baseUrl,
              'apiKey': apiKey,
              'models': [
                {
                  'id': model,
                  'name': model,
                  'input': ['text'],
                },
              ],
            },
          },
        },
      };
      await _patchModelConfig(patch);
      _log.info('setup model saved: $provider/$model');

      _phase = SetupModelPhase.validating;
      notifyListeners();
      await _validateConversation();

      _phase = SetupModelPhase.success;
      notifyListeners();
      return true;
    } catch (error) {
      _log.warning('setup model configuration failed: $error');
      return _fail(_friendlyError(error));
    }
  }

  Future<void> _patchModelConfig(Map<String, dynamic> patch) async {
    var baseHash = await _readConfigBaseHash();
    try {
      await _sendConfigPatch(patch, baseHash);
    } catch (error) {
      if (!_isBaseHashError(error)) rethrow;
      _log.info('config.patch base hash expired; refreshing config.get');
      baseHash = await _readConfigBaseHash();
      await _sendConfigPatch(patch, baseHash);
    }
  }

  Future<String> _readConfigBaseHash() async {
    final response = await GatewayConnection.shared.requestRaw(
      Method.configGet,
      timeoutMs: 15000,
    );
    final config = response['config'];
    final configMap = config is Map ? config : null;
    final value =
        response['baseHash'] ??
        response['base_hash'] ??
        response['hash'] ??
        response['configHash'] ??
        response['config_hash'] ??
        configMap?['baseHash'] ??
        configMap?['base_hash'] ??
        configMap?['hash'];
    final baseHash = value?.toString().trim() ?? '';
    _log.fine('config.get returned keys: ${response.keys.toList()}');
    if (baseHash.isEmpty) {
      throw Exception('OpenClaw config.get 未返回 base hash');
    }
    return baseHash;
  }

  Future<void> _sendConfigPatch(Map<String, dynamic> patch, String baseHash) {
    return GatewayConnection.shared.requestRaw(
      Method.configPatch,
      params: {'raw': jsonEncode(patch), 'baseHash': baseHash},
      timeoutMs: 15000,
    );
  }

  bool _isBaseHashError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('base hash') ||
        message.contains('config base hash') ||
        message.contains('re-run config.get and retry');
  }

  Future<void> _validateConversation() async {
    final sessionKey = await GatewayConnection.shared.mainSessionKey();
    final idempotencyKey = 'setup_${const Uuid().v4()}';
    final completer = Completer<void>();
    late final StreamSubscription<GatewayPush> subscription;

    subscription = GatewayConnection.shared.subscribe().listen((push) {
      if (push is! GatewayPushEvent || push.event != 'chat') return;
      final payload = push.payload;
      if (payload is! Map || payload['runId'] != idempotencyKey) return;

      switch (payload['state']) {
        case 'final':
          if (_hasAssistantText(payload['message'])) {
            if (!completer.isCompleted) completer.complete();
          } else if (!completer.isCompleted) {
            completer.completeError(Exception('模型没有返回有效内容'));
          }
          break;
        case 'error':
          if (!completer.isCompleted) {
            completer.completeError(
              Exception(payload['error']?.toString() ?? '模型对话验证失败'),
            );
          }
          break;
        case 'aborted':
          if (!completer.isCompleted) {
            completer.completeError(Exception('模型对话验证已中止'));
          }
          break;
      }
    });

    try {
      await GatewayConnection.shared.chatSend(
        sessionKey: sessionKey,
        message: '请仅回复：配置测试成功',
        idempotencyKey: idempotencyKey,
        timeoutMs: 30000,
      );
      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('模型对话验证超时'),
      );
    } finally {
      await subscription.cancel();
    }
  }

  bool _hasAssistantText(dynamic message) {
    if (message is! Map || message['role'] != 'assistant') return false;
    final content = message['content'];
    if (content is String) return content.trim().isNotEmpty;
    if (content is! List) return false;
    return content.any(
      (item) =>
          item is Map &&
          item['type'] == 'text' &&
          item['text']?.toString().trim().isNotEmpty == true,
    );
  }

  String _normalizeBaseUrl(String raw) =>
      raw.trim().replaceFirst(RegExp(r'/+$'), '');

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('401') || message.contains('unauthorized')) {
      return 'API Key 无效，请检查后重试';
    }
    if (message.contains('403') || message.contains('forbidden')) {
      return 'API Key 没有调用该模型的权限';
    }
    if (message.contains('404') || message.contains('not found')) {
      return 'Base URL 或模型名称不正确';
    }
    if (message.contains('429') || message.contains('rate limit')) {
      return '请求受限或账户额度不足，请稍后重试';
    }
    if (error is TimeoutException || message.contains('timeout')) {
      return '模型响应超时，请检查 Base URL 和网络';
    }
    return '模型配置验证失败，请检查填写内容后重试';
  }

  bool _fail(String message) {
    _phase = SetupModelPhase.error;
    _errorMessage = message;
    notifyListeners();
    return false;
  }

  void _resetFeedback() {
    _phase = SetupModelPhase.idle;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _configureGateway(ServerConfig server) {
    return GatewayConnection.shared.configure(
      url: server.wsUrl,
      token: server.isTokenAuth ? server.token : null,
      password: server.isPasswordAuth ? server.password : null,
    );
  }
}
