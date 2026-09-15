import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_edge_tts/flutter_edge_tts.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tts_voice_util.dart';

/// Edge 在线语音合成（`flutter_edge_tts`）的播放状态。
///
/// 和 `TtsState`（系统 TTS）相比多了一个 [synthesizing]：
/// Edge 是「先联网合成、再本地播放」，合成阶段还没有声音，UI 需要区分。
enum EdgeTtsState { idle, synthesizing, playing, paused }

/// `flutter_edge_tts` 的封装，用法对齐 [FlutterTTSUtil]。
///
/// 关键差异（务必先读，否则容易踩坑）：
///
/// 1. **在线合成**：文本经 WebSocket 发到 Edge 朗读服务，拿回音频字节；
///    所以断网/服务端变更会失败，这里内置了失败重试（[maxRetries]）。
/// 2. **播放要自己来**：插件明确不负责播放，这里用 `audioplayers` 补上
///    （Android 走内存字节，其余平台落临时文件再播，与 `TTSUtil` 的做法一致）。
/// 3. **没有「合成中断」**：`pause()` 只能暂停播放，已发出的合成请求仍会跑完；
///    想真正打断请用 `stop()`——它会作废当前合成结果（靠代际号丢弃迟到的字节）。
/// 4. **没有引擎概念**：Edge 服务端里「音色」就是引擎，所以不提供
///    `setEngine/getEngines`。语言由音色自身决定，`setLanguage()` 只改 SSML 的
///    `xml:lang`，**不会自动换音色**；要换音色请配合 [pickVoice] / [setVoice]。
/// 5. 音色名必须带 locale 前缀（如 `zh-CN-YunyangNeural`），否则 SSML 构建会
///    抛 `invalid_voice_locale`。
class EdgeTTSUtil {
  EdgeTTSUtil._internal();

  static final EdgeTTSUtil _instance = EdgeTTSUtil._internal();

  factory EdgeTTSUtil() => _instance;

  /// 默认音色：云扬（zh-CN 新闻男声），与语音页当前使用的一致。
  static const String defaultVoice = 'zh-CN-YunyangNeural';

  /// [defaultVoice] 对应的 locale（`zh-CN`），设置页的语言下拉框默认用它，
  /// 保证一进页面就有选中项、音色列表也默认只列中文音色。
  static final String defaultLocale = defaultVoice.split('-').take(2).join('-');

  /// 默认输出：24kHz / 96kbps 单声道 mp3（插件作者的默认值）。
  ///
  /// **不要换成 PCM**。2026-09-15 实测该接口只认 [supportedOutputFormats] 里那 3 种，
  /// 其余格式（含 `raw`/`riff` 的 24k PCM、16k/48k mp3、ogg opus）服务端一律只发
  /// `turn.start` + `turn.end` 而**不返回任何音频**，插件最终抛
  /// `EdgeTtsException(empty_audio)`。
  ///
  /// **也不要换成 webm/opus**（虽然它体积只有 mp3 一半，也是可用的格式）：
  /// iOS/macOS 的 AVPlayer 根本不支持 webm，`audioplayers` 在那边会直接播不出来，
  /// WKWebView 的 `decodeAudioData` 也解不了 opus-in-webm，口型同步同样拿不到 PCM。
  /// mp3 才是「能播 + 能解」两边都通的那个。
  static const EdgeTtsOutputFormat defaultOutputFormat =
      EdgeTtsOutputFormat.audio24Khz96KbitrateMonoMp3;

  /// 实测可用的输出格式白名单（2026-09-15）。
  ///
  /// 不在这个集合里的格式会在请求前快速失败，不浪费一次往返（见 [_checkOutputFormat]）。
  /// 服务端行为可能变，真遇到「格式升级了」，改这里即可。
  static const Set<EdgeTtsOutputFormat> supportedOutputFormats = {
    EdgeTtsOutputFormat.audio24Khz48KbitrateMonoMp3,
    EdgeTtsOutputFormat.audio24Khz96KbitrateMonoMp3,
    EdgeTtsOutputFormat.webm24Khz16BitMonoOpus,
  };

