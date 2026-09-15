/// OpenClaw Gateway `sessions.*` 系列响应的数据模型。
///
/// 这些类型原先定义在 `data/service/openclaw_runtime.dart`，但它们是纯 DTO
/// （只做 JSON 解析、不含任何连接逻辑），因此归到 model 层，供仓库与 UI 共用。
///
/// 注意：`data/service/gateway_connection.dart`（旧的直连路径）里还留着一份
/// 同名副本。新代码一律用本文件；旧文件随旧路径一起退役。
library;

/// 会话未读标记的条件确认依据。
class OpenClawSessionUnreadExpectation {
  final double? markedUnreadAt;

  const OpenClawSessionUnreadExpectation(this.markedUnreadAt);
}

class GatewaySessionEntry {
  final String key;
  final String? kind;
  final String? displayName;
  final String? derivedTitle;
  final String? classification;
  final String? agentId;
  final String? accountId;
  final String? peerKind;
  final bool? isMain;
  final bool? isBackground;
  final String? label;
  final String? category;
  final bool? pinned;
  final double? pinnedAt;
  final bool? archived;
  final double? archivedAt;
  final bool? unread;
  final GatewaySessionAgentStatus? agentStatus;
  final String? surface;
  final String? subject;
  final String? room;
  final String? space;
  final double? updatedAt;
  final double? lastReadAt;
  final double? markedUnreadAt;
  final double? lastInteractionAt;
  final double? lastActivityAt;
  final String? sessionId;
  final String? parentSessionKey;
  final String? spawnedBy;
  final List<String>? childSessions;
  final String? status;
  final String? lastRunError;
  final bool? hasActiveRun;
  final List<String>? activeRunIds;
  final bool? hasActiveSubagentRun;
  final String? subagentRunState;
  final String? swarmGroupId;
  final String? swarmPhase;
  final int? swarmPhaseRank;
  final String? swarmLog;
  final GatewaySessionWorktree? worktree;
  final double? startedAt;
  final double? endedAt;
  final double? runtimeMs;
  final GatewaySessionAgentRuntime? agentRuntime;
  final bool? systemSent;
  final bool? abortedLastRun;
  final String? thinkingLevel;
  final String? verboseLevel;
  final dynamic fastMode;
  final dynamic effectiveFastMode;
  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
  final bool? totalTokensFresh;
  final String? modelProvider;
  final String? model;
  final int? contextTokens;
  final List<GatewaySessionThinkingLevelOption>? thinkingLevels;
  final List<String>? thinkingOptions;
  final String? thinkingDefault;

  const GatewaySessionEntry({
    required this.key,
    this.kind,
    this.displayName,
    this.derivedTitle,
    this.classification,
    this.agentId,
    this.accountId,
    this.peerKind,
    this.isMain,
    this.isBackground,
    this.label,
    this.category,
    this.pinned,
    this.pinnedAt,
    this.archived,
    this.archivedAt,
    this.unread,
    this.agentStatus,
    this.surface,
    this.subject,
    this.room,
    this.space,
    this.updatedAt,
    this.lastReadAt,
    this.markedUnreadAt,
    this.lastInteractionAt,
    this.lastActivityAt,
    this.sessionId,
    this.parentSessionKey,
    this.spawnedBy,
    this.childSessions,
    this.status,
    this.lastRunError,
    this.hasActiveRun,
    this.activeRunIds,
    this.hasActiveSubagentRun,
    this.subagentRunState,
    this.swarmGroupId,
    this.swarmPhase,
    this.swarmPhaseRank,
    this.swarmLog,
    this.worktree,
    this.startedAt,
    this.endedAt,
    this.runtimeMs,
    this.agentRuntime,
    this.systemSent,
    this.abortedLastRun,
    this.thinkingLevel,
    this.verboseLevel,
    this.fastMode,
    this.effectiveFastMode,
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
    this.totalTokensFresh,
    this.modelProvider,
    this.model,
    this.contextTokens,
    this.thinkingLevels,
    this.thinkingOptions,
    this.thinkingDefault,
  });

