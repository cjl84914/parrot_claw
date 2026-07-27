import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum TtsState { initialized, playing, stopped, paused, continued }

class FlutterTTSUtil {
  static final FlutterTTSUtil _instance = FlutterTTSUtil._internal();

  factory FlutterTTSUtil() => _instance;

  FlutterTTSUtil._internal();

  late FlutterTts flutterTts;
  bool isCurrentLanguageInstalled = false;
  TtsState ttsState = TtsState.stopped;

  get isPlaying => ttsState == TtsState.playing;

  get isStopped => ttsState == TtsState.stopped;

  get isPaused => ttsState == TtsState.paused;

  get isContinued => ttsState == TtsState.continued;

  bool get isIOS => !kIsWeb && Platform.isIOS;

  bool get isAndroid => !kIsWeb && Platform.isAndroid;

  bool get isWindows => !kIsWeb && Platform.isWindows;

  bool get isWeb => kIsWeb;

  initSetting() async {
    flutterTts = FlutterTts();
    //To await speak completion.
    await flutterTts.awaitSpeakCompletion(true);
    //To await synthesize to file completion.
    if (Platform.isAndroid || Platform.isIOS) {
      await flutterTts.awaitSynthCompletion(true);
    }

    if (isAndroid) {
      // flutterTts.setInitHandler(() {
      //   print("TTS Initialized");
      //   ttsState = TtsState.initialized;
      // });
      // _getDefaultEngine();
      // _getDefaultVoice();
    }
    if (isIOS) {
      await flutterTts.setSharedInstance(true);
      // await flutterTts.setIosAudioCategory(
      //   IosTextToSpeechAudioCategory.playAndRecord,
      //   [
      //     IosTextToSpeechAudioCategoryOptions.allowBluetooth,
      //     // IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
      //     // IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      //   ],
      //   IosTextToSpeechAudioMode.voicePrompt,
      // );
    }
    flutterTts.setStartHandler(() {
      ttsState = TtsState.playing;
    });

    flutterTts.setCompletionHandler(() {
      ttsState = TtsState.stopped;
      _onComplete?.call();
    });

    flutterTts.setCancelHandler(() {
      ttsState = TtsState.stopped;
    });

    flutterTts.setPauseHandler(() {
      ttsState = TtsState.paused;
    });

    flutterTts.setContinueHandler(() {
      ttsState = TtsState.continued;
    });

    flutterTts.setErrorHandler((msg) {
      EasyLoading.showToast(msg);
      ttsState = TtsState.stopped;
    });
  }