  /// 语速倍率的合理区间（`1.0` 为正常语速）。
  ///
  /// 对齐官方 example 的 Speed 滑杆（`0.5`~`2.0`，默认 `1.0`）：
  /// https://pub.dev/packages/flutter_edge_tts/example
  static const double minRate = 0.5;
  static const double maxRate = 2.0;

  /// 音调偏移（Hz）的合理区间。
  ///
  /// 官方 example 的 Pitch 滑杆是 `-5`~`5`，取值时 `× 20` 换算成 Hz，
  /// 也就是 `-100Hz`~`+100Hz`；这里直接用 Hz，省掉那层换算。
  static const double minPitch = -100;
  static const double maxPitch = 100;

  /// 临时文件前缀，[deleteTemporaryTtsFiles] 靠它识别要清理的文件。
  static const String _tempFilePrefix = 'edge_tts_';

  FlutterEdgeTts? _client;
  AudioPlayer? _player;
  StreamSubscription<void>? _playerCompleteSub;

  EdgeTtsState _state = EdgeTtsState.idle;

  String _voice = defaultVoice;
  String? _voiceLocale;
  EdgeTtsOutputFormat _outputFormat = defaultOutputFormat;
  bool _sentenceBoundary = false;
  bool _wordBoundary = false;
  double _volume = 1.0;
  double _rate = 1.0;
  double _pitch = 0;

  /// 是否外放。Android 上会换算成音频焦点策略（见 [_applyAudioContext]）。
  bool _speakerOn = false;

  /// 合成失败时的重试次数（不含首次）。
  int maxRetries = 2;

  /// 重试前的等待时间，按尝试次数线性递增。
  Duration retryDelay = const Duration(milliseconds: 400);

  /// 是否打印插件内部日志。
  bool enableLogging = false;

  /// 失败时是否用 [EasyLoading] 弹 toast（单测里可关掉）。
  bool showErrorToast = true;

  bool _initialized = false;

  /// 代际号：每次 `speak/stop` 自增，用来丢弃迟到的合成结果。
  int _generation = 0;

  List<EdgeTtsVoice>? _voiceCache;

  Function()? _onComplete;
  Function(String error)? _onError;

  // ---------------------------------------------------------------- 状态

  EdgeTtsState get state => _state;

  bool get isPlaying => _state == EdgeTtsState.playing;

  bool get isPaused => _state == EdgeTtsState.paused;

  bool get isSynthesizing => _state == EdgeTtsState.synthesizing;

  /// 空闲即「没有在合成、也没有在播放」，与 `FlutterTTSUtil.isStopped` 语义对齐。
  bool get isStopped => _state == EdgeTtsState.idle;

  bool get isInitialized => _initialized;

  String get voice => _voice;

  String? get voiceLocale => _voiceLocale;

  EdgeTtsOutputFormat get outputFormat => _outputFormat;

  double get volume => _volume;

  double get rate => _rate;

  double get pitch => _pitch;

  /// 当前生效的合成配置。
  EdgeTtsConfig get config => EdgeTtsConfig(
    voice: _voice,
    voiceLocale: _voiceLocale,
    outputFormat: _outputFormat,
    enableSentenceBoundary: _sentenceBoundary,
    enableWordBoundary: _wordBoundary,
  );

  /// 当前生效的韵律参数（音量/语速/音调）。
  EdgeTtsProsody get prosody => EdgeTtsProsody(
    rate: rateToEdgeRate(_rate),
    pitch: pitchToEdgePitch(_pitch),
    volume: volumeToEdgeVolume(_volume),
  );

  /// 底层客户端；未初始化时抛 [StateError]，需要自动初始化请用 [ensureClient]。
  FlutterEdgeTts get client {
    final client = _client;
    if (client == null) {
      throw StateError('EdgeTTSUtil 尚未初始化，请先调用 initSetting()。');
    }
    return client;
  }

  /// 播放器；未初始化时为 null。
  AudioPlayer? get player => _player;

  // ------------------------------------------------------------ 初始化

