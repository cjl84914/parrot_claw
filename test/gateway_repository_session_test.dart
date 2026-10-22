import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_app/data/repository/gateway_repository.dart';
import 'package:parrot_app/data/service/gateway_connector.dart';

/// 网关会话的生命周期回归测试。
///
/// 这一层守的是「连接断了能不能自己回来」。runtime 层被删掉之后，自愈完全
/// 依赖 `GatewaySession` 自带的退避重连 + tick 看门狗，仓库只负责把状态翻给
/// UI。所以这里用**真实会话 + 假 socket**跑端到端：重连真的会发生、半开连接
/// 会被看门狗抓到、主动断开之后不会再自己连回来。

/// 可控的内存 socket。
///
/// [failSend] 置 true 后所有写入都抛错 —— 这就是「这条配置连不上」的模拟方式。
class FakeSocket implements GatewaySocket {
  FakeSocket({this.failSend = false});

  final controller = StreamController<dynamic>();
  final sent = <String>[];
  bool failSend;
  bool closed = false;

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  Future<void> get ready async {}

  @override
  void send(String data) {
    if (failSend) throw StateError('socket write failed');
    sent.add(data);
    final frame = jsonDecode(data) as Map<String, dynamic>;
    // connect 握手由用例显式应答（这样测试才能控制「什么时候算连上」）；
    // 其余请求一律立即回一个空成功响应，免得仓库在 _markConnected 之后拉的
    // 会话 / 模型 / 历史堆一堆 15s 超时定时器。
    if (frame['method'] == 'connect') return;
    scheduleMicrotask(() {
      emit({'type': 'res', 'id': frame['id'], 'ok': true, 'payload': {}});
    });
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!controller.isClosed) await controller.close();
  }

  void emit(Map<String, dynamic> frame) {
    if (controller.isClosed) return;
    controller.add(jsonEncode(frame));
  }
}

class FakeSocketFactory implements GatewaySocketFactory {
  FakeSocketFactory({this.failSend = false});

  final bool failSend;
  final sockets = <FakeSocket>[];

  @override
  GatewaySocket connect(Uri uri, {required Duration timeout}) {
    final socket = FakeSocket(failSend: failSend);
    sockets.add(socket);
    // challenge 一定要发：连不上的场景靠 send() 抛错来模拟，而不是靠握手超时。
    scheduleMicrotask(() {
      socket.emit({
        'type': 'event',
        'event': 'connect.challenge',
        'payload': {'nonce': 'nonce-${sockets.length}'},
      });
    });
    return socket;
  }
}

Map<String, dynamic> helloPayload({num? tickIntervalMs}) => {
  'type': 'hello-ok',
  'protocol': 4,
  'snapshot': <String, dynamic>{},
  'server': <String, dynamic>{},
  'features': <String, dynamic>{},
  'auth': <String, dynamic>{},
  'policy': {if (tickIntervalMs != null) 'tickIntervalMs': tickIntervalMs},
};

/// 应答 socket 上的 connect 握手。
///
/// [tickIntervalMs] 决定会话的 tick 看门狗节拍（检查周期 = tick，判死阈值 =
/// 2×tick），用来在毫秒级复现「半开连接」。
Future<void> completeHandshake(
  FakeSocket socket, {
  num? tickIntervalMs,
}) async {
  final request = socket.sent
      .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
      .firstWhere((frame) => frame['method'] == 'connect');
  socket.emit({
    'type': 'res',
    'id': request['id'],
    'ok': true,
    'payload': helloPayload(tickIntervalMs: tickIntervalMs),
  });
  await Future<void>.delayed(Duration.zero);
}

int _nextRequestId = 0;

GatewaySession buildSession(
  FakeSocketFactory factory, {
  required void Function(GatewayPush push) onPush,
  required void Function(String reason) onDisconnect,
}) {
  return GatewaySession(
    url: 'ws://test',
    token: null,
    password: null,
    pushHandler: onPush,
    disconnectHandler: onDisconnect,
    connectOptions: const GatewayConnectOptions(
      role: 'operator',
      scopes: ['operator.read'],
      caps: [],
      commands: [],
      permissions: {},
      clientId: 'test-client',
      clientMode: 'ui',
      includeDeviceIdentity: false,
    ),
    socketFactory: factory,
    idGenerator: () => 'req-${_nextRequestId++}',
    // 刻意用很短的退避：这样「会话自己会不会重连」在测试里几毫秒就能观察到。
    retryPolicy: const GatewayRetryPolicy(
      initialDelay: Duration(milliseconds: 10),
      maxDelay: Duration(milliseconds: 20),
    ),
  );
}

