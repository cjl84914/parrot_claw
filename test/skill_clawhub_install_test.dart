import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_app/data/model/gateway_skill.dart';
import 'package:parrot_app/data/repository/gateway_repository.dart';
import 'package:parrot_app/data/service/gateway_session.dart';

import 'support/fake_gateway_session.dart';

/// ClawHub 安装流程的失败路径。
///
/// 这里守着一个容易写错的地方：超时或被网关拒绝时，**安装可能其实已经成功**。
/// 如果直接报「失败」，用户会重复点安装；如果直接报「成功」，又可能在没装上的
/// 情况下把列表刷成「已安装」。所以两条失败路径都必须先回读列表再定性。

/// 网关里已经装好的那条记录（对应 `skills.status` 的 `clawhub` 对象）。
Map<String, dynamic> installedSkillJson({
  String slug = 'youdao-note',
  String ownerHandle = 'youdao',
  String? requestedReference,
  String? installedVersion = '1.0.0',
}) => {
  'skillKey': 'youdao',
  'name': 'YoudaoNote',
  'clawhub': {
    'slug': '@$ownerHandle/$slug',
    'valid': true,
    if (requestedReference != null) 'requestedReference': requestedReference,
    if (installedVersion != null) 'installedVersion': installedVersion,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeGatewaySession session;
  late GatewayRepository repository;

  /// 网关上的技能列表；安装成功的用例里由 [onInstall] 改写它。
  List<Map<String, dynamic>> skills = const [];
  Map<String, dynamic> searchResponse = const {'results': <dynamic>[]};
  Map<String, dynamic> detailResponse = const {};

  /// 安装行为完全交给用例决定：返回什么、抛什么、装完之后网关长什么样。
  Future<Map<String, dynamic>> Function(String slug, String? version)? onInstall;

  int installCalls = 0;

  /// 造一个已连接的仓库，并把协议请求接到上面那几个用例可改的字段上。
  Future<void> setUpRepository({
    bool admin = true,
    bool clawHubMethods = true,
  }) async {
    skills = const [];
    searchResponse = const {'results': <dynamic>[]};
    detailResponse = const {};
    onInstall = null;
    installCalls = 0;

    // "有没有 admin" 必须在两处同时成立：hello 说的**凭据授权**，以及这次握手
    // **请求的集合**。网关的方法鉴权只认后者（`dist/server-methods-NpEcZnvp.js:80-83`），
    // 只把 hello 的 scopes 改小是测不出"缺权限"的。
    final scopes =
        admin
            ? const <String>['operator.admin', 'operator.read']
            : const <String>['operator.read'];

    final built = await buildConnectedRepository(
      hello: helloJson(
        scopes: scopes,
        methods: clawHubMethods
            ? const <String>['skills.search', 'skills.detail', 'skills.install']
            : const <String>['skills.status'],
      ),
      scopes: scopes,
    );
    session = built.session;
    repository = built.repository;
    session.handler = (method, params) {
      switch (method) {
        case 'skills.status':
          return {'skills': skills};
        case 'skills.search':
          return searchResponse;
        case 'skills.detail':
          return detailResponse;
        case 'skills.install':
          installCalls++;
          final handler = onInstall;
          if (handler == null) return const <String, dynamic>{};
          return handler(
            params?['slug'] as String? ?? '',
            params?['version'] as String?,
          );
      }
      // 其余方法（sessions.list / models 等）一律回空成功响应。
      return const <String, dynamic>{};
    };
    // 等 _markConnected 里那几个 fire-and-forget 的初始化跑完。
    await pumpEventQueue();
  }

  setUp(setUpRepository);

  test('安装成功：写回提示并刷新出「已安装」', () async {
    onInstall = (slug, version) async {
      expect(slug, '@youdao/youdao-note');
      expect(version, '1.0.0');
      skills = [installedSkillJson()];
      return const {'message': 'Installed @youdao/youdao-note.'};
    };

    final ok = await repository.installClawHubSkillFromGateway(
      slug: '@youdao/youdao-note',
      version: '1.0.0',
    );

    expect(ok, isTrue);
    expect(repository.clawHubMessage, 'Installed @youdao/youdao-note.');
    expect(repository.clawHubError, isNull);
    expect(repository.skills.single.clawHubInstalledVersion, '1.0.0');
  });

  test('安装返回 warning 时，提示里两段都要带上', () async {
    onInstall = (_, _) async {
      skills = [installedSkillJson()];
      return const {
        'message': 'Installed.',
        'warning': 'Not scanned by ClawHub.',
      };
    };

    await repository.installClawHubSkillFromGateway(
      slug: '@youdao/youdao-note',
      version: '1.0.0',
    );

    expect(repository.clawHubMessage, 'Installed.\n\nNot scanned by ClawHub.');
  });

  test('超时但回读发现装上了 → 算成功，不能报失败让用户重装', () async {
    onInstall = (_, _) async {
      skills = [installedSkillJson()];
      throw TimeoutException('gateway request timed out');
    };

    final ok = await repository.installClawHubSkillFromGateway(
      slug: '@youdao/youdao-note',
      version: '1.0.0',
    );

    expect(ok, isTrue);
    expect(repository.clawHubError, isNull);
    expect(repository.clawHubMessage, '已安装 @youdao/youdao-note');
  });

  test('超时且确实没装上 → 提示「结果未知」并说明网关会接续', () async {
    onInstall =
        (_, _) async => throw TimeoutException('gateway request timed out');

    final ok = await repository.installClawHubSkillFromGateway(
      slug: '@youdao/youdao-note',
      version: '1.0.0',
    );

    expect(ok, isFalse);
    expect(repository.clawHubError, contains('安装结果未知'));
    expect(repository.clawHubError, contains('接续'));
  });

  test('被网关拒绝：带上网关的 message 与 clawhubWarning', () async {
    onInstall = (_, _) async {
      throw GatewayResponseError(
        method: 'skills.install',
        code: 'UNAVAILABLE',
        message: 'ClawHub blocked this release.',
        details: const {'clawhubWarning': 'Security verification failed.'},
      );
    };

    final ok = await repository.installClawHubSkillFromGateway(
      slug: '@youdao/youdao-note',
      version: '1.0.0',
    );

    expect(ok, isFalse);
    expect(repository.clawHubError, contains('ClawHub blocked this release.'));
    expect(repository.clawHubError, contains('Security verification failed.'));
  });

  test('被拒绝但其实装上了 → 算成功', () async {
    onInstall = (_, _) async {
      skills = [installedSkillJson()];
      throw GatewayResponseError(
        method: 'skills.install',
        code: 'UNAVAILABLE',
        message: 'timeout upstream',
      );
    };

    final ok = await repository.installClawHubSkillFromGateway(
      slug: '@youdao/youdao-note',
      version: '1.0.0',
    );

    expect(ok, isTrue);
    expect(repository.clawHubMessage, '已安装 @youdao/youdao-note');
  });

  test('装了别的版本不算安装成功', () async {
    onInstall = (_, _) async {
      skills = [installedSkillJson(installedVersion: '0.9.0')];
      throw TimeoutException('gateway request timed out');
    };

    final ok = await repository.installClawHubSkillFromGateway(
      slug: '@youdao/youdao-note',
      version: '1.0.0',
    );

    expect(ok, isFalse);
    expect(repository.clawHubError, contains('安装结果未知'));
  });

  test('install-only 的来源不带版本，按原始引用回读', () async {
    onInstall = (slug, version) async {
      expect(version, isNull);
      skills = [
        installedSkillJson(requestedReference: 'raw/thing'),
      ];
      throw TimeoutException('gateway request timed out');
    };

    final ok = await repository.installClawHubSkillFromGateway(
      slug: 'raw/thing',
    );

    expect(ok, isTrue);
  });

  test('缺 operator.admin 时直接拦下，不打网关', () async {
    await setUpRepository(admin: false);

    final ok = await repository.installClawHubSkillFromGateway(
      slug: '@youdao/youdao-note',
      version: '1.0.0',
    );

    expect(ok, isFalse);
    expect(installCalls, 0);
    expect(repository.clawHubError, contains('operator.admin'));
  });

  test('网关没宣告方法族时提示升级，不打网关', () async {
    await setUpRepository(clawHubMethods: false);

    final ok = await repository.installClawHubSkillFromGateway(
      slug: '@youdao/youdao-note',
      version: '1.0.0',
    );

    expect(ok, isFalse);
    expect(installCalls, 0);
    expect(repository.clawHubError, contains('升级 Gateway'));
  });

  test('同一条结果重复点击只打一次网关', () async {
    final gate = Completer<void>();
    onInstall = (_, _) async {
      await gate.future;
      skills = [installedSkillJson()];
      return const <String, dynamic>{};
    };

    final first = repository.installClawHubSkillFromGateway(
      slug: '@youdao/youdao-note',
      version: '1.0.0',
    );
    final second = await repository.installClawHubSkillFromGateway(
      slug: '@youdao/youdao-note',
      version: '1.0.0',
    );
    expect(second, isFalse);
    expect(installCalls, 1);

    gate.complete();
    expect(await first, isTrue);
    // 安装结束后要把「安装中」清掉，否则按钮永远停在那一档。
    expect(repository.clawHubInstallingSlugs, isEmpty);
  });

  test('审核弹窗取消后清空审核信息，可以再次审核', () async {
    detailResponse = {
      'skill': {'slug': 'youdao-note', 'displayName': 'YoudaoNote'},
      'latestVersion': {'version': '1.0.0'},
      'owner': {'handle': 'youdao', 'displayName': 'Youdao'},
    };
    const summary = GatewayClawHubSkillSummary(
      slug: 'youdao-note',
      displayName: 'YoudaoNote',
      version: '1.0.0',
    );

    expect(
      await repository.reviewClawHubSkillInstallFromGateway(summary),
      isTrue,
    );
    expect(repository.clawHubInstallReview?.version, '1.0.0');

    repository.dismissClawHubSkillInstallReview();
    expect(repository.clawHubInstallReview, isNull);

    expect(
      await repository.reviewClawHubSkillInstallFromGateway(summary),
      isTrue,
    );
    expect(repository.clawHubInstallReview?.slug, '@youdao/youdao-note');
  });
}
