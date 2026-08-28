import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parrot_app/main.dart';

/// OpenClaw 网关连接入口界面。
class ConnGatewayScreen extends StatefulWidget {
  const ConnGatewayScreen({super.key});

  static const _background = Color(0xFF000000);
  static const _surface = Color(0xFF1B1B1F);
  static const _border = Color(0xFF2B2B31);
  static const _muted = Color(0xFF9B9BA1);
  static const _orange = Color(0xFFFF8A3D);

  @override
  State<ConnGatewayScreen> createState() => _ConnGatewayScreenState();
}

class _ConnGatewayScreenState extends State<ConnGatewayScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ConnGatewayScreen._background,
      // appBar: AppBar(
      //   backgroundColor: ConnGatewayScreen._background,
      //   foregroundColor: Colors.white,
      //   elevation: 0,
      //   scrolledUnderElevation: 0,
      //   centerTitle: true,
      //   leading: IconButton(
      //     tooltip: '返回',
      //     icon: const Icon(Icons.arrow_back_rounded),
      //     onPressed: () => context.pop(),
      //   ),
      // ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 34),
                      _buildHero(),
                      const SizedBox(height: 34),
                      _buildBeforeStart(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrandAvatar() {
    return Container(
      width: 38,
      height: 38,
      decoration: const BoxDecoration(color: ConnGatewayScreen._orange, shape: BoxShape.circle),
      child: const Icon(Icons.electric_scooter, color: Colors.white, size: 22),
    );
  }

  Widget _buildHero() {
    return Column(
      children: [
        Container(
          width: 82,
          height: 82,
          decoration: const BoxDecoration(
            color: Color(0xFF222226),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.qr_code_2_rounded,
            color: Colors.white,
            size: 48,
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          '连接网关',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          '扫描二维码，或使用 ParrotClaw 网关提供的\n设置代码。',
          textAlign: TextAlign.center,
          style: TextStyle(color: ConnGatewayScreen._muted, fontSize: 15, height: 1.55),
        ),
      ],
    );
  }

  Widget _buildBeforeStart() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '开始之前',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 18),
        _RequirementItem(
          title: '可以访问网关设备',
          description: '在运行 OpenClaw 的设备上打开一个终端。',
        ),
        const SizedBox(height: 22),
        _RequirementItem(
          title: '手机可以连接到网关',
          description: '使用同一个网络，或使用安全的远程网关 URL。',
        ),
        const SizedBox(height: 48),
        Center(
          child: TextButton.icon(
            onPressed: () {
              context.push(Routes.more);
            },
            icon: const Icon(Icons.link_rounded, size: 18),
            label: const Text('设置指南'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: () => context.push(Routes.qrScan),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('扫描二维码'), //或设置代码
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(48),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () => context.push(Routes.serverEdit),
            icon: const Icon(Icons.link_rounded),
            label: const Text('手动设置'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: ConnGatewayScreen._border),
              backgroundColor: ConnGatewayScreen._background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(48),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RequirementItem extends StatelessWidget {
  const _RequirementItem({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 7),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: const TextStyle(
                  color: ConnGatewayScreen._muted,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
