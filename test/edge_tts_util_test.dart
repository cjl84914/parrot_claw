import 'dart:typed_data';

import 'package:flutter_edge_tts/flutter_edge_tts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_app/util/edge_tts_util.dart';
import 'package:parrot_app/util/tts_voice_util.dart';

EdgeTtsVoice _voice(
  String shortName,
  String locale, {
  String gender = 'Female',
}) {
  return EdgeTtsVoice(
    name:
        'Microsoft Server Speech Text to Speech Voice ($locale, ${shortName.split('-').last})',
    shortName: shortName,
    gender: gender,
    locale: locale,
    suggestedCodec: 'audio-24khz-48kbitrate-mono-mp3',
    friendlyName: '$shortName ($locale)',
    status: 'GA',
  );
}

void main() {
  group('语速换算', () {
    test('夹紧到 0.5~2.0', () {
      expect(EdgeTTSUtil.clampRate(0.1), 0.5);
      expect(EdgeTTSUtil.clampRate(9), 2.0);
      expect(EdgeTTSUtil.clampRate(1.2), 1.2);
    });

    test('转成 SSML 字符串保留两位', () {
      expect(EdgeTTSUtil.rateToEdgeRate(1), '1.00');
      expect(EdgeTTSUtil.rateToEdgeRate(1.25), '1.25');
      expect(EdgeTTSUtil.rateToEdgeRate(5), '2.00');
    });

    test('flutter_tts 的 0.5 是正常语速', () {
      expect(EdgeTTSUtil.rateFromLocalRate(0.5), 1.0);
      expect(EdgeTTSUtil.rateFromLocalRate(0.25), 0.5);
      expect(EdgeTTSUtil.rateFromLocalRate(1.0), 2.0);
      // 非正数按正常语速兜底，避免算出 0 让服务端报错
      expect(EdgeTTSUtil.rateFromLocalRate(0), 1.0);
      expect(EdgeTTSUtil.rateFromLocalRate(-1), 1.0);
    });
  });

  group('音量与音调', () {
    test('音量 0.0~1.0 映射成 0~100', () {
      expect(EdgeTTSUtil.volumeToEdgeVolume(0), '0');
      expect(EdgeTTSUtil.volumeToEdgeVolume(0.8), '80');
      expect(EdgeTTSUtil.volumeToEdgeVolume(1), '100');
      expect(EdgeTTSUtil.volumeToEdgeVolume(1.5), '100');
    });

    test('音调带符号，0 输出 +0Hz', () {
      expect(EdgeTTSUtil.pitchToEdgePitch(0), '+0Hz');
      expect(EdgeTTSUtil.pitchToEdgePitch(10.4), '+10Hz');
      expect(EdgeTTSUtil.pitchToEdgePitch(-20), '-20Hz');
      expect(EdgeTTSUtil.pitchToEdgePitch(-0.4), '+0Hz');
      // 上限对齐官方 example 的音调滑杆（-5~5 × 20 = ±100Hz）
      expect(EdgeTTSUtil.pitchToEdgePitch(999), '+100Hz');
      expect(EdgeTTSUtil.pitchToEdgePitch(-999), '-100Hz');
    });
  });

  group('音色映射', () {
    final voices = [
      _voice('zh-CN-XiaoxiaoNeural', 'zh-CN'),
      _voice('zh-CN-YunyangNeural', 'zh-CN', gender: 'Male'),
      _voice('zh-TW-HsiaoChenNeural', 'zh-TW'),
      _voice('en-US-AriaNeural', 'en-US'),
    ];

    test('转出的 Map 能被 TtsVoiceUtil 直接消费', () {
      final maps = EdgeTTSUtil.voicesToMaps(voices);
      expect(maps.first['name'], 'zh-CN-XiaoxiaoNeural');
      expect(maps.first['locale'], 'zh-CN');
      expect(TtsVoiceUtil.keyOf(maps.first), 'zh-CN-XiaoxiaoNeural');
      expect(TtsVoiceUtil.labelOf(maps.first), 'zh-CN-XiaoxiaoNeural (zh-CN)');
      // 同一份数据走设置页的音色筛选逻辑，只应留下中文音色
      final visible = TtsVoiceUtil.visibleVoices(
        voices: maps,
        language: 'zh-CN',
      );
      expect(visible.length, 3);
    });

    test('locale 去重排序', () {
      expect(EdgeTTSUtil.localesOf(voices), ['en-US', 'zh-CN', 'zh-TW']);
    });

    test('locale 去重时保留服务端的规范写法', () {
      final duplicated = [...voices, _voice('zh-CN-YunxiNeural', 'zh-cn')];
      expect(EdgeTTSUtil.localesOf(duplicated), ['en-US', 'zh-CN', 'zh-TW']);
      expect(EdgeTTSUtil.canonicalLocale(' zh_CN '), 'zh-CN');
    });

    test('挑音色：精确匹配优先，再退到同主语言', () {
      expect(EdgeTTSUtil.pickVoice(voices, 'zh-CN'), 'zh-CN-XiaoxiaoNeural');
      expect(
        EdgeTTSUtil.pickVoice(voices, 'zh-CN', gender: 'Male'),
        'zh-CN-YunyangNeural',
      );
      // zh-HK 没有精确音色，退到第一个同主语言音色
      expect(EdgeTTSUtil.pickVoice(voices, 'zh-HK'), 'zh-CN-XiaoxiaoNeural');
      // 大小写/下划线不敏感
      expect(EdgeTTSUtil.pickVoice(voices, 'ZH_cn'), 'zh-CN-XiaoxiaoNeural');
      expect(EdgeTTSUtil.pickVoice(voices, ''), isNull);
      expect(EdgeTTSUtil.pickVoice(const [], 'zh-CN'), isNull);
    });
  });

  group('音频扩展名嗅探', () {
    Uint8List bytes(List<int> head) => Uint8List.fromList(head);

    test('按文件头识别常见容器', () {
      // RIFF....WAVE
      expect(
        EdgeTTSUtil.audioExtensionOf(
          bytes([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0]),
        ),
        'wav',
      );
      // ID3 开头的 mp3
      expect(
        EdgeTTSUtil.audioExtensionOf(bytes([0x49, 0x44, 0x33, 0x03])),
        'mp3',
      );
      // MPEG 帧同步（0xFF 0xFB）
      expect(
        EdgeTTSUtil.audioExtensionOf(bytes([0xFF, 0xFB, 0x90, 0x00])),
        'mp3',
      );
      expect(
        EdgeTTSUtil.audioExtensionOf(bytes([0x4F, 0x67, 0x67, 0x53])),
        'ogg',
      );
      expect(
        EdgeTTSUtil.audioExtensionOf(bytes([0x1A, 0x45, 0xDF, 0xA3])),
        'webm',
      );
    });

    test('认不出来时退回 fallback', () {
      expect(EdgeTTSUtil.audioExtensionOf(bytes([0, 0, 0, 0])), 'wav');
      expect(
        EdgeTTSUtil.audioExtensionOf(bytes([0, 0, 0, 0]), fallback: 'pcm'),
        'pcm',
      );
      expect(
        EdgeTTSUtil.audioExtensionOf(Uint8List(0), fallback: 'pcm'),
        'pcm',
      );
      expect(EdgeTTSUtil.audioExtensionOf(bytes([0xFF])), 'wav');
    });
  });

  group('实例参数', () {
    test('默认音色与默认 locale 对得上', () {
      expect(EdgeTTSUtil.defaultVoice, 'zh-CN-YunyangNeural');
      // defaultLocale 由 defaultVoice 推导（zh-CN-YunyangNeural -> zh-CN），
      // 设置页的语言下拉框默认选中它。
      expect(EdgeTTSUtil.defaultLocale, 'zh-CN');
    });

    test('设置语速/音调/音量后 prosody 与 config 同步', () {
      final tts = EdgeTTSUtil()..showErrorToast = false;
      tts.setSpeechRate(1.5);
      tts.setPitch(-12);
      tts.setVolume(0.6);

      expect(tts.rate, 1.5);
      expect(tts.pitch, -12);
      expect(tts.volume, 0.6);
      expect(tts.prosody.rate, '1.50');
      expect(tts.prosody.pitch, '-12Hz');
      expect(tts.prosody.volume, '60');

      tts.setSpeechRateFromLocalRate(0.5);
      expect(tts.prosody.rate, '1.00');

      tts.configure(
        voice: 'en-US-AriaNeural',
        outputFormat: EdgeTtsOutputFormat.ogg24Khz16BitMonoOpus,
      );
      expect(tts.config.voice, 'en-US-AriaNeural');
      expect(tts.config.outputFormat.fileExtension, 'ogg');

      // 换音色会清掉显式 locale，交给 SSML 从音色名推断
      tts.setLanguage('zh_CN');
      expect(tts.voiceLocale, 'zh-CN');
      tts.setVoice('zh-CN-YunxiNeural');
      expect(tts.voiceLocale, isNull);

      // 单例是共享的，改完要复原，避免污染后面的用例。
      tts.configure(
        voice: EdgeTTSUtil.defaultVoice,
        outputFormat: EdgeTTSUtil.defaultOutputFormat,
      );
    });

    test('未初始化时状态为空闲、无客户端', () {
      final tts = EdgeTTSUtil();
      expect(tts.isInitialized, isFalse);
      expect(tts.state, EdgeTtsState.idle);
      expect(tts.isStopped, isTrue);
      expect(tts.isPlaying, isFalse);
      expect(tts.isSynthesizing, isFalse);
      expect(tts.player, isNull);
      expect(() => tts.client, throwsStateError);
      expect(() => tts.synthesizeStream('你好'), throwsStateError);
    });

    test('空文本不触发合成', () async {
      final tts = EdgeTTSUtil()..showErrorToast = false;
      expect(await tts.speak('   '), isFalse);
      await expectLater(tts.synthesize(''), throwsA(isA<EdgeTtsException>()));
      // 空 base64 不应该去碰播放器
      await tts.playBase64('');
    });

    test('默认输出必须是实测可用的格式', () {
      // 2026-09-15 实测：服务端只认白名单里那 3 种，其余（含 raw/riff 的 24k PCM、
      // 16k/48k mp3、ogg opus）都只发 turn.end 不给音频 -> empty_audio。
      expect(
        EdgeTTSUtil.supportedOutputFormats,
        contains(EdgeTTSUtil.defaultOutputFormat),
      );
      expect(
        EdgeTTSUtil.supportedOutputFormats,
        isNot(contains(EdgeTtsOutputFormat.raw24Khz16BitMonoPcm)),
      );
      expect(
        EdgeTTSUtil.supportedOutputFormats,
        isNot(contains(EdgeTtsOutputFormat.riff24Khz16BitMonoPcm)),
      );
      // 也不能默认 webm：iOS/macOS 的 AVPlayer 不认，那边直接播不出来。
      expect(EdgeTTSUtil.defaultOutputFormat.fileExtension, 'mp3');
    });

    test('不支持的格式本地快速失败，不白跑一次请求', () async {
      final tts = EdgeTTSUtil()..showErrorToast = false;
      tts.configure(outputFormat: EdgeTtsOutputFormat.raw24Khz16BitMonoPcm);
      expect(tts.isOutputFormatSupported, isFalse);
      await expectLater(
        tts.synthesize('你好'),
        throwsA(
          isA<EdgeTtsException>().having(
            (e) => e.code,
            'code',
            'unsupported_output_format',
          ),
        ),
      );

      // 单例是共享的，改完复原
      tts.configure(outputFormat: EdgeTTSUtil.defaultOutputFormat);
      expect(tts.isOutputFormatSupported, isTrue);
    });

    test('MIME 跟当前输出格式对齐', () {
      final tts = EdgeTTSUtil();
      expect(tts.audioMimeType, 'audio/mpeg');
      tts.configure(outputFormat: EdgeTtsOutputFormat.webm24Khz16BitMonoOpus);
      expect(tts.audioMimeType, 'audio/webm');
      tts.configure(outputFormat: EdgeTTSUtil.defaultOutputFormat);
      expect(tts.audioMimeType, 'audio/mpeg');
    });

    test('未初始化时 setSpeakerOn 只记状态、不碰播放器', () async {
      final tts = EdgeTTSUtil();
      await tts.setSpeakerOn(true);
      expect(tts.isSpeakerOn, isTrue);
      expect(tts.player, isNull);
    });
  });
}