Future<void> waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('等待条件超时');
}

const healthyConfig = GatewayConnectConfig(url: 'ws://healthy.test');
const brokenConfig = GatewayConnectConfig(url: 'ws://broken.test');

/// 同一个地址、只换 token 的一对配置。
///
/// 「同一地址」是关键：设备令牌/长效 token 都是打到同一个网关端口，改的只是
/// 凭据本身。仓库判「要不要换会话」靠的是 `GatewayConnectConfig` 的**值相等**
/// （`==` 里含 token / password / scopes），所以只换 token 也必须被判成新配置 ——
/// 一旦有人把它"优化"成只比 url，新凭据就永远换不上，而症状极具迷惑性：
/// 能连上、配置也是对的，只是权限还是旧的（要重启 App 才生效）。
const oldTokenConfig = GatewayConnectConfig(
  url: 'ws://gw.test',
  token: 'old-token',
  scopes: <String>['operator.read'],
);
const newTokenConfig = GatewayConnectConfig(
  url: 'ws://gw.test',
  token: 'new-token',
  scopes: <String>['operator.admin', 'operator.read'],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('掉线后由会话自带的退避重连把连接拉回来，仓库状态回到已连接', () async {
    final factory = FakeSocketFactory();
    final repository = GatewayRepository(
      sessionFactory:
          ({required config, required onPush, required onDisconnect}) =>
              buildSession(factory, onPush: onPush, onDisconnect: onDisconnect),
    );

    final connected = repository.connect(healthyConfig);
    await Future<void>.delayed(Duration.zero);
    await completeHandshake(factory.sockets[0]);
    await connected;
    expect(repository.connected, isTrue);
    expect(repository.isReconnecting, isFalse);

    // 网关重启：服务端关闭连接。
    await factory.sockets[0].controller.close();

    // 仓库只负责把状态翻成「正在重连」……
    await waitUntil(() => repository.isReconnecting);
    expect(repository.connected, isFalse);
    expect(repository.disconnectReason, isNotNull);

    // ……把连接拉回来的是会话自己的退避循环，这里没有任何守护层参与。
    await waitUntil(() => factory.sockets.length >= 2);
    await completeHandshake(factory.sockets[1]);
    await waitUntil(() => repository.connected);
    expect(repository.isReconnecting, isFalse);
    expect(
      repository.disconnectReason,
      isNull,
      reason: '自愈之后 UI 不该还挂着「已断开」的文案',
    );

    repository.dispose();
  });

  test('tick 看门狗抓得住半开连接并重开 socket', () async {
    final factory = FakeSocketFactory();
    final repository = GatewayRepository(
      sessionFactory:
          ({required config, required onPush, required onDisconnect}) =>
              buildSession(factory, onPush: onPush, onDisconnect: onDisconnect),
    );

    final connected = repository.connect(healthyConfig);
    await Future<void>.delayed(Duration.zero);
    // tickIntervalMs=20 → 看门狗每 20ms 检查一次，静默超过 40ms 就判死。
    await completeHandshake(factory.sockets[0], tickIntervalMs: 20);
    await connected;
    expect(repository.connected, isTrue);

    // 对端半开：socket 既不关闭、也不发 tick。没有看门狗的话，这里会一直
    // 停在「已连接」直到某次请求超时。
    await waitUntil(() => factory.sockets.length >= 2);
    await completeHandshake(factory.sockets[1], tickIntervalMs: 20);
    await waitUntil(() => repository.connected);
    expect(repository.connected, isTrue);

    repository.dispose();
  });

  test('主动断开后不再自动重连', () async {
    final factory = FakeSocketFactory();
    final repository = GatewayRepository(
      sessionFactory:
          ({required config, required onPush, required onDisconnect}) =>
              buildSession(factory, onPush: onPush, onDisconnect: onDisconnect),
    );

    final connected = repository.connect(healthyConfig);
    await Future<void>.delayed(Duration.zero);
    await completeHandshake(factory.sockets[0]);
    await connected;

    await repository.disconnect();
    await factory.sockets[0].controller.close();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(factory.sockets, hasLength(1), reason: '主动断开后不应再自动重连');
    expect(repository.connected, isFalse);
    expect(repository.isReconnecting, isFalse);

    repository.dispose();
  });

  test('切到连不上的配置：旧会话保持可用，坏配置不留重连风暴', () async {
    final healthy = FakeSocketFactory();
    final broken = FakeSocketFactory(failSend: true);
    final repository = GatewayRepository(
      sessionFactory:
          ({required config, required onPush, required onDisconnect}) =>
              buildSession(
                config.url == brokenConfig.url ? broken : healthy,
                onPush: onPush,
                onDisconnect: onDisconnect,
              ),
    );

    final connected = repository.connect(healthyConfig);
    await Future<void>.delayed(Duration.zero);
    await completeHandshake(healthy.sockets[0]);
    await connected;
    expect(repository.connected, isTrue);

    await repository.connect(brokenConfig);

    // 失败的新配置既不能带走旧连接，也不能让 UI 掉到「未连接」。
    expect(repository.connected, isTrue);
    expect(healthy.sockets[0].closed, isFalse);

    // 候选会话已被退役：即使退避只有 10ms，也不该拉起后台重连风暴。
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(broken.sockets, hasLength(1), reason: '失败不该拉起后台重连风暴');
    expect(repository.connected, isTrue);

    repository.dispose();
  });

  test('切换网关成功后才拆掉旧会话', () async {
    final factory = FakeSocketFactory();
    final repository = GatewayRepository(
      sessionFactory:
          ({required config, required onPush, required onDisconnect}) =>
              buildSession(factory, onPush: onPush, onDisconnect: onDisconnect),
    );

    final first = repository.connect(healthyConfig);
    await Future<void>.delayed(Duration.zero);
    await completeHandshake(factory.sockets[0]);
    await first;

    final second = repository.connect(brokenConfig);
    await Future<void>.delayed(Duration.zero);
    expect(factory.sockets, hasLength(2), reason: '新会话先连上，旧会话此时还开着');
    expect(factory.sockets[0].closed, isFalse);

    await completeHandshake(factory.sockets[1]);
    await second;

    expect(repository.connected, isTrue);
    await waitUntil(() => factory.sockets[0].closed);
    expect(
      factory.sockets[0].closed,
      isTrue,
      reason: '握手成功之后才退役旧会话',
    );

    repository.dispose();
  });

  /// 回归背景：在配置页改掉 token 后，权限（`operator.admin`）一直不生效，但
  /// **重启 App 就好了**。原因不是 scopes 存错了 —— 是那条活着的会话根本没被
  /// 替换：它仍然握着旧凭据、旧请求列表在工作，而重启会重新建会话，于是"看起来
  /// 是重启才生效"。
  ///
  /// 这里钉住的是替换判据：同一个 url、只有 token 不同，也必须算"换了配置"。
  test('同一个 url、只换了 token 也必须换会话并退役旧的', () async {
    final factory = FakeSocketFactory();
    final configs = <GatewayConnectConfig>[];
    final repository = GatewayRepository(
      sessionFactory: ({
        required config,
        required onPush,
        required onDisconnect,
      }) {
        configs.add(config);
        return buildSession(factory, onPush: onPush, onDisconnect: onDisconnect);
      },
    );

    final first = repository.connect(oldTokenConfig);
    await Future<void>.delayed(Duration.zero);
    await completeHandshake(factory.sockets[0]);
    await first;
    expect(factory.sockets, hasLength(1));

    final second = repository.connect(newTokenConfig);
    await Future<void>.delayed(Duration.zero);
    expect(
      factory.sockets,
      hasLength(2),
      reason: 'token 变了就是新配置，必须另建会话而不是在旧会话上重连',
    );
    expect(configs[1].token, 'new-token');

    await completeHandshake(factory.sockets[1]);
    await second;

    await waitUntil(() => factory.sockets[0].closed);
    expect(factory.sockets[0].closed, isTrue, reason: '旧会话必须被退役');
    expect(repository.connected, isTrue);

    repository.dispose();
  });
}
