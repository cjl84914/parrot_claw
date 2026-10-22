import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_app/data/service/gateway_session.dart';

class FakeSocket implements GatewaySocket {
  final controller = StreamController<dynamic>();
  final sent = <String>[];
  bool closed = false;

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  Future<void> get ready async {}

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    if (!controller.isClosed) await controller.close();
  }

  void emit(Map<String, dynamic> frame) {
    // 真实 socket 关闭后不会再投递服务端帧，这里同样静默丢弃。
    if (controller.isClosed) return;
    controller.add(jsonEncode(frame));
  }
}

class FakeFactory implements GatewaySocketFactory {
  final sockets = <FakeSocket>[];

  @override
  GatewaySocket connect(Uri uri, {required Duration timeout}) {
    final socket = FakeSocket();
    sockets.add(socket);
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

GatewayConnectOptions testOptions() => const GatewayConnectOptions(
  role: 'operator',
  scopes: ['operator.read'],
  caps: [],
  commands: [],
  permissions: {},
  clientId: 'test-client',
  clientMode: 'ui',
  includeDeviceIdentity: false,
);

Map<String, dynamic> helloPayload({num? tickIntervalMs}) => {
  'type': 'hello-ok',
  'protocol': 4,
  'server': {'version': 'test'},
  'features': <String, dynamic>{},
  'snapshot': <String, dynamic>{},
  'auth': <String, dynamic>{},
  'policy': {if (tickIntervalMs != null) 'tickIntervalMs': tickIntervalMs},
};

/// 应答 socket 上的 connect 握手。
///
/// [tickIntervalMs] 决定看门狗节拍：检查周期 = tick，判死阈值 = 2×tick，
/// 所以毫秒级的 tick 就能在测试里复现「半开连接」。
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
  // 让帧先被 socket 流投递出去。
  await Future<void>.delayed(Duration.zero);
}

Future<void> waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('等待条件超时：${predicate()}');
}

GatewaySession buildSession({
  required FakeFactory factory,
  required List<GatewayPush> pushes,
  List<String>? disconnects,
  Duration initialDelay = const Duration(milliseconds: 10),
}) => GatewaySession(
  url: 'ws://test',
  token: null,
  password: null,
  pushHandler: pushes.add,
  disconnectHandler: (reason) => disconnects?.add(reason),
  connectOptions: testOptions(),
  socketFactory: factory,
  idGenerator: () => 'id-${factory.sockets.length}-${pushes.length}',
  retryPolicy: GatewayRetryPolicy(
    initialDelay: initialDelay,
    maxDelay: const Duration(milliseconds: 40),
  ),
);

/// 首条连接的握手 + 断言，返回握手后的会话。
Future<GatewaySession> connectOnce(
  FakeFactory factory,
  List<GatewayPush> pushes, {
  List<String>? disconnects,
}) async {
  final session = buildSession(
    factory: factory,
    pushes: pushes,
    disconnects: disconnects,
  );
  final connecting = session.connect();
  await Future<void>.delayed(Duration.zero);
  await completeHandshake(factory.sockets.single);
  await connecting;
  return session;
}

