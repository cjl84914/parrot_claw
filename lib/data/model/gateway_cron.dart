/// 网关 Cron（定时任务）模型。
///
/// 结构对齐网关 `cron.*` 工具调用：
/// - `schedule`：`at`（一次性）/ `every`（固定间隔）/ `cron`（表达式）；
/// - `payload`：`agentTurn`（隔离会话，`message`）/ `systemEvent`（主会话，`text`）；
/// - `delivery`：`announce` / `none`，可带 `channel` / `to`；
/// - 运行态在 `state` 里：`nextRunAtMs` / `lastRunAtMs` / `lastRunStatus` 等。
///
/// 解析一律「多候选键 + 容错」：网关版本之间字段名有出入（`id`/`jobId`、
/// `expr`/`cron`、`message`/`text`），拿不准的一律退化为 null，不抛异常。
library;

// ==================== 调度 ====================

/// 任务调度计划（`schedule`）。
class GatewayCronSchedule {
  const GatewayCronSchedule({
    required this.kind,
    this.at,
    this.everyMs,
    this.expr,
    this.tz,
  });

  static const kindAt = 'at';
  static const kindEvery = 'every';
  static const kindCron = 'cron';

  /// `at` / `every` / `cron`。
  final String kind;

  /// `at`：ISO 8601 时间戳。
  final String? at;

  /// `every`：间隔毫秒。
  final int? everyMs;

  /// `cron`：5 字段表达式。
  final String? expr;

  /// `cron`：IANA 时区；省略则用网关主机的本地时区。
  final String? tz;

  factory GatewayCronSchedule.fromJson(Map<String, dynamic> json) {
    return GatewayCronSchedule(
      kind: _text(json['kind'] ?? json['type']) ?? '',
      at: _text(json['at']),
      everyMs: _int(json['everyMs'] ?? json['every']),
      expr: _text(json['expr'] ?? json['cron'] ?? json['expression']),
      tz: _text(json['tz'] ?? json['timezone']),
    );
  }

  /// 反向：构造 `cron.add` / `cron.update` 里的 `schedule`。
  Map<String, dynamic> toJson() {
    switch (kind) {
      case kindAt:
        return {'kind': kindAt, if (at != null) 'at': at};
      case kindEvery:
        return {'kind': kindEvery, if (everyMs != null) 'everyMs': everyMs};
      default:
        return {
          'kind': kindCron,
          if (expr != null) 'expr': expr,
          if (tz != null) 'tz': tz,
        };
    }
  }

  /// 人类可读：`2026/12/10 09:00` / `Every 30分` / `0 9 * * *`。
  String get label {
    switch (kind) {
      case kindAt:
        final parsed = _parseTime(at);
        return parsed == null ? (at ?? '') : formatCronDateTime(parsed);
      case kindEvery:
        final ms = everyMs;
        return ms == null ? 'Every' : 'Every ${humanCronInterval(ms)}';
      default:
        return expr ?? '';
    }
  }
}

// ==================== 任务 ====================

class GatewayCronJob {
  const GatewayCronJob({
    required this.id,
    this.name,
    this.enabled,
    this.schedule,
    this.payload = const <String, dynamic>{},
    this.description,
    this.agentId,
    this.status,
    this.lastRunStatus,
    this.nextRunAt,
    this.lastRunAt,
    this.raw = const <String, dynamic>{},
  });

  final String id;
  final String? name;
  final bool? enabled;

  /// 调度计划；网关未返回时为 null。
  final GatewayCronSchedule? schedule;

  /// 原始 payload（`agentTurn` / `systemEvent`），编辑时作为合并基底。
  final Map<String, dynamic> payload;

  final String? description;

  /// 绑定的智能体 ID；缺省表示回退到默认智能体。
  final String? agentId;

  /// 计算态：`disabled` / `running` / `ok` / `error` / `skipped` / `idle`。
  final String? status;

  /// 最近一次执行结果：`ok` / `error` / `skipped`。
  final String? lastRunStatus;

  final DateTime? nextRunAt;
  final DateTime? lastRunAt;

  final Map<String, dynamic> raw;

