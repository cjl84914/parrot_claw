import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatefulWidget {
  static String name = "/about";

  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutScreen> {
  String version = "";

  @override
  void initState() {
    initData();
    super.initState();
  }

  initData() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    version = packageInfo.version;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    String locale = Localizations.localeOf(context).languageCode;
    return Scaffold(
      backgroundColor: Colors.white,
      // appBar: AppBar(title: const Text("关于我们")),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(12.0),
              child: Image.asset(
                "assets/images/icon.png",
                height: 100,
                width: 100,
              ),
            ),
            const SizedBox(height: 24),
            Text("当前版本：$version", style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text("反馈建议:", style: TextStyle(color: Colors.black54)),
                TextButton(
                  child: const Text(
                    "alex@geetion.com",
                    style: TextStyle(
                      decoration: TextDecoration.underline,
                      color: Colors.black,
                    ),
                  ),
                  onPressed: () {
                    launch("mailto:alex@geetion.com");
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text("QQ群：", style: TextStyle(color: Colors.black54)),
                  Text("暂未开放"),
                ],
            ),
          ],
        ),
      ),
    );
  }
}
