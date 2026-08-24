import 'package:flutter/material.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/model/openclaw_model.dart';
import 'package:parrot_app/data/service/openclaw_model_service.dart';

class ModelListScreen extends StatefulWidget {
  final OpenClawModelService service;

  const ModelListScreen({super.key, required this.service});

  @override
  State<ModelListScreen> createState() => _ModelListScreenState();
}

class _ModelListScreenState extends State<ModelListScreen> {
  late Future<List<OpenClawModel>> _modelsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _modelsFuture = widget.service.loadModels();
  }

  Future<void> _showAddModelDialog({OpenClawModel? model}) async {
    final request = await showDialog<_AddModelRequest>(
      context: context,
      builder:
          (context) => _AddModelDialog(model: model, service: widget.service),
    );
    if (request == null || !mounted) return;

    try {
      await widget.service.addModel(
        provider: request.provider,
        id: request.modelName,
        name: request.modelName,
        baseUrl: request.baseUrl,
        apiKey: request.apiKey,
      );
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('模型已保存')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }

  Future<void> _deleteModel(OpenClawModel model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('删除模型？'),
            content: Text('确定删除“${model.displayName}”吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;

    try {
      await widget.service.deleteModel(model);
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('模型已删除')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('模型'),
        actions: [
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: FutureBuilder<List<OpenClawModel>>(
        future: _modelsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _buildMessage(
              icon: Icons.error_outline,
              title: '读取模型失败',
              subtitle: snapshot.error.toString(),
            );
          }

          final models = snapshot.data ?? const <OpenClawModel>[];
          return RefreshIndicator(
            onRefresh: () async => setState(_reload),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                const Text('自定义模型', style: AppTextStyles.titleMedium),
                const SizedBox(height: 8),
                _buildConfigCard(),
                const SizedBox(height: 24),
                const Text('已保存模型', style: AppTextStyles.titleMedium),
                const SizedBox(height: 8),
                if (models.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('暂未读取到模型配置'),
                    ),
                  )
                else
                  ...models.map(_buildModelCard),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildConfigCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        title: const Text('本地配置文件'),
        subtitle: Text(
          '管理写入 ${widget.service.configFile.path} 的本地模型配置。',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: FilledButton.icon(
          onPressed: _showAddModelDialog,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('添加模型'),
        ),
      ),
    );
  }

  Widget _buildModelCard(OpenClawModel model) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        // leading: CircleAvatar(
        //   backgroundColor: AppColors.primary.withValues(alpha: 0.15),
        //   child: Icon(
        //     model.input.contains('image')
        //         ? Icons.visibility_outlined
        //         : Icons.psychology_outlined,
        //     color: AppColors.primary,
        //     size: 20,
        //   ),
        // ),
        title: Text(model.displayName),
        subtitle: Text('${model.providerLabel}\n${model.capabilityLabel}'),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '编辑模型',
              onPressed: () => _showAddModelDialog(model: model),
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
            IconButton(
              tooltip: '删除模型',
              onPressed: () => _deleteModel(model),
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(title, style: AppTextStyles.titleLarge),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddModelRequest {
  final String provider;
  final String modelName;
  final String baseUrl;
  final String apiKey;

  const _AddModelRequest({
    required this.provider,
    required this.modelName,
    required this.baseUrl,
    required this.apiKey,
  });
}

class _AddModelDialog extends StatefulWidget {
  final OpenClawModel? model;
  final OpenClawModelService service;

  const _AddModelDialog({this.model, required this.service});

  @override
  State<_AddModelDialog> createState() => _AddModelDialogState();
}

class _AddModelDialogState extends State<_AddModelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _modelNameController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();

  List<OpenClawProvider> _availableProviders = [];
  String? _selectedProvider;
  List<String> _baseUrlOptions = [];
  bool _loadingProviders = true;

  @override
  void initState() {
    super.initState();
    final model = widget.model;
    if (model != null) {
      _selectedProvider = model.provider;
      _modelNameController.text = model.id;
    }
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    try {
      final providers = await widget.service.fetchAvailableProviders();
      if (mounted) {
        setState(() {
          _availableProviders = providers;
          _loadingProviders = false;
          if (_selectedProvider != null &&
              !providers.any((provider) => provider.id == _selectedProvider)) {
            _availableProviders.insert(
              0,
              OpenClawProvider(id: _selectedProvider!),
            );
          }
          _applyProviderBaseUrl(_selectedProvider, fillEmptyOnly: true);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingProviders = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _modelNameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProvider == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择提供商')));
      return;
    }
    Navigator.of(context).pop(
      _AddModelRequest(
        provider: _selectedProvider!,
        modelName: _modelNameController.text.trim(),
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.model != null;
    return AlertDialog(
      title: Text(isEditing ? '编辑模型' : '添加模型'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loadingProviders)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: CircularProgressIndicator(),
                )
              else
                _buildProviderDropdown(),
              _buildBaseUrlField(),
              _field(_modelNameController, '模型名称', '例如 gpt-4o'),
              _field(
                _apiKeyController,
                'API Key',
                'sk-...',
                obscureText: false,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }

  OpenClawProvider? _providerById(String? id) {
    if (id == null) return null;
    for (final provider in _availableProviders) {
      if (provider.id == id) return provider;
    }
    return null;
  }

  void _applyProviderBaseUrl(String? providerId, {bool fillEmptyOnly = false}) {
    final provider = _providerById(providerId);
    final urls = provider?.baseUrls ?? const <String>[];
    _baseUrlOptions = urls;
    if (urls.isEmpty) {
      if (!fillEmptyOnly) _baseUrlController.clear();
      return;
    }
    if (!fillEmptyOnly || _baseUrlController.text.trim().isEmpty) {
      _baseUrlController.text = urls.first;
    }
  }

  Widget _buildProviderDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: _selectedProvider,
        decoration: const InputDecoration(
          labelText: 'Provider',
          hintText: '选择模型提供商',
        ),
        items: [
          ..._availableProviders.map(
            (provider) => DropdownMenuItem(
              value: provider.id,
              child: Text(_getProviderDisplayName(provider.id)),
            ),
          ),
          const DropdownMenuItem(value: '__custom__', child: Text('自定义...')),
        ],
        onChanged: (value) async {
          if (value == '__custom__') {
            final customProvider = await _showCustomProviderDialog();
            if (customProvider != null && mounted) {
              setState(() {
                if (!_availableProviders.any(
                  (provider) => provider.id == customProvider,
                )) {
                  _availableProviders.insert(
                    0,
                    OpenClawProvider(id: customProvider),
                  );
                }
                _selectedProvider = customProvider;
                _baseUrlOptions = const [];
                _baseUrlController.clear();
              });
            }
          } else {
            setState(() {
              _selectedProvider = value;
              _applyProviderBaseUrl(value);
            });
          }
        },
        validator: (value) => value == null ? '请选择 Provider' : null,
      ),
    );
  }

  Widget _buildBaseUrlField() {
    if (_baseUrlOptions.length > 1) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue:
              _baseUrlOptions.contains(_baseUrlController.text)
                  ? _baseUrlController.text
                  : null,
          decoration: const InputDecoration(
            labelText: 'Base URL（可选）',
            hintText: '选择接口地址',
          ),
          items:
              _baseUrlOptions
                  .map((url) => DropdownMenuItem(value: url, child: Text(url)))
                  .toList(),
          onChanged: (url) {
            if (url == null) return;
            setState(() => _baseUrlController.text = url);
          },
        ),
      );
    }
    return _field(_baseUrlController, 'Base URL（可选）', 'https://...');
  }

  String _getProviderDisplayName(String provider) {
    // 为常见提供商添加友好的显示名称
    return switch (provider.toLowerCase()) {
      'openai' => 'OpenAI',
      'anthropic' => 'Anthropic',
      'deepseek' => '深度求索 (DeepSeek)',
      'qwen' => '通义千问 (Qwen)',
      'moonshot' => '月之暗面 (Moonshot)',
      'google' => 'Google',
      'mistral' => 'Mistral AI',
      'openrouter' => 'OpenRouter',
      _ => provider,
    };
  }

  Future<String?> _showCustomProviderDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('输入自定义 Provider'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Provider ID',
                hintText: '例如 custom-provider',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final value = controller.text.trim();
                  Navigator.of(context).pop(value.isEmpty ? null : value);
                },
                child: const Text('确定'),
              ),
            ],
          ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    bool obscureText = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator: (value) {
          if (label.contains('可选')) return null;
          return value?.trim().isEmpty == true ? '请输入$label' : null;
        },
      ),
    );
  }
}
