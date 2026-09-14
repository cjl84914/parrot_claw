/// 网关 `skills.status` 返回的单个技能。
///
/// 字段语义对齐 openclaw `dist/status-*.js` 的 `buildSkillStatus()`：
///
/// - 响应里**没有 `enabled`**，启用状态由 `disabled` 反向表达
///   （只有 `skills.entries.<key>.enabled === false` 才会 disabled=true）。
///   配置文件里没有该条目时 `disabled=false`，即**默认启用**——这是最容易踩的坑：
///   直接读 `json['enabled']` 会永远拿到 null，把已启用的技能全渲染成「关闭」。
/// - `eligible` = 未被禁用 && 未被 allowlist 拦 && 依赖齐全，即「能不能跑」。
/// - `missing` 是**对象** `{bins, anyBins, env, config, os}`（每项是数组），不是数组。
class GatewaySkill {
  const GatewaySkill({
    required this.key,
    required this.name,
    this.description,
    this.disabled = false,
    this.eligible,
    this.blockedByAllowlist = false,
    this.blockedByAgentFilter = false,
    this.platformIncompatible = false,
    this.missing = const <String, dynamic>{},
    this.clawHubSlug,
    this.clawHubValid = false,
    this.clawHubRequestedReference,
    this.clawHubOwnerHandle,
    this.clawHubInstalledVersion,
    this.raw = const <String, dynamic>{},
  });

  final String key;
  final String name;
  final String? description;

  /// 网关是否显式禁用了这个技能（`skills.entries.<key>.enabled === false`）。
  final bool disabled;

  /// 是否可以真正运行（未禁用 + 未被拦截 + 依赖/密钥/平台都满足）。
  final bool? eligible;

  /// 被 bundled allowlist 拦截。
  final bool blockedByAllowlist;

  /// 被当前 agent 的技能过滤器拦截。
  final bool blockedByAgentFilter;

  /// 当前平台不在技能声明支持的平台里。
  final bool platformIncompatible;

  /// 缺失的依赖项，形如
  /// `{bins: [], anyBins: [], env: ['GITHUB_TOKEN'], config: [], os: []}`。
  final Map<String, dynamic> missing;

  /// 该技能在 ClawHub 上的标识（`clawhub.slug`）。
  final String? clawHubSlug;

  /// 网关是否确认它来自 ClawHub 且引用有效。
  final bool clawHubValid;

  /// 安装时请求的原始引用。
  ///
  /// 「只能直接安装」的来源（install-only）引用不是 `@owner/slug` 形式，
  /// slug 比对永远匹配不上，回读已安装状态只能靠这个字段。
  final String? clawHubRequestedReference;

  /// ClawHub 上的发布者 handle。
  final String? clawHubOwnerHandle;

  /// 实际安装的版本号。
  final String? clawHubInstalledVersion;

  final Map<String, dynamic> raw;

  /// 列表里统一的「启用状态」。网关用 [disabled] 反向表达，这里归一成 enabled 语义，
  /// 免得每个调用方都要自己取反。
  bool get enabled => !disabled;

  /// 是否有缺失的依赖项（密钥 / 命令 / 配置 / 平台）。
  bool get hasMissingRequirements =>
      missing.values.any((value) => value is List && value.isNotEmpty);

  /// 缺失项的可读描述，用于详情页展示。
  List<String> get missingLabels {
    const labels = <String, String>{
      'bins': '缺少命令',
      'anyBins': '缺少命令',
      'env': '缺少环境变量',
      'config': '缺少配置',
      'os': '平台不支持',
    };
    final result = <String>[];
    for (final entry in missing.entries) {
      final value = entry.value;
      if (value is! List || value.isEmpty) continue;
      result.add('${labels[entry.key] ?? entry.key}: ${value.join('、')}');
    }
    return result;
  }

