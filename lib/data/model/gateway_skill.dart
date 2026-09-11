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
      raw: Map<String, dynamic>.from(json),
    );
  }
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
