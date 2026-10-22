import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'support/fake_gateway_session.dart';

/// 「run 身份」回归测试。
///
/// 症状：发完一条消息后**马上**再发一条，输入行的「打断」按钮不再出现。
/// 根因：`abortMessage()` 在 `await chat.abort` 之后无条件清空 `_runId`，
/// 而这段等待期间用户已经发出下一条，`_runId` 早已是**新** run —— 旧 run 的
/// 打断把新 run 的状态一起抹了。于是 `runId == ''`，「打断」按钮不显示，
/// 而且新 run 的 final 事件也因 runId 不匹配被忽略，界面上不会自愈。
///
/// 守的规则：任何收尾逻辑只能清掉「自己这一次」的 run，不能踩到后发起的 run。
void main() {
  test('打断上一次 run 时，不能清掉紧接着发起的新 run', () async {
    final (:repository, :session) = await buildConnectedRepository();

    // 让 chat.abort 挂住，模拟「打断请求还在路上，用户已经又发了一条」。
    final abortGate = Completer<void>();
    session.handler = (method, params) async {
      if (method == 'chat.abort') await abortGate.future;
      return const <String, dynamic>{};
    };

    await repository.sendChatMessage('第一条');
    final firstRunId = repository.runId;
    expect(firstRunId, isNotEmpty);

    // 聊天页 _sendMessage 的真实顺序：先 fire-and-forget 打断，再发新消息。
    final abortFuture = repository.abortMessage();
    await repository.sendChatMessage('第二条');
    final secondRunId = repository.runId;
    expect(secondRunId, isNotEmpty);
    expect(secondRunId, isNot(firstRunId));

    // 旧打断的响应现在才回来。
    abortGate.complete();
    await abortFuture;

    expect(
      repository.runId,
      secondRunId,
      reason: '旧 run 的打断收尾不能把新 run 抹掉，否则「打断」按钮不会显示',
    );
    expect(session.requests, contains('chat.abort'));
    expect(session.requests, contains('chat.send'));
  });

  test('打断自己那一次时，仍然会清空 runId', () async {
    final (:repository, session: _) = await buildConnectedRepository();

    await repository.sendChatMessage('只有这一条');
    expect(repository.runId, isNotEmpty);

    await repository.abortMessage();

    expect(repository.runId, isEmpty);
  });

  test('没有 run 在跑时打断是 no-op，不打网关', () async {
    final (:repository, :session) = await buildConnectedRepository();

    await repository.abortMessage();

    expect(repository.runId, isEmpty);
    expect(session.requests, isNot(contains('chat.abort')));
  });

  test('chat.send 失败时，不能清掉后一次发送的 run', () async {
    final (:repository, :session) = await buildConnectedRepository();

    final failGate = Completer<void>();
    session.handler = (method, params) async {
      if (method != 'chat.send') return const <String, dynamic>{};
      if (params?['message'] == '会失败的第一条') {
        await failGate.future;
        throw StateError('chat.send boom');
      }
      return const <String, dynamic>{};
    };

    final firstSend = repository.sendChatMessage('会失败的第一条');
    await repository.sendChatMessage('第二条');
    final secondRunId = repository.runId;
    expect(secondRunId, isNotEmpty);

    failGate.complete();
    await expectLater(firstSend, throwsA(isA<StateError>()));

    expect(
      repository.runId,
      secondRunId,
      reason: '失败的旧请求收尾不能把新 run 抹掉',
    );
  });
}
