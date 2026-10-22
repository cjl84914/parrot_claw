import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_app/data/model/message.dart';
import 'package:parrot_app/data/repository/gateway_repository.dart';
import 'package:parrot_app/data/service/gateway_connector.dart';

import 'support/fake_gateway_session.dart';

/// 助手流式文字的**投影选择**回归测试。
///
/// 背景（真实事故）：网关会把同一段助手文字投影两次 —— `agent`
///（`stream: assistant`，只有首条带 `data.text` 快照、其余全是 `data.delta`）
/// 和 `chat`（`deltaText` 追加 + 首帧/终态带完整 `message`）。早先仓库只读
/// `agent` 的 `data.text`，于是「收到，我还在 😊 有事就说。」只显示出第一小段
/// 「收到」；而终态 `final` 里的完整 `message` 又只喂给了 TTS，没回填气泡，
/// 所以界面永远停在半截。
///
/// 现在约定：**文字只认 `chat` 投影**（握手声明 `chat-only-assistant-text`），
/// `agent` 的 assistant 文本一律不渲染。

/// 收集一次 run 期间仓库推给 UI 的助手消息。
Future<({List<ChatMessage> messages, StreamSubscription<ChatMessage> sub})>
collectAssistantMessages(GatewayRepository repository) async {
  final messages = <ChatMessage>[];
  final sub = repository.messageController.stream.listen(messages.add);
  return (messages: messages, sub: sub);
}

/// 让 `messageController` 上排队的广播事件落地。
///
/// 刻意不用 `pumpEventQueue()`：这里跑的是普通 `test()`，一次事件循环轮转
/// 就足以把 broadcast stream 的 microtask 全部排空。
Future<void> flushStream() => Future<void>.delayed(Duration.zero);

/// 网关真实下发的 `chat` 终态 payload（`state: final` + 完整 message）。
Map<String, dynamic> finalPayload(String runId, String text) => {
  'runId': runId,
  'sessionKey': 'agent:main:main',
  'agentId': 'main',
  'seq': 18,
  'state': 'final',
  'stopReason': 'stop',
  'message': {
    'role': 'assistant',
    'content': [
      {'type': 'text', 'text': text},
    ],
    'timestamp': 1791451104848,
  },
};

/// 一条 `chat` delta。`message` 只在首帧 / item 边界 / replace 时下发。
Map<String, dynamic> deltaPayload(
  String runId, {
  required String deltaText,
  String? snapshot,
  bool replace = false,
}) => {
  'runId': runId,
  'sessionKey': 'agent:main:main',
  'agentId': 'main',
  'state': 'delta',
  'deltaText': deltaText,
  if (snapshot != null)
    'message': {
      'role': 'assistant',
      'content': [
        {'type': 'text', 'text': snapshot},
      ],
    },
  if (replace) 'replace': true,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('chat delta 逐条累积，最终得到完整回复（事故回归）', () async {
    final built = await buildConnectedRepository();
    final repository = built.repository;
    final session = built.session;
    final collected = await collectAssistantMessages(repository);
    addTearDown(collected.sub.cancel);

    await repository.sendChatMessage('在吗');
    final runId = repository.runId;
    expect(runId, isNotEmpty);

    // 与事故日志同构：首帧带快照，之后两条只有 deltaText。
    session.emitEvent(
      'chat',
      deltaPayload(runId, deltaText: '收到', snapshot: '收到'),
    );
    session.emitEvent('chat', deltaPayload(runId, deltaText: '，我还在 😊'));
    session.emitEvent('chat', deltaPayload(runId, deltaText: ' 有事就说。'));
    session.emitEvent(
      'chat',
      finalPayload(runId, '收到，我还在 😊 有事就说。'),
    );
    await flushStream();

    final assistant = collected.messages.where((m) => m.role == 'assistant');
    expect(assistant, isNotEmpty);
    // 全程复用同一个气泡 id：UI 侧是就地更新，不是新增气泡。
    expect(assistant.map((m) => m.id).toSet(), hasLength(1));
    expect(assistant.last.content.first.text, '收到，我还在 😊 有事就说。');
    expect(repository.runId, isEmpty);
  });

  test('终态 message 会回填气泡，即使一条 delta 都没收到', () async {
    final built = await buildConnectedRepository();
    final repository = built.repository;
    final session = built.session;
    final collected = await collectAssistantMessages(repository);
    addTearDown(collected.sub.cancel);

    await repository.sendChatMessage('在吗');
    final runId = repository.runId;

    session.emitEvent('chat', finalPayload(runId, '完整的回复'));
    await flushStream();

    final assistant = collected.messages.where((m) => m.role == 'assistant');
    expect(assistant, hasLength(1));
    expect(assistant.single.content.first.text, '完整的回复');
  });

  test('replace: true 用 deltaText 整体替换，而不是追加', () async {
    final built = await buildConnectedRepository();
    final repository = built.repository;
    final session = built.session;
    final collected = await collectAssistantMessages(repository);
    addTearDown(collected.sub.cancel);

    await repository.sendChatMessage('在吗');
    final runId = repository.runId;

    session.emitEvent(
      'chat',
      deltaPayload(runId, deltaText: 'Hello world', snapshot: 'Hello world'),
    );
    session.emitEvent(
      'chat',
      deltaPayload(runId, deltaText: 'Rewritten', replace: true),
    );
    await flushStream();

    final assistant = collected.messages.where((m) => m.role == 'assistant');
    expect(assistant.last.content.first.text, 'Rewritten');
  });

  test('agent 的 assistant 文本不再渲染（避免两条投影重复输出）', () async {
    final built = await buildConnectedRepository();
    final repository = built.repository;
    final session = built.session;
    final collected = await collectAssistantMessages(repository);
    addTearDown(collected.sub.cancel);

    await repository.sendChatMessage('在吗');
    final runId = repository.runId;

    session.emitEvent('agent', {
      'runId': runId,
      'stream': 'assistant',
      'data': {'text': 'Hello', 'delta': 'Hello', 'itemId': 'answer:1'},
    });
    session.emitEvent('agent', {
      'runId': runId,
      'stream': 'assistant',
      'data': {'delta': ' world', 'itemId': 'answer:1'},
    });
    await flushStream();

    expect(collected.messages.where((m) => m.role == 'assistant'), isEmpty);
  });

  test('助手正文里的 MEDIA: 行不会漏进气泡', () async {
    final built = await buildConnectedRepository();
    final repository = built.repository;
    final session = built.session;
    final collected = await collectAssistantMessages(repository);
    addTearDown(collected.sub.cancel);

    await repository.sendChatMessage('画个图');
    final runId = repository.runId;

    session.emitEvent(
      'chat',
      finalPayload(runId, '给你画好了\nMEDIA:/tmp/out/pic.png'),
    );
    await flushStream();

    final assistant = collected.messages.where((m) => m.role == 'assistant');
    expect(assistant.single.content.first.text, '给你画好了');
  });

  test('握手声明 chat-only-assistant-text，让网关不再下发 agent 助手文本', () {
    const config = GatewayConnectConfig(url: 'ws://fake');
    expect(config.caps, contains('chat-only-assistant-text'));
    expect(config.toGatewayOptions().caps, contains('chat-only-assistant-text'));
  });
}
