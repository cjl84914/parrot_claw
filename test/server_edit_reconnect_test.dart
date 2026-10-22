import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/repository/gateway_repository.dart';
import 'package:parrot_app/data/repository/server_repository.dart';
import 'package:parrot_app/data/service/gateway_session.dart';
import 'package:parrot_app/data/service/storage_service.dart';
import 'package:parrot_app/ui/screen/server_edit_screen.dart';
import 'package:parrot_app/ui/view_model/conn_viewmodel.dart';
import 'package:parrot_app/ui/view_model/server_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_gateway_session.dart';

/// 配置页保存之后，「正在用的那条连接」有没有被换成新凭据。
///
/// 回归背景（用户实测）：在配置页改掉 token 并保存，权限（`operator.admin`）
/// 当场不生效，**重启 App 才生效**。
///
/// 根因不是"scopes 存错了"——存的是对的。是**那条活着的会话根本没被替换**：
/// - 改的是**同一个**服务器，`id` 没变 → `main.dart` 里 `IndexScreen` 的
///   `ValueKey(selectedServer.id)` 也没变 → 壳不重建 → `initState` 里那次
///   `connect()` 不会再跑；
/// - 配置页里那次"测试连接"用的是**用完即弃**的探测会话（`probeGateway`），
///   它不会碰正在工作的那条；
/// - 于是保存完回到首页，页面显示"已连接"，但握在手里的还是旧凭据、旧请求
///   列表。重启时冷启动会重新建会话，所以"重启就好了"。
///
/// 修法是 `_saveConfig()` 末尾主动 `connect()` 一次。这个用例走真实控件复现
/// 用户的操作顺序（改 token → 点「连接」），钉住"保存后必须重连"。
void main() {
  /// 只做内存记录的服务器仓库：真实那个要 Hive 落盘，测试里没有 box。
  ///
  /// `updateServer` / `selectServer` 都要把选中项换成新实例 —— 生产代码里
  /// 正是靠这一步让随后的 `connect()` 读到新配置。
  final servers = _InMemoryServerRepository();

  tearDown(servers.reset);

  ServerConfig deviceTokenServer({String token = 'old-token'}) => ServerConfig(
    id: 's1',
    name: 'gw',
    host: '192.168.1.10',
    port: 18789,
    token: token,
    authMode: ServerConfig.authModeDeviceToken,
    operatorScopes: const <String>['operator.read', 'operator.write'],
    isDefault: true,
  );

  testWidgets('改 token 后保存：必须按新凭据重建会话，权限当场生效', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // 配置页比默认的 800×600 高，「连接」按钮会落在屏幕外点不到。
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final oldConfig = deviceTokenServer();
    servers.reset(oldConfig);

    // 记录仓库实际建了哪几条会话、用的什么配置。
    final sessions = <FakeGatewaySession>[];
    final configs = <GatewayConnectConfig>[];
    final repository = GatewayRepository(
      sessionFactory: ({
        required config,
        required onPush,
        required onDisconnect,
      }) {
        configs.add(config);
        final session = FakeGatewaySession(
          onPush: onPush,
          onDisconnect: onDisconnect,
          // 网关侧事实：新 token 带 admin，旧 token 不带。
          hello: helloJson(
            scopes:
                config.token == 'new-token'
                    ? const <String>[
                      'operator.admin',
                      'operator.read',
                      'operator.write',
                    ]
                    : const <String>['operator.read', 'operator.write'],
          ),
        );
        sessions.add(session);
        return session;
      },
    );

    final serverViewModel = _StubServerViewModel(
      serverRepository: servers,
      gatewayRepository: repository,
      // 探测（试连）成功，且网关回带的是新凭据的授权。
      hello: helloJson(
        scopes: const <String>[
          'operator.admin',
          'operator.read',
          'operator.write',
        ],
      ),
    );
    final connViewModel = ConnViewModel(
      gatewayRepository: repository,
      serverRepository: servers,
    );

    // ① 冷启动那条连接：按**旧**凭据建的，没有 admin。
    await connViewModel.connect();
    expect(sessions, hasLength(1));
    expect(configs.single.token, 'old-token');
    expect(repository.clawHubCanInstall, isFalse);

    final router = GoRouter(
      initialLocation: '/server_edit',
      routes: <RouteBase>[
        GoRoute(
          path: '/index',
          builder: (context, state) => const Scaffold(body: Text('首页')),
        ),
        GoRoute(
          path: '/server_edit',
          builder:
              (context, state) => ServerEditScreen(
                viewModel: serverViewModel,
                server: oldConfig,
              ),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<ConnViewModel>.value(value: connViewModel),
          ChangeNotifierProvider<ServerViewModel>.value(
            value: serverViewModel,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    // ② 用户把 token 改掉（第 4 个输入框：名称 / 地址 / 端口 / 令牌）。
    await tester.enterText(find.byType(TextFormField).at(3), 'new-token');
    await tester.pump();

    // ③ 点「连接」→ 试连成功 → 保存 → 回首页。
    await tester.tap(find.widgetWithText(FilledButton, '连接'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(serverViewModel.probes, hasLength(1));
    expect(serverViewModel.probes.single.token, 'new-token');

    // ④ 关键断言：那条活着的会话必须被换成新凭据的。
    expect(
      configs,
      hasLength(2),
      reason: '保存后必须重连一次；只有探测那条（用完即弃）不算',
    );
    expect(configs[1].token, 'new-token', reason: '新会话必须用新 token');
    expect(sessions[0].shutDown, isTrue, reason: '旧会话必须被退役');
    expect(
      repository.clawHubCanInstall,
      isTrue,
      reason: '换完会话后，当前连接当场就该有 operator.admin',
    );

    // 让提示条那 3s 定时器走完，避免留下 pending timer。
    await tester.pump(const Duration(seconds: 4));

    repository.dispose();
    connViewModel.dispose();
  });
}

/// 内存版服务器仓库：只保留"当前选中"这一份配置。
class _InMemoryServerRepository extends ServerRepository {
  _InMemoryServerRepository() : super(StorageService());

  ServerConfig? _selected;

  final List<ServerConfig> saved = <ServerConfig>[];

  void reset([ServerConfig? selected]) {
    _selected = selected;
    saved.clear();
  }

  @override
  ServerConfig? get selectedServer => _selected;

  @override
  List<ServerConfig> get servers =>
      _selected == null ? const <ServerConfig>[] : <ServerConfig>[_selected!];

  @override
  Future<void> updateServer(String id, ServerConfig newConfig) async {
    saved.add(newConfig);
    _selected = newConfig;
    notifyListeners();
  }

  @override
  void selectServer(ServerConfig? server) {
    _selected = server;
    notifyListeners();
  }
}

/// 把试连固定成「成功」的服务器 ViewModel。
///
/// 真实的 `probeServer` 会经 `probeGateway` 开一条真 WebSocket，测试里跑不了；
/// 它本身也不是本用例要验证的东西 —— 要验证的是"试连成功之后有没有重连"。
class _StubServerViewModel extends ServerViewModel {
  _StubServerViewModel({
    required super.serverRepository,
    required super.gatewayRepository,
    required this.hello,
  });

  /// 试连时网关回带的 hello（决定探测结果里那份授权）。
  final Map<String, dynamic> hello;

  final List<ServerConfig> probes = <ServerConfig>[];

  @override
  Future<GatewayOperationResult<HelloOk>> probeServer(
    ServerConfig config,
  ) async {
    probes.add(config);
    return GatewayOperationResult<HelloOk>.success(
      data: HelloOk.fromJson(hello),
    );
  }
}