  /// 初始化客户端与播放器。
  ///
  /// 幂等：重复调用只会把新的参数应用到已存在的客户端上。
  /// 参数留空则沿用 [defaultVoice] 等默认值（或上次设置的值）。
  Future<void> initSetting({
    String? voice,
    String? voiceLocale,
    EdgeTtsOutputFormat? outputFormat,
    bool? enableSentenceBoundary,
    bool? enableWordBoundary,
    bool? enableLogging,
  }) async {
    if (voice != null) _voice = voice;
    if (voiceLocale != null) _voiceLocale = voiceLocale;
    if (outputFormat != null) _outputFormat = outputFormat;
    if (enableSentenceBoundary != null) {
      _sentenceBoundary = enableSentenceBoundary;
    }
    if (enableWordBoundary != null) _wordBoundary = enableWordBoundary;
    if (enableLogging != null) this.enableLogging = enableLogging;

    if (_initialized) {
      _applyConfig();
      return;
    }

    _client = FlutterEdgeTts(
      voice: _voice,
      voiceLocale: _voiceLocale,
      outputFormat: _outputFormat,
      enableSentenceBoundary: _sentenceBoundary,
      enableWordBoundary: _wordBoundary,
      enableLogging: this.enableLogging,
    );

    _player = AudioPlayer();
    _playerCompleteSub = _player!.onPlayerComplete.listen(
      (_) => _handlePlaybackCompleted(),
    );

    _initialized = true;

    await _applyAudioContext();
  }

  /// 保证已初始化并返回客户端。
  Future<FlutterEdgeTts> ensureClient() async {
    if (!_initialized || _client == null) await initSetting();
    return _client!;
  }

  /// 仅供测试：注入假的底层客户端，绕开真实网络。
  ///
  /// widget 测试里传一个配了假 `http.Client` 的 [FlutterEdgeTts] 就能喂固定的
  /// 音色目录。顺带清掉音色缓存——[EdgeTTSUtil] 是单例，不清会把上一条用例的
  /// 数据带到下一条。传 null 表示恢复「未初始化」。
  @visibleForTesting
  void debugSetClient(FlutterEdgeTts? client) {
    _client = client;
    _initialized = client != null;
    _voiceCache = null;
  }

  /// 运行期改配置（音色/格式/边界元数据等）。
  void configure({
    String? voice,
    String? voiceLocale,
    EdgeTtsOutputFormat? outputFormat,
    bool? enableSentenceBoundary,
    bool? enableWordBoundary,
    bool? enableLogging,
  }) {
    if (voice != null) _voice = voice;
    if (voiceLocale != null) _voiceLocale = voiceLocale;
    if (outputFormat != null) _outputFormat = outputFormat;
    if (enableSentenceBoundary != null) {
      _sentenceBoundary = enableSentenceBoundary;
    }
    if (enableWordBoundary != null) _wordBoundary = enableWordBoundary;
    if (enableLogging != null) this.enableLogging = enableLogging;
    _applyConfig();
  }

  void _applyConfig() {
    _client?.updateConfig(config);
  }

  // -------------------------------------------------------------- 参数

  /// 音色名，如 `zh-CN-XiaoxiaoNeural`。换音色会清掉显式指定的 locale，
  /// 让 SSML 从音色名重新推断（避免音色与语言对不上）。
  void setVoice(String voice) {
    _voice = voice;
    _voiceLocale = null;
    _applyConfig();
  }

  /// SSML 的 `xml:lang`（如 `zh-CN`）。传 null 表示由音色名推断。
  /// 注意：只影响发音语言，不会自动换音色。
  void setLanguage(String? language) {
    final value = language == null ? '' : canonicalLocale(language);
    _voiceLocale = value.isEmpty ? null : value;
    _applyConfig();
  }

  /// 语速倍率，`1.0` 为正常语速，超出 [[minRate], [maxRate]] 会被夹紧。
  void setSpeechRate(double rate) {
    _rate = clampRate(rate);
  }

  /// 把 flutter_tts 的语速（0.0~1.0，`0.5` 为正常）换算成 Edge 倍率后应用。
  ///
  /// 设置页里已有「本地 TTS 语速」时用它，可以沿用同一个数值。
  void setSpeechRateFromLocalRate(double localRate) {
    setSpeechRate(rateFromLocalRate(localRate));
  }

  /// 音调偏移，单位 Hz（`0` 为原始音高）。
  void setPitch(double pitch) {
    _pitch = clampPitch(pitch);
  }

