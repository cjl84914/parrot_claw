import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_app/data/model/gateway_skill.dart';
import 'package:parrot_app/data/repository/gateway_repository.dart';
import 'package:parrot_app/ui/screen/skill_search_screen.dart';
import 'package:parrot_app/ui/view_model/skill_viewmodel.dart';

import 'support/fake_gateway_session.dart';

/// 审核弹窗里展示的元数据。
///
/// 这里守的是「下载数」：它来自详情响应的 `skill.stats.downloads`，
/// 而 `stats` 是后来才加的字段 —— 老网关不返回时**必须整栏不显示**，
/// 一旦写成 `?? 0` 就会把「不知道」渲染成「没人下载过」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 真实网关 `skills.detail` 的响应（节选自 runninghub-skills）。
  Map<String, dynamic> detailWithStats() => {
    'skill': {
      'slug': 'runninghub-skills',
      'displayName': 'RunningHub',
      'summary': 'Generate images, videos, audio, and 3D models.',
      'stats': {
        'comments': 0,
        'downloads': 978,
        'installs': 26,
        'stars': 0,
        'versions': 1,
      },
      'updatedAt': 1778491913988,
    },
    'latestVersion': {'version': '1.0.1'},
    'owner': {'handle': 'hm-runninghub', 'displayName': 'HM-RunningHub'},
    'moderation': {
      'isSuspicious': false,
      'isMalwareBlocked': false,
      'verdict': 'clean',
      'reasonCodes': ['review.llm_review'],
      'engineVersion': 'v2.4.26',
    },
  };

  /// 老网关：详情响应里没有 `stats`，也没有 `moderation`。
  Map<String, dynamic> detailWithoutStats() => {
    'skill': {'slug': 'runninghub-skills', 'displayName': 'RunningHub'},
    'latestVersion': {'version': '1.0.1'},
    'owner': {'handle': 'hm-runninghub'},
  };

  const summary = GatewayClawHubSkillSummary(
    slug: 'runninghub-skills',
    displayName: 'RunningHub',
    version: '1.0.1',
  );

  /// 起一个连着假网关的搜索页，并让 `skills.detail` 返回给定响应。
  Future<GatewayRepository> pumpScreen(
    WidgetTester tester, {
    required Map<String, dynamic> detail,
  }) async {
    final built = await buildConnectedRepository();
    built.session.handler = (method, params) {
      if (method == 'skills.detail') return detail;
      if (method == 'skills.status') return {'skills': <dynamic>[]};
      return const <String, dynamic>{};
    };
    await tester.pumpWidget(
      MaterialApp(
        home: SkillSearchScreen(
          viewModel: SkillViewModel(gatewayRepository: built.repository),
        ),
      ),
    );
    await tester.pump();
    return built.repository;
  }

  testWidgets('审核弹窗显示下载数、安全审核与最近更新', (tester) async {
    final repository = await pumpScreen(tester, detail: detailWithStats());
    await repository.reviewClawHubSkillInstallFromGateway(summary);
    await tester.pumpAndSettle();

    expect(find.text('查看 ClawHub 技能'), findsOneWidget);
    expect(find.text('版本'), findsOneWidget);
    expect(find.text('1.0.1'), findsOneWidget);
    expect(find.text('下载'), findsOneWidget);
    expect(find.text('978'), findsOneWidget);
    // 名字与 handle 只差大小写，所以不再重复拼一个 (@handle)。
    expect(find.text('HM-RunningHub'), findsOneWidget);
    expect(find.text('安全审核'), findsOneWidget);
    expect(find.text('通过'), findsOneWidget);
    expect(find.text('最近更新'), findsOneWidget);
    expect(find.text(formatStatDate(DateTime.utc(2026, 5, 11, 9, 31, 53, 988))), findsOneWidget);
  });

  testWidgets('详情不带 stats / moderation 时整栏不显示，不会退化成 0 或「通过」', (tester) async {
    final repository = await pumpScreen(tester, detail: detailWithoutStats());
    await repository.reviewClawHubSkillInstallFromGateway(summary);
    await tester.pumpAndSettle();

    expect(find.text('版本'), findsOneWidget);
    expect(find.text('下载'), findsNothing);
    expect(find.text('0'), findsNothing);
    expect(find.text('安全审核'), findsNothing);
    expect(find.text('通过'), findsNothing);
    expect(find.text('最近更新'), findsNothing);
  });
}
