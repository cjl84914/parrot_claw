import 'package:flutter/material.dart';
import 'package:parrot_app/data/model/gateway_skill.dart';
import 'package:parrot_app/ui/view_model/skill_viewmodel.dart';
import 'package:parrot_app/ui/widget/my_snack_bar.dart';

/// ClawHub 市场搜索页（深色，对齐 [SkillScreen] 的风格）。
///
/// 数据与操作全部走 [SkillViewModel]（它转发给 GatewayRepository）：
/// - [SkillViewModel.clawHubResults] 渲染搜索结果；
/// - [SkillViewModel.clawHubSearching] 控制搜索按钮的 loading；
/// - [SkillViewModel.clawHubReviewingSlug] 控制某一行的 loading；
/// - [SkillViewModel.clawHubError] / [SkillViewModel.clawHubMessage] 渲染提示卡；
/// - [SkillViewModel.clawHubSkillsAvailable] 决定网关是否支持这套能力；
/// - [SkillViewModel.skills] 用来判断某条结果是否**已经装过**。
///
/// 点「审核」只读取版本信息（`skills.detail`），不下载任何东西 ——
/// 真正的信任验证与安装都在网关侧，所以这里的按钮是「审核」而不是「安装」。
class SkillSearchScreen extends StatefulWidget {
  const SkillSearchScreen({super.key, required this.viewModel});

  final SkillViewModel viewModel;

  @override
  State<SkillSearchScreen> createState() => _SkillSearchScreenState();
}

class _SkillSearchScreenState extends State<SkillSearchScreen> {
  /// 进页面时的默认关键词：直接出结果，省得用户先对着空列表发呆。
  static const _initialQuery = '';

  late final TextEditingController _queryController;

  /// 已经弹过的那份审核信息，避免 ViewModel 每次通知都把弹窗重开一遍。
  GatewayClawHubInstallReview? _shownReview;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: _initialQuery);
    widget.viewModel.addListener(_onViewModelChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {});
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    _queryController.dispose();
    super.dispose();
  }

  /// 审核信息落地就弹确认框；被清空（取消 / 已安装）时复位，下次还能再弹。
  void _onViewModelChanged() {
    final review = widget.viewModel.clawHubInstallReview;
    if (review == null) {
      _shownReview = null;
      return;
    }
    if (identical(review, _shownReview)) return;
    _shownReview = review;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showReviewDialog(review);
    });
  }

  /// 点放大镜才发起显式搜索；输入框内容变化不自动打网关。
  Future<void> _search() async {
    FocusScope.of(context).unfocus();
    await widget.viewModel.searchClawHubSkills(_queryController.text);
  }

  Future<void> _review(GatewayClawHubSkillSummary skill) async {
    final ok = await widget.viewModel.reviewClawHubSkillInstall(skill);
    // 成功的情况交给监听器弹窗，这里只管失败提示。
    if (!mounted || ok) return;
    final error = widget.viewModel.clawHubError;
    if (error != null) MySnackBar.showError(context, error);
  }

  /// 详情确认框：「验证并安装」走网关校验安装，「取消」只关弹窗。
  Future<void> _showReviewDialog(GatewayClawHubInstallReview review) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (dialogContext) => _ReviewDialog(review: review),
    );
    if (!mounted) return;
    if (confirmed != true) {
      widget.viewModel.dismissClawHubSkillInstallReview();
      return;
    }
    final ok = await widget.viewModel.installClawHubSkill(
      slug: review.slug,
      version: review.version,
    );
    if (!mounted) return;
    if (!ok) {
      final error = widget.viewModel.clawHubError;
      if (error != null) MySnackBar.showError(context, error);
      return;
    }
    final message = widget.viewModel.clawHubMessage;
    if (message != null) MySnackBar.showSuccess(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.background,
      appBar: AppBar(title: const Text('在 ClawHub 上查找'), elevation: 0),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.viewModel,
          builder: (context, _) => _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final viewModel = widget.viewModel;
    final results = viewModel.clawHubResults;
    final available = viewModel.clawHubSkillsAvailable;
    final error = viewModel.clawHubError;
    final message = viewModel.clawHubMessage;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        _SearchPanel(
          controller: _queryController,
          searching: viewModel.clawHubSearching,
          enabled: available,
          onSearch: _search,
        ),
        if (!available) ...[
          const SizedBox(height: 12),
          const _HintLine(
            icon: Icons.system_update_alt_rounded,
            color: _Palette.amber,
            text: '当前网关不支持 ClawHub 搜索与安装，请升级 Gateway 后重试。',
          ),
        ],
        if (error != null || message != null) ...[
          const SizedBox(height: 12),
          _NoticeCard(error: error, message: message),
        ],
        if (viewModel.clawHubSearching && results.isEmpty) ...[
          const SizedBox(height: 28),
          const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: _Palette.muted,
              ),
            ),
          ),
        ] else if (results.isEmpty && error == null && message == null) ...[
          const SizedBox(height: 12),
          const _HintLine(
            icon: Icons.travel_explore_rounded,
            color: _Palette.muted,
            text: '输入关键词后点右侧放大镜，搜索 ClawHub 上可安装的技能。',
          ),
        ],
        if (results.isNotEmpty) ...[
          const SizedBox(height: 14),
          _ResultList(
            results: results,
            installedSkills: viewModel.skills,
            reviewingSlug: viewModel.clawHubReviewingSlug,
            installingSlugs: viewModel.clawHubInstallingSlugs,
            canInstall: viewModel.clawHubCanInstall,
            interactive: available && !viewModel.clawHubSearching,
            onReview: _review,
          ),
        ],
      ],
    );
  }
}

