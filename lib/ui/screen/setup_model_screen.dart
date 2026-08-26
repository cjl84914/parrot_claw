import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/view_model/setup_model_viewmodel.dart';

class _SetupModelColors {
  static const background = Color(0xFF101114);
  static const surface = Color(0xFF1B1D22);
  static const border = Color(0xFF363B44);
  static const input = Color(0xFF242731);
  static const textSecondary = Color(0xFFC9D7F2);
}

class SetupModelScreen extends StatefulWidget {
  final SetupModelViewModel viewModel;

  const SetupModelScreen({super.key, required this.viewModel});

  @override
  State<SetupModelScreen> createState() => _SetupModelScreenState();
}

class _SetupModelScreenState extends State<SetupModelScreen> {
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  final _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _syncProviderFields(widget.viewModel.selectedProvider);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _SetupModelColors.background,
      appBar: AppBar(
        actions: [
          TextButton.icon(
            onPressed: () => context.push(Routes.serverEdit),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('手动配置 Gateway'),
            style: TextButton.styleFrom(
              foregroundColor: _SetupModelColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.viewModel,
          builder: (context, _) {
            final vm = widget.viewModel;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHero(),
                  const SizedBox(height: 22),
                  Expanded(child: _buildMainCard(vm)),
                  const SizedBox(height: 16),
                  _buildActions(vm),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text('配置模型能力', style: AppTextStyles.headlineLarge),
        const SizedBox(height: 8),
        Text(
          '填写模型信息后，ParrotClaw 会直接添加模型并验证一次对话。',
          style: AppTextStyles.bodyMedium.copyWith(
            color: _SetupModelColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildMainCard(SetupModelViewModel vm) {
    final busy = vm.busy;
    final title = switch (vm.phase) {
      SetupModelPhase.saving => '正在保存模型配置',
      SetupModelPhase.validating => '正在验证模型对话',
      SetupModelPhase.success => '模型已配置成功',
      SetupModelPhase.error => '配置未完成',
      SetupModelPhase.idle => '填写模型配置',
    };
    final subtitle = switch (vm.phase) {
      SetupModelPhase.saving => '正在将供应商、模型和 API Key 写入 OpenClaw。',
      SetupModelPhase.validating => '正在发送一次最小测试消息，请稍候。',
      SetupModelPhase.success => '模型已添加，可以开始聊天。',
      SetupModelPhase.error => vm.errorMessage ?? '请检查填写内容后重试。',
      SetupModelPhase.idle => '选择供应商并填写可编辑的 Base URL、模型和 API Key。',
    };
    final icon = switch (vm.phase) {
      SetupModelPhase.saving || SetupModelPhase.validating => Icons.sync,
      SetupModelPhase.success => Icons.check_circle,
      SetupModelPhase.error => Icons.error_outline,
      SetupModelPhase.idle => Icons.tune,
    };
    final color = switch (vm.phase) {
      SetupModelPhase.success => AppColors.online,
      SetupModelPhase.error => AppColors.error,
      _ => AppColors.primary,
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _SetupModelColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _SetupModelColors.border),
      ),
      child: ListView(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStateIcon(icon, color, busy),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: _SetupModelColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!busy && vm.phase != SetupModelPhase.success) ...[
            const SizedBox(height: 22),
            _buildProviderSelector(vm),
            const SizedBox(height: 14),
            _buildTextField(
              _baseUrlController,
              'Base URL',
              '例如 https://api.example.com/v1',
              Icons.link,
            ),
            const SizedBox(height: 14),
            _buildTextField(
              _modelController,
              '模型名称',
              '例如 deepseek-chat',
              Icons.psychology_outlined,
            ),
            const SizedBox(height: 14),
            _buildTextField(
              _apiKeyController,
              'API Key',
              '请输入 API Key',
              Icons.vpn_key_outlined,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProviderSelector(SetupModelViewModel vm) {
    return DropdownButtonFormField<SetupProviderOption>(
      initialValue: vm.selectedProvider,
      dropdownColor: _SetupModelColors.surface,
      iconEnabledColor: _SetupModelColors.textSecondary,
      isExpanded: true,
      decoration: _inputDecoration('供应商', Icons.cloud_outlined),
      items:
          SetupModelViewModel.providerOptions
              .map(
                (provider) => DropdownMenuItem(
                  value: provider,
                  child: Text(provider.name),
                ),
              )
              .toList(),
      onChanged: (provider) {
        if (provider == null) return;
        vm.selectProvider(provider);
        _syncProviderFields(provider);
      },
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hint,
    IconData icon,
  ) {
    return TextField(
      controller: controller,
      obscureText: false,
      enableSuggestions: false,
      autocorrect: false,
      style: AppTextStyles.bodyMedium,
      decoration: _inputDecoration(label, icon).copyWith(
        hintText: hint,
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: _SetupModelColors.textSecondary.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _SetupModelColors.textSecondary),
      filled: true,
      fillColor: _SetupModelColors.input,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _SetupModelColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _SetupModelColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );
  }

  Widget _buildStateIcon(IconData icon, Color color, bool loading) {
    if (loading) {
      return const SizedBox(
        width: 34,
        height: 34,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: AppColors.primary,
        ),
      );
    }
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }

  Widget _buildActions(SetupModelViewModel vm) {
    if (vm.busy) return const SizedBox(height: 52);
    if (vm.configured) {
      return _button(
        label: '开始聊天',
        icon: Icons.arrow_forward,
        onPressed: () => context.go(Routes.index),
      );
    }
    return _button(
      label: '保存并验证',
      icon: Icons.check,
      onPressed: () async {
        final ok = await vm.saveModelConfig(
          SetupModelConfig(
            provider: vm.selectedProvider.id,
            baseUrl: _baseUrlController.text,
            model: _modelController.text,
            apiKey: _apiKeyController.text,
          ),
        );
        if (ok && mounted) context.go(Routes.index);
      },
    );
  }

  void _syncProviderFields(SetupProviderOption provider) {
    _baseUrlController.text = provider.defaultBaseUrl ?? '';
    _modelController.text = provider.models.first.id;
  }

  Widget _button({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label, style: AppTextStyles.titleMedium),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.round),
          ),
        ),
      ),
    );
  }
}
