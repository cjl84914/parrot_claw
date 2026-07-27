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
      if(_isPlaying){
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
        initialUrlRequest: !kIsWeb
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
  Future<void> Function()? _stopCallback;
  Future<void> Function()? _testCallback;
  VoidCallback? _clearQueueCallback;

  /// 内部方法：用于 State 绑定
  void _attach({
    Future<void> Function(String audioPath)? onSpeak,
    Future<void> Function()? onStopSpeak,
    Future<void> Function()? onTest,
    VoidCallback? onClearQueue,
  }) {
    _speakCallback = onSpeak;
    _stopCallback = onStopSpeak;
    _testCallback = onTest;
    _clearQueueCallback = onClearQueue;
  }

  /// 内部方法：用于 State 解绑
  void _detach() {
    _speakCallback = null;
    _testCallback = null;
    _clearQueueCallback = null;
  }

  /// 调用 Live2D 说话
  Future<void> speak(String audioPath) async {
    await _speakCallback?.call(audioPath);
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