  /// 音量，0.0~1.0；同时作用在合成音量与本地播放器上。
  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    _player?.setVolume(_volume);
  }

  /// 是否外放。Android 上真正的路由由系统 / `audio_session` 决定，
  /// 这里只负责记住状态并刷新音频上下文（见 [_applyAudioContext]）。
  bool get isSpeakerOn => _speakerOn;

  Future<void> setSpeakerOn(bool isOn) async {
    _speakerOn = isOn;
    await _applyAudioContext();
  }

  /// 一次性设置韵律，绕过上面的换算。
  void setProsody(EdgeTtsProsody prosody) {
    _rate = clampRate(double.tryParse(prosody.rate) ?? _rate);
    _pitch = clampPitch(_parseHz(prosody.pitch) ?? _pitch);
    _volume = (double.tryParse(prosody.volume) ?? (_volume * 100)) / 100;
    setVolume(_volume);
  }

  /// 播放完成 / 出错回调。多次调用会覆盖上一次。
  void setCallbacks({Function()? onComplete, Function(String error)? onError}) {
    _onComplete = onComplete;
    _onError = onError;
  }

  // -------------------------------------------------------------- 合成

  /// 当前输出格式对应的 MIME，拼 data URI 时用得上。
  ///
  /// 注意 `decodeAudioData` 是**按字节嗅探**的，MIME 写错不影响解码；
  /// 但 `audioplayers` / `<audio>` 在个别平台会参考它，所以还是给准。
  String get audioMimeType => switch (_outputFormat.fileExtension) {
    'mp3' => 'audio/mpeg',
    'wav' => 'audio/wav',
    'ogg' => 'audio/ogg',
    'webm' => 'audio/webm',
    _ => 'application/octet-stream',
  };

  /// 当前输出格式是否在实测可用的白名单里。
  bool get isOutputFormatSupported =>
      supportedOutputFormats.contains(_outputFormat);

  /// 格式不被支持时快速失败。
  ///
  /// 服务端遇到不认识的格式不会报错，只是**一个字节音频都不发**就 `turn.end`，
  /// 插件最终抛一个看不出原因的 `empty_audio`。与其白跑一次往返（还带重试），
  /// 不如在本地就说清楚。
  void _checkOutputFormat() {
    if (isOutputFormatSupported) return;
    throw EdgeTtsException(
      'unsupported_output_format',
      'Edge 接口不支持输出格式 ${_outputFormat.value}，它只会返回空音频。'
          '可用格式：${supportedOutputFormats.map((e) => e.value).join('、')}。',
    );
  }

  /// 合成文本并返回音频字节 + 边界元数据。失败抛 [EdgeTtsException]。
  Future<EdgeTtsSynthesisResult> synthesize(
    String text, {
    EdgeTtsProsody? prosody,
  }) async {
    final content = text.trim();
    if (content.isEmpty) {
      throw const EdgeTtsException('empty_text', '合成文本为空。');
    }
    _checkOutputFormat();
    return _synthesizeWithRetry(content, prosody);
  }

  /// 原始 SSML 合成（需要自己保证 XML 合法）。
  Future<EdgeTtsSynthesisResult> synthesizeSsml(String ssml) async {
    _checkOutputFormat();
    final client = await ensureClient();
    return client.synthesizeSsml(ssml, config: config);
  }

  /// 流式合成事件（音频分片 + 元数据），适合边合成边播。
  Stream<EdgeTtsStreamEvent> synthesizeStream(
    String text, {
    EdgeTtsProsody? prosody,
  }) {
    _checkOutputFormat();
    // 未初始化时 _client 为 null，这里退化成先同步抛错，避免返回一个
    // 「永远不产出事件」的空流让调用方干等。
    final client = _client;
    if (client == null) {
      throw StateError('EdgeTTSUtil 尚未初始化，请先调用 initSetting()。');
    }
    return client.synthesizeStream(
      text,
      prosody: prosody ?? this.prosody,
      config: config,
    );
  }

  Future<EdgeTtsSynthesisResult> _synthesizeWithRetry(
    String text,
    EdgeTtsProsody? prosody,
  ) async {
    final client = await ensureClient();
    final value = prosody ?? this.prosody;

    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await client.synthesize(text, prosody: value);
      } on Object catch (error) {
        lastError = error;
        // 配置类错误重试多少次都一样，直接抛出。
        if (error is EdgeTtsException && !_isRetryable(error)) rethrow;
        if (attempt < maxRetries) {
          await Future.delayed(retryDelay * (attempt + 1));
        }
      }
    }

    if (lastError is Exception) throw lastError;
    throw EdgeTtsException('synthesis_failed', '合成失败：$lastError');
  }

  static bool _isRetryable(EdgeTtsException error) {
    switch (error.code) {
      case 'invalid_voice_locale':
      case 'invalid_voice':
      case 'empty_text':
        return false;
      default:
        return true;
    }
  }

  // -------------------------------------------------------------- 播放

  /// 合成并播放。[interrupt] 为 true 时先打断上一次播放。
  ///
  /// 返回是否成功播放；失败会通过 [showErrorToast] / `onError` 反馈。
  Future<bool> speak(
    String text, {
    EdgeTtsProsody? prosody,
    bool interrupt = true,
  }) async {
    final content = text.trim();
    if (content.isEmpty) return false;

    if (interrupt) await stop();
    final token = ++_generation;

    try {
      _setState(EdgeTtsState.synthesizing);
      final result = await _synthesizeWithRetry(content, prosody);
      // 期间被 stop() 或新的 speak() 打断：丢弃这份迟到的音频。
      if (token != _generation) return false;
      await playBytes(result.audioBytes);
      return true;
    } on Object catch (error) {
      if (token == _generation) _setState(EdgeTtsState.idle);
      _reportError(error);
      return false;
    }
  }

  /// 直接播放一段音频字节（不做合成）。
  Future<void> playBytes(Uint8List bytes) async {
    if (bytes.isEmpty) return;
    final player = await _preparePlayer();

    if (!kIsWeb && Platform.isAndroid) {
      // Android 可以直接从内存播。
      await player.play(BytesSource(bytes));
    } else {
      // 其余平台落成临时文件再播，播完删除（与 TTSUtil 一致）。
      final file = await _newTempFile(
        'play',
        extension: audioExtensionOf(
          bytes,
          fallback: _outputFormat.fileExtension,
        ),
      );
      await file.writeAsBytes(bytes, flush: true);
      await player.play(DeviceFileSource(file.path));
      player.onPlayerComplete.first.then((_) {
        if (file.existsSync()) file.deleteSync();
      });
    }

    _setState(EdgeTtsState.playing);
  }

  /// 播放 base64 音频：网关 TTS 返回的音频、或 [getTtsAudioBase64] 的结果都走这里。
  Future<void> playBase64(String base64) async {
    if (base64.isEmpty) return;
    await playBytes(base64Decode(base64));
  }

  /// 播放本地音频文件。
  Future<void> playFile(String filePath) async {
    final player = await _preparePlayer();
    await player.play(DeviceFileSource(filePath));
    _setState(EdgeTtsState.playing);
  }

  /// 播放网络音频地址。
  Future<void> playUrl(String audioUrl) async {
    final player = await _preparePlayer();
    await player.play(UrlSource(audioUrl));
    _setState(EdgeTtsState.playing);
  }

  /// 停止播放，并作废正在进行中的合成（迟到的结果会被丢弃）。
  Future<void> stop() async {
    _generation++;
    await _player?.stop();
    _setState(EdgeTtsState.idle);
  }

  /// 暂停播放。注意：不会中断已经在跑的合成请求。
  Future<void> pause() async {
    await _player?.pause();
    if (_state == EdgeTtsState.playing) _setState(EdgeTtsState.paused);
  }

  /// 继续播放。
  Future<void> resume() async {
    await _player?.resume();
    if (_state == EdgeTtsState.paused) _setState(EdgeTtsState.playing);
  }

  Future<AudioPlayer> _ensurePlayer() async {
    if (_player == null) await initSetting();
    return _player!;
  }

  /// 播放前的统一准备：停掉上一段、设音量、应用音频上下文。
  Future<AudioPlayer> _preparePlayer() async {
    final player = await _ensurePlayer();
    await player.stop();
    await player.setVolume(_volume);
    await _applyAudioContext();
    return player;
  }

  /// Android 音频焦点策略。
  ///
  /// `audioFocus: none` 是**刻意保留**的：TTS 一旦抢焦点，正在录音的 ASR 会被
  /// 系统掐断（原本 `TTSUtil` 里就有这条注释，迁移时原样带过来）。
  Future<void> _applyAudioContext() async {
    final player = _player;
    if (player == null) return;
    try {
      await player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            usageType: AndroidUsageType.media,
            contentType: AndroidContentType.speech,
            audioFocus: AndroidAudioFocus.none,
          ),
        ),
      );
    } on Object catch (error) {
      // 个别平台/设备不支持设置上下文，不应该影响播放。
      debugPrint('Edge TTS 设置音频上下文失败: $error');
    }
  }

  void _handlePlaybackCompleted() {
    _setState(EdgeTtsState.idle);
    _onComplete?.call();
  }

  void _setState(EdgeTtsState state) {
    _state = state;
  }

  // -------------------------------------------------------------- 音色

  /// 拉取 Edge 音色列表（322+ 个，覆盖 142 个 locale），结果会缓存。
  ///
  /// 默认不抛异常：失败时上报并返回上一次的缓存（没有缓存则空列表），
  /// 这样列表页不会因为一次网络抖动就白屏。需要严格失败语义传
  /// `throwOnError: true`。
  Future<List<EdgeTtsVoice>> getVoices({
    bool refresh = false,
    bool throwOnError = false,
  }) async {
    if (!refresh && _voiceCache != null) return _voiceCache!;
    try {
      final client = await ensureClient();
      final voices = await client.getVoices();
      _voiceCache = voices;
      return voices;
    } on Object catch (error) {
      _reportError(error);
      if (throwOnError) rethrow;
      return _voiceCache ?? const <EdgeTtsVoice>[];
    }
  }

  /// 把音色列表转成 `TtsVoiceUtil` 认识的结构（`name` / `locale` / `gender` /
  /// `identifier`），可以直接喂给设置页的音色下拉框逻辑。
  Future<List<Map<String, String>>> getVoiceMaps({
    bool refresh = false,
    bool throwOnError = false,
  }) async {
    final voices = await getVoices(
      refresh: refresh,
      throwOnError: throwOnError,
    );
    return voicesToMaps(voices);
  }

  /// 音色覆盖的语言（locale）列表，语义对齐 `FlutterTTSUtil.getLanguages`。
  Future<List<String>> getLanguages({bool refresh = false}) async {
    final voices = await getVoices(refresh: refresh);
    return localesOf(voices);
  }

  /// 按 locale（可选性别）挑一个音色名，挑不到返回 null。
  Future<String?> pickVoiceForLocale(String locale, {String? gender}) async {
    final voices = await getVoices();
    return pickVoice(voices, locale, gender: gender);
  }

  // -------------------------------------------------------------- 文件

  /// 合成到文件，返回音频文件路径。
  ///
  /// [filePath] 留空时写到 [getDefaultTemporaryPath] 下；[withMetadata] 为 true
  /// 时额外输出同名 `.json` 元数据（需要先开启 sentence/word boundary）。
  Future<String> saveTtsFile(
    String text, {
    String? filePath,
    bool withMetadata = false,
    EdgeTtsProsody? prosody,
  }) async {
    _checkOutputFormat();
    final client = await ensureClient();
    final audioPath = filePath ?? (await _newTempFile('file')).path;
    final result = await client.synthesizeToFile(
      text,
      audioFilePath: audioPath,
      metadataFilePath: withMetadata ? '$audioPath.json' : null,
      prosody: prosody ?? this.prosody,
    );
    return result.audioFilePath;
  }

  /// 合成并直接转 base64（不落盘），语义对齐 `FlutterTTSUtil.getTtsAudioBase64`。
  Future<String> getTtsAudioBase64(
    String text, {
    EdgeTtsProsody? prosody,
  }) async {
    final result = await synthesize(text, prosody: prosody);
    final base64String = base64Encode(result.audioBytes);
    debugPrint('Edge TTS 音频已转换为 base64，长度: ${base64String.length}');
    return base64String;
  }

  /// 读取本地音频文件并转 base64。
  static Future<String> audioFileToBase64(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final base64String = base64Encode(bytes);
    debugPrint('Edge TTS 音频已转换为 base64，长度: ${base64String.length}');
    return base64String;
  }

  /// 下载网络音频并转 base64。
  static Future<String> networkAudioFileToBase64(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('下载音频失败: HTTP ${response.statusCode}');
      }
      final base64String = base64Encode(response.bodyBytes);
      debugPrint('网络音频已转换为 base64，长度: ${base64String.length}');
      return base64String;
    } catch (e) {
      debugPrint('网络音频转换 base64 失败: $e');
      rethrow;
    }
  }

  /// Edge 临时文件目录：`<tmp>/edge_tts`。
  Future<Directory> getDefaultTemporaryPath() async {
    final tempDir = await getTemporaryDirectory();
    final directory = Directory(p.join(tempDir.path, 'edge_tts'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// 清理 [getDefaultTemporaryPath] 下本工具产生的临时文件。
  Future<void> deleteTemporaryTtsFiles() async {
    try {
      final directory = await getDefaultTemporaryPath();
      final files = await directory.list().toList();

      var deletedCount = 0;
      for (final file in files) {
        if (file is! File) continue;
        if (!p.basename(file.path).startsWith(_tempFilePrefix)) continue;
        try {
          await file.delete();
          deletedCount++;
        } catch (e) {
          debugPrint('删除文件失败 ${file.path}: $e');
        }
      }

      debugPrint('共删除 $deletedCount 个 Edge TTS 临时文件');
    } catch (e) {
      debugPrint('删除 Edge TTS 临时文件时出错: $e');
    }
  }

  Future<File> _newTempFile(String tag, {String? extension}) async {
    final directory = await getDefaultTemporaryPath();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final name =
        '$_tempFilePrefix${tag}_$timestamp.${extension ?? _outputFormat.fileExtension}';
    return File(p.join(directory.path, name));
  }

  // -------------------------------------------------------------- 释放

  /// 释放播放器与客户端。之后可以再次 [initSetting] 重新使用。
  ///
  /// 注意：插件 `close()` 会关掉内部 http client，所以这里把引用置空，
  /// 下次调用会自动重建，避免复用已关闭的客户端。
  Future<void> dispose() async {
    _generation++;
    await _playerCompleteSub?.cancel();
    _playerCompleteSub = null;
    await _player?.dispose();
    _player = null;
    await _client?.close();
    _client = null;
    _initialized = false;
    _voiceCache = null;
    _state = EdgeTtsState.idle;
  }

  void _reportError(Object error) {
    final message = error is EdgeTtsException ? error.message : '$error';
    debugPrint('Edge TTS 出错: $message');
    if (showErrorToast) {
      // EasyLoading 未初始化（如单测）时不要因为弹 toast 再抛一次。
      try {
        EasyLoading.showToast(message);
      } on Object catch (toastError) {
        debugPrint('Edge TTS toast 展示失败: $toastError');
      }
    }
    _onError?.call(message);
  }

  // ---------------------------------------------------------- 纯函数工具

  /// 按文件头猜扩展名，猜不出用 [fallback]。
  ///
  /// [playBytes] 也会被用来播网关回推的音频，那个格式不一定等于当前合成格式
  /// （合成用 WAV、网关给 mp3 是可能的）。非 Android 平台要落临时文件再播，
  /// 而 AVPlayer / MediaFoundation 会按扩展名判容器，写错就播不出来。
  static String audioExtensionOf(Uint8List bytes, {String fallback = 'wav'}) {
    if (bytes.length >= 4) {
      // 'RIFF'
      if (_startsWith(bytes, 0x52, 0x49, 0x46, 0x46)) return 'wav';
      // 'OggS'
      if (_startsWith(bytes, 0x4F, 0x67, 0x67, 0x53)) return 'ogg';
      // EBML（webm/mkv）
      if (_startsWith(bytes, 0x1A, 0x45, 0xDF, 0xA3)) return 'webm';
    }
    // 'ID3'
    if (bytes.length >= 3 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      return 'mp3';
    }
    // MPEG 帧同步：11 个 1
    if (bytes.length >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
      return 'mp3';
    }
    return fallback;
  }

  static bool _startsWith(Uint8List bytes, int a, int b, int c, int d) =>
      bytes[0] == a && bytes[1] == b && bytes[2] == c && bytes[3] == d;

  /// 规范化 locale 写法：`zh_CN` → `zh-CN`。
  ///
  /// 与 `TtsVoiceUtil.normalizeLocale`（比较用的全小写）不同，这里保留大小写，
  /// 因为结果会直接写进 SSML 的 `xml:lang`。
  static String canonicalLocale(String locale) =>
      locale.trim().replaceAll('_', '-');

  /// 语速夹紧到服务端允许区间。
  static double clampRate(double rate) =>
      rate.clamp(minRate, maxRate).toDouble();

  /// 音调夹紧到服务端允许区间。
  static double clampPitch(double pitch) =>
      pitch.clamp(minPitch, maxPitch).toDouble();

  /// 倍率 → SSML 的 `rate` 字符串（`1.0` → `'1.00'`）。
  static String rateToEdgeRate(double rate) =>
      clampRate(rate).toStringAsFixed(2);

  /// flutter_tts 语速（0.5 为正常）→ Edge 倍率。非正数按正常语速处理。
  static double rateFromLocalRate(double localRate) {
    if (localRate <= 0) return 1.0;
    return clampRate(localRate / 0.5);
  }

  /// 0.0~1.0 → SSML 的 `volume` 字符串（`0`~`100`）。
  static String volumeToEdgeVolume(double volume) =>
      (volume.clamp(0.0, 1.0) * 100).round().toString();

  /// Hz 偏移 → SSML 的 `pitch` 字符串（`+10Hz` / `-10Hz` / `+0Hz`）。
  static String pitchToEdgePitch(double hz) {
    final rounded = clampPitch(hz).round();
    if (rounded == 0) return '+0Hz';
    return '${rounded > 0 ? '+' : '-'}${rounded.abs()}Hz';
  }

  /// `EdgeTtsVoice` → `TtsVoiceUtil` 用的 Map。
  ///
  /// `identifier` 用 `shortName`（音色唯一名），这样 `TtsVoiceUtil.keyOf`
  /// 在 Edge 音色上也能拿到稳定 key。
  static Map<String, String> voiceToMap(EdgeTtsVoice voice) => {
    'name': voice.shortName,
    'locale': voice.locale,
    'gender': voice.gender,
    'identifier': voice.shortName,
    'friendly_name': voice.friendlyName,
    'status': voice.status,
  };

  static List<Map<String, String>> voicesToMaps(List<EdgeTtsVoice> voices) =>
      voices.map(voiceToMap).toList();

  /// 音色覆盖的 locale 列表（去重、排序）。
  ///
  /// 保留服务端给的规范写法（`zh-CN`），只按归一化后的值去重，这样列表里显示的
  /// 仍是标准 BCP-47 形式，而不是被压成小写的 `zh-cn`。
  static List<String> localesOf(List<EdgeTtsVoice> voices) {
    final seen = <String>{};
    final locales = <String>[];
    for (final voice in voices) {
      final locale = voice.locale.trim();
      if (locale.isEmpty) continue;
      if (seen.add(TtsVoiceUtil.normalizeLocale(locale))) locales.add(locale);
    }
    locales.sort();
    return locales;
  }

  /// 按 locale 挑音色：先精确匹配 locale，再退到同主语言；可选按性别过滤。
  static String? pickVoice(
    List<EdgeTtsVoice> voices,
    String locale, {
    String? gender,
  }) {
    final target = TtsVoiceUtil.normalizeLocale(locale);
    if (target.isEmpty) return null;

    EdgeTtsVoice? exact;
    EdgeTtsVoice? sameLanguage;
    for (final voice in voices) {
      if (!_genderMatches(voice, gender)) continue;
      if (TtsVoiceUtil.normalizeLocale(voice.locale) == target) {
        exact ??= voice;
        continue;
      }
      if (sameLanguage == null &&
          TtsVoiceUtil.localeMatches(voice.locale, target)) {
        sameLanguage = voice;
      }
    }
    return (exact ?? sameLanguage)?.shortName;
  }

  static bool _genderMatches(EdgeTtsVoice voice, String? gender) {
    if (gender == null || gender.isEmpty) return true;
    return voice.gender.toLowerCase() == gender.toLowerCase();
  }

  /// 解析 `'+10Hz'` / `'-10Hz'` / `'10'` 这类音调字符串，失败返回 null。
  static double? _parseHz(String value) {
    final match = RegExp(r'^([+-]?\d+(?:\.\d+)?)').firstMatch(value.trim());
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }
}
