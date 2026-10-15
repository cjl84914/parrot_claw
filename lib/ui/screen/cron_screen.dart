import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/model/gateway_cron.dart';
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/screen/index_screen.dart';
import 'package:parrot_app/ui/view_model/cron_viewmodel.dart';
import 'package:parrot_app/ui/widget/my_snack_bar.dart';
import 'package:pull_down_button/pull_down_button.dart';

/// 深色「定时任务（自动化）」管理页。
///
/// 数据与操作全部走 [CronViewModel]（它转发给 GatewayRepository）：
/// - [CronViewModel.jobs] 渲染列表；
/// - [CronViewModel.isLoading] 控制首屏 loading / 操作去重；
/// - [CronViewModel.error] 渲染错误态；
/// - [CronViewModel.run] 立即运行、[CronViewModel.load] 重新拉取。
///
/// 字段命名参照官方「自动化」页：
/// 任务名 / 状态 / 调度 / 智能体 / 上次结果 / 下次运行 / 上次运行 / 描述。
class CronScreen extends StatefulWidget {
  const CronScreen({super.key, required this.viewModel});

  final CronViewModel viewModel;

  @override
  State<CronScreen> createState() => _CronScreenState();
}

class _CronScreenState extends State<CronScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.viewModel.load();
    });
  }

  Future<void> _reload() async {
    await widget.viewModel.load();
    if (!mounted) return;
    final error = widget.viewModel.error;
    if (error != null) MySnackBar.showError(context, error);
  }

  Future<void> _run(GatewayCronJob job) async {
    if (widget.viewModel.isLoading) return;
    final ok = await widget.viewModel.run(job.id);
    if (!mounted) return;
    if (ok) {
      MySnackBar.showSuccess(context, '${job.title} 已触发运行');
    } else {
      MySnackBar.showError(context, widget.viewModel.error ?? '运行失败');
    }
  }

  /// 长按卡片 → 确认 → 删除任务。
  Future<void> _delete(GatewayCronJob job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('确认删除'),
            content: Text('确认删除 ${job.title} 吗？'),
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

    final ok = await widget.viewModel.remove(job.id);
    if (!mounted) return;
    if (ok) {
      MySnackBar.showSuccess(context, '${job.title} 已删除');
    } else {
      MySnackBar.showError(context, widget.viewModel.error ?? '删除失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: '打开侧边栏',
          onPressed: () => indexController.switchSideBarVisible(),
        ),
        title: const Text('定时任务'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建任务',
            onPressed: () => context.push(Routes.cronEdit),
          ),
        ],
        elevation: 0,
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.viewModel,
          builder: (context, _) => _buildBody(),
        ),
      ),
    );
  }

  // ==================== 列表 ====================

  Widget _buildBody() {
    final viewModel = widget.viewModel;
    final jobs = viewModel.jobs;

    if (jobs.isEmpty && viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (jobs.isEmpty && viewModel.error != null) {
      return _buildError(viewModel.error!);
    }
    if (jobs.isEmpty) {
      return _buildEmpty();
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: jobs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final job = jobs[index];
          return _CronJobCard(
            job: job,
            busy: viewModel.isLoading,
            onTap: () => context.push(Routes.cronEdit, extra: job),
            onRun: () => _run(job),
            onDelete: () => _delete(job),
          );
        },
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(32, 24, 32, 64),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule_outlined, size: 30, color: _Palette.muted),
            SizedBox(height: 14),
            Text(
              '暂无定时任务',
              style: TextStyle(
                color: _Palette.title,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '点击右上角「+」新建一个任务。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _Palette.subtitle,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 64),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 30, color: _Palette.red),
            const SizedBox(height: 14),
            const Text(
              '任务列表加载失败',
              style: TextStyle(
                color: _Palette.title,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _Palette.subtitle,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _reload,
              style: FilledButton.styleFrom(
                backgroundColor: _Palette.green,
                foregroundColor: Colors.black,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 组件 ====================

class _CronJobCard extends StatelessWidget {
  const _CronJobCard({
    required this.job,
    required this.busy,
    required this.onTap,
    required this.onRun,
    required this.onDelete,
  });

  final GatewayCronJob job;

  /// 有操作在进行（列表加载 / 运行），「立即运行」置灰防重复点击。
  final bool busy;

  /// 点击整行 → 进编辑页。
  final VoidCallback onTap;
  final VoidCallback onRun;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final description = job.description?.trim();
    final agent = job.agentId?.trim();
    final schedule = job.schedule?.label.trim();

    final card = Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusBadge(enabled: job.isEnabled),
              const SizedBox(width: 10),
              Text(
                job.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _Palette.title,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ],
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _Palette.subtitle,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (schedule != null && schedule.isNotEmpty)
                _InfoChip(text: schedule),
              if (agent != null && agent.isNotEmpty)
                _InfoChip(icon: Icons.smart_toy_outlined, text: agent),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 1, color: _Palette.divider),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _MetaLine(job: job)),
              const SizedBox(width: 12),
              _ActionButton(
                label: '立即运行',
                primary: true,
                onPressed: busy ? null : onRun,
              ),
            ],
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      onLongPressStart:
          (details) => _showActions(context, details.globalPosition),
      child: card,
    );
  }

  /// 长按卡片弹出操作菜单（与网关管理 `ServerCard` 同款）。
  Future<void> _showActions(BuildContext context, Offset globalPosition) async {
    await showPullDownMenu(
      context: context,
      position: Rect.fromCenter(center: globalPosition, width: 0, height: 0),
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
}

/// 调度 / 智能体这类短标签。
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _Palette.chip,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: _Palette.muted),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: const TextStyle(
              color: _Palette.muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// 配置与日志一行：`ok · next … · last …`。
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.job});

  final GatewayCronJob job;

  @override
  Widget build(BuildContext context) {
    final segments = <Widget>[];

    void addSegment(Widget child) {
      if (segments.isNotEmpty) {
        segments.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '·',
              style: TextStyle(color: _Palette.subtitle, fontSize: 12),
            ),
          ),
        );
      }
      segments.add(child);
    }

    final status = job.displayStatus?.trim();
    if (status != null && status.isNotEmpty) {
      addSegment(
        Text(
          status,
          style: TextStyle(
            color: _statusColor(status),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final next = job.nextRunAt;
    if (next != null) {
      addSegment(_metaText('next ${formatCronDateTime(next)}'));
    }

    final last = job.lastRunAt;
    if (last != null) {
      addSegment(_metaText('last ${formatCronDateTime(last)}'));
    }

    if (segments.isEmpty) return const SizedBox.shrink();

    return Wrap(
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: segments,
    );
  }

  Widget _metaText(String text) => Text(
    text,
    style: const TextStyle(color: _Palette.subtitle, fontSize: 12),
  );

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'ok':
      case 'success':
        return _Palette.green;
      case 'fail':
      case 'failed':
      case 'error':
        return _Palette.red;
      default:
        return _Palette.muted;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? _Palette.green : _Palette.grey;
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _Palette.green,
          foregroundColor: Colors.black,
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _Palette.title,
        side: const BorderSide(color: Color(0xFF2B2B31)),
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }
}

// ==================== 配色（与 skill_screen 保持一致） ====================

abstract final class _Palette {
  static const background = Color(0xFF000000);
  static const card = Color(0xFF141416);
  static const chip = Color(0xFF1C1C1F);
  static const divider = Color(0xFF1F1F23);
  static const title = Color(0xFFF2F2F4);
  static const muted = Color(0xFF9B9BA1);
  static const subtitle = Color(0xFF8E8E93);
  static const green = Color(0xFF30D158);
  static const grey = Color(0xFF8E8E93);
  static const red = Color(0xFFFF6B66);
}