  factory GatewayCronJob.fromJson(Map<String, dynamic> json) {
    final state =
        json['state'] is Map
            ? (json['state'] as Map).cast<String, dynamic>()
            : const <String, dynamic>{};
    final id =
        (json['id'] ?? json['jobId'] ?? json['key'])?.toString().trim() ?? '';
    return GatewayCronJob(
      id: id,
      name: (json['name'] ?? json['title'])?.toString(),
      enabled: _bool(json['enabled']),
      schedule: _scheduleFromJson(json),
      payload:
          json['payload'] is Map
              ? (json['payload'] as Map).cast<String, dynamic>()
              : const <String, dynamic>{},
      description: _text(json['description']),
      agentId: _text(json['agentId'] ?? json['agent']),
      status: _text(json['status']),
      lastRunStatus: _text(state['lastRunStatus'] ?? json['lastRunStatus']),
      nextRunAt: _parseTime(
        state['nextRunAtMs'] ??
            json['nextRunAtMs'] ??
            state['nextRunAt'] ??
            json['nextRunAt'],
      ),
      lastRunAt: _parseTime(
        state['lastRunAtMs'] ??
            json['lastRunAtMs'] ??
            state['lastRunAt'] ??
            json['lastRunAt'],
      ),
      raw: Map<String, dynamic>.from(json),
    );
  }

  /// 是否启用：优先显式 `enabled`，否则按计算态 `disabled` 反推；
  /// 两者都没有时按「启用」呈现，避免把未知状态误报成已关闭。
  bool get isEnabled {
    final explicit = enabled;
    if (explicit != null) return explicit;
    final state = status;
    return state == null || state != 'disabled';
  }

  /// 提示词：隔离任务取 `payload.message`，主会话任务取 `payload.text`。
  String? get prompt => _text(payload['message'] ?? payload['text']);

  /// 任务级模型覆盖；为空表示用默认模型。
  String? get model => _text(payload['model']);

  /// payload 类型：`agentTurn` / `systemEvent`。
  String? get payloadKind => _text(payload['kind']);

  /// 展示用的最近结果：优先 `lastRunStatus`，退回计算态。
  String? get displayStatus => lastRunStatus ?? status;

  /// 列表展示名：没名字就退回 id。
  String get title {
    final text = _text(name);
    return text ?? id;
  }
}

class GatewayCronList {
  final List<GatewayCronJob> jobs;
  final Map<String, dynamic> raw;

  const GatewayCronList({this.jobs = const [], this.raw = const {}});

  factory GatewayCronList.fromJson(Map<String, dynamic> json) {
    final rawJobs = json['jobs'] ?? json['items'] ?? json['entries'];
    final jobs =
        rawJobs is List
            ? rawJobs
                .whereType<Map>()
                .map(
                  (item) =>
                      GatewayCronJob.fromJson(item.cast<String, dynamic>()),
                )
                .where((job) => job.id.isNotEmpty)
                .toList(growable: false)
            : const <GatewayCronJob>[];
    return GatewayCronList(jobs: jobs, raw: Map<String, dynamic>.from(json));
  }
}

// ==================== 运行记录 ====================

/// 一条运行记录（`cron.runs` 返回的 entry）。
class GatewayCronRun {
  const GatewayCronRun({
    this.id,
    this.status,
    this.startedAt,
    this.durationMs,
    this.error,
    this.raw = const <String, dynamic>{},
  });

  final String? id;

  /// `ok` / `error` / `skipped`。
  final String? status;

  final DateTime? startedAt;
  final int? durationMs;

  /// 失败原因（若有）。
  final String? error;

  final Map<String, dynamic> raw;

  factory GatewayCronRun.fromJson(Map<String, dynamic> json) {
    final state =
        json['state'] is Map
            ? (json['state'] as Map).cast<String, dynamic>()
            : const <String, dynamic>{};
    return GatewayCronRun(
      id: _text(json['runId'] ?? json['id']),
      status: _text(json['status'] ?? state['status'] ?? json['lastRunStatus']),
      startedAt: _parseTime(
        json['startedAtMs'] ??
            json['runAtMs'] ??
            json['atMs'] ??
            json['tsMs'] ??
            json['createdAtMs'] ??
            json['startedAt'] ??
            json['at'] ??
            json['ts'],
      ),
      durationMs: _int(json['durationMs'] ?? state['durationMs']),
      error: _text(
        json['error'] ?? json['errorMessage'] ?? json['reason'] ?? json['message'],
      ),
      raw: Map<String, dynamic>.from(json),
    );
  }
}

class GatewayCronRuns {
  final List<Map<String, dynamic>> entries;
  final Map<String, dynamic> raw;

  const GatewayCronRuns({this.entries = const [], this.raw = const {}});

  factory GatewayCronRuns.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'] ?? json['runs'] ?? json['items'];
    final entries =
        rawEntries is List
            ? rawEntries
                .whereType<Map>()
                .map((item) => item.cast<String, dynamic>())
                .toList(growable: false)
            : const <Map<String, dynamic>>[];
    return GatewayCronRuns(
      entries: entries,
      raw: Map<String, dynamic>.from(json),
    );
  }
}

// ==================== 表单 → 请求 ====================

