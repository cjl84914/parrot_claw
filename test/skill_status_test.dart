import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_app/data/model/gateway_skill.dart';
import 'package:parrot_app/ui/screen/skill_screen.dart';

/// skill_screen 的列表状态推导（决定状态标签颜色与筛选结果）是纯函数，
/// 单独覆盖一遍，避免以后改 skills.status 字段解析时静默错位。
///
/// 这里守着一个已经踩过的坑：网关响应里**没有 `enabled`**，只有 `disabled`
/// （`skills.entries.<key>.enabled === false` 才为 true）。之前直接读 `enabled`
/// 导致所有已启用技能都被渲染成「关闭」。
void main() {
  GatewaySkill skill({
    bool disabled = false,
    bool? eligible,
    bool blockedByAllowlist = false,
    bool platformIncompatible = false,
    Map<String, dynamic> missing = const <String, dynamic>{},
  }) {
    return GatewaySkill(
      key: 'demo',
      name: 'demo',
      disabled: disabled,
      eligible: eligible,
      blockedByAllowlist: blockedByAllowlist,
      platformIncompatible: platformIncompatible,
      missing: missing,
    );
  }

  group('skillStatusOf 三态推导', () {
    test('未禁用（网关默认）就是就绪', () {
      expect(skillStatusOf(skill(eligible: true)), SkillStatus.ready);
    });

    test('disabled 为 true 时是关闭', () {
      expect(
        skillStatusOf(skill(disabled: true, eligible: false)),
        SkillStatus.disabled,
      );
    });

    test('已启用但 eligible 为 false 时需要设置', () {
      expect(skillStatusOf(skill(eligible: false)), SkillStatus.needsSetup);
    });

    test('已启用但 missing 里有缺项时需要设置', () {
      expect(
        skillStatusOf(
          skill(eligible: true, missing: const {'env': ['GITHUB_TOKEN']}),
        ),
        SkillStatus.needsSetup,
      );
    });

    test('missing 里全是空数组不算缺项', () {
      expect(
        skillStatusOf(
          skill(eligible: true, missing: const {'env': [], 'bins': []}),
        ),
        SkillStatus.ready,
      );
    });

    test('平台不支持时需要设置', () {
      expect(
        skillStatusOf(skill(eligible: true, platformIncompatible: true)),
        SkillStatus.needsSetup,
      );
    });

    test('被 allowlist 拦下时需要设置', () {
      expect(
        skillStatusOf(skill(eligible: true, blockedByAllowlist: true)),
        SkillStatus.needsSetup,
      );
    });

    test('关闭优先于缺项判定，不出现「关着却提示需要设置」', () {
      expect(
        skillStatusOf(
          skill(disabled: true, eligible: false, missing: const {'env': ['X']}),
        ),
        SkillStatus.disabled,
      );
    });
  });

  group('状态标签与开关同源（enabled 覆盖）', () {
    test('开关乐观打开时，即使网关还写着关闭也显示就绪', () {
      expect(
        skillStatusOf(skill(disabled: true, eligible: true), enabled: true),
        SkillStatus.ready,
      );
    });

    test('开关乐观关闭时，即使网关还写着启用也显示关闭', () {
      expect(
        skillStatusOf(skill(eligible: true), enabled: false),
        SkillStatus.disabled,
      );
    });

    test('开关打开时不会再显示关闭（启用维度与开关严格一致）', () {
      expect(
        skillStatusOf(skill(disabled: true), enabled: true),
        isNot(SkillStatus.disabled),
      );
    });

    test('开关关闭时一定是关闭，不会出现「关着却提示需要设置」', () {
      expect(
        skillStatusOf(skill(eligible: false), enabled: false),
        SkillStatus.disabled,
      );
    });

    test('乐观打开后仍按缺项判定：缺依赖时提示需要设置，但开关是开的', () {
      expect(
        skillStatusOf(skill(disabled: true, eligible: false), enabled: true),
        SkillStatus.needsSetup,
      );
    });
  });

  group('GatewaySkill.fromJson 对齐网关 skills.status 真实字段', () {
    // 形状取自 openclaw dist/status-*.js 的 buildSkillStatus()：没有 enabled，只有 disabled。
    Map<String, dynamic> payload({
      required String key,
      bool disabled = false,
      bool eligible = true,
      Map<String, dynamic> missing = const <String, dynamic>{
        'bins': <String>[],
        'anyBins': <String>[],
        'env': <String>[],
        'config': <String>[],
        'os': <String>[],
      },
    }) => <String, dynamic>{
      'name': key,
      'description': 'description of $key',
      'source': 'bundled',
      'bundled': true,
      'skillKey': key,
      'always': false,
      'disabled': disabled,
      'blockedByAllowlist': false,
      'blockedByAgentFilter': false,
      'eligible': eligible,
      'platformIncompatible': false,
      'modelVisible': eligible,
      'requirements': missing,
      'missing': missing,
      'configChecks': <Map<String, dynamic>>[],
    };

    test('响应没有 enabled 字段时，disabled=false 解析为已启用', () {
      final parsed = GatewaySkill.fromJson(payload(key: 'github'));
      expect(parsed.key, 'github');
      expect(parsed.disabled, isFalse);
      expect(parsed.enabled, isTrue);
      expect(skillStatusOf(parsed), SkillStatus.ready);
    });

    test('disabled=true 解析为关闭', () {
      final parsed = GatewaySkill.fromJson(
        payload(key: '1password', disabled: true, eligible: false),
      );
      expect(parsed.enabled, isFalse);
      expect(skillStatusOf(parsed), SkillStatus.disabled);
    });

    test('missing 是对象而不是数组，缺项能被识别并给出可读文案', () {
      final parsed = GatewaySkill.fromJson(
        payload(
          key: 'github',
          eligible: false,
          missing: const <String, dynamic>{
            'bins': <String>[],
            'anyBins': <String>[],
            'env': <String>['GITHUB_TOKEN'],
            'config': <String>[],
            'os': <String>[],
          },
        ),
      );
      expect(parsed.hasMissingRequirements, isTrue);
      expect(parsed.missingLabels, ['缺少环境变量: GITHUB_TOKEN']);
      expect(skillStatusOf(parsed), SkillStatus.needsSetup);
    });

    test('兼容旧格式：只给 enabled 时按取反处理', () {
      final parsed = GatewaySkill.fromJson(<String, dynamic>{
        'skillKey': 'legacy',
        'enabled': false,
      });
      expect(parsed.enabled, isFalse);
    });

    test('skills.status 整体解析会丢弃没有 key 的条目', () {
      final status = GatewaySkillsStatus.fromJson(<String, dynamic>{
        'skills': <Map<String, dynamic>>[
          payload(key: 'github'),
          <String, dynamic>{'description': 'no key here'},
        ],
      });
      expect(status.skills.length, 1);
      expect(status.skills.single.key, 'github');
    });
  });
}
