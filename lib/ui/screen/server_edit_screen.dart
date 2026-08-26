import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/service/gateway_connection.dart';
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/view_model/server_viewmodel.dart';
import 'package:uuid/uuid.dart';

class ServerEditScreen extends StatefulWidget {
  final ServerConfig? server;
  final ServerViewModel viewModel;

  const ServerEditScreen({super.key, this.server, required this.viewModel});

  @override
  State<ServerEditScreen> createState() => _ServerEditPageState();
}

class _ServerEditPageState extends State<ServerEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '18789');
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isEditing = false;
  bool _useTLS = false;
  bool _isTesting = false;
  bool _testSuccess = false;
  String? _testError;
  String? _serverId;
  String _authMode = 'password';

  @override
  void initState() {
    super.initState();
    if (widget.server != null) {
      _isEditing = true;
      _serverId = widget.server!.id;
      _nameController.text = widget.server!.name;
      _hostController.text = widget.server!.host;
      _portController.text = widget.server!.port.toString();
      _tokenController.text = widget.server!.token;
      _passwordController.text = widget.server!.password;
      _useTLS = widget.server!.useTLS;
      _authMode = widget.server!.authMode;
    } else {
      _serverId = const Uuid().v4();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑服务器' : '添加服务器'),
        actions: [
          if (Platform.isAndroid || Platform.isIOS)
          TextButton(
            onPressed: () {
              context.push(Routes.qrScan);
            },
            child: const Text('扫一扫'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            _buildSectionHeader('基本信息'),
            _buildCard([
              _buildTextField(
                controller: _nameController,
                label: '名称',
                hint: '给服务器起个名字',
                icon: Icons.label_outline,
                validator: (v) => (v == null || v.isEmpty) ? '请输入名称' : null,
              ),
            ]),

            const SizedBox(height: 20),

            _buildSectionHeader('连接地址'),
            _buildCard([
              _buildTextField(
                controller: _hostController,
                label: '服务器地址',
                hint: '例如: 192.168.1.100 或 api.example.com',
                icon: Icons.dns_outlined,
                validator: (v) => (v == null || v.isEmpty) ? '请输入地址' : null,
              ),
              const Divider(height: 0.5, indent: 44, color: AppColors.divider),
              _buildTextField(
                controller: _portController,
                label: '端口',
                hint: '18789',
                icon: Icons.tag,
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return '请输入端口';
                  final port = int.tryParse(v);
                  if (port == null || port < 1 || port > 65535) return '无效端口';
                  return null;
                },
              ),
              const Divider(height: 0.5, indent: 44, color: AppColors.divider),
              _buildSwitchTile(
                icon: Icons.lock_outlined,
                title: '加密连接 (TLS)',
                subtitle: '云端服务器建议开启',
                value: _useTLS,
                onChanged: (v) => setState(() => _useTLS = v),
              ),
            ]),

            const SizedBox(height: 20),

            _buildSectionHeader('认证方式'),
            _buildCard([
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'password',
                      label: Text('密码认证'),
                      icon: Icon(Icons.lock_outline, size: 16),
                    ),
                    ButtonSegment(
                      value: 'token',
                      label: Text('Token认证'),
                      icon: Icon(Icons.key_outlined, size: 16),
                    ),
                  ],
                  selected: {_authMode},
                  onSelectionChanged:
                      (s) => setState(() => _authMode = s.first),
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(AppTextStyles.bodyMedium),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              if (_authMode == 'password') ...[
                _buildTextField(
                  controller: _passwordController,
                  label: '密码',
                  hint: '输入网关密码',
                  icon: Icons.password_outlined,
                  obscureText: true,
                  validator:
                      (v) =>
                          _authMode == 'password' && (v == null || v.isEmpty)
                              ? '请输入密码'
                              : null,
                ),
                _buildHelpText('使用密码连接到网关'),
              ] else ...[
                _buildTextField(
                  controller: _tokenController,
                  label: '访问令牌',
                  hint: '从服务器配置获取',
                  icon: Icons.key_outlined,
                  obscureText: true,
                  validator:
                      (v) =>
                          _authMode == 'token' && (v == null || v.isEmpty)
                              ? '请输入令牌'
                              : null,
                ),
                _buildHelpText('使用长效 Token 连接到网关'),
              ],
            ]),

            const SizedBox(height: 24),

            if (_isTesting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              )
            else if (_testSuccess)
              _buildResultBanner(
                icon: Icons.check_circle_outline,
                color: AppColors.online,
                title: '连接成功',
              )
            else if (_testError != null)
              _buildResultBanner(
                icon: Icons.error_outline,
                color: AppColors.error,
                title: '连接失败',
                detail: _testError,
              ),

            const SizedBox(height: 12),

            OutlinedButton.icon(
              onPressed: _isTesting ? null : _testConnection,
              icon: const Icon(Icons.wifi_tethering, size: 18),
              label: const Text('测试连接'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.round),
                  ),
                ),
                child: Text(
                  _isEditing ? '保存' : '添加服务器',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                context.push(Routes.more);
              },
              child: const Text('帮助'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // -- UI 构建辅助方法 --

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title, style: AppTextStyles.caption),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: AppTextStyles.bodyMedium,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: AppColors.textSecondary),
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textTertiary,
        ),
        errorStyle: AppTextStyles.captionSmall.copyWith(color: AppColors.error),
      ),
      validator: validator,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: SwitchListTile(
        secondary: Icon(icon, size: 20, color: AppColors.textSecondary),
        title: Text(title, style: AppTextStyles.bodyMedium),
        subtitle:
            subtitle != null
                ? Text(subtitle, style: AppTextStyles.caption)
                : null,
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }

  Widget _buildHelpText(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(44, 0, 16, 12),
      child: Text(text, style: AppTextStyles.caption),
    );
  }

  Widget _buildResultBanner({
    required IconData icon,
    required Color color,
    required String title,
    String? detail,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                detail,
                style: AppTextStyles.caption.copyWith(color: color),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // -- 业务逻辑 --

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testSuccess = false;
      _testError = null;
    });

    final config = _buildConfig();
    try {
      await GatewayConnection.shared.configure(
        url: config.wsUrl,
        token: config.token,
        password: config.password,
      );
      print('[ParrotClaw] Testing connection to ${config.wsUrl}');
      final result = await GatewayConnection.shared.status();
      if (mounted) {
        setState(() {
          _testSuccess = result.ok;
          _testError = result.error;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testSuccess = false;
          _testError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      try {
        await GatewayConnection.shared.shutdown();
      } catch (e) {
        print('[ParrotClaw] Failed to close test connection: $e');
      }
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;

    final config = _buildConfig();

    if (_isEditing) {
      await widget.viewModel.updateServer(widget.server!.id, config);
    } else {
      await widget.viewModel.addServer(config);
    }

    widget.viewModel.selectServer(config);

    context.go(Routes.index);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_isEditing ? '服务器已更新' : '服务器已添加')));
  }

  ServerConfig _buildConfig() {
    return ServerConfig(
      id: _serverId ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      host: _hostController.text.trim(),
      port: int.parse(_portController.text.trim()),
      token: _tokenController.text.trim(),
      password: _passwordController.text.trim(),
      authMode: _authMode,
      useTLS: _useTLS,
      isDefault: widget.server?.isDefault ?? false,
    );
  }
}
