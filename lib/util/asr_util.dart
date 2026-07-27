import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'file_util.dart';

Future<sherpa_onnx.OfflineRecognizer> createOfflineRecognizer() async {
  final type = 0;

  final modelConfig = await getOfflineModelConfig(type: type);
  final config = sherpa_onnx.OfflineRecognizerConfig(
    model: modelConfig,
    ruleFsts: '',
  );
  return sherpa_onnx.OfflineRecognizer(config);
}

class ASRUtil {
  final Logger _log = Logger('ASRUtil');
  static final ASRUtil _instance = ASRUtil._internal();

  factory ASRUtil() => _instance;

  ASRUtil._internal();

  final AudioRecorder _audioRecorder = AudioRecorder();
  sherpa_onnx.OfflineRecognizer? _recognizer;
  final int _sampleRate = 16000;

  StreamSubscription<RecordState>? _recordSub;
  Function(RecordState recordState)? _listenerCallback;
  Function()? _initCallback;

  // VAD related vars
  sherpa_onnx.VoiceActivityDetector? _vad;
  sherpa_onnx.CircularBuffer? _buffer;

  // VAD config
  late sherpa_onnx.VadModelConfig _vadConfig;

  // 1. 定义回调
  Function(String text)? _onTextResult;
  bool _isIniting = false;

  // 2. 提供设置回调的方法
  void setCallbacks({
    Function(RecordState recordState)? onStateChanged,
    Function(String text)? onTextResult,
    Function()? initCallback,
  }) {
    _listenerCallback = onStateChanged;
    _onTextResult = onTextResult;
    _initCallback = initCallback;
  }

  final Completer<void> _initCompleter = Completer<void>();

  Future<void> get initialized => _initCompleter.future;

  bool get isInitialized => _initCompleter.isCompleted;

  RecordState? _recordState;

  void _init() async {
    try {
      if (isInitialized || _isIniting) return;
      _isIniting = true;

      sherpa_onnx.initBindings();

      _recordSub = _audioRecorder.onStateChanged().listen((recordState) {
        _recordState = recordState;
        _log.info(_recordState);
        _listenerCallback?.call(recordState);
      });

      // 初始化 VAD
      final sileroVadConfig = sherpa_onnx.SileroVadModelConfig(
        model: await copyAssetFile('assets/silero_vad.onnx'),
        minSilenceDuration: 0.25,
        minSpeechDuration: 0.5,
        maxSpeechDuration: 5.0,
      );

      _vadConfig = sherpa_onnx.VadModelConfig(
        sileroVad: sileroVadConfig,
        numThreads: 1,
        debug: false,
      );

      // create VAD, use buffer model
      _vad = sherpa_onnx.VoiceActivityDetector(
        config: _vadConfig,
        bufferSizeInSeconds: 30,
      );
      _buffer = sherpa_onnx.CircularBuffer(capacity: 30 * _sampleRate);

      _recognizer = await createOfflineRecognizer();

      final devs = await _audioRecorder.listInputDevices();
      _log.info(devs.toString());

      _initCompleter.complete(); // 通知初始化完成
      _initCallback?.call();
      _isIniting = false;
    } catch (e) {
      _initCompleter.completeError(e);
    }
  }

  void dispose() {
    _recordSub?.cancel();
    _audioRecorder.dispose();
    _recognizer?.free();
    _vad?.free(); // release vad
    _buffer?.free(); // release buffer
  }

  bool _isStarting = false;

  Future<void> start() async {
    if (_isStarting || _recordState == RecordState.record) {
      return;
    }

    _isStarting = true;

    try {
      _init();
      await initialized;
      await stop();
      if (await _audioRecorder.hasPermission()) {
        const encoder = AudioEncoder.pcm16bits;
        if (!await _isEncoderSupported(encoder)) {
          return;
        }
        final config = RecordConfig(
          encoder: encoder,
          sampleRate: _sampleRate,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: true,
          // streamBufferSize: 4096,
          // bitRate: 16,
          androidConfig: const AndroidRecordConfig(
            speakerphone: true,
            audioSource: AndroidAudioSource.voiceCommunication,
            audioManagerMode: AudioManagerMode.modeInCommunication,
            service: AndroidService(title: '正在倾听...'), //Background recording
          ),
        );
        final stream = await _audioRecorder.startStream(config);
        stream.listen(
          (data) {
            final samplesFloat32 = convertBytesToFloat32(
              Uint8List.fromList(data),
            );

            // use _buffer and _vad for offline stream data making
            _buffer!.push(samplesFloat32);

            final windowSize = _vadConfig.sileroVad.windowSize;
            while (_buffer!.size > windowSize) {
              final samples = _buffer!.get(
                startIndex: _buffer!.head,
                n: windowSize,
              );
              _buffer!.pop(windowSize);
              _vad!.acceptWaveform(samples);

              while (!_vad!.isEmpty()) {
                final segment = _vad!.front();
                final samples = segment.samples;

                // offline _recognizer stream handle logic
                final stream = _recognizer!.createStream();
                stream.acceptWaveform(
                  samples: samples,
                  sampleRate: _sampleRate,
                );
                _recognizer!.decode(stream);
                final text = _recognizer!.getResult(stream).text;

                stream.free();
                _vad!.pop();

                if (text != '嗯') {
                  _onTextResult?.call(text);
                }
              }
            }
          },
          onDone: () {
            _log.info('stream stopped.');
          },
        );
      }
    } catch (e, stackTrace) {
      _log.severe('启动录音失败', e, stackTrace);
    } finally {
      _isStarting = false;
    }
  }