  Future<void> configureIosAudioSession({required bool speakerOn}) async {
    if (!isIOS) return;

    await flutterTts.setSharedInstance(true);
    await flutterTts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playAndRecord,
      [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        if (speakerOn) IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
      ],
      IosTextToSpeechAudioMode.voiceChat,
    );
  }

  Function()? _onComplete;

  void setCallbacks({Function()? onComplete}) {
    _onComplete = onComplete;
  }

  void setVolume(double volume) async {
    flutterTts.setVolume(volume);
  }

  void setSpeechRate(double rate) async {
    flutterTts.setSpeechRate(rate);
  }

  void setPitch(double pitch) async {
    flutterTts.setPitch(pitch);
  }

  void setLanguage(String language) async {
    flutterTts.setLanguage(language);
  }

  void setEngine(String engine) async {
    flutterTts.setEngine(engine);
  }

  Future speak(text) async {
    if (text != null) {
      if (ttsState == TtsState.playing) {
        await flutterTts.stop();
        await Future.delayed(const Duration(seconds: 1));
      }
      if (ttsState == TtsState.stopped) {
        await flutterTts.speak(text, focus: false);
      }
    }
  }

  Future stop() async {
    await flutterTts.stop();
  }

  Future pause() async {
    await flutterTts.pause();
  }

  Future dispose() async {
    await flutterTts.stop();
    flutterTts.clearVoice();
  }

  Future<dynamic> getLanguages() async => await flutterTts.getLanguages;

  Future<dynamic> getEngines() async => await flutterTts.getEngines;

  Future _getDefaultEngine() async {
    var engine = await flutterTts.getDefaultEngine;
    if (engine != null) {
      print(engine);
    }
  }

  Future _getDefaultVoice() async {
    var voice = await flutterTts.getDefaultVoice;
    if (voice != null) {
      print(voice);
    }
  }

  Future<bool> isSupport(String language) async {
    return await flutterTts.isLanguageAvailable(language);
  }

  List<DropdownMenuItem<String>> getEnginesDropDownMenuItems(dynamic engines) {
    var items = <DropdownMenuItem<String>>[];
    for (dynamic type in engines) {
      items.add(
        DropdownMenuItem(
          value: type as String?,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(type as String, maxLines: 1),
          ),
        ),
      );
    }
    return items;
  }

  List<DropdownMenuItem<String>> getLanguageDropDownMenuItems(
    dynamic languages,
  ) {
    var items = <DropdownMenuItem<String>>[];
    for (dynamic type in languages) {
      if (type.toString().startsWith("zh")) {
        items.add(
          DropdownMenuItem(value: type as String?, child: Text(type as String)),
        );
      }
    }
    return items;
  }

  Future<Directory> getDefaultTemporaryPath() async {
    final tempDir = await getTemporaryDirectory();
    final directory = Directory("${tempDir.path}/audio");
    if (!await directory.exists()) {
      directory.create();
    }
    return directory;
  }

  // Future<String> saveTtsFile(String sentence) async {
  //   final directory = await getDefaultTemporaryPath();
  //   final timestamp = DateTime.now().millisecondsSinceEpoch;
  //   final extension = isIOS ? 'caf' : 'wav';
  //   final fileName = "tts_temp_$timestamp.$extension";
  //   final filePath = '${directory.path}/$fileName';
  //   // 生成WAV文件
  //   await flutterTts.synthesizeToFile(sentence, filePath, true);
  //   debugPrint('TTS文件已保存: $filePath');
  //   return filePath;
  // }

  /// 获取TTS音频的base64编码
  Future<String> getTtsAudioBase64(String sentence) async {
    final directory = await getDefaultTemporaryPath();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = isIOS ? 'caf' : 'wav';
    final fileName = "tts_temp_$timestamp.$extension";
    final filePath = '${directory.path}/$fileName';

    try {
      // 生成WAV文件
      await flutterTts.synthesizeToFile(sentence, filePath, true);

      // 读取文件并转换为base64
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);

      // 删除临时文件
      await file.delete();

      debugPrint('TTS音频已转换为base64，长度: ${base64String.length}');
      return base64String;
    } catch (e) {
      debugPrint('生成TTS base64时出错: $e');
      rethrow;
    }
  }

  /// 删除临时TTS文件
  Future<void> deleteTemporaryTtsFiles() async {
    try {
      final directory = await getDefaultTemporaryPath();
      final files = await directory.list().toList();

      int deletedCount = 0;
      for (var file in files) {
        if (file is File &&
            file.path.endsWith('.wav') &&
            file.path.contains('tts_')) {
          try {
            await file.delete();
            debugPrint('删除临时TTS文件: ${file.path}');
            deletedCount++;
          } catch (e) {
            debugPrint('删除文件失败 ${file.path}: $e');
          }
        }
      }

      debugPrint('共删除 $deletedCount 个临时TTS文件');
    } catch (e) {
      debugPrint('删除临时TTS文件时出错: $e');
    }
  }

  static Future<String> audioFileToBase64(String filePath) async {
    // 读取文件并转换为base64
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final base64String = base64Encode(bytes);
    debugPrint('TTS音频已转换为base64，长度: ${base64String.length}');
    return base64String;
  }

  /// 从网络URL下载音频文件并转换为base64
  static Future<String> networkAudioFileToBase64(String url) async {
    try {
      // debugPrint('开始从网络下载音频: $url');

      // 下载音频文件
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        // 将下载的字节数据转换为base64
        final base64String = base64Encode(response.bodyBytes);
        debugPrint('网络音频已转换为base64，长度: ${base64String.length}');
        return base64String;
      } else {
        throw Exception('下载音频失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('网络音频转换base64失败: $e');
      rethrow;
    }
  }
}
