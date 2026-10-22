import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_edge_tts/flutter_edge_tts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:parrot_app/data/repository/server_repository.dart';
import 'package:parrot_app/data/repository/setting_repository.dart';
import 'package:parrot_app/data/service/shared_preferences_service.dart';
import 'package:parrot_app/data/service/storage_service.dart';
import 'package:parrot_app/ui/screen/setting_screen.dart';
import 'package:parrot_app/ui/view_model/setting_viewmodel.dart';
import 'package:parrot_app/util/edge_tts_util.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置页的音色列表来自 Edge 的在线目录，测试里换成假的 http.Client 喂固定数据，
/// 既不走网络、也不会因为断网让用例随机失败。
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({this.body, this.error, this.statusCode = 200});

  final String? body;
  final Object? error;
  final int statusCode;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final error = this.error;
    if (error != null) throw error;
    final bytes = utf8.encode(body ?? '[]');
    return http.StreamedResponse(Stream.value(bytes), statusCode);
  }
}

Map<String, dynamic> _voiceJson(String shortName, String locale, String gender) {
  return {
    'Name': 'Microsoft Server Speech Text to Speech Voice ($locale, $shortName)',
    'ShortName': shortName,
    'Gender': gender,
    'Locale': locale,
    'SuggestedCodec': 'audio-24khz-48kbitrate-mono-mp3',
    'FriendlyName': '$shortName ($locale)',
    'Status': 'GA',
  };
}

/// 两个中文音色 + 一个粤语音色 + 一个英文音色。
/// zh-HK 和 zh-CN 属于同一门语言，所以「按语言过滤」时应该一起留下，英文的被滤掉。
final _defaultVoices = <Map<String, dynamic>>[
  _voiceJson('zh-CN-XiaoxiaoNeural', 'zh-CN', 'Female'),
  _voiceJson('zh-CN-YunyangNeural', 'zh-CN', 'Male'),
  _voiceJson('zh-HK-HiuMaanNeural', 'zh-HK', 'Female'),
  _voiceJson('en-US-AriaNeural', 'en-US', 'Female'),
];

/// 给 [EdgeTTSUtil] 单例装上假的底层客户端。
void _installEdgeClient({
  List<Map<String, dynamic>>? voices,
  Object? error,
  int statusCode = 200,
}) {
  EdgeTTSUtil()
    ..showErrorToast = false
    ..debugSetClient(
      FlutterEdgeTts(
        voice: EdgeTTSUtil.defaultVoice,
        httpClient: _FakeHttpClient(
          body: error == null ? jsonEncode(voices ?? _defaultVoices) : null,
          error: error,
          statusCode: statusCode,
        ),
      ),
    );
}

/// 把单例恢复成干净状态，避免上一条用例的音色/语速串到下一条。
void _resetEdgeTts() {
  EdgeTTSUtil()
    ..setVolume(1.0)
    ..setPitch(0)
    ..setSpeechRate(1.0)
    ..setVoice(EdgeTTSUtil.defaultVoice)
    ..debugSetClient(null);
}