  Future<void> stop() async {
    await _audioRecorder.stop();
   // handle rest of vad data
    _vad!.flush();
    while (!_vad!.isEmpty()) {
      final segment = _vad!.front();
      final samples = segment.samples;

      final stream = _recognizer!.createStream();
      stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);
      _recognizer!.decode(stream);
      final text = _recognizer!.getResult(stream).text;
      _onTextResult?.call(text);
      stream.free();
      _vad!.pop();
    }
  }

  // Future<void> cancel() async {
  //   await _audioRecorder.cancel();
  // }

  Future<bool> isEncoderSupported(AudioEncoder encoder) async {
    final isSupported = await _audioRecorder.isEncoderSupported(encoder);

    if (!isSupported) {
      _log.info('${encoder.name} is not supported on this platform.');
      _log.info('Supported encoders are:');

      for (final e in AudioEncoder.values) {
        if (await _audioRecorder.isEncoderSupported(e)) {
          _log.info('- ${encoder.name}');
        }
      }
    }

    return isSupported;
  }

  Future<void> pause() async {
    if (_recordState == RecordState.record) {
      _log.info("暂停录音");
      await _audioRecorder.pause();
    }
  }

  Future<void> resume() async {
    if (_recordState == RecordState.pause) {
      _log.info('iOS 重新启动录音');

      try {
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          await stop();
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await start();
          return;
        }

        await _audioRecorder.resume();
      } catch (e, stackTrace) {
        _log.severe('恢复录音失败', e, stackTrace);
      }
    }
  }

  getAmplitude() => _audioRecorder.getAmplitude();

  Future<bool> _isEncoderSupported(AudioEncoder encoder) async {
    final isSupported = await _audioRecorder.isEncoderSupported(encoder);

    if (!isSupported) {
      _log.info('${encoder.name} is not supported on this platform.');
      _log.info('Supported encoders are:');

      for (final e in AudioEncoder.values) {
        if (await _audioRecorder.isEncoderSupported(e)) {
          _log.info('- ${encoder.name}');
        }
      }
    }

    return isSupported;
  }
}

Future<sherpa_onnx.OfflineModelConfig> getOfflineModelConfig({
  required int type,
  String modelDir = "assets",
}) async {
  switch (type) {
    // senseVoice
    case 0:
      return sherpa_onnx.OfflineModelConfig(
        senseVoice: sherpa_onnx.OfflineSenseVoiceModelConfig(
          model: await copyAssetFile('$modelDir/senseVoice/model.int8.onnx'),
        ),
        tokens: await copyAssetFile('$modelDir/senseVoice/tokens.txt'),
      );
    // whisper
    case 1:
      return sherpa_onnx.OfflineModelConfig(
        whisper: sherpa_onnx.OfflineWhisperModelConfig(
          encoder: await copyAssetFile('$modelDir/whisper/base-encoder.onnx'),
          decoder: await copyAssetFile('$modelDir/whisper/base-decoder.onnx'),
        ),
        tokens: await copyAssetFile('$modelDir/whisper/base-tokens.txt'),
        modelType: 'whisper',
      );
    // nemo_transducer-parakeet-tdt
    case 2:
      return sherpa_onnx.OfflineModelConfig(
        transducer: sherpa_onnx.OfflineTransducerModelConfig(
          encoder: await copyAssetFile(
            '$modelDir/nemo_transducer/encoder.int8.onnx',
          ),
          decoder: await copyAssetFile(
            '$modelDir/nemo_transducer/decoder.int8.onnx',
          ),
          joiner: await copyAssetFile(
            '$modelDir/nemo_transducer/joiner.int8.onnx',
          ),
        ),
        tokens: await copyAssetFile('$modelDir/nemo_transducer/tokens.txt'),
        modelType: 'nemo_transducer',
      );
    default:
      throw ArgumentError('Unsupported type: $type');
  }
}
