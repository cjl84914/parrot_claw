import 'dart:async';

import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/repository/gateway_repository.dart';
import 'package:parrot_app/data/repository/server_repository.dart';
import 'package:parrot_app/data/repository/setting_repository.dart';
import 'package:parrot_app/data/service/gateway_session.dart';
import 'package:parrot_app/data/service/shared_preferences_service.dart';
import 'package:parrot_app/data/service/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 测试用的假会话。
///
/// 仓库现在直接持有 `GatewaySession`，所以测试的接缝就在这一层：覆写
/// `connect` / `shutdown` / `request` 三个方法，就能把整条协议链路替换掉，
/// 不需要真 WebSocket。协议请求按方法名分派 —— 比原先「继承 runtime 再逐个
/// 覆写 40 个命名方法」好维护得多。
class FakeGatewaySession extends GatewaySession {
  FakeGatewaySession({
    required void Function(GatewayPush push) onPush,
    required void Function(String reason) onDisconnect,
    this.hello = const <String, dynamic>{},
  }) : super(
         url: 'ws://fake',
         token: null,
         password: null,
         pushHandler: onPush,
         disconnectHandler: onDisconnect,
       );

  /// 握手时推给仓库的 hello 快照（决定 scopes 与 features.methods）。
  final Map<String, dynamic> hello;

  /// 按方法名决定响应；返回 null 表示「回一个空成功响应」。
  FutureOr<Map<String, dynamic>> Function(
    String method,
    Map<String, dynamic>? params,
  )?
  handler;

  /// 置 true 后所有请求都抛错，用来测失败路径。
  bool fail = false;

  /// 记录收到过的方法名，便于断言「有没有真的打到网关」。
  final List<String> requests = <String>[];

  bool shutDown = false;
  bool _connected = false;

  @override
  GatewaySessionState get state =>
      _connected ? GatewaySessionState.ready : GatewaySessionState.idle;

  @override
  bool get connected => _connected;

  @override
  Future<void> connect() async {
    _connected = true;
    // 握手成功推一份 snapshot —— 仓库的 _markConnected 认这个。
    pushHandler(GatewayPushSnapshot(HelloOk.fromJson(hello)));
  }

  @override
  Future<void> shutdown() async {
    shutDown = true;
    _connected = false;
  }

  @override
  Future<Map<String, dynamic>> request({
    required String method,
    Map<String, dynamic>? params,
    Duration? timeout,
  }) async {
    requests.add(method);
    if (fail) throw StateError('$method failed');
    final handler = this.handler;
    if (handler == null) return const <String, dynamic>{};
    return await handler(method, params);
  }

  /// 手动推一个网关事件（例如 chat 的 final）。
  void emitEvent(String event, dynamic payload) =>
      pushHandler(GatewayPushEvent(event, payload));
}

/// 只用来指定「当前选中的服务器」的仓库替身。
///
/// 真实的 ServerRepository 靠 Hive 落盘，测试里没有 box，selectServer() 会立刻
/// 被 _loadServers() 复位成 null。所以这里直接覆写 getter。
class FakeServerRepository extends ServerRepository {
  FakeServerRepository(this._selected) : super(StorageService());

  ServerConfig? _selected;

  @override
  ServerConfig? get selectedServer => _selected;

  void setSelected(ServerConfig? server) => _selected = server;
}

ServerConfig serverAt(String host) =>
    ServerConfig(id: host, name: host, host: host, port: 18789);

/// 造一个 hello 快照 JSON。
Map<String, dynamic> helloJson({
  List<String> scopes = const <String>['operator.admin', 'operator.read'],
  List<String> methods = const <String>[
    'skills.status',
    'skills.search',
    'skills.detail',
    'skills.install',
  ],
}) => {
  'type': 'hello',
  'protocol': 4,
  'features': {'methods': methods},
  'auth': {'scopes': scopes},
  'snapshot': <String, dynamic>{},
  'server': <String, dynamic>{},
  'policy': <String, dynamic>{},
};

/// 造一个已经连上的仓库，并把工厂实际造出的那条假会话交回给用例。
///
/// 握手成功后仓库会自动拉会话列表 / 模型 / 历史，假会话对未知方法一律回空
/// 成功响应，所以这些副作用不会炸。
///
/// [scopes] 是**这次握手请求的集合**。它与 [hello] 里 `auth.scopes` 是两回事：
/// 后者是凭据授权（设备令牌会话回的是令牌自身的 scopes，可能是请求集合的超集），
/// 而网关的方法鉴权只认请求列表（`dist/server-methods-NpEcZnvp.js:80-83`）。
/// 要测"这次会话有没有某个权限"，必须把 [scopes] 一起收窄。
Future<({GatewayRepository repository, FakeGatewaySession session})>
buildConnectedRepository({
  ServerConfig? server,
  Map<String, dynamic>? hello,
  List<String> scopes = openClawOperatorScopes,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  late FakeGatewaySession session;
  final repository = GatewayRepository(
    sessionFactory: ({required config, required onPush, required onDisconnect}) {
      session = FakeGatewaySession(
        onPush: onPush,
        onDisconnect: onDisconnect,
        hello: hello ?? helloJson(),
      );
      return session;
    },
  );

  await repository.connect(
    GatewayConnectConfig(url: 'ws://fake', scopes: scopes),
  );
  // 这里**不要**顺手 pumpEventQueue()：它内部靠 `Future.delayed`，
  // 在 `testWidgets` 的假时钟下没有 pump 就永远不返回，整个用例会卡死。
  // 需要「等 `_markConnected` 那几个 fire-and-forget 请求落地」的用例，
  // 自己在用例体里 await pumpEventQueue()。
  return (repository: repository, session: session);
}
