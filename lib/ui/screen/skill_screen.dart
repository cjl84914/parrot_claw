import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parrot_app/data/model/gateway_skill.dart';
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/screen/index_screen.dart';
import 'package:parrot_app/ui/view_model/skill_viewmodel.dart';
import 'package:parrot_app/ui/widget/my_snack_bar.dart';

/// 深色技能（插件）管理页。
///
/// 数据与操作全部走 [SkillViewModel]（它转发给 GatewayRepository）：
/// - [SkillViewModel.skills] 渲染列表；
/// - [SkillViewModel.isLoading] 控制首屏 loading / 开关去重；
/// - [SkillViewModel.error] 渲染错误横幅；
/// - [SkillViewModel.update] 切换启用状态（网关会重新下发 skills.status）。
class SkillScreen extends StatefulWidget {
  const SkillScreen({super.key, required this.viewModel});

  final SkillViewModel viewModel;

  @override
  State<SkillScreen> createState() => _SkillScreenState();
}

class _SkillScreenState extends State<SkillScreen> {
  _SkillFilter _filter = _SkillFilter.all;

  /// 开关的乐观覆盖值：key → 用户刚切到的目标状态。
  ///
  /// 网关是「改完再重拉列表」的异步往返，没有它开关会先弹回原位再跳过去。
  /// 操作结束（成功或失败）后立即移除，让真实状态接管。
  final Map<String, bool> _pendingEnabled = <String, bool>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.viewModel.load();
    });
  }

  /// 列表里**唯一**的启用状态来源：开关、状态标签、筛选都读它。
  ///
  /// 网关值优先被乐观覆盖值顶掉，操作结束后覆盖移除、回到网关值。
  bool _isEnabled(GatewaySkill skill) =>
      _pendingEnabled[skill.key] ?? skill.enabled;

  Future<void> _setEnabled(GatewaySkill skill, bool value) async {
    if (widget.viewModel.isLoading) return;
    setState(() => _pendingEnabled[skill.key] = value);
    final ok = await widget.viewModel.update(
      skillKey: skill.key,
      enabled: value,
    );
    if (!mounted) return;
    setState(() => _pendingEnabled.remove(skill.key));
    if (!ok) {
      MySnackBar.showError(
        context,
        widget.viewModel.error ?? '${skill.name} 状态切换失败',
      );
      return;
    }
    MySnackBar.showSuccess(
      context,
      value ? '${skill.name} 已启用' : '${skill.name} 已关闭',
    );
  }

  Future<void> _reload() async {
    await widget.viewModel.load();
    if (!mounted) return;
    final error = widget.viewModel.error;
    if (error != null) MySnackBar.showError(context, error);
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
        title: _buildFilterBar(),
        elevation: 0,
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.viewModel,
          builder: (context, _) {
            return _buildBody();
          },
        ),
      ),
    );
  }

  // ==================== 顶部筛选栏 ====================

  Widget _buildFilterBar() {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        itemCount: _SkillFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _SkillFilter.values[index];
          return _FilterPill(
            label: filter.label,
            selected: _filter == filter,
            onTap: () => setState(() => _filter = filter),
          );
        },
      ),
    );
  }

  // ==================== 列表 ====================

  Widget _buildBody() {
    final viewModel = widget.viewModel;
    final skills = viewModel.skills;

    if (skills.isEmpty && viewModel.isLoading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: _Palette.muted,
          ),
        ),
      );
    }

    if (skills.isEmpty) {
      final error = viewModel.error;
      return _EmptyState(
        icon:
            error != null ? Icons.cloud_off_rounded : Icons.extension_outlined,
        title: error != null ? '无法读取技能列表' : '暂无技能',
        detail: error ?? '网关还没有安装任何技能，或当前还没有连接到网关。',
        onRetry: _reload,
      );
    }

    final visible = skills
        .where(
          (skill) =>
              _filter.matches(skillStatusOf(skill, enabled: _isEnabled(skill))),
        )
        .toList(growable: false);

    return RefreshIndicator(
      color: _Palette.title,
      backgroundColor: _Palette.chip,
      onRefresh: _reload,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (viewModel.error != null)
            SliverToBoxAdapter(child: _buildErrorBanner(viewModel.error!)),
          if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                icon: Icons.filter_alt_off_outlined,
                title: '该分类下暂无技能',
                detail: '「${_filter.label}」分类下没有匹配的条目，换个筛选看看。',
              ),
            )
          else
            SliverList.separated(
              itemCount: visible.length,
              separatorBuilder:
                  (_, _) => const Divider(
                    height: 1,
                    thickness: 1,
                    indent: 68,
                    color: _Palette.divider,
                  ),
              itemBuilder: (context, index) {
                final skill = visible[index];
                return _SkillTile(
                  skill: skill,
                  enabled: _isEnabled(skill),
                  interactive: !viewModel.isLoading,
                  onToggle: (value) => _setEnabled(skill, value),
                  onTap: () => _openDetail(skill),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: _Palette.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: _Palette.red,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _Palette.red,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
          TextButton(
            onPressed: _reload,
            style: TextButton.styleFrom(
              foregroundColor: _Palette.red,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  // ==================== 详情 ====================

  Future<void> _openDetail(GatewaySkill skill) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: _Palette.sheet,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder:
          (sheetContext) => _SkillDetailSheet(
            viewModel: widget.viewModel,
            skillKey: skill.key,
            onToggle: _setEnabled,
          ),
    );
  }
}

// ==================== 状态与视觉映射 ====================

/// Skill 在列表中的三态。
///
/// 截图里只出现「就绪 / 关闭」，这里多一档「需要设置」，用于网关返回
/// `eligible=false` / `installed=false` / `missing` 非空（缺密钥、缺依赖）的情况。
enum SkillStatus {
  ready('就绪'),
  needsSetup('需要设置'),
  disabled('关闭');

  const SkillStatus(this.label);

  final String label;
}

/// 由网关字段推导列表状态。
///
/// [enabled] 传入列表里**真正生效**的启用值（开关的当前值，可能带乐观覆盖）。
/// 状态标签与开关必须同源，否则切换的瞬间会出现「标签写着关闭、开关已经打开」
/// 这种自相矛盾的画面。
///
/// 语义分两层：
/// 1. 启用与否 —— 只看开关（网关的 `disabled` 取反），关了就是「关闭」；
/// 2. 已启用但跑不起来（缺密钥/命令、被 allowlist 拦、平台不支持）→「需要设置」。
SkillStatus skillStatusOf(GatewaySkill skill, {bool? enabled}) {
  final effective = enabled ?? skill.enabled;
  if (!effective) return SkillStatus.disabled;
  if (skill.eligible == false ||
      skill.platformIncompatible ||
      skill.blockedByAllowlist ||
      skill.hasMissingRequirements) {
    return SkillStatus.needsSetup;
  }
  return SkillStatus.ready;
}

enum _SkillFilter {
  all('全部'),
  ready('就绪'),
  needsSetup('需要设置'),
  disabled('关闭');

  const _SkillFilter(this.label);

  final String label;

  bool matches(SkillStatus status) => switch (this) {
    _SkillFilter.all => true,
    _SkillFilter.ready => status == SkillStatus.ready,
    _SkillFilter.needsSetup => status == SkillStatus.needsSetup,
    _SkillFilter.disabled => status == SkillStatus.disabled,
  };
}

abstract final class _Palette {
  static const background = Color(0xFF000000);
  static const sheet = Color(0xFF141416);
  static const chip = Color(0xFF1C1C1F);
  static const divider = Color(0xFF1F1F23);
  static const title = Color(0xFFF2F2F4);
  static const muted = Color(0xFF9B9BA1);
  static const subtitle = Color(0xFF8E8E93);
  static const green = Color(0xFF30D158);
  static const amber = Color(0xFFFFD60A);
  static const grey = Color(0xFF8E8E93);
  static const red = Color(0xFFFF6B66);
  static const trackOff = Color(0xFF333336);
  static const knobOff = Color(0xFF8E8E93);
}

class _SkillVisual {
  const _SkillVisual(this.icon, this.color);

  final IconData icon;
  final Color color;
}

/// 已知技能 → 图标 + 品牌色。命中规则按顺序取第一个 `match` 子串。
const List<({String match, _SkillVisual visual})> _skillVisualRules = [
  (
    match: '1password',
    visual: _SkillVisual(Icons.lock_outline_rounded, Color(0xFF4A8CFF)),
  ),
  (
    match: 'reminders',
    visual: _SkillVisual(Icons.checklist_rounded, Color(0xFFFF7A5C)),
  ),
  (
    match: 'apple-notes',
    visual: _SkillVisual(Icons.edit_note_rounded, Color(0xFFFFC44D)),
  ),
  (match: 'bear', visual: _SkillVisual(Icons.pets_rounded, Color(0xFFE4573D))),
  (
    match: 'blog',
    visual: _SkillVisual(Icons.rss_feed_rounded, Color(0xFFFF9F0A)),
  ),
  (
    match: 'blucli',
    visual: _SkillVisual(Icons.speaker_rounded, Color(0xFF5AC8FA)),
  ),
  (
    match: 'browser',
    visual: _SkillVisual(Icons.public_rounded, Color(0xFF64D2FF)),
  ),
  (
    match: 'automation',
    visual: _SkillVisual(Icons.smart_toy_outlined, Color(0xFFBF5AF2)),
  ),
  (
    match: 'cam',
    visual: _SkillVisual(Icons.photo_camera_rounded, Color(0xFFFFD60A)),
  ),
  (
    match: 'snap',
    visual: _SkillVisual(Icons.photo_camera_rounded, Color(0xFFFFD60A)),
  ),
  (
    match: 'canvas',
    visual: _SkillVisual(Icons.dashboard_customize_rounded, Color(0xFF30D158)),
  ),
  (
    match: 'mail',
    visual: _SkillVisual(Icons.mail_outline_rounded, Color(0xFF4A8CFF)),
  ),
  (
    match: 'calendar',
    visual: _SkillVisual(Icons.calendar_today_rounded, Color(0xFFFF6B66)),
  ),
  (
    match: 'weather',
    visual: _SkillVisual(Icons.wb_sunny_rounded, Color(0xFFFFD60A)),
  ),
  (
    match: 'github',
    visual: _SkillVisual(Icons.code_rounded, Color(0xFFC7C7CC)),
  ),
  (
    match: 'spotify',
    visual: _SkillVisual(Icons.music_note_rounded, Color(0xFF30D158)),
  ),
  (
    match: 'music',
    visual: _SkillVisual(Icons.music_note_rounded, Color(0xFFBF5AF2)),
  ),
  (
    match: 'notion',
    visual: _SkillVisual(Icons.description_outlined, Color(0xFFC7C7CC)),
  ),
  (
    match: 'note',
    visual: _SkillVisual(Icons.sticky_note_2_outlined, Color(0xFFFFC44D)),
  ),
  (
    match: 'shell',
    visual: _SkillVisual(Icons.terminal_rounded, Color(0xFF8E8E93)),
  ),
  (
    match: 'file',
    visual: _SkillVisual(Icons.folder_rounded, Color(0xFF5AC8FA)),
  ),
  (
    match: 'image',
    visual: _SkillVisual(Icons.image_outlined, Color(0xFFBF5AF2)),
  ),
  (
    match: 'screen',
    visual: _SkillVisual(Icons.desktop_windows_outlined, Color(0xFF64D2FF)),
  ),
];

const List<Color> _fallbackColors = [
  Color(0xFF4A8CFF),
  Color(0xFF30D158),
  Color(0xFFBF5AF2),
  Color(0xFFFF9F0A),
  Color(0xFF64D2FF),
  Color(0xFFFF6B66),
];

_SkillVisual _visualOf(GatewaySkill skill) {
  final key = skill.key.toLowerCase();
  for (final rule in _skillVisualRules) {
    if (key.contains(rule.match)) return rule.visual;
  }
  // 没有命中规则时用 key 做稳定哈希取色，保证同名技能每次颜色一致。
  final seed = key.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
  return _SkillVisual(
    Icons.extension_rounded,
    _fallbackColors[seed % _fallbackColors.length],
  );
}

// ==================== 组件 ====================

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : _Palette.chip,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : _Palette.muted,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _SkillTile extends StatelessWidget {
  const _SkillTile({
    required this.skill,
    required this.enabled,
    required this.interactive,
    required this.onToggle,
    required this.onTap,
  });

  final GatewaySkill skill;
  final bool enabled;
  final bool interactive;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = _visualOf(skill);
    // 状态标签跟开关同源：开关打开就一定是「就绪」，关闭才看要不要「需要设置」。
    final status = skillStatusOf(skill, enabled: enabled);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            _SkillAvatar(visual: visual),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    skill.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _Palette.title,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    skill.description?.trim().isNotEmpty == true
                        ? skill.description!.trim()
                        : skill.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _Palette.subtitle,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _StatusBadge(status: status),
            const SizedBox(width: 8),
            _SkillSwitch(
              value: enabled,
              interactive: interactive,
              onChanged: onToggle,
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillAvatar extends StatelessWidget {
  const _SkillAvatar({required this.visual});

  final _SkillVisual visual;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: visual.color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Icon(visual.icon, size: 20, color: visual.color),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final SkillStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SkillStatus.ready => _Palette.green,
      SkillStatus.needsSetup => _Palette.amber,
      SkillStatus.disabled => _Palette.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// 自绘开关：Material 的 Switch 在深色小尺寸下内边距偏大，
/// 这里按截图做成 46×28 的胶囊，关闭=灰轨灰点，开启=绿轨白点。
class _SkillSwitch extends StatelessWidget {
  const _SkillSwitch({
    required this.value,
    required this.interactive,
    required this.onChanged,
  });

  final bool value;
  final bool interactive;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      enabled: interactive,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: interactive ? () => onChanged(!value) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 46,
          height: 28,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? _Palette.green : _Palette.trackOff,
            borderRadius: BorderRadius.circular(100),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: value ? Colors.white : _Palette.knobOff,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 64),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: _Palette.chip,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: _Palette.muted),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _Palette.title,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _Palette.subtitle,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => onRetry!(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _Palette.title,
                  side: const BorderSide(color: Color(0xFF2B2B31)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 10,
                  ),
                ),
                child: const Text('重新加载'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 技能详情（点击列表项主体进入）。开关与列表共享同一套状态与操作。
class _SkillDetailSheet extends StatefulWidget {
  const _SkillDetailSheet({
    required this.viewModel,
    required this.skillKey,
    required this.onToggle,
  });

  final SkillViewModel viewModel;
  final String skillKey;
  final Future<void> Function(GatewaySkill skill, bool value) onToggle;

  @override
  State<_SkillDetailSheet> createState() => _SkillDetailSheetState();
}

class _SkillDetailSheetState extends State<_SkillDetailSheet> {
  bool? _pending;

  GatewaySkill? _find(List<GatewaySkill> skills) {
    for (final skill in skills) {
      if (skill.key == widget.skillKey) return skill;
    }
    return null;
  }

  Future<void> _toggle(GatewaySkill skill, bool value) async {
    setState(() => _pending = value);
    await widget.onToggle(skill, value);
    if (!mounted) return;
    setState(() => _pending = null);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final skill = _find(widget.viewModel.skills);
        if (skill == null) {
          return const SizedBox(
            height: 220,
            child: Center(
              child: Text(
                '技能已不存在，请刷新列表',
                style: TextStyle(color: _Palette.muted, fontSize: 14),
              ),
            ),
          );
        }

        final visual = _visualOf(skill);
        final enabled = _pending ?? skill.enabled;
        final status = skillStatusOf(skill, enabled: enabled);
        final description = skill.description?.trim();

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A3A3E),
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _SkillAvatar(visual: visual),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            skill.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _Palette.title,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            skill.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _Palette.subtitle,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _StatusBadge(status: status),
                  ],
                ),
                const SizedBox(height: 18),
                if (description != null && description.isNotEmpty)
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFFC7C7CC),
                      fontSize: 13.5,
                      height: 1.55,
                    ),
                  )
                else
                  const Text(
                    '该技能没有提供描述。',
                    style: TextStyle(
                      color: _Palette.subtitle,
                      fontSize: 13.5,
                      height: 1.55,
                    ),
                  ),
                if (status == SkillStatus.needsSetup) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _Palette.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: _Palette.amber,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            skill.missingLabels.isEmpty
                                ? '该技能已启用，但当前环境还跑不起来（依赖或密钥未就绪）。'
                                : '该技能已启用，但还缺少：\n${skill.missingLabels.join('\n')}',
                            style: const TextStyle(
                              color: _Palette.amber,
                              fontSize: 12.5,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                  decoration: BoxDecoration(
                    color: _Palette.chip,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '启用',
                          style: TextStyle(
                            color: _Palette.title,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      _SkillSwitch(
                        value: enabled,
                        interactive: !widget.viewModel.isLoading,
                        onChanged: (value) => _toggle(skill, value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: _Palette.muted,
                      minimumSize: const Size(0, 44),
                    ),
                    child: const Text('关闭'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
