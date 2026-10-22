import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_app/data/model/gateway_skill.dart';
import 'package:parrot_app/ui/screen/skill_search_screen.dart';

/// ClawHub 搜索页的三个纯函数：缩写、详情解析、已安装判定。
///
/// 单独覆盖一遍的原因：这三处都在「按名字/引用猜身份」，猜错的表现很隐蔽
/// —— 缩写错了只是难看，引用或版本比对错了会把「装了旧版」显示成「已安装」，
/// 或者反过来让用户重复安装。
void main() {
  GatewayClawHubSkillSummary summary({
    required String displayName,
    String slug = 'youdao-note',
    String? installRef,
    bool? installOnly,
    String? trustState,
    String? summaryText,
    String? version,
  }) {
    return GatewayClawHubSkillSummary(
      slug: slug,
      installRef: installRef,
      installOnly: installOnly,
      trustState: trustState,
      displayName: displayName,
      summary: summaryText,
      version: version,
    );
  }

  GatewaySkill installed({
    String? clawHubSlug,
    String? ownerHandle,
    bool valid = true,
    String? requestedReference,
    String? installedVersion,
  }) {
    return GatewaySkill(
      key: 'youdao',
      name: 'YoudaoNote',
      clawHubSlug: clawHubSlug,
      clawHubValid: valid,
      clawHubOwnerHandle: ownerHandle,
      clawHubRequestedReference: requestedReference,
      clawHubInstalledVersion: installedVersion,
    );
  }

  group('skillBadge 缩写', () {
    // 这 7 个名字直接来自设计稿，缩写必须一一对上。
    const expected = <String, String>{
      'Youdao Note Web': 'YN',
      'YoudaoNote': 'Y',
      'YoudaoNote News': 'YN',
      'YoudaoNote Clip': 'YC',
      'YoudaoNote OKF Wiki': 'YO',
      'YoudaoNote LLM Wiki': 'YL',
    };

    for (final entry in expected.entries) {
      test('${entry.key} → ${entry.value}', () {
        expect(skillBadge(entry.key), entry.value);
      });
    }

    test('分隔符连写和空白不会产生空字母', () {
      expect(skillBadge('apple-notes  helper'), 'AN');
      expect(skillBadge('  leading space'), 'LS');
    });

    test('取不到字母时兜底 S', () {
      expect(skillBadge('   '), 'S');
    });
  });

  group('skills.search 响应解析', () {
    test('正常结果按 schema 字段读出来', () {
      final results = GatewayClawHubSkillSummary.listFromSearchResponse({
        'results': [
          {
            'score': 1.0,
            'slug': 'youdao-note',
            'installRef': '@youdao/youdao-note',
            'trustState': 'not-scanned-by-clawhub',
            'displayName': 'Youdao Note Web',
            'summary': '安全地操作用户的有道云笔记',
            'version': '1.2.0',
          },
        ],
      });

      expect(results, hasLength(1));
      expect(results.single.reference, '@youdao/youdao-note');
      expect(results.single.isUnscannedSource, isTrue);
      expect(results.single.canReadDetails, isTrue);
      expect(results.single.version, '1.2.0');
    });

    test('缺 slug / displayName 的条目被丢弃，缺 results 返回空表', () {
      expect(
        GatewayClawHubSkillSummary.listFromSearchResponse({
          'results': [
            {'slug': 'a', 'displayName': 'A'},
            {'slug': 'b'},
            {'displayName': 'C'},
            'not-a-map',
          ],
        }),
        hasLength(1),
      );
      expect(
        GatewayClawHubSkillSummary.listFromSearchResponse(const {}),
        isEmpty,
      );
    });

    test('installOnly=true 时跳过审核，reference 回退到 slug', () {
      final results = GatewayClawHubSkillSummary.listFromSearchResponse({
        'results': [
          {'slug': 'raw/thing', 'displayName': 'Raw', 'installOnly': true},
        ],
      });
      expect(results.single.canReadDetails, isFalse);
      expect(results.single.reference, 'raw/thing');
    });
  });

  group('skills.detail 审核解析', () {
    final fallback = summary(
      displayName: 'YoudaoNote',
      slug: 'youdao-note',
      version: '1.0.0',
    );

    test('版本优先取 latestVersion，发布者 handle 用来规范化引用', () {
      final review = GatewayClawHubInstallReview.fromDetailResponse({
        'skill': {'slug': 'youdao-note', 'displayName': 'YoudaoNote'},
        'latestVersion': {'version': '2.0.0'},
        'owner': {'handle': 'Youdao', 'displayName': 'Youdao Official'},
      }, fallback: fallback);

      expect(review, isNotNull);
      expect(review!.version, '2.0.0');
      expect(review.slug, '@youdao/youdao-note');
      expect(review.author, 'Youdao Official (@Youdao)');
    });

    test('详情没有版本时回退搜索结果的版本，两边都没有则返回 null', () {
      final fallbackVersion = GatewayClawHubInstallReview.fromDetailResponse({
        'skill': {'slug': 'youdao-note', 'displayName': 'YoudaoNote'},
      }, fallback: fallback);
      expect(fallbackVersion?.version, '1.0.0');

      final none = GatewayClawHubInstallReview.fromDetailResponse({
        'skill': {'slug': 'youdao-note', 'displayName': 'YoudaoNote'},
      }, fallback: summary(displayName: 'YoudaoNote'));
      expect(none, isNull);
    });

    test('发布者只有名字 / 只有 handle / 都没有时的文案', () {
      String? authorOf(Map<String, dynamic> owner) => GatewayClawHubInstallReview
          .fromDetailResponse({
            'skill': {'slug': 'youdao-note', 'displayName': 'YoudaoNote'},
            'latestVersion': {'version': '2.0.0'},
            'owner': owner,
          }, fallback: fallback)
          ?.author;

      expect(authorOf({'displayName': 'Youdao'}), 'Youdao');
      expect(authorOf({'handle': 'youdao'}), '@youdao');
      expect(authorOf(const {}), '未知发布者');
      // 名字和 handle 只差大小写时不再重复展示。
      expect(authorOf({'displayName': 'Youdao', 'handle': 'youdao'}), 'Youdao');
    });

    test('slug 语法非法时返回 null，不产生一个没法安装的引用', () {
      final review = GatewayClawHubInstallReview.fromDetailResponse({
        'skill': {'slug': '@broken', 'displayName': 'Broken'},
        'latestVersion': {'version': '2.0.0'},
      }, fallback: summary(displayName: 'Broken', slug: '@broken'));
      expect(review, isNull);
    });

    test('下载数取 skill.stats.downloads，缺 stats 时保持 null', () {
      final withStats = GatewayClawHubInstallReview.fromDetailResponse({
        'skill': {
          'slug': 'youdao-note',
          'displayName': 'YoudaoNote',
          'stats': {'comments': 0, 'downloads': 978, 'installs': 26},
        },
        'latestVersion': {'version': '2.0.0'},
        'owner': {'handle': 'youdao'},
      }, fallback: fallback);
      expect(withStats?.downloads, 978);

      // 老网关不带 stats：必须是 null（弹窗不显示），不能落成 0。
      final withoutStats = GatewayClawHubInstallReview.fromDetailResponse({
        'skill': {'slug': 'youdao-note', 'displayName': 'YoudaoNote'},
        'latestVersion': {'version': '2.0.0'},
      }, fallback: fallback);
      expect(withoutStats?.downloads, isNull);

      // 字符串 / double 形态也认。
      final asText = GatewayClawHubInstallReview.fromDetailResponse({
        'skill': {
          'slug': 'youdao-note',
          'displayName': 'YoudaoNote',
          'stats': {'downloads': '1234'},
        },
        'latestVersion': {'version': '2.0.0'},
      }, fallback: fallback);
      expect(asText?.downloads, 1234);

      final asDouble = GatewayClawHubInstallReview.fromDetailResponse({
        'skill': {
          'slug': 'youdao-note',
          'displayName': 'YoudaoNote',
          'stats': {'downloads': 12.0},
        },
        'latestVersion': {'version': '2.0.0'},
      }, fallback: fallback);
      expect(asDouble?.downloads, 12);
    });
  });

  group('下载量文案', () {
    test('按三位加分隔符', () {
      expect(formatStatCount(0), '0');
      expect(formatStatCount(978), '978');
      expect(formatStatCount(1234), '1,234');
      expect(formatStatCount(12345), '12,345');
      expect(formatStatCount(1234567), '1,234,567');
    });
  });

  group('安全审核解析', () {
    ClawHubSecurityAudit? auditOf(Map<String, dynamic>? moderation) =>
        ClawHubSecurityAudit.fromJson(moderation);

    test('没有 moderation 块 → null（弹窗不显示这一项）', () {
      expect(auditOf(null), isNull);
      expect(auditOf(const {}), isNull);
    });

    test('verdict: clean → 通过', () {
      final audit = auditOf(const {
        'isSuspicious': false,
        'isMalwareBlocked': false,
        'verdict': 'clean',
      });
      expect(audit?.verdict, ClawHubSecurityVerdict.clean);
    });

    test('两个布尔标记优先于 verdict 文案', () {
      // 标记说被拦，文案却写 clean —— 以标记为准，宁可显示得更严重。
      expect(
        auditOf(const {'verdict': 'clean', 'isMalwareBlocked': true})?.verdict,
        ClawHubSecurityVerdict.blocked,
      );
      expect(
        auditOf(const {'verdict': 'clean', 'isSuspicious': true})?.verdict,
        ClawHubSecurityVerdict.suspicious,
      );
    });

    test('认不出来的 verdict 落到 unknown 并保留原文，绝不猜成通过', () {
      final audit = auditOf(const {'verdict': 'quarantined-pending'});
      expect(audit?.verdict, ClawHubSecurityVerdict.unknown);
      expect(audit?.rawVerdict, 'quarantined-pending');
    });

    test('大小写与同义词都认', () {
      expect(
        auditOf(const {'verdict': 'MALICIOUS'})?.verdict,
        ClawHubSecurityVerdict.blocked,
      );
      expect(
        auditOf(const {'verdict': 'Suspicious'})?.verdict,
        ClawHubSecurityVerdict.suspicious,
      );
    });
  });

  group('最近更新时间', () {
    // 这个 group 在「审核解析」之外，所以自己造一份 fallback。
    final fallback = summary(
      displayName: 'YoudaoNote',
      slug: 'youdao-note',
      version: '1.0.0',
    );

    test('取 skill.updatedAt，缺失时退回 latestVersion.createdAt', () {
      final withSkill = GatewayClawHubInstallReview.fromDetailResponse({
        'skill': {
          'slug': 'youdao-note',
          'displayName': 'YoudaoNote',
          'updatedAt': 1778491913988,
        },
        'latestVersion': {'version': '1.0.0', 'createdAt': 1773529670272},
        'owner': {'handle': 'youdao'},
      }, fallback: fallback);
      expect(withSkill?.updatedAt, DateTime.utc(2026, 5, 11, 9, 31, 53, 988));

      final onlyVersion = GatewayClawHubInstallReview.fromDetailResponse({
        'skill': {'slug': 'youdao-note', 'displayName': 'YoudaoNote'},
        'latestVersion': {'version': '1.0.0', 'createdAt': 1773529670272},
      }, fallback: fallback);
      expect(onlyVersion?.updatedAt, isNotNull);

      final none = GatewayClawHubInstallReview.fromDetailResponse({
        'skill': {'slug': 'youdao-note', 'displayName': 'YoudaoNote'},
        'latestVersion': {'version': '1.0.0'},
      }, fallback: fallback);
      expect(none?.updatedAt, isNull);
    });
  });

  group('时间文案', () {
    test('输出本地日期 YYYY-MM-DD', () {
      // 传入 UTC 时间，展示时换算成本地时区。
      final utc = DateTime.utc(2026, 5, 11, 9, 31, 53);
      final local = utc.toLocal();
      final expected =
          '${local.year}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}';
      expect(formatStatDate(utc), expected);
    });
  });

  group('安全审核文案', () {
    test('四档结论各有自己的文案，unknown 用网关原文兜底', () {
      expect(
        securityVerdictLabel(
          const ClawHubSecurityAudit(verdict: ClawHubSecurityVerdict.clean),
        ),
        '通过',
      );
      expect(
        securityVerdictLabel(
          const ClawHubSecurityAudit(
            verdict: ClawHubSecurityVerdict.suspicious,
          ),
        ),
        '可疑',
      );
      expect(
        securityVerdictLabel(
          const ClawHubSecurityAudit(verdict: ClawHubSecurityVerdict.blocked),
        ),
        '已拦截',
      );
      expect(
        securityVerdictLabel(
          const ClawHubSecurityAudit(
            verdict: ClawHubSecurityVerdict.unknown,
            rawVerdict: 'quarantined-pending',
          ),
        ),
        'quarantined-pending',
      );
      expect(
        securityVerdictLabel(
          const ClawHubSecurityAudit(verdict: ClawHubSecurityVerdict.unknown),
        ),
        '未知',
      );
    });
  });

  group('已安装判定', () {
    test('带版本的结果必须版本一致才算已安装', () {
      final result = summary(displayName: 'YoudaoNote', version: '2.0.0');

      expect(
        isClawHubSkillInstalled([
          installed(clawHubSlug: '@youdao/youdao-note', installedVersion: '2.0.0'),
        ], result),
        isTrue,
      );
      // 装了旧版：不能显示「已安装」，否则用户以为已经是最新。
      expect(
        isClawHubSkillInstalled([
          installed(clawHubSlug: '@youdao/youdao-note', installedVersion: '1.0.0'),
        ], result),
        isFalse,
      );
    });

    test('没版本号时只比对引用，发布者也要对上', () {
      final result = summary(displayName: 'YoudaoNote', installRef: '@youdao/youdao-note');

      expect(
        isClawHubSkillInstalled([
          installed(clawHubSlug: '@youdao/youdao-note'),
        ], result),
        isTrue,
      );
      expect(
        isClawHubSkillInstalled([
          installed(clawHubSlug: '@someone/youdao-note'),
        ], result),
        isFalse,
      );
      // 安装记录没带 owner 时，用 clawhub.ownerHandle 补上。
      expect(
        isClawHubSkillInstalled([
          installed(clawHubSlug: 'youdao-note', ownerHandle: 'Youdao'),
        ], result),
        isTrue,
      );
    });

    test('install-only 的来源按原始引用回读', () {
      final result = summary(
        displayName: 'Raw',
        slug: 'raw/thing',
        installOnly: true,
      );

      expect(
        isClawHubSkillInstalled([
          installed(requestedReference: 'raw/thing'),
        ], result),
        isTrue,
      );
      expect(
        isClawHubSkillInstalled([
          installed(requestedReference: 'other/thing'),
        ], result),
        isFalse,
      );
    });

    test('clawhub.valid=false 的条目一律不算已安装', () {
      final result = summary(displayName: 'YoudaoNote', version: '2.0.0');
      expect(
        isClawHubSkillInstalled([
          installed(
            clawHubSlug: '@youdao/youdao-note',
            installedVersion: '2.0.0',
            valid: false,
          ),
        ], result),
        isFalse,
      );
    });
  });
}
