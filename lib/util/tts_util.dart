import 'dart:async';
import 'dart:convert';
import "dart:io";
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'file_util.dart';

class TTSUtil {
  TTSUtil._internal();

  static final TTSUtil _instance = TTSUtil._internal();

  factory TTSUtil() => _instance;

  sherpa_onnx.OfflineTts? _tts;
  bool _isInitialized = false;
  late final AudioPlayer _player = AudioPlayer() ..onPlayerComplete.listen((_) {
    _onComplete?.call();
  });
  double _speed = 0.8;
  bool _isSpeekOn = false;

  Function()? _onComplete;

  void setCallbacks({Function()? onComplete}) {
    _onComplete = onComplete;
  }

  Future _init() async {
    if (!_isInitialized) {
      sherpa_onnx.initBindings();

      _tts?.free();
      _tts = await createOfflineTts();

      _isInitialized = true;

      // setSpeakerOn(false);
    }
  }

  // 新增：切换扬声器的方法
  Future setSpeakerOn(bool isOn) async {
    _isSpeekOn = isOn;
    await _setAudioContext();
  }

  Future _setAudioContext() async {
    await _player.setAudioContext(
      AudioContext(
        android: AudioContextAndroid(
          usageType: AndroidUsageType.media,
          contentType: AndroidContentType.speech,
          audioFocus: AndroidAudioFocus.none, // 严格保留，防止 ASR 被终止
        ),
        // iOS: AudioContextIOS(
        //   category: AVAudioSessionCategory.playAndRecord,
        //   options: [
        //     if (_isSpeekOn)
        //       AVAudioSessionOptions.defaultToSpeaker,
        //     AVAudioSessionOptions.allowBluetooth
        //   ],
        // ),
      ),
    );
  }

  // Future speak(String text) async {
  //   final File? file = await _genAudioFile(text);
  //   if (file != null) {
  //     await _player.play(DeviceFileSource(file.path));
  //   } else {
  //     print('Failed to save generated audio');
  //   }
  // }

  Future<String?> getTtsAudioBase64(String text) async {
    File? file = await _genAudioFile(text);
    if (file != null) {
      // 读取文件并转换为base64
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);

      // 删除临时文件
      await file.delete();
      return base64String;
    }
    return null;
  }

  Future<File?> _genAudioFile(String text) async {
    if (text == '') {
      return null;
    }
    await _init();
    if (_tts == null) {
      return null;
    }
    await stop();
    final stopwatch = Stopwatch();
    stopwatch.start();
    final genConfig = sherpa_onnx.OfflineTtsGenerationConfig(
      sid: 0,
      speed: _speed,
      referenceSampleRate: 16000,
      silenceScale: 0.2,
    );
    final audio = _tts!.generateWithConfig(text: text, config: genConfig);

    final suffix = '-sid-0-speed-${_speed.toStringAsPrecision(2)}';
    final filename = await generateWaveFilename(suffix);

    final ok = sherpa_onnx.writeWave(
      filename: filename,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );

    if (ok) {
      stopwatch.stop();
      double elapsed = stopwatch.elapsed.inMilliseconds.toDouble();

      double waveDuration =
          audio.samples.length.toDouble() / audio.sampleRate.toDouble();

      print(
        'Saved to\n$filename\n'
        'Elapsed: ${(elapsed / 1000).toStringAsPrecision(4)} s\n'
        'Wave duration: ${waveDuration.toStringAsPrecision(4)} s\n'
        'RTF: ${(elapsed / 1000).toStringAsPrecision(4)}/${waveDuration.toStringAsPrecision(4)} '
        '= ${(elapsed / 1000 / waveDuration).toStringAsPrecision(3)} ',
      );

      return File(filename);
    }
    return null;
  }

  Future stop() async {
    await _player.stop();
  }

  void dispose() {
    _tts?.free();
    _player.dispose();
  }

  Future playBase64(String base64) async {
    await _player.stop();
    await _player.setVolume(1.0);
    await _setAudioContext();
    final Uint8List bytes = base64Decode(base64);
    if (Platform.isAndroid) {
      // Android 端：直接内存播放
      await _player.play(BytesSource(bytes));
    } else {
      final tempDir = await getTemporaryDirectory();
      final fileName = 'tts_${DateTime.now().millisecondsSinceEpoch}.wav';
      final tempFile = File(p.join(tempDir.path, fileName));
      await tempFile.writeAsBytes(bytes);
      // 等待播放完成或至少让文件存在足够长时间
      await _player.play(DeviceFileSource(tempFile.path));
      // 建议：监听播放完成事件再删除，或者干脆只在下次播放前清理临时目录
      _player.onPlayerComplete.first.then((_) {
        if (tempFile.existsSync()) tempFile.delete();
      });
    }
  }

  Future playUrl(String audioUrl) async {
    await _player.stop();
    await _player.setVolume(1.0);
    await _setAudioContext();
    await _player.play(UrlSource(audioUrl));
  }
}

