import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_app/data/repository/gateway_repository.dart';
import 'package:parrot_app/data/repository/setting_repository.dart';
import 'package:parrot_app/data/service/shared_preferences_service.dart';
import 'package:parrot_app/ui/screen/chat_screen.dart';
import 'package:parrot_app/ui/view_model/chat_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_gateway_session.dart';

/// 「正在输入」气泡的生命周期回归测试。
///
/// 症状：点「打断」之后 typing 气泡一直挂着不消失。
/// 根因：typing 只有两个出口 —— 收到新消息时清、以及 `_abortMessage()` 里那行
/// **被注释掉的** `_removeTyping()`。而打断这条路径网关不会再推消息，于是气泡
/// 永远留在列表里。现在改成挂在 run 的生死上（`runId` 由非空变空即收），
/// 同时覆盖 final / aborted / error 三种收尾。
///
/// 这里走真实控件：输入文字 → 点发送 / 敲回车 → 点打断，复现用户的操作顺序。
void main() {
  Future<ChatViewModel> buildViewModel(GatewayRepository repository) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    return ChatViewModel(
      settingRepository: SettingRepository(
        preferencesService: SharedPreferencesService(prefs),
      ),
      gatewayRepository: repository,
      serverRepository: FakeServerRepository(serverAt('fake')),
    );
  }

  Future<void> pumpChat(WidgetTester tester, ChatViewModel viewModel) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ChatViewModel>.value(
        value: viewModel,
        child: MaterialApp(home: ChatScreen(viewModel: viewModel)),
      ),
    );
    // 连上后仓库会 fire-and-forget 拉历史 / 模型，多跑几帧等它们落地
    //（typing 气泡带无限动画，pumpAndSettle 会卡死，只能按帧 pump）。
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// typing 气泡进出都有动画，断言必须等动画走完，否则会数到正在退场的那个。
  Future<void> settleTypingAnimation(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('打断后「正在输入」气泡要收掉', (tester) async {
    final (:repository, :session) = await buildConnectedRepository();
    final viewModel = await buildViewModel(repository);
    await pumpChat(tester, viewModel);

    expect(find.byType(IsTypingIndicator), findsNothing);

    // 发送第一条：输入 → 点发送。
    await tester.enterText(find.byType(TextField), '第一条');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await settleTypingAnimation(tester);

    expect(viewModel.runId, isNotEmpty, reason: '发送后应处于生成中');
    expect(find.byType(IsTypingIndicator), findsOneWidget);

    // 点输入行里的「打断」（生成中发送键换成 Icons.stop）。
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();
    await settleTypingAnimation(tester);

    expect(viewModel.runId, isEmpty);
    expect(
      find.byType(IsTypingIndicator),
      findsNothing,
      reason: '打断后网关不会再推消息，typing 必须靠 run 结束来收',
    );
    expect(session.requests, contains('chat.abort'));
  });

  testWidgets('生成中再发一条（敲回车）不会把 typing 留成两个', (tester) async {
    final (:repository, session: _) = await buildConnectedRepository();
    final viewModel = await buildViewModel(repository);
    await pumpChat(tester, viewModel);

    await tester.enterText(find.byType(TextField), '第一条');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await settleTypingAnimation(tester);
    expect(find.byType(IsTypingIndicator), findsOneWidget);

    // 生成中发送键已被「打断」占位，用户是敲回车发的第二条：
    // `TextField.onSubmitted` → `_sendMessage` → 先打断上一次再发新的。
    await tester.enterText(find.byType(TextField), '第二条');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await settleTypingAnimation(tester);

    expect(viewModel.runId, isNotEmpty, reason: '新 run 不能被旧 run 的打断收尾抹掉');
    expect(find.byType(IsTypingIndicator), findsOneWidget);
  });

  testWidgets('网关推 final 收尾时 typing 也要收掉', (tester) async {
    final (:repository, :session) = await buildConnectedRepository();
    final viewModel = await buildViewModel(repository);
    await pumpChat(tester, viewModel);

    await tester.enterText(find.byType(TextField), '第一条');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await settleTypingAnimation(tester);
    expect(find.byType(IsTypingIndicator), findsOneWidget);

    final runId = viewModel.runId;
    session.emitEvent('chat', {
      'runId': runId,
      'state': 'final',
      'message': {
        'id': 'msg-final',
        'role': 'assistant',
        'timestamp': 1790134943762,
        'content': [
          {'type': 'text', 'text': '好的'},
        ],
      },
    });
    await tester.pump();
    await settleTypingAnimation(tester);

    expect(viewModel.runId, isEmpty);
    expect(find.byType(IsTypingIndicator), findsNothing);
  });
}
