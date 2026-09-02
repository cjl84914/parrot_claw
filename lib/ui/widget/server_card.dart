import 'package:flutter/material.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:pull_down_button/pull_down_button.dart';

class ServerCard extends StatelessWidget {
  final ServerConfig config;
  final bool isConnected;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onShareQr;
  final bool isDefault;

  const ServerCard({
    super.key,
    required this.config,
    this.isConnected = false,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onShareQr,
    this.isDefault = false,
  });

  Color _avatarColor(String name) {
    final colors = [
      const Color(0xFF3370FF),
      const Color(0xFF7B67EE),
      const Color(0xFF00B42A),
      const Color(0xFFFF7D00),
      const Color(0xFF14C9C9),
      const Color(0xFFF54A45),
    ];
    final index = name.isEmpty ? 0 : name.codeUnitAt(0) % colors.length;
    return colors[index];
  }

  Future<void> _showActions(BuildContext context, Offset globalPosition) async {
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
          icon: Icons.delete_outline,
          isDestructive: true,
          onTap: onDelete,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: (details) =>
          _showActions(context, details.globalPosition),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar with status indicator
            _buildAvatar(),
            const SizedBox(width: 12),
            // Server info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          config.name,
                          style: AppTextStyles.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isDefault)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(
                            Icons.check_circle,
                            size: 18,
                            color: Colors.green,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        config.useTLS ? Icons.lock_outlined : Icons.lock_open_outlined,
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          config.displayAddress,
                          style: AppTextStyles.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (config.lastConnected != null)
                        Text(
                          _formatTime(context, config.lastConnected!),
                          style: AppTextStyles.captionSmall,
                        ),
                    ],
                  ),
                ],
              ),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final color = _avatarColor(config.name);
    final initial = config.name.isEmpty ? 'S' : config.name.characters.first.toUpperCase();

    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.large),
            ),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ),
          // Positioned(
          //   right: 0,
          //   bottom: 0,
          //   child: Container(
          //     width: 10,
          //     height: 10,
          //     decoration: BoxDecoration(
          //       color: isConnected ? AppColors.online : AppColors.offline,
          //       shape: BoxShape.circle,
          //       border: Border.all(color: AppColors.surface, width: 1.5),
          //     ),
          //   ),
          // ),
        ],
      ),
    );
  }

  String _formatTime(BuildContext context, DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.month}/${time.day}';
  }
}
