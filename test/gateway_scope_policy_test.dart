import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/repository/gateway_repository.dart';
import 'package:parrot_app/data/service/gateway_session.dart';
import 'package:parrot_app/ui/view_model/conn_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_gateway_session.dart';

/// 连接时请求哪些 scopes，由**凭据种类 + 配置里记录的授权集合**决定。
///
/// 网关的两条规则（`dist/device-pairing`、`dist/server-methods`）：
/// - 设备令牌会话要求「请求 ⊆ 该令牌授权」，多要一个就整条握手被拒
///   （`device token scope mismatch`）；
/// - **会话权限就是请求列表本身**（方法鉴权读 `client.connect.scopes`），
///   所以少要一个就真的没有那个权限。
///
/// 回归背景：曾经把扫码配对拿到的 scopes 按 `wsUrl` 存一份、重连时读回来；
/// 凭据换成网关长效 token 后旧记录仍然命中，请求里永远没有 `operator.admin`
/// （删会话等功能报缺权限）。改成"按凭据推导"后走到另一个极端 —— 硬编码的
/// 受限集合里有 `operator.questions`，而网关只授了 4 个 scope，于是握手被拒。
/// 正确做法是：**配对时记下网关发的那一份，连接时原样请求，连上后再用
/// `hello.auth.scopes` 校正**。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ServerConfig config({
    required String authMode,
    String token = 'gateway-token',
    String password = '',
    List<String> operatorScopes = const <String>[],
  }) {
    return ServerConfig(
      id: 's1',
      name: 'gw',
      host: '192.168.1.10',
      port: 18789,
      token: token,
      password: password,
      authMode: authMode,
      operatorScopes: operatorScopes,
    );
  }

  group('请求哪些 scopes', () {
    test('长效 token（手动配置）按默认全量请求，拿得到 operator.admin', () {
      final connect = GatewayConnectConfig.fromServer(
        config(authMode: ServerConfig.authModeToken),
      );

      expect(connect.scopes, contains('operator.admin'));
      expect(connect.scopes, openClawOperatorScopes);
      expect(connect.token, 'gateway-token');
      expect(connect.password, isNull);
    });

    test('设备令牌原样请求配对时记下的那一份，不多也不少', () {
      // 网关实际只授了 4 个（没有 operator.questions）—— 多要就会被拒。
      const granted = <String>[
        'operator.approvals',
        'operator.read',
        'operator.talk.secrets',
        'operator.write',
      ];

      final connect = GatewayConnectConfig.fromServer(
        config(
          authMode: ServerConfig.authModeDeviceToken,
          token: 'device-token',
          operatorScopes: granted,
        ),
      );

      expect(connect.scopes, granted);
      expect(connect.scopes, isNot(contains('operator.questions')));
      expect(connect.scopes, isNot(contains('operator.admin')));
      expect(connect.token, 'device-token');
    });

    test('设备令牌没有记录时退到最小可用集合（保证握手能过）', () {
      final connect = GatewayConnectConfig.fromServer(
        config(authMode: ServerConfig.authModeDeviceToken, token: 'device-token'),
      );

      expect(connect.scopes, openClawMinimalOperatorScopes);
      // 关键：不能退到硬编码的受限集合 —— 里面的 operator.questions 在很多网关
      // 上并不在授权范围内，会被 device token scope mismatch 直接拒掉。
      expect(connect.scopes, isNot(contains('operator.questions')));
      expect(connect.scopes, isNot(contains('operator.admin')));
    });

    test('密码认证按全量请求，凭据走 password 字段', () {
      final connect = GatewayConnectConfig.fromServer(
        config(
          authMode: ServerConfig.authModePassword,
          token: '',
          password: 'pw',
        ),
      );

      expect(connect.scopes, openClawOperatorScopes);
      expect(connect.token, isNull);
      expect(connect.password, 'pw');
    });

    test('authMode 语义：设备令牌算 token 认证，不算密码认证', () {
      final deviceToken = config(authMode: ServerConfig.authModeDeviceToken);

      expect(deviceToken.isTokenAuth, isTrue);
      expect(deviceToken.isDeviceTokenAuth, isTrue);
      expect(deviceToken.isPasswordAuth, isFalse);
    });
  });

  group('连接成功后校正 scopes', () {
    test('设备令牌配置用 hello.auth.scopes 覆盖旧记录（网关升权后自愈）', () async {
      final servers = _RecordingServerRepository(
        config(
          authMode: ServerConfig.authModeDeviceToken,
          token: 'device-token',
          operatorScopes: const <String>['operator.read'],
        ),
      );
      final built = await buildConnectedRepository(
        hello: helloJson(
          scopes: const <String>[
            'operator.admin',
            'operator.approvals',
            'operator.read',
            'operator.write',
          ],
        ),
      );
      final viewModel = ConnViewModel(
        gatewayRepository: built.repository,
        serverRepository: servers,
      );

      await viewModel.connect();

      expect(servers.updates, hasLength(1));
      expect(servers.updates.single.operatorScopes, <String>[
        'operator.admin',
        'operator.approvals',
        'operator.read',
        'operator.write',
      ]);
      // 凭据种类不能被动摇。
      expect(
        servers.updates.single.authMode,
        ServerConfig.authModeDeviceToken,
      );
    });

    test('记录已经一致时不写盘（避免每次连接都触发一次仓库通知）', () async {
      final servers = _RecordingServerRepository(
        config(
          authMode: ServerConfig.authModeDeviceToken,
          token: 'device-token',
          operatorScopes: const <String>['operator.admin', 'operator.read'],
        ),
      );
      final built = await buildConnectedRepository(
        hello: helloJson(scopes: const <String>['operator.admin', 'operator.read']),
      );
      final viewModel = ConnViewModel(
        gatewayRepository: built.repository,
        serverRepository: servers,
      );

      await viewModel.connect();

      expect(servers.updates, isEmpty);
    });

    test('共享 token 配置不写回（它的 auth.scopes 就是请求值本身）', () async {
      final servers = _RecordingServerRepository(
        config(authMode: ServerConfig.authModeToken),
      );
      final built = await buildConnectedRepository(
        hello: helloJson(scopes: const <String>['operator.admin']),
      );
      final viewModel = ConnViewModel(
        gatewayRepository: built.repository,
        serverRepository: servers,
      );

      await viewModel.connect();

      expect(servers.updates, isEmpty);
    });
  });

  /// 回归背景：扫码配对时把网关发的那份 scopes 记进了配置，之后在网关侧
  /// `devices approve` 升到含 `operator.admin` 的 6 个。此时客户端持有的凭据
  /// 一个字没变，配置页保存时若沿用旧记录，连接请求里就永远没有 admin。
  /// 唯一能学到最新权限的时机是握手本身 —— 探测（`probeServer`）拿回的那份
  /// hello 必须用来覆盖配置，而不是被丢掉。
  group('用探测结果校正配置里的 scopes', () {
    ServerConfig deviceTokenConfig({List<String> operatorScopes = const []}) =>
        config(
          authMode: ServerConfig.authModeDeviceToken,
          token: 'device-token',
          operatorScopes: operatorScopes,
        );

    test('设备令牌会话回的是该令牌自身的 scopes，原样取出', () {
      final hello = HelloOk.fromJson(
        helloJson(
          scopes: const <String>[
            'operator.admin',
            'operator.read',
            'operator.write',
          ],
        ),
      );

      expect(grantedScopesFromHello(hello), <String>[
        'operator.admin',
        'operator.read',
        'operator.write',
      ]);
    });

    test('归一化：去空白、丢空串与非字符串', () {
      final hello = HelloOk.fromJson(<String, dynamic>{
        'auth': {
          'scopes': <dynamic>[' operator.read ', '', '   ', 7, 'operator.admin'],
        },
      });

      expect(grantedScopesFromHello(hello), <String>[
        'operator.read',
        'operator.admin',
      ]);
    });

    test('没学到 scopes 时返回 null', () {
      expect(grantedScopesFromHello(null), isNull);
      expect(
        grantedScopesFromHello(HelloOk.fromJson(helloJson(scopes: const []))),
        isNull,
      );
      expect(
        grantedScopesFromHello(HelloOk.fromJson(const <String, dynamic>{})),
        isNull,
      );
    });

    test('approve 后的 6 个覆盖掉扫码时那份旧的（本次问题回归）', () {
      final stale = deviceTokenConfig(
        operatorScopes: const <String>[
          'operator.approvals',
          'operator.read',
          'operator.talk.secrets',
          'operator.write',
        ],
      );
      final hello = HelloOk.fromJson(
        helloJson(
          scopes: const <String>[
            'operator.admin',
            'operator.approvals',
            'operator.questions',
            'operator.read',
            'operator.talk.secrets',
            'operator.write',
          ],
        ),
      );

      final saved = withGrantedScopesFromHello(stale, hello);

      expect(saved.operatorScopes, contains('operator.admin'));
      expect(saved.operatorScopes, hasLength(6));
      // 覆盖只动 scopes：凭据种类与凭据本身不能被牵连。
      expect(saved.authMode, ServerConfig.authModeDeviceToken);
      expect(saved.token, 'device-token');
      // 覆盖后的这份必须原样成为连接请求 —— 否则"保存了却没生效"。
      expect(GatewayConnectConfig.fromServer(saved).scopes, saved.operatorScopes);
    });

    test('没学到时原样返回同一实例，不清空已知能用的记录', () {
      final stale = deviceTokenConfig(
        operatorScopes: const <String>['operator.read'],
      );

      expect(identical(withGrantedScopesFromHello(stale, null), stale), isTrue);
    });
  });
  /// `hello.auth.scopes` 与"本次会话能用什么"是两回事：前者是**凭据授权**
  /// （设备令牌会话回的是令牌自身的 scopes，可能是请求集合的超集），后者只由
  /// **握手请求列表**决定（网关 `authorizeGatewayMethod` 读 `client.connect.scopes`，
  /// 见 `dist/server-methods-NpEcZnvp.js:80-83`）。
  /// 拿前者判断"能不能装"会给出一个可点、但必然报 missing scope 的按钮。
  group('clawHubCanInstall 只认请求列表', () {
    Future<GatewayRepository> connectRequesting(List<String> requested) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final repository = GatewayRepository(
        sessionFactory:
            ({required config, required onPush, required onDisconnect}) =>
                FakeGatewaySession(
                  onPush: onPush,
                  onDisconnect: onDisconnect,
                  // 令牌授权里始终有 admin —— 设备令牌会话的 hello 就长这样。
                  hello: helloJson(
                    scopes: const <String>[
                      'operator.admin',
                      'operator.approvals',
                      'operator.read',
                      'operator.write',
                    ],
                  ),
                ),
      );
      await repository.connect(
        GatewayConnectConfig(url: 'ws://fake', scopes: requested),
      );
      return repository;
    }

    test('令牌有 admin、但只请求了 read 时判为不可安装', () async {
      final repository = await connectRequesting(const <String>['operator.read']);

      // hello 确实在说"这份令牌有 admin"……
      expect(repository.grantedScopes, contains('operator.admin'));
      // ……但方法鉴权只认请求列表，所以实际装不了，不能给出可点的按钮。
      expect(repository.clawHubCanInstall, isFalse);
    });

    test('请求里带上 admin 时才判为可安装', () async {
      final repository = await connectRequesting(const <String>[
        'operator.admin',
        'operator.read',
      ]);

      expect(repository.clawHubCanInstall, isTrue);
    });
  });
}

/// 记录 updateServer 调用的服务器仓库替身。
class _RecordingServerRepository extends FakeServerRepository {
  _RecordingServerRepository(super.selected);

  final List<ServerConfig> updates = <ServerConfig>[];

  @override
  Future<void> updateServer(String id, ServerConfig newConfig) async {
    updates.add(newConfig);
    setSelected(newConfig);
  }
}
