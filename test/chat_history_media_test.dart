import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_app/data/repository/gateway_repository.dart';

import 'support/fake_gateway_session.dart';

/// 助手回复正文 + `MEDIA:` 附件的历史解析回归测试。
///
/// 这里守着两个已经踩过的坑：
///
/// 1. 助手消息里的 `MEDIA:` 附件曾经被**插在正文之前**，而 UI 只取
///    `content.first`，于是文件卡片把回复文字整个挤掉 —— 聊天页只显示文件、
///    看不到 AI 的回复。正文必须排在前，且用剥离过 `MEDIA:` 行的文本，
///    否则修好渲染后又会把原始路径 `MEDIA:/Users/...` 露出来。
/// 2. 图片块（只有 `base64`、没有 `text`）曾经命中 `chatMessageContent.text!`
///    的非空断言而抛异常；调用方 `beginHistoryLoad` 把异常吞在 catch 里，
///    表现是**整条历史记录都加载不出来**，而不是只坏这一条。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> historyWith(List<dynamic> content) => {
    'messages': [
      {
        'id': 'msg-1',
        'role': 'assistant',
        'timestamp': 1790134943762,
        'content': content,
      },
    ],
    'sessionInfo': {
      'model': 'deepseek-v4-flash',
      'thinkingOptions': ['low'],
    },
  };

  /// 连上仓库、把 `chat.history` 换成 [content]，再跑一次历史加载。
  Future<List<dynamic>> loadHistory(
    GatewayRepository repository,
    FakeGatewaySession session,
    List<dynamic> content,
  ) async {
    session.handler = (method, params) async {
      if (method == 'chat.history') return historyWith(content);
      return const <String, dynamic>{};
    };
    // 等 _initializeSessionData() 落地：beginHistoryLoad 要求 sessionKey 非空。
    await pumpEventQueue();
    final updates = repository.sessionUpdateController.stream.first;
    await repository.beginHistoryLoad();
    return updates.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('历史加载没有产出任何消息'),
    );
  }

  test('正文排在媒体之前，且已剥离 MEDIA: 行', () async {
    final (:repository, :session) = await buildConnectedRepository();
    final messages = await loadHistory(repository, session, [
      {'type': 'thinking', 'thinking': '用户要我把这个文件发回去。'},
      {
        'type': 'text',
        'text':
            '收到，内容如下：\n'
            '\n'
            '- 暗黑宝典地址：https://www.wolai.com/dyhongye/mjPLP8apMem5VPEgURgQPw\n'
            '- 战网MOD地址：https://www.wolai.com/dyhongye/ngfhCL3A843T15EyD2AFpg\n'
            '\n'
            '复制网址到浏览器即可打开。\n'
            '\n'
            'MEDIA:/Users/alexcai/.openclaw/media/inbound/下载地址.txt',
      },
    ]);

    expect(messages, hasLength(1));
    final content = messages.single.content;
    expect(
      content.map((c) => c.type).toList(),
      ['text', 'file'],
      reason: '正文要在媒体之前，UI 才不会只渲染出文件卡片',
    );
    expect(content.first.text, contains('收到，内容如下：'));
    expect(content.first.text, contains('复制网址到浏览器即可打开。'));
    expect(
      content.first.text,
      isNot(contains('MEDIA:')),
      reason: '剥离不干净的话，聊天页会露出原始 MEDIA: 路径',
    );
    expect(content.last.text, '/Users/alexcai/.openclaw/media/inbound/下载地址.txt');
    expect(content.last.fileName, '下载地址.txt');

    repository.dispose();
  });

  test('只有 base64 的图片块不会让整条历史加载失败', () async {
    final (:repository, :session) = await buildConnectedRepository();
    final messages = await loadHistory(repository, session, [
      {'type': 'image', 'content': 'aGVsbG8=', 'mimeType': 'image/png'},
    ]);

    expect(messages, hasLength(1));
    final content = messages.single.content;
    expect(content, hasLength(1));
    expect(content.single.type, 'image');
    expect(content.single.base64, 'aGVsbG8=');

    repository.dispose();
  });

  test('纯文本回复不带媒体时保持一个文本块', () async {
    final (:repository, :session) = await buildConnectedRepository();
    final messages = await loadHistory(repository, session, [
      {'type': 'text', 'text': '✅ Session reset.'},
    ]);

    expect(messages, hasLength(1));
    final content = messages.single.content;
    expect(content, hasLength(1));
    expect(content.single.type, 'text');
    expect(content.single.text, '✅ Session reset.');

    repository.dispose();
  });

  /// 用户消息的图片必须用**网关侧的副本**（`MediaPath`）渲染，而不是
  /// `content` 里发送方那台设备的本地路径。
  ///
  /// 症状：桌面端显示手机发的图 → `cross_cache` 转成 assistant-media 请求
  /// 网关那台机器上不存在的路径 → `DioException 404`（未捕获异常，气泡一直转圈）；
  /// 反过来手机看桌面端发的图同理。
  test('用户消息的图片优先用 MediaPath（网关侧副本）', () async {
    final (:repository, :session) = await buildConnectedRepository();
    const senderPath = '/Users/alexcai/Downloads/微信图片_2026-01-07_142249_916.jpg';
    const gatewayCopy =
        '/Users/alexcai/.openclaw/media/inbound/'
        '微信图片_2026-01-07_142249_916---d11129d5-0eff-4805-9030-4ec8a1049916.jpg';

    session.handler = (method, params) async {
      if (method == 'chat.history') {
        return {
          'messages': [
            {
              'id': 'msg-user-1',
              'role': 'user',
              'timestamp': 1790136109588,
              'content': senderPath,
              'MediaType': 'image/jpeg',
              'MediaTypes': ['image/jpeg'],
              'MediaPath': gatewayCopy,
              'MediaPaths': [gatewayCopy],
            },
          ],
          'sessionInfo': {
            'model': 'deepseek-v4-flash',
            'thinkingOptions': ['low'],
          },
        };
      }
      return const <String, dynamic>{};
    };
    await pumpEventQueue();
    final updates = repository.sessionUpdateController.stream.first;
    await repository.beginHistoryLoad();
    final messages = await updates.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('历史加载没有产出任何消息'),
    );

    expect(messages, hasLength(1));
    final content = messages.single.content;
    final image = content.firstWhere((c) => c.type == 'image');
    expect(
      image.text,
      gatewayCopy,
      reason: '发送方设备的路径别的客户端取不到，只能用网关侧副本',
    );

    repository.dispose();
  });

  test('没有 MediaPath 时退回 content，行为与改动前一致', () async {
    final (:repository, :session) = await buildConnectedRepository();
    const senderPath = '/Users/alexcai/Downloads/图片.jpg';

    session.handler = (method, params) async {
      if (method == 'chat.history') {
        return {
          'messages': [
            {
              'id': 'msg-user-2',
              'role': 'user',
              'timestamp': 1790136109588,
              'content': senderPath,
              'MediaType': 'image/jpeg',
            },
          ],
          'sessionInfo': {
            'model': 'deepseek-v4-flash',
            'thinkingOptions': ['low'],
          },
        };
      }
      return const <String, dynamic>{};
    };
    await pumpEventQueue();
    final updates = repository.sessionUpdateController.stream.first;
    await repository.beginHistoryLoad();
    final messages = await updates.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('历史加载没有产出任何消息'),
    );

    final image = messages.single.content.firstWhere((c) => c.type == 'image');
    expect(image.text, senderPath);

    repository.dispose();
  });
}
