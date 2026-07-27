import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/view_model/server_viewmodel.dart';
import 'package:parrot_app/ui/widget/server_card.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 服务器列表页（首页）
class ServerListScreen extends StatefulWidget {
  final ServerViewModel viewModel;

  const ServerListScreen({super.key, required this.viewModel});

  @override
  State<ServerListScreen> createState() => _ServerListPageState();
}

class _ServerListPageState extends State<ServerListScreen> {
  final _exportKey = GlobalKey();

  @override
  void initState() {
    super.initState();
  }

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
              IconButton(
                key: _exportKey,
                icon: const Icon(Icons.ios_share_outlined, size: 20),
                tooltip: '导出配置',
                onPressed: _exportConfig,
              ),
              IconButton(
                icon: const Icon(Icons.download_outlined, size: 20),
                tooltip: '导入配置',
                onPressed: () => _importConfig(),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: servers.isEmpty
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

  void _editServer(ServerConfig server) {
    context.push(Routes.serverEdit, extra: server);
  }

  void _deleteServer(ServerConfig server) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确认删除 ${server.name} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              widget.viewModel.deleteServer(server.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('服务器已删除')));
            },
            child: Text(
              '删除',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error),
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

  Future<void> _exportConfig() async {
    try {
      final json = widget.viewModel.exportConfig();

      // 保存到临时文件
      final tempDir = await getApplicationSupportDirectory();
      final fileName =
          'clawchat_config_${DateTime.now().millisecondsSinceEpoch}.json';
      final filePath = path.join(tempDir.path, fileName);

      final file = File(filePath);
      await file.writeAsString(json);

      // 获取按钮位置（iOS 分享弹窗锚点）
      Rect? sharePositionOrigin;
      final renderBox =
          _exportKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final position = renderBox.localToGlobal(Offset.zero);
        sharePositionOrigin = position & renderBox.size;
      }

      // 分享文件
      final result = await Share.shareXFiles(
        [XFile(filePath)],
        subject: '配置备份',
        sharePositionOrigin: sharePositionOrigin,
      );

      // 分享完成后清理临时文件
      if (await file.exists()) {
        await file.delete();
      }

      if (mounted && result.status == ShareResultStatus.success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('配置已导出')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败: ${e.toString()}')));
      }
    }
  }

  Future<void> _importConfig() async {
    try {
      // 选择文件
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        throw Exception('无法读取文件');
      }

      final jsonString = String.fromCharCodes(file.bytes!);

      // 确认导入
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入配置'),
          content: const Text('确定要导入配置吗？将会覆盖现有配置。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('导入'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      // 导入
      await widget.viewModel.importConfig(jsonString);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('配置已导入')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入失败: ${e.toString()}')));
      }
    }
  }
}