/// 编辑表单 → `cron.add` payload / `cron.update` patch 的构造器。
///
/// `payload.kind` 与 `sessionTarget` 必须匹配：主会话配 `systemEvent`、
/// 隔离会话配 `agentTurn`。界面上「提示词在独立会话中启动智能体运行」对应
/// 隔离会话，因此新建一律走 `isolated` + `agentTurn`。
class GatewayCronDraft {
  const GatewayCronDraft({
    required this.name,
    required this.prompt,
    required this.schedule,
    this.enabled = true,
    this.model,
    this.description,
    this.agentId,
    this.payloadKind,
    this.basePayload = const <String, dynamic>{},
  });

  static const sessionTargetMain = 'main';
  static const sessionTargetIsolated = 'isolated';
  static const payloadSystemEvent = 'systemEvent';
  static const payloadAgentTurn = 'agentTurn';

  /// 界面上「默认」表示不覆盖模型。
  static const defaultModelLabel = '默认';

  final String name;
  final String prompt;
  final GatewayCronSchedule schedule;

  /// 任务是否启用；关闭后网关不再按计划触发。
  final bool enabled;

  /// 任务级模型；空 / 「默认」表示不覆盖。
  final String? model;

  final String? description;
  final String? agentId;

  /// 编辑已有任务时保留原 payload 类型，避免把主会话任务改成隔离任务。
  final String? payloadKind;

  /// 编辑时原有 payload，作为合并基底（保留 timeoutSeconds 等未暴露字段）。
  final Map<String, dynamic> basePayload;

  /// 新建：完整 payload。
  Map<String, dynamic> toAddPayload() {
    final kind = payloadKind ?? payloadAgentTurn;
    return {
      'name': name,
      'schedule': schedule.toJson(),
      'sessionTarget':
          kind == payloadSystemEvent ? sessionTargetMain : sessionTargetIsolated,
      'payload': _mergedPayload(kind),
      if (description != null && description!.isNotEmpty)
        'description': description,
      if (agentId != null && agentId!.isNotEmpty) 'agentId': agentId,
      'enabled': enabled,
    };
  }

  /// 编辑：只补丁表单能改的字段（名称 / 计划 / payload / 启用状态）。
  Map<String, dynamic> toPatch() {
    final kind = payloadKind ?? _text(basePayload['kind']) ?? payloadAgentTurn;
    return {
      'name': name,
      'schedule': schedule.toJson(),
      'payload': _mergedPayload(kind),
      'enabled': enabled,
    };
  }

  Map<String, dynamic> _mergedPayload(String kind) {
    final payload = <String, dynamic>{...basePayload, 'kind': kind};
    if (kind == payloadSystemEvent) {
      payload['text'] = prompt;
      payload.remove('message');
    } else {
      payload['message'] = prompt;
      payload.remove('text');
    }
    final trimmed = model?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == defaultModelLabel) {
      payload.remove('model');
    } else {
      payload['model'] = trimmed;
    }
    return payload;
  }
}

// ==================== 解析辅助 ====================

GatewayCronSchedule? _scheduleFromJson(Map<String, dynamic> json) {
  final raw = json['schedule'];
  if (raw is Map) {
    return GatewayCronSchedule.fromJson(raw.cast<String, dynamic>());
  }
  final kind = _text(json['scheduleKind'] ?? json['scheduleType']);
  return kind == null ? null : GatewayCronSchedule(kind: kind);
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return (text == null || text.isEmpty) ? null : text;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

bool? _bool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  switch (value?.toString().toLowerCase()) {
    case 'true':
      return true;
    case 'false':
      return false;
    default:
      return null;
  }
}

/// 毫秒时间戳或 ISO 8601 字符串 → 本地时间。
DateTime? _parseTime(Object? value) {
  if (value == null) return null;
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  final ms = int.tryParse(text);
  if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
  return DateTime.tryParse(text)?.toLocal();
}

/// `yyyy/MM/dd HH:mm`（本地时间）。
String formatCronDateTime(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}/${two(value.month)}/${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

/// 毫秒 → 人读间隔：`30秒` / `1分钟` / `6小时` / `2天`。
String humanCronInterval(int ms) {
  if (ms <= 0) return '0秒';
  const second = 1000;
  const minute = 60 * second;
  const hour = 60 * minute;
  const day = 24 * hour;
  if (ms % day == 0) return '${ms ~/ day}天';
  if (ms % hour == 0) return '${ms ~/ hour}小时';
  if (ms % minute == 0) return '${ms ~/ minute}分钟';
  if (ms % second == 0) return '${ms ~/ second}秒';
  return '${ms}毫秒';
}
