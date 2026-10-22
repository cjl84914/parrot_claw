import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_app/util/tts_voice_util.dart';

void main() {
  group('parseVoices', () {
    test('过滤掉非 Map 元素，并把值统一成字符串', () {
      final voices = TtsVoiceUtil.parseVoices([
        {'name': 'Tingting', 'locale': 'zh-CN', 'network_required': 1},
        'not-a-map',
        null,
      ]);

      expect(voices, hasLength(1));
      expect(voices.first['name'], 'Tingting');
      expect(voices.first['network_required'], '1');
    });

    test('原始值不是 List 时返回空列表', () {
      expect(TtsVoiceUtil.parseVoices(null), isEmpty);
      expect(TtsVoiceUtil.parseVoices('boom'), isEmpty);
    });
  });

  group('localeMatches', () {
    test('忽略大小写与下划线/连字符差异', () {
      expect(TtsVoiceUtil.localeMatches('zh_CN', 'zh-CN'), isTrue);
      expect(TtsVoiceUtil.localeMatches('ZH-cn', 'zh-CN'), isTrue);
    });

    test('主语言一致即可匹配，语言只给主标签时也能匹配具体 locale', () {
      expect(TtsVoiceUtil.localeMatches('zh-CN', 'zh'), isTrue);
      expect(TtsVoiceUtil.localeMatches('zh-TW', 'zh-CN'), isTrue);
      expect(TtsVoiceUtil.localeMatches('en-US', 'en'), isTrue);
    });

    test('不同语言不匹配，空值不匹配', () {
      expect(TtsVoiceUtil.localeMatches('en-US', 'zh-CN'), isFalse);
      expect(TtsVoiceUtil.localeMatches('', 'zh'), isFalse);
      expect(TtsVoiceUtil.localeMatches('zh-CN', null), isFalse);
    });
  });

  group('keyOf / labelOf', () {
    test('有 identifier 时用它做 key（iOS、macOS）', () {
      final voice = {
        'name': 'Tingting',
        'locale': 'zh-CN',
        'identifier': 'com.apple.voice.compact.zh-CN.Tingting',
      };
      expect(
        TtsVoiceUtil.keyOf(voice),
        'com.apple.voice.compact.zh-CN.Tingting',
      );
    });

    test('没有 identifier 时退回 name@locale（Android、Windows）', () {
      expect(
        TtsVoiceUtil.keyOf({'name': 'Tingting', 'locale': 'zh-CN'}),
        'Tingting@zh-CN',
      );
      expect(TtsVoiceUtil.keyOf({'name': 'X', 'identifier': ''}), 'X@');
    });

    test('展示文案带上 locale，缺字段时优雅降级', () {
      expect(
        TtsVoiceUtil.labelOf({'name': 'Tingting', 'locale': 'zh-CN'}),
        'Tingting (zh-CN)',
      );
      expect(TtsVoiceUtil.labelOf({'locale': 'zh-CN'}), 'zh-CN');
      expect(TtsVoiceUtil.labelOf({'name': 'Tingting'}), 'Tingting');
    });
  });

  group('visibleVoices', () {
    final voices = [
      {'name': 'Tingting', 'locale': 'zh-CN'},
      {'name': 'Sinji', 'locale': 'zh-HK'},
      {'name': 'Alex', 'locale': 'en-US'},
      {'name': 'Samantha', 'locale': 'en-US'},
    ];

    test('按当前语言过滤，并按 locale、name 排序', () {
      final visible = TtsVoiceUtil.visibleVoices(
        voices: voices,
        language: 'zh-CN',
      );

      expect(visible.map((v) => v['name']), ['Tingting', 'Sinji']);
    });

    test('语言为空或一个都匹配不到时退回全部，下拉框不会空白', () {
      expect(
        TtsVoiceUtil.visibleVoices(voices: voices, language: null),
        hasLength(4),
      );
      expect(
        TtsVoiceUtil.visibleVoices(voices: voices, language: 'ja-JP'),
        hasLength(4),
      );
    });

    test('已选音色不在语言过滤结果里也要保留', () {
      final visible = TtsVoiceUtil.visibleVoices(
        voices: voices,
        language: 'zh-CN',
        selected: {'name': 'Alex', 'locale': 'en-US'},
      );

      expect(visible.map((v) => v['name']), contains('Alex'));
      expect(visible, hasLength(3));
    });

    test('已选音色本机已不存在时，仍作为一项展示，避免下拉框显示成默认', () {
      final visible = TtsVoiceUtil.visibleVoices(
        voices: voices,
        language: 'zh-CN',
        selected: {'name': '已卸载音色', 'locale': 'zh-CN'},
      );

      expect(visible.map((v) => v['name']), contains('已卸载音色'));
    });

    test('按 key 去重，同名同 locale 的重复项只留一条', () {
      final visible = TtsVoiceUtil.visibleVoices(
        voices: [
          {'name': 'Tingting', 'locale': 'zh-CN'},
          {'name': 'Tingting', 'locale': 'zh-CN'},
        ],
        language: 'zh-CN',
      );

      expect(visible, hasLength(1));
    });

    test('不修改传入的原始列表', () {
      final input = [
        {'name': 'Alex', 'locale': 'en-US'},
        {'name': 'Tingting', 'locale': 'zh-CN'},
      ];
      TtsVoiceUtil.visibleVoices(voices: input, language: 'zh-CN');

      expect(input.map((v) => v['name']), ['Alex', 'Tingting']);
    });
  });
}
