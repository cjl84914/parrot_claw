import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parrot_app/main.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('使用指南'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          _buildItem(context, '关于我们', 'assets/docs/docs/about.html'),
          _buildItem(context, '快速开始', 'assets/docs/docs/getting-started.html'),
          _buildItem(
            context,
            'Openclaw安装指南',
            'assets/docs/docs/openclaw-setup.html',
          ),
          _buildItem(
            context,
            'ComfyU指南',
            'assets/docs/docs/comfyui-usage.html',
          ),
          _buildItem(context, '开发指南', 'assets/docs/docs/contributing.html'),
          _buildItem(context, '常见问题', 'assets/docs/docs/faq.html'),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, String title, String assetPath) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontSize: 14)),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () {
          context.push(
            Uri(
              path: Routes.webview,
              queryParameters: {'title': title, 'assetPath': assetPath},
            ).toString(),
          );
        },
      ),
    );
  }
}