  bool get isPinned => pinned == true;

  bool get isArchived => archived == true;

  factory GatewaySessionEntry.fromJson(Map<String, dynamic> json) =>
      GatewaySessionEntry(
        key: json['key'] as String? ?? '',
        kind: json['kind'] as String?,
        displayName: json['displayName'] as String?,
        derivedTitle: json['derivedTitle'] as String?,
        classification: json['classification'] as String?,
        agentId: json['agentId'] as String?,
        accountId: json['accountId'] as String?,
        peerKind: json['peerKind'] as String?,
        isMain: json['isMain'] as bool?,
        isBackground: json['isBackground'] as bool?,
        label: json['label'] as String?,
        category: json['category'] as String?,
        pinned: json['pinned'] as bool?,
        pinnedAt: (json['pinnedAt'] as num?)?.toDouble(),
        archived: json['archived'] as bool?,
        archivedAt: (json['archivedAt'] as num?)?.toDouble(),
        unread: json['unread'] as bool?,
        agentStatus: _mapValue(
          json['agentStatus'],
          GatewaySessionAgentStatus.fromJson,
        ),
        surface: json['surface'] as String?,
        subject: json['subject'] as String?,
        room: json['room'] as String?,
        space: json['space'] as String?,
        updatedAt: (json['updatedAt'] as num?)?.toDouble(),
        lastReadAt: (json['lastReadAt'] as num?)?.toDouble(),
        markedUnreadAt: (json['markedUnreadAt'] as num?)?.toDouble(),
        lastInteractionAt: (json['lastInteractionAt'] as num?)?.toDouble(),
        lastActivityAt: (json['lastActivityAt'] as num?)?.toDouble(),
        sessionId: json['sessionId'] as String?,
        parentSessionKey: json['parentSessionKey'] as String?,
        spawnedBy: json['spawnedBy'] as String?,
        childSessions: _stringList(json['childSessions']),
        status: json['status'] as String?,
        lastRunError: json['lastRunError'] as String?,
        hasActiveRun: json['hasActiveRun'] as bool?,
        activeRunIds: _stringList(json['activeRunIds']),
        hasActiveSubagentRun: json['hasActiveSubagentRun'] as bool?,
        subagentRunState: json['subagentRunState'] as String?,
        swarmGroupId: json['swarmGroupId'] as String?,
        swarmPhase: json['swarmPhase'] as String?,
        swarmPhaseRank: (json['swarmPhaseRank'] as num?)?.toInt(),
        swarmLog: json['swarmLog'] as String?,
        worktree: _mapValue(json['worktree'], GatewaySessionWorktree.fromJson),
        startedAt: (json['startedAt'] as num?)?.toDouble(),
        endedAt: (json['endedAt'] as num?)?.toDouble(),
        runtimeMs: (json['runtimeMs'] as num?)?.toDouble(),
        agentRuntime: _mapValue(
          json['agentRuntime'],
          GatewaySessionAgentRuntime.fromJson,
        ),
        systemSent: json['systemSent'] as bool?,
        abortedLastRun: json['abortedLastRun'] as bool?,
        thinkingLevel: json['thinkingLevel'] as String?,
        verboseLevel: json['verboseLevel'] as String?,
        fastMode: json['fastMode'],
        effectiveFastMode: json['effectiveFastMode'],
        inputTokens: (json['inputTokens'] as num?)?.toInt(),
        outputTokens: (json['outputTokens'] as num?)?.toInt(),
        totalTokens: (json['totalTokens'] as num?)?.toInt(),
        totalTokensFresh: json['totalTokensFresh'] as bool?,
        modelProvider: json['modelProvider'] as String?,
        model: json['model'] as String?,
        contextTokens: (json['contextTokens'] as num?)?.toInt(),
        thinkingLevels: _mapList(
          json['thinkingLevels'],
          GatewaySessionThinkingLevelOption.fromJson,
        ),
        thinkingOptions: _stringList(json['thinkingOptions']),
        thinkingDefault: json['thinkingDefault'] as String?,
      );
}