void main() {
  test('RawJson preserves exact JSON text and can decode on demand', () {
    const raw = RawJson('{"b":2,"a":1}');
    expect(raw.value, '{"b":2,"a":1}');
    expect(raw.decode(), {'b': 2, 'a': 1});
  });

  test('connect handshake and request use injected socket', () async {
    final factory = FakeFactory();
    final pushes = <GatewayPush>[];
    final session = GatewaySession(
      url: 'ws://127.0.0.1:18789',
      token: null,
      password: null,
      pushHandler: pushes.add,
      connectOptions: testOptions(),
      socketFactory: factory,
      idGenerator: () => 'request-${factory.sockets.length}-${pushes.length}',
    );

    final connecting = session.connect();
    await Future<void>.delayed(Duration.zero);
    final socket = factory.sockets.single;
    final connectRequest =
        jsonDecode(socket.sent.single) as Map<String, dynamic>;
    expect(connectRequest['method'], 'connect');
    socket.emit({
      'type': 'res',
      'id': connectRequest['id'],
      'ok': true,
      'payload': {
        'type': 'hello-ok',
        'protocol': 4,
        'server': {'version': 'test'},
        'features': {},
        'snapshot': {},
        'auth': {},
        'policy': {},
      },
    });
    await connecting;
    expect(session.state, GatewaySessionState.ready);

    final requestFuture = session.request(method: 'status');
    await Future<void>.delayed(Duration.zero);
    final request = jsonDecode(socket.sent.last) as Map<String, dynamic>;
    expect(request['method'], 'status');
    socket.emit({
      'type': 'res',
      'id': request['id'],
      'ok': true,
      'payload': {'ok': true},
    });
    expect(await requestFuture, {'ok': true});
    await session.shutdown();
  });

  test('disconnect completes pending request and clears pending map', () async {
    final factory = FakeFactory();
    final session = GatewaySession(
      url: 'ws://test',
      token: null,
      password: null,
      pushHandler: (_) {},
      connectOptions: testOptions(),
      socketFactory: factory,
      idGenerator: () => 'id-${factory.sockets.length}',
      retryPolicy: const GatewayRetryPolicy(initialDelay: Duration(hours: 1)),
    );
    final connectFuture = session.connect();
    await Future<void>.delayed(Duration.zero);
    final socket = factory.sockets.single;
    final connectRequest =
        jsonDecode(socket.sent.single) as Map<String, dynamic>;
    socket.emit({
      'type': 'res',
      'id': connectRequest['id'],
      'ok': true,
      'payload': {
        'type': 'hello-ok',
        'protocol': 4,
        'snapshot': {},
        'server': {},
        'features': {},
        'auth': {},
        'policy': {},
      },
    });
    await connectFuture;

    final pending = session.request(method: 'health');
    await Future<void>.delayed(Duration.zero);
    expect(session.pendingCount, 1);
    await socket.controller.close();
    await expectLater(pending, throwsA(isA<StateError>()));
    expect(session.pendingCount, 0);
    await session.shutdown();
  });

  test('scheduled reconnect starts a new attempt after disconnect', () async {
    final factory = FakeFactory();
    final session = GatewaySession(
      url: 'ws://test',
      token: null,
      password: null,
      pushHandler: (_) {},
      connectOptions: testOptions(),
      socketFactory: factory,
      idGenerator: () => 'id-${factory.sockets.length}',
      retryPolicy: const GatewayRetryPolicy(
        initialDelay: Duration(milliseconds: 1),
      ),
    );
    final initialConnect = session.connect();
    await Future<void>.delayed(Duration.zero);
    final firstSocket = factory.sockets.single;
    final firstRequest =
        jsonDecode(firstSocket.sent.single) as Map<String, dynamic>;
    firstSocket.emit({
      'type': 'res',
      'id': firstRequest['id'],
      'ok': true,
      'payload': {
        'type': 'hello-ok',
        'protocol': 4,
        'snapshot': {},
        'server': {},
        'features': {},
        'auth': {},
        'policy': {},
      },
    });
    await initialConnect;

    await firstSocket.controller.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(factory.sockets, hasLength(2));
    expect(session.isConnecting, isTrue);
    await session.shutdown();
  });

  test('old generation frames cannot complete new requests', () async {
    final factory = FakeFactory();
    final session = GatewaySession(
      url: 'ws://test',
      token: null,
      password: null,
      pushHandler: (_) {},
      connectOptions: testOptions(),
      socketFactory: factory,
      idGenerator: () => 'same-id',
      retryPolicy: const GatewayRetryPolicy(initialDelay: Duration(hours: 1)),
    );
    final first = session.connect();
    await Future<void>.delayed(Duration.zero);
    final oldSocket = factory.sockets.single;
    final oldConnect =
        jsonDecode(oldSocket.sent.single) as Map<String, dynamic>;
    oldSocket.emit({
      'type': 'res',
      'id': oldConnect['id'],
      'ok': true,
      'payload': {
        'type': 'hello-ok',
        'protocol': 4,
        'snapshot': {},
        'server': {},
        'features': {},
        'auth': {},
        'policy': {},
      },
    });
    await first;
    final pending = session.request(method: 'status');
    await Future<void>.delayed(Duration.zero);
    // 先挂上期望，再 shutdown，避免 pending 的失败被上报为未处理的异步错误。
    final pendingExpectation = expectLater(pending, throwsA(isA<StateError>()));
    await session.shutdown();
    await pendingExpectation;
    expect(session.pendingCount, 0);

    // 旧连接迟到的同 ID 响应不能再完成任何请求。
    oldSocket.emit({
      'type': 'res',
      'id': 'same-id',
      'ok': true,
      'payload': {'stale': true},
    });
    await Future<void>.delayed(Duration.zero);
    expect(session.pendingCount, 0);
  });

  test('hello 快照推送时会话已经是 ready', () async {
    // 回归：快照以前在 `_state = authenticating` 时就推出去，订阅者（仓库）
    // 读到 `connected == false` 会把这份 hello 丢掉 —— 首次连接有兜底看不出来，
    // 但断线自愈时 UI 会永远停在「正在自动重连」。
    final factory = FakeFactory();
    final pushes = <GatewayPush>[];
    final readyAtPush = <bool>[];
    late GatewaySession session;
    session = GatewaySession(
      url: 'ws://test',
      token: null,
      password: null,
      pushHandler: (push) {
        pushes.add(push);
        if (push is GatewayPushSnapshot) readyAtPush.add(session.connected);
      },
      connectOptions: testOptions(),
      socketFactory: factory,
      idGenerator: () => 'id-${pushes.length}',
    );

    final connecting = session.connect();
    await Future<void>.delayed(Duration.zero);
    await completeHandshake(factory.sockets.single);
    await connecting;

    expect(pushes.whereType<GatewayPushSnapshot>(), hasLength(1));
    expect(readyAtPush, [isTrue], reason: '推 hello 时会话必须已经 ready');
    await session.shutdown();
  });

  test('掉线后由退避重连把连接拉回来并重新推快照', () async {
    final factory = FakeFactory();
    final pushes = <GatewayPush>[];
    final disconnects = <String>[];
    final session = await connectOnce(
      factory,
      pushes,
      disconnects: disconnects,
    );
    expect(session.connected, isTrue);
    expect(factory.sockets, hasLength(1));

    // 网关重启：服务端关闭连接。
    await factory.sockets[0].controller.close();
    await waitUntil(() => disconnects.isNotEmpty);
    expect(session.connected, isFalse);

    // 会话自己重开 socket —— 没有别的守护层参与。
    await waitUntil(() => factory.sockets.length >= 2);
    await completeHandshake(factory.sockets[1]);
    await waitUntil(() => session.connected);

    final snapshots = pushes.whereType<GatewayPushSnapshot>().toList();
    expect(snapshots, hasLength(2), reason: '重连成功要再推一份 hello 给仓库');
    await session.shutdown();
  });

  test('tick 看门狗抓得住半开连接并重开 socket', () async {
    final factory = FakeFactory();
    final pushes = <GatewayPush>[];
    final disconnects = <String>[];
    final session = buildSession(
      factory: factory,
      pushes: pushes,
      disconnects: disconnects,
      initialDelay: const Duration(milliseconds: 10),
    );
    final connecting = session.connect();
    await Future<void>.delayed(Duration.zero);
    // 毫秒级 tick：检查周期 = 20ms，判死阈值 = 40ms。
    // 对端半开 —— 既不关 socket，也不再发 tick。没有看门狗的话这里会一直
    // 停在「已连接」。
    await completeHandshake(factory.sockets.single, tickIntervalMs: 20);
    await connecting;
    expect(session.connected, isTrue);

    await waitUntil(() => disconnects.isNotEmpty);
    expect(disconnects.first, 'gateway tick missed');

    // 判死之后照旧走退避重连：新 socket 会被开出来。
    await waitUntil(() => factory.sockets.length >= 2);
    await completeHandshake(factory.sockets[1], tickIntervalMs: 20);
    await waitUntil(() => session.connected);

    await session.shutdown();
  });

  test('看门狗被对端任何一帧刷新，不会误判', () async {
    final factory = FakeFactory();
    final pushes = <GatewayPush>[];
    final disconnects = <String>[];
    final session = buildSession(
      factory: factory,
      pushes: pushes,
      disconnects: disconnects,
      initialDelay: const Duration(milliseconds: 10),
    );
    final connecting = session.connect();
    await Future<void>.delayed(Duration.zero);
    await completeHandshake(factory.sockets.single, tickIntervalMs: 20);
    await connecting;

    // 持续发非 tick 事件（对端明显还活着），看门狗不该判死。
    for (var i = 0; i < 6; i++) {
      factory.sockets.single.emit({
        'type': 'event',
        'event': 'health',
        'payload': {'seq': i},
      });
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }

    expect(disconnects, isEmpty);
    expect(session.connected, isTrue);
    expect(factory.sockets, hasLength(1));
    await session.shutdown();
  });

  test('重连尝试进行中时再次 connect() 不会另开 socket', () async {
    final factory = FakeFactory();
    final pushes = <GatewayPush>[];
    final session = await connectOnce(factory, pushes);

    await factory.sockets[0].controller.close();
    await waitUntil(() => factory.sockets.length >= 2);
    expect(session.isConnecting, isTrue);

    // 仓库在 ServerRepository 变更时会重复调 connect()，此时必须合并成
    // 同一个等待者，而不是把刚建的 socket 拆掉再开一条。
    final extra = session.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(factory.sockets, hasLength(2));

    await completeHandshake(factory.sockets[1]);
    await extra;
    expect(session.connected, isTrue);
    await session.shutdown();
  });

  test('主动 shutdown 之后不再自动重连', () async {
    final factory = FakeFactory();
    final pushes = <GatewayPush>[];
    final session = await connectOnce(factory, pushes);

    await session.shutdown();
    expect(session.connected, isFalse);

    await factory.sockets[0].controller.close();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(factory.sockets, hasLength(1), reason: '主动断开后不该再自己连回来');
  });
}
