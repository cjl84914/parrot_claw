import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/model/gateway_cron.dart';
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/view_model/cron_viewmodel.dart';
import 'package:parrot_app/ui/widget/my_snack_bar.dart';

/// 「定时任务 · 编辑 / 新建」页。
///
/// 数据与操作走 [CronViewModel]（它转发给 GatewayRepository）：
/// - 传 [job] 为编辑（回填名称 / 提示词 / 模型 / 计划），为空为新建；
/// - 「保存更改」按有无 [job] 走 `cron.add` / `cron.update`；
/// - 「运行历史」tab 调 [CronViewModel.loadRuns] 并渲染 `cron.runs`。
///
/// 表单风格对齐 `server_edit_screen.dart`：全局主题（`AppColors` /
/// `AppTextStyles` / `AppRadius`）+ 无边框浮动标签输入框 + 胶囊按钮。
class CronEditScreen extends StatefulWidget {
  const CronEditScreen({super.key, required this.viewModel, this.job});

  final CronViewModel viewModel;

  /// 为空表示新建任务。
  final GatewayCronJob? job;

  @override
  State<CronEditScreen> createState() => _CronEditScreenState();
}

class _CronEditScreenState extends State<CronEditScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _promptController = TextEditingController();
  final _modelController = TextEditingController(
    text: GatewayCronDraft.defaultModelLabel,
  );
  final _intervalController = TextEditingController(text: '30');
  final _unitController = TextEditingController(text: '分');
  final _cronController = TextEditingController(text: '0 9 * * *');
  final _timezoneController = TextEditingController(text: 'Asia/Shanghai');
  final _runAtController = TextEditingController();

  int _tab = 0;

  /// 任务是否启用（关闭后网关不再按计划触发）。
  bool _enabled = true;

  /// 「下次运行」倒计时用的秒级刷新（仅编辑已有任务时开）。
  Timer? _ticker;

  /// 「重复」当前选中的模式：间隔 / 单次 / Cron。
  String _repeat = '单次';

  /// 「单次」模式下的运行时间。
  late DateTime _singleRunAt;

  static const _unitOptions = ['秒', '分', '时', '天'];
  static const _timezoneOptions = [
    'Asia/Shanghai',
    'UTC',
    'Asia/Tokyo',
    'America/New_York',
  ];

  @override
  void initState() {
    super.initState();
    final job = widget.job;
    if (job == null) {
      _singleRunAt = _defaultRunAt();
    } else {
      _applyJob(job);
    }
    _runAtController.text = formatCronDateTime(_singleRunAt);

    // 已有任务带「下次运行」时间，秒级刷新让倒计时保持正确。
    if (job?.nextRunAt != null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }

    // 「模型」下拉列的是网关实际可用的模型（models.list），不是写死的几项。
    unawaited(_loadModels());
  }

  /// 拉一次模型列表；回来后重建，让下拉立刻拿到真实选项。
  Future<void> _loadModels() async {
    await widget.viewModel.loadModels();
    if (mounted) setState(() {});
  }

  /// 「模型」下拉的选项：`默认` + 网关实际可用的模型。
  ///
  /// 值就是写进 `payload.model` 的模型 id（与聊天页的模型菜单同源，
  /// 都取自 `models.list`）。当前任务已存的模型若不在列表里（网关换了模型
  /// 配置，或列表还没拉回来），也补进去，避免看起来像「值丢了」。
  List<String> get _modelOptions {
    const fallback = GatewayCronDraft.defaultModelLabel;
    final ids =
        <String>[
          for (final model in widget.viewModel.rawModels ?? const [])
            if (model is Map) model['id']?.toString().trim() ?? '',
        ].where((id) => id.isNotEmpty && id != fallback).toSet().toList();

    final current = _modelController.text.trim();
    return [
      fallback,
      if (current.isNotEmpty && current != fallback && !ids.contains(current))
        current,
      ...ids,
    ];
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _nameController.dispose();
    _promptController.dispose();
    _modelController.dispose();
    _intervalController.dispose();
    _unitController.dispose();
    _cronController.dispose();
    _timezoneController.dispose();
    _runAtController.dispose();
    super.dispose();
  }

  /// 新建时默认「下一个整点」。
  DateTime _defaultRunAt() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour + 1);
  }

  /// 用已有任务回填表单。
  void _applyJob(GatewayCronJob job) {
    _nameController.text = job.name ?? '';
    _promptController.text = job.prompt ?? '';
    _modelController.text = job.model ?? GatewayCronDraft.defaultModelLabel;
    _enabled = job.isEnabled;

    final schedule = job.schedule;
    switch (schedule?.kind) {
      case GatewayCronSchedule.kindAt:
        _repeat = '单次';
        _singleRunAt =
            DateTime.tryParse(schedule?.at ?? '')?.toLocal() ?? _defaultRunAt();
      case GatewayCronSchedule.kindEvery:
        _repeat = '间隔';
        _applyInterval(schedule?.everyMs);
        _singleRunAt = _defaultRunAt();
      case GatewayCronSchedule.kindCron:
        _repeat = 'Cron';
        _cronController.text = schedule?.expr ?? '';
        if ((schedule?.tz ?? '').isNotEmpty) {
          _timezoneController.text = schedule!.tz!;
        }
        _singleRunAt = _defaultRunAt();
      default:
        _singleRunAt = _defaultRunAt();
    }
  }

  /// 毫秒间隔 → 数值 + 单位（取能整除的最大单位）。
  void _applyInterval(int? ms) {
    if (ms == null || ms <= 0) return;
    const day = 86400000;
    const hour = 3600000;
    const minute = 60000;
    const second = 1000;
    if (ms % day == 0) {
      _intervalController.text = '${ms ~/ day}';
      _unitController.text = '天';
    } else if (ms % hour == 0) {
      _intervalController.text = '${ms ~/ hour}';
      _unitController.text = '时';
    } else if (ms % minute == 0) {
      _intervalController.text = '${ms ~/ minute}';
      _unitController.text = '分';
    } else {
      _intervalController.text = '${ms ~/ second}';
      _unitController.text = '秒';
    }
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.cron);
    }
  }

  void _selectTab(int index) {
    if (_tab == index) return;
    setState(() => _tab = index);
    final job = widget.job;
    if (index == 1 && job != null) {
      widget.viewModel.loadRuns(job.id);
    }
  }

  /// 表单 → 网关 `schedule`。
  GatewayCronSchedule _buildSchedule() {
    switch (_repeat) {
      case '间隔':
        final value = int.tryParse(_intervalController.text.trim()) ?? 1;
        return GatewayCronSchedule(
          kind: GatewayCronSchedule.kindEvery,
          everyMs: value * _unitMilliseconds(_unitController.text),
        );
      case 'Cron':
        return GatewayCronSchedule(
          kind: GatewayCronSchedule.kindCron,
          expr: _cronController.text.trim(),
          tz: _timezoneController.text.trim(),
        );
      default:
        return GatewayCronSchedule(
          kind: GatewayCronSchedule.kindAt,
          at: _singleRunAt.toUtc().toIso8601String(),
        );
    }
  }

  int _unitMilliseconds(String unit) {
    switch (unit) {
      case '秒':
        return 1000;
      case '时':
        return 3600000;
      case '天':
        return 86400000;
      case '分':
      default:
        return 60000;
    }
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    final job = widget.job;
    final draft = GatewayCronDraft(
      name: _nameController.text.trim(),
      prompt: _promptController.text.trim(),
      schedule: _buildSchedule(),
      enabled: _enabled,
      model: _modelController.text,
      // 编辑时保留原描述 / 智能体绑定 / payload 类型与未暴露字段。
      description: job?.description,
      agentId: job?.agentId,
      payloadKind: job?.payloadKind,
      basePayload: job?.payload ?? const <String, dynamic>{},
    );

    final ok =
        job == null
            ? await widget.viewModel.add(draft.toAddPayload())
            : await widget.viewModel.update(job.id, draft.toPatch());
    if (!mounted) return;
    if (!ok) {
      MySnackBar.showError(context, widget.viewModel.error ?? '保存失败');
      return;
    }
    MySnackBar.showSuccess(context, job == null ? '任务已创建' : '任务已保存');
    _close();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: _close,
        ),
        title: Text(widget.job == null ? '新建任务' : '编辑任务'),
      ),
      body: Column(
        children: [
          _buildTabs(),
          Expanded(child: _tab == 0 ? _buildSettingsTab() : _buildHistoryTab()),
        ],
      ),
      // 底部操作栏属于「设置」表单：切到「运行历史」时整条隐藏，
      // 避免在只读的运行记录里出现「保存更改」。
      bottomNavigationBar:
          _tab == 0
              ? ListenableBuilder(
                listenable: widget.viewModel,
                builder: (context, _) => _buildBottomBar(),
              )
              : null,
    );
  }

  // ==================== 顶部导航 ====================

  Widget _buildTabs() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          _TabButton(
            label: '设置',
            selected: _tab == 0,
            onTap: () => _selectTab(0),
          ),
          _TabButton(
            label: '运行历史',
            selected: _tab == 1,
            onTap: () => _selectTab(1),
          ),
        ],
      ),
    );
  }

  // ==================== 设置 ====================

  Widget _buildSettingsTab() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _buildEnableRow(),
          _buildCard([
            _buildTextField(
              controller: _nameController,
              label: '名称',
              hint: '给任务起个名字',
              icon: Icons.label_outline,
              validator:
                  (v) => (v == null || v.trim().isEmpty) ? '请输入名称' : null,
            ),
            _buildTextField(
              controller: _promptController,
              label: '提示词',
              icon: Icons.notes_outlined,
              maxLines: 4,
              validator:
                  (v) => (v == null || v.trim().isEmpty) ? '请输入提示词' : null,
            ),
            _buildSelectField(
              value: _modelController.text,
              label: '模型',
              icon: Icons.memory_outlined,
              options: _modelOptions,
              onChanged: (value) {
                if (value == null) return;
                setState(() => _modelController.text = value);
              },
            ),
          ]),
          _buildCard([
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: '间隔', label: Text('间隔')),
                  ButtonSegment(value: '单次', label: Text('单次')),
                  ButtonSegment(value: 'Cron', label: Text('Cron')),
                ],
                selected: {_repeat},
                onSelectionChanged: (s) => setState(() => _repeat = s.first),
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(AppTextStyles.bodyMedium),
                ),
              ),
            ),
            ..._buildRepeatDetail(),
          ]),
        ],
      ),
    );
  }

  // ==================== 重复（间隔 / 单次 / Cron） ====================

  Future<void> _pickSingleTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _singleRunAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_singleRunAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _singleRunAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _runAtController.text = formatCronDateTime(_singleRunAt);
    });
  }

  /// 「重复」下方随模式变化的输入区。
  List<Widget> _buildRepeatDetail() {
    switch (_repeat) {
      case '间隔':
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _intervalController,
                  label: '间隔',
                  hint: '数值',
                  icon: Icons.timer_outlined,
                  keyboardType: TextInputType.number,
                  validator:
                      (v) =>
                          (v == null || v.trim().isEmpty) ? '请输入间隔' : null,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 112,
                child: _buildSelectField(
                  value: _unitController.text,
                  label: '单位',
                  icon: Icons.schedule_outlined,
                  options: _unitOptions,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _unitController.text = value);
                  },
                ),
              ),
            ],
          ),
        ];
      case 'Cron':
        return [
          _buildTextField(
            controller: _cronController,
            label: 'Cron 表达式',
            hint: '0 9 * * *',
            icon: Icons.code,
            validator:
                (v) => (v == null || v.trim().isEmpty) ? '请输入表达式' : null,
          ),
          _buildSelectField(
            value: _timezoneController.text,
            label: '时区',
            icon: Icons.public,
            options: _timezoneOptions,
            onChanged: (value) {
              if (value == null) return;
              setState(() => _timezoneController.text = value);
            },
          ),
        ];
      // 单次（及其他未知值）
      default:
        return [
          _buildTextField(
            controller: _runAtController,
            label: '运行时间',
            icon: Icons.event_outlined,
            readOnly: true,
            onTap: _pickSingleTime,
            suffixIcon: const Icon(
              Icons.expand_more,
              size: 20,
              color: AppColors.textSecondary,
            ),
            validator:
                (v) => (v == null || v.trim().isEmpty) ? '请选择运行时间' : null,
          ),
          _buildHelpText('在 ${formatCronDateTime(_singleRunAt)} 运行一次'),
        ];
    }
  }

  // ==================== 运行历史 ====================

  Widget _buildHistoryTab() {
    final job = widget.job;
    if (job == null) {
      return _buildHistoryEmpty('任务保存后，这里会显示每次执行的时间与结果。');
    }
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final viewModel = widget.viewModel;
        final runs =
            viewModel.runs.map(GatewayCronRun.fromJson).toList(growable: false);
        if (runs.isEmpty && viewModel.isLoading) {
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2.5),
          );
        }
        if (runs.isEmpty) {
          return _buildHistoryEmpty(
            viewModel.error ?? '暂无运行记录。任务运行后，这里会显示每次执行的时间与结果。',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: runs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) => _RunTile(run: runs[index]),
        );
      },
    );
  }

  Widget _buildHistoryEmpty(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 64),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.history_rounded,
              size: 28,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 14),
            Text('暂无运行记录', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 底部按钮 ====================

  Widget _buildBottomBar() {
    final busy = widget.viewModel.isLoading;
    final isCreate = widget.job == null;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _close,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.round),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('取消'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.round),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(isCreate ? '创建任务' : '保存更改'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== UI 构建辅助（对齐 server_edit_screen） ====================

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
    required IconData icon,
    String? hint,
    String? helper,
    bool readOnly = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    VoidCallback? onTap,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onTap: onTap,
      style: AppTextStyles.bodyMedium,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 4,
        suffixIcon: suffixIcon,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        labelStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textTertiary,
        ),
        helperStyle: AppTextStyles.caption,
        errorStyle: AppTextStyles.captionSmall.copyWith(
          color: AppColors.error,
        ),
      ),
      validator: validator,
    );
  }

  /// 下拉选择字段：外观与普通输入框一致（`InputDecorator` 提供浮动标签 +
  /// 无边框），控件本身用 Material 自带的 `DropdownButton`，与
  /// `setting_screen.dart` 的下拉一致（`isExpanded: true` + 文本溢出省略）。
  Widget _buildSelectField({
    required String value,
    required String label,
    required IconData icon,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    String? helper,
  }) {
    // 已存的值可能不在候选里（网关换了模型配置 / 列表还没拉回来），
    // 补进去，否则 `DropdownButton` 会因「value 不在 items 中」直接断言失败。
    final items = <String>[
      if (value.isNotEmpty && !options.contains(value)) value,
      ...options,
    ];
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 4,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        labelStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
        helperStyle: AppTextStyles.caption,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : null,
          isExpanded: true,
          isDense: true,
          icon: const Icon(
            Icons.expand_more,
            size: 20,
            color: AppColors.textSecondary,
          ),
          style: AppTextStyles.bodyMedium,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          items: [
            for (final option in items)
              DropdownMenuItem<String>(
                value: option,
                child: Text(
                  option,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  /// 启用行：`[开关] 已启用  Every 1分钟 · 下次 39秒后`（左对齐）。
  Widget _buildEnableRow() {
    final schedule = _buildSchedule().label.trim();
    final next = widget.job?.nextRunAt;
    final meta = [
      if (schedule.isNotEmpty) schedule,
      if (next != null) '下次 ${_relativeUntil(next)}',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          _Toggle(
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          const SizedBox(width: 10),
          Text(
            _enabled ? '已启用' : '已关闭',
            style: AppTextStyles.bodyMedium.copyWith(
              color: _enabled ? _Toggle.green : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 相对时间：`39秒后` / `5分钟后` / `2小时后` / `3天后`。
  String _relativeUntil(DateTime target) {
    final diff = target.difference(DateTime.now());
    if (diff.isNegative) return '即将运行';
    if (diff.inSeconds < 60) return '${diff.inSeconds}秒后';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟后';
    if (diff.inHours < 24) return '${diff.inHours}小时后';
    return '${diff.inDays}天后';
  }

  Widget _buildHelpText(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Text(text, style: AppTextStyles.caption),
    );
  }
}

// ==================== 基础组件 ====================

/// 自绘开关：与 `skill_screen` 的 `_SkillSwitch` 同款
/// （46×28 胶囊，关闭=灰轨灰点，开启=绿轨白点）。
class _Toggle extends StatelessWidget {
  const _Toggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  static const green = Color(0xFF30D158);
  static const trackOff = Color(0xFF333336);
  static const knobOff = Color(0xFF8E8E93);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 46,
          height: 28,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? green : trackOff,
            borderRadius: BorderRadius.circular(AppRadius.round),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: value ? Colors.white : knobOff,
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

/// 一条运行记录。
class _RunTile extends StatelessWidget {
  const _RunTile({required this.run});

  final GatewayCronRun run;

  @override
  Widget build(BuildContext context) {
    final status = run.status ?? 'unknown';
    final color = _statusColor(status);
    final startedAt = run.startedAt;
    final durationMs = run.durationMs;
    final error = run.error;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      status,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (startedAt != null)
                      Text(
                        formatCronDateTime(startedAt),
                        style: AppTextStyles.caption,
                      ),
                  ],
                ),
                if (durationMs != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '耗时 ${humanCronInterval(durationMs)}',
                    style: AppTextStyles.caption,
                  ),
                ],
                if (error != null && error.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    error,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'ok':
      case 'success':
        return AppColors.online;
      case 'fail':
      case 'failed':
      case 'error':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style:
              (selected ? AppTextStyles.titleMedium : AppTextStyles.bodyMedium)
                  .copyWith(
                    color: selected ? primary : AppColors.textSecondary,
                  ),
        ),
      ),
    );
  }
}
