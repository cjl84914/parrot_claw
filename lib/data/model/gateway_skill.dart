class GatewaySkill {
  final String key;
  final String name;
  final String? description;
  final bool? enabled;
  final bool? eligible;
  final bool? installed;
  final bool? blocked;
  final Map<String, dynamic> raw;

  const GatewaySkill({
    required this.key,
    required this.name,
    this.description,
    this.enabled,
    this.eligible,
    this.installed,
    this.blocked,
    this.raw = const <String, dynamic>{},
  });

  factory GatewaySkill.fromJson(Map<String, dynamic> json) {
    final key =
        (json['skillKey'] ?? json['key'] ?? json['slug'] ?? json['name'])
            ?.toString()
            .trim() ??
        '';
    final name = (json['name'] ?? json['displayName'] ?? key).toString();
    return GatewaySkill(
      key: key,
      name: name,
      description: json['description']?.toString(),
      enabled: json['enabled'] as bool?,
      eligible: json['eligible'] as bool?,
      installed: json['installed'] as bool?,
      blocked: json['blocked'] as bool?,
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
