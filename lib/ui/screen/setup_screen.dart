import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/view_model/setup_viewmodel.dart';

class _LocalSetupColors {
  static const background = Color(0xFF101114);
  static const surface = Color(0xFF1B1D22);
  static const border = Color(0xFF363B44);
  static const textSecondary = Color(0xFFC9D7F2);
}

/// 本地 OpenClaw 引导界面
///
/// 体验原则：用户选择越少越好。
/// - 已有网关：连接
/// - 已安装但未运行：启动
/// - 未安装：安装
/// 所有半成品入口都不能暴露给用户。
class SetupScreen extends StatefulWidget {
  final SetupViewModel viewModel;

  const SetupScreen({super.key, required this.viewModel});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.viewModel.init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _LocalSetupColors.background,
      appBar: AppBar(
        title: const Text('安装OpenClaw', style: AppTextStyles.headlineLarge),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.viewModel,
          builder: (context, _) {
            final vm = widget.viewModel;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 22),
                  _buildHero(),
                  // const SizedBox(height: 22),
                  // _buildSteps(vm),
                  const SizedBox(height: 18),
                  Expanded(child: _buildMainCard(vm)),
                  const SizedBox(height: 16),
                  _buildPrimaryAction(vm),
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
        Text(
          'ParrotClaw 会自动检测、安装并连接本机 OpenClaw。',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildMainCard(SetupViewModel vm) {
    final state = _stateView(vm);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _LocalSetupColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _LocalSetupColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStateIcon(state),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state.title, style: AppTextStyles.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      state.subtitle,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: _LocalSetupColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (vm.outputLogs.isNotEmpty) ...[
            const SizedBox(height: 18),
            _buildLogs(vm),
          ],
        ],
      ),
    );
  }

  Widget _buildStateIcon(_StateView state) {
    if (state.loading) {
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
        color: state.color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(state.icon, color: state.color, size: 22),
    );
  }

  Widget _buildLogs(SetupViewModel vm) {
    final logs =
        vm.outputLogs.length > 5
            ? vm.outputLogs.sublist(vm.outputLogs.length - 5)
            : vm.outputLogs;
    return Container(
      height: 300,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _LocalSetupColors.border.withValues(alpha: 0.6),
        ),
      ),
      child: ListView.builder(
        itemCount: logs.length,
        itemBuilder: (context, index) {
          return Text(
            logs[index],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.captionSmall
          );
        },
      ),
    );
  }

  Widget _buildPrimaryAction(SetupViewModel vm) {
    if (vm.isBusy) return const SizedBox(height: 52);

    return switch (vm.phase) {
      LocalSetupPhase.ready => _button(
        label: '开始使用',
        icon: Icons.arrow_forward,
        loading: _connecting,
        onPressed: _connecting ? null : _connect,
      ),
      LocalSetupPhase.needsStart => _button(
        label: '启动 OpenClaw',
        icon: Icons.play_arrow,
        onPressed: () async {
          final ok = await vm.startGateway();
          if (ok && mounted) await _connect();
        },
      ),
      LocalSetupPhase.needsInstall => _button(
        label: '自动安装',
        icon: Icons.download,
        onPressed: () async {
          final ok = await vm.install();
          if (ok) await vm.detectAfterInstall();
        },
      ),
      LocalSetupPhase.installed => _button(
        label: '继续检测',
        icon: Icons.refresh,
        onPressed: () => vm.detectAfterInstall(),
      ),
      LocalSetupPhase.error => _button(
        label: '重试',
        icon: Icons.refresh,
        onPressed: () => vm.retry(),
      ),
      _ => const SizedBox(height: 52),
    };
  }

  Widget _button({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool loading = false,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon:
            loading
                ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                : Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        )),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.56),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.76),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.round),
          ),
        ),
      ),
    );
  }

  _StateView _stateView(SetupViewModel vm) {
    return switch (vm.phase) {
      LocalSetupPhase.detecting => const _StateView(
        title: '正在检测环境',
        subtitle: '检查本机是否已安装并运行 OpenClaw。',
        icon: Icons.radar,
        color: AppColors.primary,
        loading: true,
      ),
      LocalSetupPhase.ready => _StateView(
        title: '本机 OpenClaw 已就绪',
        subtitle: '检测到网关端口 ${vm.port ?? 18789}，可以直接开始使用。',
        icon: Icons.check_circle,
        color: AppColors.online,
      ),
      LocalSetupPhase.needsStart => const _StateView(
        title: '需要启动 OpenClaw',
        subtitle: '已安装 OpenClaw，但本机网关暂未运行。',
        icon: Icons.power_settings_new,
        color: AppColors.warning,
      ),
      LocalSetupPhase.starting => const _StateView(
        title: '正在启动 OpenClaw',
        subtitle: '启动完成后会自动连接。',
        icon: Icons.play_arrow,
        color: AppColors.primary,
        loading: true,
      ),
      LocalSetupPhase.needsInstall => const _StateView(
        title: '需要安装 OpenClaw',
        subtitle: '将使用国内镜像自动安装 Node.js 与 OpenClaw。',
        icon: Icons.download,
        color: AppColors.primary,
      ),
      LocalSetupPhase.installing => const _StateView(
        title: '正在安装 OpenClaw',
        subtitle: '安装过程可能需要几分钟，请保持网络连接。',
        icon: Icons.download,
        color: AppColors.primary,
        loading: true,
      ),
      LocalSetupPhase.installed => _StateView(
        title: '安装完成',
        subtitle: 'OpenClaw ${vm.version ?? ''} 已安装，接下来会检测网关。',
        icon: Icons.verified,
        color: AppColors.online,
      ),
      LocalSetupPhase.error => _StateView(
        title: '处理失败',
        subtitle: vm.errorMessage ?? '请重试，或检查网络与本机权限。',
        icon: Icons.error_outline,
        color: AppColors.error,
      ),
    };
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    try {
      final result = await widget.viewModel.connectLocal();
      if (!mounted) return;
      if (result != null) {
        context.push(result.hasModel ? Routes.index : Routes.setupModel);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('连接失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }
}

class _StateView {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool loading;

  const _StateView({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.loading = false,
  });
}