class GatewayCreateSessionResponse {
  final bool? ok;
  final String key;
  final String? sessionId;

  const GatewayCreateSessionResponse({
    required this.key,
    this.ok,
    this.sessionId,
  });

  factory GatewayCreateSessionResponse.fromJson(Map<String, dynamic> json) =>
      GatewayCreateSessionResponse(
        ok: json['ok'] as bool?,
        key: json['key'] as String? ?? '',
        sessionId: json['sessionId'] as String?,
      );
}

class GatewaySessionsListResponse {
  final double? ts;
  final String? path;
  final int? count;
  final int? totalCount;
  final int? offset;
  final int? nextOffset;
  final bool? hasMore;
  final Map<String, dynamic>? defaults;
  final List<GatewaySessionEntry> sessions;

  const GatewaySessionsListResponse({
    this.ts,
    this.path,
    this.count,
    this.totalCount,
    this.offset,
    this.nextOffset,
    this.hasMore,
    this.defaults,
    this.sessions = const [],
  });

  factory GatewaySessionsListResponse.fromJson(Map<String, dynamic> json) =>
      GatewaySessionsListResponse(
        ts: (json['ts'] as num?)?.toDouble(),
        path: json['path'] as String?,
        count: (json['count'] as num?)?.toInt(),
        totalCount: (json['totalCount'] as num?)?.toInt(),
        offset: (json['offset'] as num?)?.toInt(),
        nextOffset: (json['nextOffset'] as num?)?.toInt(),
        hasMore: json['hasMore'] as bool?,
        defaults: (json['defaults'] as Map?)?.cast<String, dynamic>(),
        sessions:
            _mapList(json['sessions'], GatewaySessionEntry.fromJson) ??
            const [],
      );
}

class GatewaySessionAgentStatus {
  final String note;
  final double expiresAt;
  final String? attention;

  const GatewaySessionAgentStatus({
    required this.note,
    required this.expiresAt,
    this.attention,
  });

  factory GatewaySessionAgentStatus.fromJson(Map<String, dynamic> json) =>
      GatewaySessionAgentStatus(
        note: json['note'] as String? ?? '',
        expiresAt: (json['expiresAt'] as num?)?.toDouble() ?? 0,
        attention: json['attention'] as String?,
      );
}

class GatewaySessionWorktree {
  final String? id;
  final String? branch;
  final String? repoRoot;

  const GatewaySessionWorktree({this.id, this.branch, this.repoRoot});

  factory GatewaySessionWorktree.fromJson(Map<String, dynamic> json) =>
      GatewaySessionWorktree(
        id: json['id'] as String?,
        branch: json['branch'] as String?,
        repoRoot: json['repoRoot'] as String?,
      );
}

class GatewaySessionAgentRuntime {
  final String id;
  final String? fallback;
  final String? source;

  const GatewaySessionAgentRuntime({
    required this.id,
    this.fallback,
    this.source,
  });

  factory GatewaySessionAgentRuntime.fromJson(Map<String, dynamic> json) =>
      GatewaySessionAgentRuntime(
        id: json['id'] as String? ?? '',
        fallback: json['fallback'] as String?,
        source: json['source'] as String?,
      );
}

class GatewaySessionThinkingLevelOption {
  final String id;
  final String label;

  const GatewaySessionThinkingLevelOption({
    required this.id,
    required this.label,
  });

  factory GatewaySessionThinkingLevelOption.fromJson(
    Map<String, dynamic> json,
  ) => GatewaySessionThinkingLevelOption(
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
  );
}

T? _mapValue<T>(dynamic value, T Function(Map<String, dynamic>) parser) {
  if (value is Map) return parser(value.cast<String, dynamic>());
  return null;
}

List<T>? _mapList<T>(dynamic value, T Function(Map<String, dynamic>) parser) {
  if (value is! List) return null;
  return value
      .whereType<Map>()
      .map((item) => parser(item.cast<String, dynamic>()))
      .toList();
}

List<String>? _stringList(dynamic value) {
  if (value is! List) return null;
  return value.whereType<String>().toList();
}