Future<sherpa_onnx.OfflineTts> createOfflineTts() async {
  // sherpa_onnx requires that model files are in the local disk, so we
  // need to copy all asset files to disk.
  await copyAllAssetFiles();

  sherpa_onnx.initBindings();

  String modelDir = '';
  String modelName = '';
  String voices = ''; // for Kokoro only
  String ruleFsts = '';
  String ruleFars = '';
  String lexicon = '';
  String dataDir = '';
  String dictDir = '';

  modelDir = 'vits-melo-tts-zh_en';
  modelName = 'model.onnx';
  lexicon = 'lexicon.txt';
  dictDir = 'vits-melo-tts-zh_en/dict';

  if (modelName == '') {
    throw Exception(
      'You are supposed to select a model by changing the code before you run the app',
    );
  }

  final Directory directory = await getApplicationSupportDirectory();
  modelName = p.join(directory.path, modelDir, modelName);

  if (ruleFsts != '') {
    final all = ruleFsts.split(',');
    var tmp = <String>[];
    for (final f in all) {
      tmp.add(p.join(directory.path, f));
    }
    ruleFsts = tmp.join(',');
  }

  if (ruleFars != '') {
    final all = ruleFars.split(',');
    var tmp = <String>[];
    for (final f in all) {
      tmp.add(p.join(directory.path, f));
    }
    ruleFars = tmp.join(',');
  }

  if (lexicon.contains(',')) {
    final all = lexicon.split(',');
    var tmp = <String>[];
    for (final f in all) {
      tmp.add(p.join(directory.path, f));
    }
    lexicon = tmp.join(',');
  } else if (lexicon != '') {
    lexicon = p.join(directory.path, modelDir, lexicon);
  }

  if (dataDir != '') {
    dataDir = p.join(directory.path, dataDir);
  }

  if (dictDir != '') {
    dictDir = p.join(directory.path, dictDir);
  }

  final tokens = p.join(directory.path, modelDir, 'tokens.txt');
  if (voices != '') {
    voices = p.join(directory.path, modelDir, voices);
  }

  late final sherpa_onnx.OfflineTtsVitsModelConfig vits;
  late final sherpa_onnx.OfflineTtsKokoroModelConfig kokoro;

  if (voices != '') {
    vits = sherpa_onnx.OfflineTtsVitsModelConfig();
    kokoro = sherpa_onnx.OfflineTtsKokoroModelConfig(
      model: modelName,
      voices: voices,
      tokens: tokens,
      dataDir: dataDir,
      dictDir: dictDir,
      lexicon: lexicon,
    );
  } else {
    vits = sherpa_onnx.OfflineTtsVitsModelConfig(
      model: modelName,
      lexicon: lexicon,
      tokens: tokens,
      dataDir: dataDir,
      dictDir: dictDir,
    );

    kokoro = sherpa_onnx.OfflineTtsKokoroModelConfig();
  }

  final modelConfig = sherpa_onnx.OfflineTtsModelConfig(
    vits: vits,
    kokoro: kokoro,
    numThreads: 4,
    debug: false,
    provider: 'cpu',
  );

  final config = sherpa_onnx.OfflineTtsConfig(
    model: modelConfig,
    ruleFsts: ruleFsts,
    ruleFars: ruleFars,
    maxNumSenetences: 1,
  );
  // print(config);

  final tts = sherpa_onnx.OfflineTts(config);
  print('tts created successfully');

  return tts;
}

Future<String> generateWaveFilename([String suffix = '']) async {
  final Directory directory = await getTemporaryDirectory();
  DateTime now = DateTime.now();
  final filename =
      '${now.year.toString()}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}$suffix.wav';

  return p.join(directory.path, filename);
}