void main() {
  Future<SettingRepository> buildRepository() async {
    // isOpenclawTTS=false 才会渲染本地 TTS 的那组设置项（语言/音色/音量...）。
    SharedPreferences.setMockInitialValues({'isOpenclawTTS': false});
    final prefs = await SharedPreferences.getInstance();
    return SettingRepository(preferencesService: SharedPreferencesService(prefs));
  }

  Future<void> pumpSettingScreen(
    WidgetTester tester,
    SettingRepository repository,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingRepository>.value(value: repository),
          ChangeNotifierProvider<ServerRepository>.value(
            value: ServerRepository(StorageService()),
          ),
        ],
        child: MaterialApp(
          home: SettingScreen(
            viewmodel: SettingViewmodel(settingRepository: repository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder voiceDropdown() => find.descendant(
    of: find.ancestor(of: find.text('音色'), matching: find.byType(ListTile)),
    matching: find.byType(DropdownButton<String>),
  );

  setUp(() {
    _resetEdgeTts();
    _installEdgeClient();
  });

  tearDown(_resetEdgeTts);

  group('设置页', () {
    testWidgets('音色下拉框只列出当前语言的音色，选中后记到仓储和 Edge 上', (tester) async {
      final repository = await buildRepository();
      expect(repository.language, 'zh-CN');

      await pumpSettingScreen(tester, repository);

      // 未选择时显示「默认」，代表跟随语言用默认音色。
      expect(find.text('默认'), findsOneWidget);

      await tester.tap(voiceDropdown());
      await tester.pumpAndSettle();

      expect(find.text('zh-CN-XiaoxiaoNeural (zh-CN)'), findsOneWidget);
      expect(find.text('zh-CN-YunyangNeural (zh-CN)'), findsOneWidget);
      // zh-HK 与 zh-CN 同属中文，一并列出
      expect(find.text('zh-HK-HiuMaanNeural (zh-HK)'), findsOneWidget);
      // 不同语言的音色不进列表，避免下拉框被无关音色塞满。
      expect(find.text('en-US-AriaNeural (en-US)'), findsNothing);

      await tester.tap(find.text('zh-CN-XiaoxiaoNeural (zh-CN)'));
      await tester.pumpAndSettle();

      expect(repository.voice, 'zh-CN-XiaoxiaoNeural');
      expect(EdgeTTSUtil().voice, 'zh-CN-XiaoxiaoNeural');
      expect(find.text('zh-CN-XiaoxiaoNeural (zh-CN)'), findsOneWidget);
    });

    testWidgets('音色列表为空时给出提示，而不是留一个空下拉框', (tester) async {
      _installEdgeClient(voices: <Map<String, dynamic>>[]);

      final repository = await buildRepository();
      await pumpSettingScreen(tester, repository);

      expect(find.text('无可用音色'), findsOneWidget);
      expect(voiceDropdown(), findsNothing);
    });

    testWidgets('取音色失败时展示「不可用」，不影响页面其它设置项', (tester) async {
      _installEdgeClient(error: http.ClientException('boom'));

      final repository = await buildRepository();
      await pumpSettingScreen(tester, repository);

      expect(find.text('不可用'), findsOneWidget);
      expect(find.text('音量'), findsOneWidget);
    });
  });

  group('仓储', () {
    test('切换语言时，当前音色不属于该语言会自动挑一个', () async {
      final repository = await buildRepository();
      await repository.setVoice('zh-CN-YunyangNeural');

      await repository.setLanguage('en-US');

      expect(repository.voice, 'en-US-AriaNeural');
      expect(EdgeTTSUtil().voice, 'en-US-AriaNeural');
    });

    test('切换语言时，当前音色已属于该语言就保持不动', () async {
      final repository = await buildRepository();
      await repository.setVoice('zh-CN-YunyangNeural');

      await repository.setLanguage('zh-CN');

      expect(repository.voice, 'zh-CN-YunyangNeural');
    });

    test('音色目录拉不到时，切语言不会把已有音色弄丢', () async {
      _installEdgeClient(error: http.ClientException('boom'));

      final repository = await buildRepository();
      await repository.setVoice('zh-CN-YunyangNeural');

      await repository.setLanguage('en-US');

      expect(repository.voice, 'zh-CN-YunyangNeural');
    });

    test('applySavedSetting 把存下来的参数应用到 Edge', () async {
      SharedPreferences.setMockInitialValues({
        'isOpenclawTTS': false,
        '_edgeTTS': jsonEncode({
          'volume': 0.5,
          'pitch': -100,
          'rate': 2.0,
          'language': 'zh-CN',
          'voice': 'zh-CN-YunyangNeural',
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final repository = SettingRepository(
        preferencesService: SharedPreferencesService(prefs),
      );

      expect(repository.volume, 0.5);
      expect(repository.pitch, -100);
      expect(repository.rate, 2.0);
      expect(repository.voice, 'zh-CN-YunyangNeural');

      repository.applySavedSetting();

      expect(EdgeTTSUtil().volume, 0.5);
      expect(EdgeTTSUtil().pitch, -100);
      expect(EdgeTTSUtil().rate, 2.0);
      expect(EdgeTTSUtil().voice, 'zh-CN-YunyangNeural');
    });

    test('存下来的设置坏掉时退回默认值，不把启动流程打挂', () async {
      SharedPreferences.setMockInitialValues({
        'isOpenclawTTS': false,
        '_edgeTTS': '{不是合法 json',
      });
      final prefs = await SharedPreferences.getInstance();
      final repository = SettingRepository(
        preferencesService: SharedPreferencesService(prefs),
      );

      expect(repository.volume, 1.0);
      expect(repository.pitch, 0);
      expect(repository.rate, 1.0);
      expect(repository.language, EdgeTTSUtil.defaultLocale);
      expect(repository.voice, isNull);
    });
  });
}