// ==================== 顶部搜索模块 ====================

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({
    required this.controller,
    required this.searching,
    required this.enabled,
    required this.onSearch,
  });

  final TextEditingController controller;
  final bool searching;
  final bool enabled;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        const Text(
          '搜索注册表元数据。Gateway 会在下载前再次验证信任状态。',
          style: TextStyle(
            color: _Palette.subtitle,
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: _Palette.chip,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _Palette.divider),
                ),
                alignment: Alignment.center,
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => onSearch(),
                  cursorColor: _Palette.title,
                  style: const TextStyle(color: _Palette.title, fontSize: 14),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '搜索 ClawHub',
                    hintStyle: TextStyle(color: _Palette.muted, fontSize: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _SearchButton(
              searching: searching,
              enabled: enabled,
              onTap: onSearch,
            ),
          ],
        ),
      ],
    );
  }
}

/// 圆形放大镜按钮：搜索中时换成转圈，并顺带挡住重复点击。
class _SearchButton extends StatelessWidget {
  const _SearchButton({
    required this.searching,
    required this.enabled,
    required this.onTap,
  });

  final bool searching;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !searching;
    return Semantics(
      button: true,
      enabled: active,
      label: searching ? '正在搜索' : '搜索',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: active ? onTap : null,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _Palette.chip,
            shape: BoxShape.circle,
            border: Border.all(color: _Palette.divider),
          ),
          child:
              searching
                  ? const Padding(
                    padding: EdgeInsets.all(13),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: _Palette.muted,
                    ),
                  )
                  : Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: active ? _Palette.title : _Palette.muted,
                  ),
        ),
      ),
    );
  }
}

// ==================== 结果列表 ====================

class _ResultList extends StatelessWidget {
  const _ResultList({
    required this.results,
    required this.installedSkills,
    required this.reviewingSlug,
    required this.installingSlugs,
    required this.canInstall,
    required this.interactive,
    required this.onReview,
  });

  final List<GatewayClawHubSkillSummary> results;
  final List<GatewaySkill> installedSkills;
  final String? reviewingSlug;
  final Set<String> installingSlugs;
  final bool canInstall;
  final bool interactive;
  final Future<void> Function(GatewayClawHubSkillSummary skill) onReview;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _Palette.sheet,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Palette.divider),
      ),
      child: Column(
        children: [
          for (var index = 0; index < results.length; index++) ...[
            if (index > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 66,
                color: _Palette.divider,
              ),
            _ResultTile(
              skill: results[index],
              installed: isClawHubSkillInstalled(
                installedSkills,
                results[index],
              ),
              reviewing: reviewingSlug == results[index].reference,
              installing: installingSlugs.contains(results[index].reference),
              canInstall: canInstall,
              interactive: interactive,
              onReview: onReview,
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.skill,
    required this.installed,
    required this.reviewing,
    required this.installing,
    required this.canInstall,
    required this.interactive,
    required this.onReview,
  });

  final GatewayClawHubSkillSummary skill;
  final bool installed;
  final bool reviewing;
  final bool installing;
  final bool canInstall;
  final bool interactive;
  final Future<void> Function(GatewayClawHubSkillSummary skill) onReview;

  @override
  Widget build(BuildContext context) {
    // 「已安装」是终态：不再提供动作，只做弱化展示。
    final state =
        installed
            ? _TileState.installed
            : installing
            ? _TileState.installing
            : reviewing
            ? _TileState.loading
            : skill.canReadDetails
            ? _TileState.review
            : _TileState.install;
    // 「只能直接安装」的来源点一下就直接装，没有 admin 就别给可点的假象。
    final canAct =
        interactive &&
        !installed &&
        !reviewing &&
        !installing &&
        (skill.canReadDetails || canInstall);

    return InkWell(
      onTap: canAct ? () => onReview(skill) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            _BadgeAvatar(text: skillBadge(skill.displayName)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    skill.displayName,
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
                    skill.summary?.trim().isNotEmpty == true
                        ? skill.summary!.trim()
                        : skill.reference,
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
            _StateButton(
              state: state,
              enabled: canAct,
              onTap: () => onReview(skill),
            ),
          ],
        ),
      ),
    );
  }
}

