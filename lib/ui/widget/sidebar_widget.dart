import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/repository/server_repository.dart';
import 'package:parrot_app/data/service/gateway_connection.dart';
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/view_model/conn_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:pull_down_button/pull_down_button.dart';
import 'package:uuid/uuid.dart';

/// 应用侧边栏。
///
/// 会话数据目前使用静态列表，后续可以通过 [sessions] 和 [onSessionSelected]
/// 接入真实的会话仓库。
int _selectedNavIndex = 0;
int _selectedSessionIndex = 0;

class SidebarWidget extends StatefulWidget {
  final ConnViewModel viewModel;

  const SidebarWidget({super.key, required this.viewModel});

  @override
  State<SidebarWidget> createState() => _SidebarWidgetState();
}

class _SidebarWidgetState extends State<SidebarWidget> {
  List<GatewaySessionEntry> _sessions = const [];
  bool _isCreatingSession = false;
  String? _deletingSessionKey;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onViewModelChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSessions();
    });
  }

  Future<void> _loadSessions() async {
    try {
      await widget.viewModel.listSessions();
    } catch (error) {
      // Session loading is best-effort. A temporary gateway disconnect should
      // not escape from a post-frame callback as an unhandled exception.
      debugPrint('[ParrotClaw] Failed to load sessions: $error');
    }
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    super.dispose();
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    setState(_refreshSessions);
  }

  void _refreshSessions() {
    _sessions = widget.viewModel.sessions;
    if (_sessions.isEmpty) {
      _selectedSessionIndex = 0;
    } else if (_selectedSessionIndex >= _sessions.length) {
      _selectedSessionIndex = _sessions.length - 1;
    }
  }

  @override
  void didUpdateWidget(covariant SidebarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_onViewModelChanged);
      widget.viewModel.addListener(_onViewModelChanged);
      _refreshSessions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sidebarColor = theme.colorScheme.surface;
    final selectedColor = theme.colorScheme.onSurface.withValues(alpha: 0.10);
    final secondaryColor = theme.colorScheme.onSurface.withValues(alpha: 0.62);
    return Material(
      color: sidebarColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              const SizedBox(height: 22),
              _buildNavigationItem(
                context,
                icon: Icons.home_outlined,
                label: '聊天',
                index: 0,
                selectedColor: selectedColor,
              ),
              // _buildNavigationItem(
              //   context,
              //   icon: Icons.schedule_outlined,
              //   label: '定时任务',
              //   index: 1,
              //   selectedColor: selectedColor,
              // ),
              _buildNavigationItem(
                context,
                icon: Icons.dns_outlined,
                label: '网关管理',
                index: 2,
                selectedColor: selectedColor,
              ),
              const SizedBox(height: 12),
              _buildNewConversationButton(context),
              const SizedBox(height: 26),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '最近',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: secondaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child:
                    _sessions.isEmpty
                        ? Center(
                          child: Text(
                            '暂无会话',
                            style: AppTextStyles.caption.copyWith(
                              color: secondaryColor,
                            ),
                          ),
                        )
                        : ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: _sessions.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 2),
                          itemBuilder: (context, index) {
                            return _buildSessionItem(
                              context,
                              session: _sessions[index],
                              index: index,
                              selectedColor: selectedColor,
                            );
                          },
                        ),
              ),
              const SizedBox(height: 12),
              if (Platform.isWindows || Platform.isMacOS)
                Column(
                  children: [
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.05,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: '分享网关配置',
                        onPressed: () => _openQrCode(context),
                        icon: const Icon(Icons.phone_iphone_outlined, size: 21),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Text(
          'ParrotClaw',
          style: AppTextStyles.titleLarge.copyWith(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: '设置',
          onPressed: () {
            _closeDrawer(context);
            context.go(Routes.setting);
          },
          icon: const Icon(Icons.settings_outlined, size: 21),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _buildNavigationItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int index,
    required Color selectedColor,
  }) {
    final selected = _selectedNavIndex == index;
    return _SidebarItem(
      icon: icon,
      label: label,
      selected: selected,
      selectedColor: selectedColor,
      onTap: () {
        setState(() {
          _selectedNavIndex = index;
        });
        if (index == 0) {
          _closeDrawer(context);
          context.go(Routes.index);
        } else if (index == 1) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('定时任务功能即将开放')));
        } else {
          _closeDrawer(context);
          context.go(Routes.serverList);
        }
      },
    );
  }

  Widget _buildNewConversationButton(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _isCreatingSession ? null : () => _createSession(context),
      icon:
          _isCreatingSession
              ? const SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(Icons.add, size: 19),
      label: Text(_isCreatingSession ? '创建中...' : '新建会话'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(42),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.20),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }

  void _openQrCode(BuildContext context) {
    final config = context.read<ServerRepository>().selectedServer;
    if (config == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无可分享的网关配置')));
      return;
    }
    _closeDrawer(context);
    context.go(Routes.qrCode, extra: config);
  }

  Future<void> _createSession(BuildContext context) async {
    if (_isCreatingSession || !widget.viewModel.connected) {
      if (!widget.viewModel.connected && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('网关尚未连接')));
      }
      return;
    }

    setState(() => _isCreatingSession = true);
    try {
      final key = const Uuid().v4();
      final response = await widget.viewModel.createSession(key: key);
      if (!mounted) return;
      await widget.viewModel.switchSession(response.key);
      setState(() {
        _selectedNavIndex = -1;
        _selectedSessionIndex = widget.viewModel.sessions.indexWhere(
          (session) => session.key == response.key,
        );
        if (_selectedSessionIndex < 0) _selectedSessionIndex = 0;
      });
      _closeDrawer(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('创建会话失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _isCreatingSession = false);
    }
  }

  Widget _buildSessionItem(
    BuildContext context, {
    required GatewaySessionEntry session,
    required int index,
    required Color selectedColor,
  }) {
    final selected = _selectedSessionIndex == index;
    return GestureDetector(
      onTap: () async {
        await widget.viewModel.switchSession(session.key);
        if (!mounted) return;
        setState(() {
          _selectedSessionIndex = index;
          _selectedNavIndex = -1;
        });
        _closeDrawer(context);
        context.go(Routes.index);
      },
      onLongPressStart:
          (details) =>
              _showSessionActions(context, session, details.globalPosition),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? selectedColor : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 17,
              color: _secondaryText(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                session.displayName ?? session.label ?? session.key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSession(
    BuildContext context,
    GatewaySessionEntry session,
  ) async {
    if (_deletingSessionKey != null) return;
    setState(() => _deletingSessionKey = session.key);
    try {
      await widget.viewModel.deleteSession(
        sessionKey: session.key,
        agentId: session.agentId,
      );
      if (!mounted) return;
      if (widget.viewModel.sessionKey == null &&
          widget.viewModel.sessions.isNotEmpty) {
        await widget.viewModel.switchSession(
          widget.viewModel.sessions.first.key,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除会话失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _deletingSessionKey = null);
    }
  }

  Future<void> _showSessionActions(
    BuildContext context,
    GatewaySessionEntry session,
    Offset globalPosition,
  ) async {
    final menuRect = Rect.fromCenter(
      center: globalPosition,
      width: 0,
      height: 0,
    );
    await showPullDownMenu(
      context: context,
      position: menuRect,
      items: [
        PullDownMenuItem(
          title: '删除',
          // icon: Icons.delete_outline,
          isDestructive: true,
          onTap: () {
            _confirmDeleteSession(context, session);
          },
        ),
      ],
    );
  }

  Future<void> _confirmDeleteSession(
    BuildContext context,
    GatewaySessionEntry session,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('确认删除'),
            content: Text('确认删除 ${session.displayName ?? session.key} 吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  '删除',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
    );

    if (confirmed != true || !mounted) return;
    await _deleteSession(context, session);
  }

  Color _secondaryText(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62);

  void _closeDrawer(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: selected ? selectedColor : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: SizedBox(
          height: 42,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
