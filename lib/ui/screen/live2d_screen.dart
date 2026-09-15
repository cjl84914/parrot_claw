import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:window_manager/window_manager.dart';

class Live2dScreen extends StatefulWidget {
  final VoidCallback? onAudioPlayEnd;
  final Live2dController? controller;

  const Live2dScreen({this.onAudioPlayEnd, super.key, this.controller});

  @override
  State<Live2dScreen> createState() => _Live2dScreenState();
}

class _Live2dScreenState extends State<Live2dScreen> with WindowListener {
  InAppWebViewController? _webViewController;
  final InAppLocalhostServer localhostServer = InAppLocalhostServer(
    documentRoot: "assets/live2d",
    port: 10327,
  );

  // --- 原 Live2dProvider 的状态变量 ---
  bool _isInitialized = false;
  bool _isVisible = true; // 默认为可见，原 Provider 中默认为 false
  String _statusMessage = '未初始化';
  String _currentSubtitle = 'parrot';
  bool _isPlaying = false;

  @override
  void initState() {
    localhostServer.start();
    super.initState();
    _attachController(); // 绑定
  }

  @override
  void didUpdateWidget(Live2dScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?._detach();
      _attachController();
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(); // 解绑
    _webViewController?.dispose();
    localhostServer.close();
    super.dispose();
  }

  void _attachController() {
    widget.controller?._attach(
      onSpeak: speak,
      onSpeakEncoded: speakEncodedAudio,
      onStopSpeak: stopAudio,
      onTest: test,
      onClearQueue: clearQueue,
    );
  }

  void onAudioPlayEnd() {
    setState(() {
      _isPlaying = false;
      _statusMessage = '已就绪';
    });
    widget.onAudioPlayEnd?.call();
  }

  void inputAiText(String text) {
    if (_isVisible) {
      // 原逻辑为空
    }
  }

  void inputAllText(String text) {
    if (_isVisible) {
      // 原逻辑为空
    }
  }

  void clearQueue() {
    _webViewController?.dispose(); // 显式停止底层音频播放
    setState(() {
      _currentSubtitle = '';
      _isPlaying = false;
    });
  }

  void setInitialized(bool value) {
    setState(() {
      _isInitialized = value;
      _statusMessage = value ? '已就绪' : '初始化失败';
    });
  }

  void setStatus(String status) {
    setState(() {
      _statusMessage = status;
    });
  }

  void setPlaying(bool playing) {
    setState(() {
      _isPlaying = playing;
    });
  }

  void setSubtitle(String subtitle) {
    setState(() {
      _currentSubtitle = subtitle;
    });
  }

  void toggleVisibility() {
    setState(() {
      _isVisible = !_isVisible;
    });
  }

  Future<void> test() async {
    try {
      await _webViewController!.evaluateJavascript(
        source: "playAudio('./Resources/sayhi.wav');",
      );
    } catch (e) {
      debugPrint('测试调用函数时出错: $e');
    }
  }

  Future<void> speak(String audioPath) async {
    if (_webViewController != null && _isInitialized) {
      if (_isPlaying) {
        await stopAudio();
        await Future.delayed(const Duration(seconds: 1));
      }
      try {
        setPlaying(true);
        await _webViewController!.evaluateJavascript(
          source: "playAudio('$audioPath');",
        );
      } catch (e) {
        debugPrint('播放句子时出错: $e');
      }
    }
  }

  /// 播放「非 WAV」音频并同步口型（Edge TTS 给的是 mp3）。
  ///
  /// Live2D SDK 的 `_wavFileHandler` 只认 RIFF/WAVE——它 `fetch` 到音频后先找
  /// `RIFF`/`WAVE` 签名，找不到直接抛错，采样率也是从 WAV 头里读的。所以 mp3
  /// 不能直接喂给 [speak]。
  ///
  /// 这里在 WebView 里用 Web Audio 解码成 PCM，现场拼一个 44 字节 WAV 头，再用
  /// blob URL 走原来的 `playAudio`。采样率取解码结果的 `sampleRate`，和 WAV 头
  /// 保持一致，口型才不会漂。
  ///
  /// [source] 可以是 data URI（`data:audio/mpeg;base64,...`）或 http(s) 地址。
  Future<void> speakEncodedAudio(String source) async {
    if (_webViewController != null && _isInitialized) {
      if (_isPlaying) {
        await stopAudio();
        await Future.delayed(const Duration(seconds: 1));
      }
      try {
        setPlaying(true);
        await _webViewController!.evaluateJavascript(
          source: _decodeToWavJs(source),
        );
      } catch (e) {
        debugPrint('播放转码音频时出错: $e');
      }
    }
  }

