import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebViewScreen extends StatefulWidget {
  final String title;
  final String assetPath;

  const WebViewScreen({
    super.key,
    required this.title,
    required this.assetPath,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {


  @override
  Widget build(BuildContext context) {

    // 获取路径部分，例如 assets/docs/docs/about.html -> docs/about.html
    final relativePath = widget.assetPath.replaceFirst('assets/docs/', '');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri('https://parrot.geetion.com/$relativePath'),
        ),
        initialSettings: InAppWebViewSettings(
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
          isInspectable: kDebugMode,
        ),
      ),
    );
  }
}
