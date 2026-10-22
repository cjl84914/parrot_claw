import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_app/data/model/message.dart';

import 'support/fake_gateway_session.dart';

/// 会话隔离回归测试。
///
/// 背景：网关把**所有**会话的 `chat` / `agent` 事件都推给同一条连接，而聊天页
/// 只有一份消息列表。早先仓库不做任何过滤，于是「在 A 说一句你好、马上切到 B」
/// 时，A 的回复会直接插进 B 的列表里（B 里冒出「你好，XX」）。
///
/// 这里钉住四件事：
/// 1. 不属于当前会话的 `chat` 事件不落到 UI；
/// 2. 切会话时旧会话的历史请求回来也不会盖掉新会话；
/// 3. 每个会话的 run 状态各自保留（切走再切回仍显示「运行中」）；
/// 4. 切走期间跑完的 run 不会让切回来时卡在「运行中」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 造一条带 delta 文本的 chat 事件。
  Map<String, dynamic> chatDelta(String sessionKey, String text, {String? runId}) => {
    'runId': runId ?? 'run-$sessionKey',
    'sessionKey': sessionKey,
    'state': 'delta',
    'deltaText': text,
  };

  test('别的会话的 chat 事件不会插进当前会话', () async {
    final built = await buildConnectedRepository();
    final repository = built.repository;
    final session = built.session;
    await pumpEventQueue();

    final received = <ChatMessage>[];
    final sub = repository.messageController.stream.listen(received.add);

    await repository.switchSession('session-b');
    await pumpEventQueue();
    received.clear(); // 切换过程中的噪音不算

    session.emitEvent('chat', chatDelta('session-a', '你好，ALEX哥'));
    await pumpEventQueue();
    expect(
      received,
      isEmpty,
      reason: 'A 会话的流式增量不能落到正在看的 B 会话上',
    );

    session.emitEvent('chat', chatDelta('session-b', '当前会话的回复'));
    await pumpEventQueue();
    expect(received, hasLength(1), reason: '本会话的增量仍要正常显示');
    expect(received.single.content.first.text, '当前会话的回复');

    await sub.cancel();
    repository.dispose();
  });

  test('agent 媒体事件同样按会话过滤', () async {
    final built = await buildConnectedRepository();
    final repository = built.repository;
    final session = built.session;
    await pumpEventQueue();

    final received = <ChatMessage>[];
    final sub = repository.messageController.stream.listen(received.add);

    await repository.switchSession('session-b');
    await pumpEventQueue();
    received.clear();

    session.emitEvent('agent', {
      'runId': 'run-a',
      'sessionKey': 'session-a',
      'stream': 'assistant',
      'data': {
        'mediaUrls': ['/tmp/a.png'],
      },
    });
    await pumpEventQueue();
    expect(received, isEmpty, reason: 'A 会话的附件气泡不能出现在 B 会话');

    session.emitEvent('agent', {
      'runId': 'run-b',
      'sessionKey': 'session-b',
      'stream': 'assistant',
      'data': {
        'mediaUrls': ['/tmp/b.png'],
      },
    });
    await pumpEventQueue();
    expect(received, hasLength(1));

    await sub.cancel();
    repository.dispose();
  });

  test('`main` 与 `agent:main:main` 是同一个会话，不能被当成切换', () async {
    final built = await buildConnectedRepository();
    final repository = built.repository;
    final session = built.session;
    await pumpEventQueue();

    // 连接后当前会话是 `main`（hello 快照里没有 sessiondefaults 时回退）。
    expect(repository.sessionKey, 'main');

    final received = <ChatMessage>[];
    final sub = repository.messageController.stream.listen(received.add);

    // 网关规范化之后回的是带作用域的 key，必须仍然算本会话。
    session.emitEvent('chat', chatDelta('agent:main:main', '规范化 key 的回复'));
    await pumpEventQueue();
    expect(received, hasLength(1));

    await sub.cancel();
    repository.dispose();
  });

  test('切会话时旧会话的历史回来不会盖掉新会话', () async {
    final built = await buildConnectedRepository();
    final repository = built.repository;
    final session = built.session;
    await pumpEventQueue();

    final pendingA = Completer<Map<String, dynamic>>();
    session.handler = (method, params) {
      if (method == 'chat.history') {
        if (params?['sessionKey'] == 'session-a') return pendingA.future;
        return {
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'B 的历史'},
              ],
            },
          ],
        };
      }
      // 未匹配的方法必须回空对象（见 fake_gateway_session 的说明）。
      return const <String, dynamic>{};
    };

    final updates = <List<ChatMessage>>[];
    final sub = repository.sessionUpdateController.stream.listen(updates.add);

    unawaited(repository.switchSession('session-a'));
    await pumpEventQueue();
    await repository.switchSession('session-b');
    await pumpEventQueue();

    // A 的历史姗姗来迟：它属于旧会话，必须被丢弃。
    pendingA.complete({
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'A 的历史'},
          ],
        },
      ],
    });
    await pumpEventQueue();

    expect(updates, isNotEmpty);
    expect(
      updates.last.single.content.first.text,
      'B 的历史',
      reason: '旧会话的历史请求回来时不能覆盖当前会话',
    );

    await sub.cancel();
    repository.dispose();
  });

  test('切走再切回，原会话的运行状态还在', () async {
    final built = await buildConnectedRepository();
    final repository = built.repository;
    await pumpEventQueue();

    await repository.sendChatMessage('你好');
    final runId = repository.runId;
    expect(runId, isNotEmpty, reason: '发送后应有一次 run 在跑');

    await repository.switchSession('session-b');
    expect(repository.runId, isEmpty, reason: 'B 会话自己没有在跑的 run');

    await repository.switchSession('main');
    expect(
      repository.runId,
      runId,
      reason: '切回来要恢复这个会话自己的运行中状态，输入行仍应能「打断」',
    );

    repository.dispose();
  });

  test('切走期间跑完的 run，切回来不会卡在运行中', () async {
    final built = await buildConnectedRepository();
    final repository = built.repository;
    final session = built.session;
    await pumpEventQueue();

    await repository.sendChatMessage('你好');
    final runId = repository.runId;
    expect(runId, isNotEmpty);

    await repository.switchSession('session-b');

    // 这个 run 在「看着 B」的时候跑完：终态事件带的是原会话的 key。
    session.emitEvent('chat', {
      'runId': runId,
      'sessionKey': 'main',
      'state': 'final',
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': '你好，ALEX哥'},
        ],
      },
    });
    await pumpEventQueue();

    await repository.switchSession('main');
    expect(
      repository.runId,
      isEmpty,
      reason: '切回来不该还显示「运行中」—— 那个 run 已经在后台结束了',
    );

    repository.dispose();
  });
}