  factory GatewaySkill.fromJson(Map<String, dynamic> json) {
    final key =
        (json['skillKey'] ?? json['key'] ?? json['slug'] ?? json['name'])
            ?.toString()
            .trim() ??
        '';
    final name = (json['name'] ?? json['displayName'] ?? key).toString();
    final rawDisabled = json['disabled'];
    final rawEnabled = json['enabled'];
    // 优先信任 disabled；只有网关返回的是旧版/别名格式时才回退到 enabled 取反。
    final disabled =
        rawDisabled is bool
            ? rawDisabled
            : rawEnabled is bool
            ? !rawEnabled
            : false;
    final rawClawHub = json['clawhub'];
    final clawHub = rawClawHub is Map
        ? rawClawHub.cast<String, dynamic>()
        : null;
    return GatewaySkill(
      key: key,
      name: name,
      description: json['description']?.toString(),
      disabled: disabled,
      eligible: json['eligible'] as bool?,
      blockedByAllowlist: json['blockedByAllowlist'] as bool? ?? false,
      blockedByAgentFilter: json['blockedByAgentFilter'] as bool? ?? false,
      platformIncompatible: json['platformIncompatible'] as bool? ?? false,
      missing:
          json['missing'] is Map
              ? Map<String, dynamic>.from(json['missing'] as Map)
              : const <String, dynamic>{},
      clawHubSlug: _nonEmptyString(clawHub?['slug']),
      clawHubValid: clawHub?['valid'] == true,
      clawHubRequestedReference: _nonEmptyString(
        clawHub?['requestedReference'],
      ),
      clawHubOwnerHandle: _nonEmptyString(clawHub?['ownerHandle']),
      clawHubInstalledVersion: _nonEmptyString(clawHub?['installedVersion']),
      raw: Map<String, dynamic>.from(json),
    );
  }
}

/// ClawHub 搜索命中的技能（对应 Android 的 `GatewayClawHubSkillSummary`）。
///
/// 多个发布者可能共用一个 slug，所以「识别一条结果」「区分两行」「安装时回传什么」
/// 用的都是网关给的 [reference]，而不是自己拿 owner + slug 拼出来的。
class GatewayClawHubSkillSummary {
  const GatewayClawHubSkillSummary({
    required this.slug,
    this.installRef,
    this.installOnly,
    this.trustState,
    required this.displayName,
    this.summary,
    this.version,
  });

  final String slug;

  /// 网关给的可安装引用，缺省时退回 [slug]。
  final String? installRef;

  /// 该结果是否只能直接安装（不支持查看详情）。
  final bool? installOnly;

  /// ClawHub 的信任状态，`not-scanned-by-clawhub` 表示未扫描来源。
  final String? trustState;

  final String displayName;
  final String? summary;
  final String? version;

  String get reference {
    final ref = installRef?.trim();
    return (ref == null || ref.isEmpty) ? slug : ref;
  }

  /// 只有显式标记为「仅安装」的结果才跳过审核：旧网关不带这个字段，
  /// 那些结果必须保留一直以来的「先看版本再安装」流程。
  bool get canReadDetails => installOnly != true;

  bool get isUnscannedSource => trustState == 'not-scanned-by-clawhub';

  /// 解析 `skills.search` 的响应（`{results: [...]}`）。
  ///
  /// 与网关 schema 一致：`slug` 和 `displayName` 为空的结果直接丢弃。
  static List<GatewayClawHubSkillSummary> listFromSearchResponse(
    Map<String, dynamic> json,
  ) {
    final rawResults = json['results'];
    if (rawResults is! List) return const <GatewayClawHubSkillSummary>[];
    final results = <GatewayClawHubSkillSummary>[];
    for (final item in rawResults) {
      if (item is! Map) continue;
      final slug = _nonEmptyString(item['slug']);
      final displayName = _nonEmptyString(item['displayName']);
      if (slug == null || displayName == null) continue;
      final rawInstallOnly = item['installOnly'];
      results.add(
        GatewayClawHubSkillSummary(
          slug: slug,
          installRef: _nonEmptyString(item['installRef']),
          installOnly: rawInstallOnly is bool ? rawInstallOnly : null,
          trustState: _nonEmptyString(item['trustState']),
          displayName: displayName,
          summary: _nonEmptyString(item['summary']),
          version: _nonEmptyString(item['version']),
        ),
      );
    }
    return results;
  }
}