  /// 生成「解码 → 拼 WAV → playAudio」的 JS。
  static String _decodeToWavJs(String source) {
    // 只可能来自 base64 data URI / http 地址，做个最小转义防止把字符串字面量撑破。
    final escaped = source.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    return '''
(async () => {
  try {
    const src = '$escaped';
    let buf;
    if (src.startsWith('data:')) {
      // 直接 atob，不走 fetch：把整段 base64 当 URL 喂给 fetch 会撞
      // WebView 的 URL 长度限制（一句话的 mp3 base64 就有几十万字符）。
      const bin = atob(src.slice(src.indexOf(',') + 1));
      const u8 = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
      buf = u8.buffer;
    } else {
      buf = await (await fetch(src)).arrayBuffer();
    }
    const Ctx = window.AudioContext || window.webkitAudioContext;
    const ctx = new Ctx();
    const decoded = await ctx.decodeAudioData(buf);
    const rate = decoded.sampleRate;
    const ch = decoded.getChannelData(0);
    const n = ch.length;
    const bytes = new ArrayBuffer(44 + n * 2);
    const v = new DataView(bytes);
    const str = (off, s) => { for (let i = 0; i < s.length; i++) v.setUint8(off + i, s.charCodeAt(i)); };
    str(0, 'RIFF'); v.setUint32(4, 36 + n * 2, true); str(8, 'WAVE');
    str(12, 'fmt '); v.setUint32(16, 16, true); v.setUint16(20, 1, true);
    v.setUint16(22, 1, true); v.setUint32(24, rate, true);
    v.setUint32(28, rate * 2, true); v.setUint16(32, 2, true); v.setUint16(34, 16, true);
    str(36, 'data'); v.setUint32(40, n * 2, true);
    for (let i = 0, off = 44; i < n; i++, off += 2) {
      const s = Math.max(-1, Math.min(1, ch[i]));
      v.setInt16(off, s < 0 ? s * 0x8000 : s * 0x7fff, true);
    }
    await ctx.close();
    const url = URL.createObjectURL(new Blob([bytes], { type: 'audio/wav' }));
    if (window.__live2dWavUrl) { try { URL.revokeObjectURL(window.__live2dWavUrl); } catch (e) {} }
    window.__live2dWavUrl = url;
    console.log('音频已转为 WAV，采样率 ' + rate + '，样本数 ' + n);
    window.playAudio(url);
  } catch (e) {
    console.error('音频转 WAV 失败: ' + e);
    console.log('音频播放出错');
  }
})();
''';
  }

  Future<void> stopAudio() async {
    if (_webViewController != null && _isInitialized) {
      try {
        setPlaying(true);
        await _webViewController!.evaluateJavascript(source: "stopAudio();");
      } catch (e) {
        debugPrint('停止播放出错: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialSettings: InAppWebViewSettings(
        isInspectable: kDebugMode,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
      ),
      initialUrlRequest:
          !kIsWeb
              ? URLRequest(url: WebUri("http://localhost:10327/index.html"))
              : null,
      initialFile: kIsWeb ? "assets/assets/live2d/index.html" : null,
      onWebViewCreated: (controller) async {
        _webViewController = controller;
      },
      onLoadStart: (controller, url) {},
      onLoadStop: (controller, url) async {
        // 页面和 JS 加载完毕
        setInitialized(true);
        debugPrint("Live2D WebView 已加载完成。");
      },
      onConsoleMessage: (controller, consoleMessage) {
        debugPrint("Live2D WebView Console: ${consoleMessage.message})");
        if (consoleMessage.message == "音频播放完成" ||
            consoleMessage.message == "音频播放已停止") {
          onAudioPlayEnd();
          setPlaying(false);
        } else if (consoleMessage.message == "音频播放出错") {
          onAudioPlayEnd();
          setPlaying(false);
        }
      },
    );
  }
}

class Live2dController {
  Future<void> Function(String audioPath)? _speakCallback;
  Future<void> Function(String source)? _speakEncodedCallback;
  Future<void> Function()? _stopCallback;
  Future<void> Function()? _testCallback;
  VoidCallback? _clearQueueCallback;

  /// 内部方法：用于 State 绑定
  void _attach({
    Future<void> Function(String audioPath)? onSpeak,
    Future<void> Function(String source)? onSpeakEncoded,
    Future<void> Function()? onStopSpeak,
    Future<void> Function()? onTest,
    VoidCallback? onClearQueue,
  }) {
    _speakCallback = onSpeak;
    _speakEncodedCallback = onSpeakEncoded;
    _stopCallback = onStopSpeak;
    _testCallback = onTest;
    _clearQueueCallback = onClearQueue;
  }

  /// 内部方法：用于 State 解绑
  void _detach() {
    _speakCallback = null;
    _speakEncodedCallback = null;
    _testCallback = null;
    _clearQueueCallback = null;
  }

  /// 调用 Live2D 说话（音频必须是 WAV，或引擎能直接播的容器）
  Future<void> speak(String audioPath) async {
    await _speakCallback?.call(audioPath);
  }

  /// 播放 mp3 等「非 WAV」音频并同步口型（Edge TTS 走这条）。
  ///
  /// [source] 可以是 data URI（`data:audio/mpeg;base64,...`）或 http(s) 地址。
  Future<void> speakEncodedAudio(String source) async {
    await _speakEncodedCallback?.call(source);
  }

  Future<void> stopSpeak() async {
    await _stopCallback?.call();
  }

  /// 测试音频播放
  Future<void> test() async {
    await _testCallback?.call();
  }

  /// 清除播放队列
  void clearQueue() {
    _clearQueueCallback?.call();
  }
}
