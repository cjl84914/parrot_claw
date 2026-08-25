import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/view_model/server_viewmodel.dart';
import 'package:parrot_app/ui/widget/server_card.dart';

/// 服务器列表页（首页）
class ServerListScreen extends StatefulWidget {
  final ServerViewModel viewModel;

  const ServerListScreen({super.key, required this.viewModel});

  @override
  State<ServerListScreen> createState() => _ServerListPageState();
}

class _ServerListPageState extends State<ServerListScreen> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.viewModel]),
      builder: (context, child) {
        final servers = widget.viewModel.servers;
        final defaultServer = widget.viewModel.defaultServer;

        return Scaffold(
          appBar: AppBar(
            title: const Text('切换服务器', style: AppTextStyles.headlineMedium),
            elevation: 0,
            actions: [
              // 桌面端无摄像头，不显示扫码入口（扫码由移动端完成）
              if (!Platform.isMacOS && !Platform.isWindows)
                TextButton(
                  onPressed: () {
                    context.push(Routes.qrScan);
                  },
                  child: const Text('扫一扫'),
                ),
              const SizedBox(width: 4),
            ],
          ),
          body:
              servers.isEmpty
                  ? _buildEmptyState()
                  : _buildServerList(servers, defaultServer),
          floatingActionButton: FloatingActionButton(
            elevation: 0,
            onPressed: _addServer,
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                // color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.dns_outlined,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            const Text('暂无服务器', style: AppTextStyles.titleLarge),
            const SizedBox(height: 8),
            Text(
              '点击下方按钮添加服务器',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _addServer,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加服务器'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.large),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerList(
    List<ServerConfig> servers,
    ServerConfig? defaultServer,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              '共 ${servers.length} 个服务器',
              style: AppTextStyles.caption,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.large),
            ),
            clipBehavior: Clip.antiAlias,
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) {
                return Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(AppRadius.large),
                  shadowColor: Colors.black26,
                  child: child,
                );
              },
              onReorder: (oldIndex, newIndex) {
                widget.viewModel.reorderServer(oldIndex, newIndex);
              },
              itemCount: servers.length,
              itemBuilder: (context, i) {
                return Column(
                  key: ValueKey(servers[i].id),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: ServerCard(
                        config: servers[i],
                        isDefault: servers[i].id == defaultServer?.id,
                        onTap: () => _openChat(servers[i]),
                        onEdit: () => _editServer(servers[i]),
                        onDelete: () => _deleteServer(servers[i]),
                        onShareQr: () => _shareQr(servers[i]),
                      ),
                    ),
                    if (i < servers.length - 1)
                      const Divider(
                        height: 0.5,
                        thickness: 0.5,
                        indent: 72,
                        color: AppColors.divider,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _addServer() {
    context.push(Routes.serverEdit);
  }

  void _shareQr(ServerConfig server) {
    context.push(Routes.qrCode, extra: server);
  }

  void _editServer(ServerConfig server) {
    context.push(Routes.serverEdit, extra: server);
  }

  void _deleteServer(ServerConfig server) {
    // 在弹窗打开前捕获上层依赖，避免弹窗关闭后 dialogContext 失效
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('确认删除'),
            content: Text('确认删除 ${server.name} 吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  await widget.viewModel.deleteServer(server.id);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);

                  final servers = widget.viewModel.servers;
                  if (servers.isEmpty) {
                    // 服务器删空：跳回引导页（桌面端），移动端回到添加服务器页
                    if (Platform.isMacOS || Platform.isWindows) {
                      router.go(Routes.setup);
                    } else {
                      router.go(Routes.serverEdit);
                    }
                  } else {
                    // 还有服务器：自动选中列表中第一个
                    final first = servers.first;
                    if (widget.viewModel.selectedServer?.id != first.id) {
                      widget.viewModel.selectServer(first);
                    }
                    messenger.showSnackBar(
                      const SnackBar(content: Text('服务器已删除')),
                    );
                  }
                },
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
  }

  void _openChat(ServerConfig server) {
    widget.viewModel.selectServer(server);
    Navigator.pop(context);
  }
}