/// 安装前的版本审核信息（对应 Android 的 `GatewayClawHubInstallReview`）。
class GatewayClawHubInstallReview {
  const GatewayClawHubInstallReview({
    required this.slug,
    required this.displayName,
    this.summary,
    required this.version,
    required this.author,
  });

  final String slug;
  final String displayName;
  final String? summary;
  final String version;
  final String author;

  /// 解析 `skills.detail` 的响应；返回 null 表示网关没给出可安装的版本。
  ///
  /// 详情响应就是「审核」与「安装」的分界线，所以版本优先取它的
  /// `latestVersion.version`，而不是搜索列表里可能已经过期的那个。
  static GatewayClawHubInstallReview? fromDetailResponse(
    Map<String, dynamic> json, {
    required GatewayClawHubSkillSummary fallback,
  }) {
    final skill = _asObject(json['skill']);
    final latestVersion = _asObject(json['latestVersion']);
    final owner = _asObject(json['owner']);
    final version =
        _nonEmptyString(latestVersion?['version']) ?? fallback.version;
    if (version == null) return null;
    final ownerDisplayName = _nonEmptyString(owner?['displayName']);
    final ownerHandle = _nonEmptyString(owner?['handle']);
    final reviewedSlug = _canonicalClawHubReference(
      slug: _nonEmptyString(skill?['slug']) ?? fallback.slug,
      ownerHandle: ownerHandle,
    );
    if (reviewedSlug == null) return null;
    final author = switch ((ownerDisplayName, ownerHandle)) {
      (final String name, final String handle)
          when name.toLowerCase() != handle.toLowerCase() =>
        '$name (@$handle)',
      (final String name, _) => name,
      (_, final String handle) => '@$handle',
      _ => '未知发布者',
    };
    return GatewayClawHubInstallReview(
      slug: reviewedSlug,
      displayName:
          _nonEmptyString(skill?['displayName']) ?? fallback.displayName,
      summary: _nonEmptyString(skill?['summary']) ?? fallback.summary,
      version: version,
      author: author,
    );
  }
}

class _ClawHubSkillReference {
  const _ClawHubSkillReference(this.slug, this.ownerHandle);

  final String slug;
  final String? ownerHandle;
}

/// 拆 `@owner/slug`；不带 `@` 的按「只有 slug、没有发布者」处理。
_ClawHubSkillReference? _parseClawHubSkillReference(String rawValue) {
  final value = rawValue.trim();
  if (value.isEmpty) return null;
  if (!value.startsWith('@')) return _ClawHubSkillReference(value, null);
  final parts = value.substring(1).split('/');
  if (parts.length != 2 || parts.any((part) => part.isEmpty)) return null;
  return _ClawHubSkillReference(parts[1], parts[0].toLowerCase());
}

/// 审核用的规范引用：发布者以详情响应里的 `owner.handle` 为准。
String? _canonicalClawHubReference({
  required String slug,
  String? ownerHandle,
}) {
  final reference = _parseClawHubSkillReference(slug);
  if (reference == null) return null;
  final trimmedHandle = ownerHandle?.trim();
  final owner = (trimmedHandle == null || trimmedHandle.isEmpty)
      ? reference.ownerHandle
      : trimmedHandle.toLowerCase();
  return owner == null ? reference.slug : '@$owner/${reference.slug}';
}

Map<String, dynamic>? _asObject(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : null;

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  return (text == null || text.isEmpty) ? null : text;
}

