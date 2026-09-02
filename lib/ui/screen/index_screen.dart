import 'package:flutter/material.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/ui/widget/sidebar_widget.dart';
import 'package:parrot_app/ui/view_model/conn_viewmodel.dart';
import 'package:parrot_app/util/asr_util.dart';
import 'package:parrot_app/util/tts_util.dart';
import 'package:provider/provider.dart';

final GlobalKey<ScaffoldState> indexScaffoldKey = GlobalKey<ScaffoldState>();

class IndexScreen extends StatefulWidget {
  final ConnViewModel viewModel;
  final Widget child;

  const IndexScreen({super.key, required this.child, required this.viewModel});

  @override
  State<IndexScreen> createState() => _IndexScreenState();
}

class _IndexScreenState extends State<IndexScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.viewModel.connect();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.viewModel]),
        builder: (context, child) {
          return Scaffold(
            key: indexScaffoldKey,
            drawer: Drawer(child: SidebarWidget(viewModel: widget.viewModel)),
            onDrawerChanged: (isOpened) {
              if (!isOpened) {
                // 确保在路由切换和焦点恢复逻辑完成后，强制收起键盘
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  FocusManager.instance.primaryFocus?.unfocus();
                });
              }
            },
            body: Column(
              children: [
                if (widget.viewModel.disconnectReason != null &&
                    !widget.viewModel.connected)
                  _buildResultBanner(
                    icon: Icons.error_outline,
                    color: AppColors.error,
                    title: '连接失败',
                    detail: widget.viewModel.disconnectReason!,
                  ),
                Expanded(child: widget.child),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
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
}