/// 圆形缩写标记：取标题前两段的头字母（`Youdao Note Web` → `YN`）。
///
/// 与 Android `skillBadge` 同一套规则，保证同一技能在两个端上缩写字一样。
String skillBadge(String name) {
  final letters = <String>[];
  for (final part in name.split(RegExp(r'[ \-_]'))) {
    if (part.trim().isEmpty) continue;
    letters.add(part.trim().characters.first.toUpperCase());
    if (letters.length == 2) break;
  }
  return letters.isEmpty ? 'S' : letters.join();
}

class _BadgeAvatar extends StatelessWidget {
  const _BadgeAvatar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _Palette.chip,
        shape: BoxShape.circle,
        border: Border.all(color: _Palette.divider),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _Palette.title,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// 行尾状态按钮 —— 是按钮不是开关，所以用矩形圆角而不是胶囊。
enum _TileState {
  review('审核'),
  install('安装'),
  loading('加载中'),
  installing('安装中'),
  installed('已安装');

  const _TileState(this.label);

  final String label;
}

class _StateButton extends StatelessWidget {
  const _StateButton({
    required this.state,
    required this.enabled,
    required this.onTap,
  });

  final _TileState state;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 「已安装」整块弱化：底色、描边、文字都比「审核」低一档。
    final installed = state == _TileState.installed;
    final background =
        installed ? _Palette.chip.withValues(alpha: 0.55) : _Palette.chip;
    final border = installed ? _Palette.divider : _Palette.outline;
    final textColor = switch (state) {
      _TileState.installed => _Palette.grey,
      _TileState.loading || _TileState.installing => _Palette.muted,
      _TileState.review ||
      _TileState.install => enabled ? _Palette.title : _Palette.muted,
    };

    return Semantics(
      button: true,
      enabled: enabled,
      label: state.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Text(
            state.label,
            style: TextStyle(
              color: textColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== 详情确认弹窗 ====================

/// 「查看 ClawHub 技能」确认框。
///
/// 只负责展示与「装 / 不装」的二选一，`pop(true)` 表示验证并安装 ——
/// 真正的校验在网关侧，这里不下载任何东西，所以文案强调「校验」而不是「下载」。
class _ReviewDialog extends StatelessWidget {
  const _ReviewDialog({required this.review});

  final GatewayClawHubInstallReview review;

  @override
  Widget build(BuildContext context) {
    final summary = review.summary?.trim();

    return Dialog(
      backgroundColor: _Palette.sheet,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '查看 ClawHub 技能',
              style: TextStyle(
                color: _Palette.title,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              review.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            if (summary != null && summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                summary,
                style: const TextStyle(
                  color: Color(0xFFC7C7CC),
                  fontSize: 13.5,
                  height: 1.55,
                ),
              ),
            ],
            const SizedBox(height: 18),
            _MetaLine(label: '版本', value: review.version),
            const SizedBox(height: 12),
            _MetaLine(label: '发布者', value: review.author),
            const SizedBox(height: 18),
            const Text(
              'Gateway 会在下载前向 ClawHub 校验此具体版本。审查结果会显示在安装结果中。'
              '被阻止的版本或无法进行安全校验将阻止安装。',
              style: TextStyle(
                color: _Palette.muted,
                fontSize: 12.5,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: '取消',
                    primary: false,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DialogButton(
                    label: '验证并安装',
                    primary: true,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 元数据一行：标签在上、值在下。
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _Palette.muted,
            fontSize: 11.5,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: _Palette.title,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// 弹窗底部按钮：次要的只留文字，主要的给一块填充。
class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? _Palette.button : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: primary ? _Palette.outline : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: primary ? Colors.white : _Palette.muted,
              fontSize: 14,
              fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== 提示 ====================

class _HintLine extends StatelessWidget {
  const _HintLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 12.5, height: 1.45),
          ),
        ),
      ],
    );
  }
}

/// 错误 / 提示卡：搜索失败走红色，无结果走灰色。
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.error, required this.message});

  final String? error;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final isError = error != null;
    final accent = isError ? _Palette.red : _Palette.muted;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              (error ?? message)!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: accent, fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

abstract final class _Palette {
  static const background = Color(0xFF000000);
  static const sheet = Color(0xFF141416);
  static const chip = Color(0xFF1C1C1F);
  static const divider = Color(0xFF1F1F23);

  /// 按钮描边，比分割线亮一档，才能在纯黑底上看出一条边。
  static const outline = Color(0xFF3A3A3E);

  /// 弹窗主按钮的填充色：比卡片亮、比描边暗，压得住但不像选中态那么跳。
  static const button = Color(0xFF2E2E33);
  static const title = Color(0xFFF2F2F4);
  static const muted = Color(0xFF9B9BA1);
  static const subtitle = Color(0xFF8E8E93);
  static const grey = Color(0xFF6E6E73);
  static const amber = Color(0xFFFFD60A);
  static const red = Color(0xFFFF6B66);
}