/// 某条 ClawHub 搜索结果是否已经装在网关上（对应 Android `isClawHubSkillInstalled`）。
///
/// 三种回读方式，按结果的能力分派：
/// - 只能直接安装的来源没有 `@owner/slug` 引用，靠网关记录的原始引用比对；
/// - 能看详情、且带版本号的结果必须**版本也一致**才算已安装
///   （否则「装了旧版」会被误判成「已是最新」）；
/// - 能看详情但没版本号时，只比对引用。
bool isClawHubSkillInstalled(
  List<GatewaySkill> skills,
  GatewayClawHubSkillSummary result,
) {
  if (!result.canReadDetails) {
    return isClawHubSkillInstalledByReference(skills, result.reference);
  }
  final version = result.version;
  if (version != null) {
    return isClawHubSkillInstalledAtVersion(skills, result.reference, version);
  }
  return _isClawHubReferenceInstalled(skills, result.reference);
}

bool _isClawHubReferenceInstalled(
  List<GatewaySkill> skills,
  String slug,
) {
  final reference = _parseClawHubSkillReference(slug);
  if (reference == null) return false;
  return skills.any((skill) => _matchesClawHubReference(skill, reference));
}

/// 安装回读：引用与**版本**都必须对上。
///
/// 与 [isClawHubSkillInstalled] 的区别是这里不猜 —— 安装方明确知道自己
/// 请求的是哪个版本，装成了别的版本就不算成功。
bool isClawHubSkillInstalledAtVersion(
  List<GatewaySkill> skills,
  String slug,
  String version,
) {
  final reference = _parseClawHubSkillReference(slug);
  if (reference == null) return false;
  return skills.any(
    (skill) =>
        _matchesClawHubReference(skill, reference) &&
        skill.clawHubInstalledVersion == version,
  );
}

/// 安装回读：只能直接安装的来源按原始引用比对。
///
/// 它的引用不是 `@owner/slug` 形式，slug 比对永远匹配不上，
/// 网关会把安装时用的原始引用记在 `requestedReference` 里。
bool isClawHubSkillInstalledByReference(
  List<GatewaySkill> skills,
  String requestedReference,
) {
  final reference = requestedReference.trim();
  if (reference.isEmpty) return false;
  return skills.any(
    (skill) =>
        skill.clawHubValid && skill.clawHubRequestedReference == reference,
  );
}

bool _matchesClawHubReference(
  GatewaySkill skill,
  _ClawHubSkillReference reference,
) {
  if (!skill.clawHubValid) return false;
  final installedSlug = skill.clawHubSlug;
  final installedReference = installedSlug == null
      ? null
      : _parseClawHubSkillReference(installedSlug);
  if (installedReference == null) return false;
  if (installedReference.slug.toLowerCase() != reference.slug.toLowerCase()) {
    return false;
  }
  final requestedOwner = reference.ownerHandle;
  if (requestedOwner == null) return true;
  final installedOwner =
      installedReference.ownerHandle ?? skill.clawHubOwnerHandle;
  return installedOwner?.toLowerCase() == requestedOwner.toLowerCase();
}

class GatewaySkillsStatus {
  final List<GatewaySkill> skills;
  final Map<String, dynamic> raw;

  const GatewaySkillsStatus({this.skills = const [], this.raw = const {}});

  factory GatewaySkillsStatus.fromJson(Map<String, dynamic> json) {
    final rawSkills = json['skills'] ?? json['items'] ?? json['entries'];
    final skills =
        rawSkills is List
            ? rawSkills
                .whereType<Map>()
                .map(
                  (item) => GatewaySkill.fromJson(item.cast<String, dynamic>()),
                )
                .where((skill) => skill.key.isNotEmpty)
                .toList(growable: false)
            : const <GatewaySkill>[];
    return GatewaySkillsStatus(
      skills: skills,
      raw: Map<String, dynamic>.from(json),
    );
  }
}
