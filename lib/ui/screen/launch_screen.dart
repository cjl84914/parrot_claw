import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parrot_app/main.dart';

/// OpenClaw 移动端欢迎/启动界面。
class LaunchScreen extends StatelessWidget {
  const LaunchScreen({super.key});

  static const _background = Color(0xFF000000);
  static const _surface = Color(0xFF1B1B1F);
  static const _surfaceBorder = Color(0xFF29292E);
  static const _mutedText = Color(0xFF9B9BA1);
  static const _orange = Color(0xFFFF8A3D);
  static const _warning = Color(0xFFFFC247);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 38),
                child: Column(
                  children: [
                    // _buildTopAvatar(),
                    const SizedBox(height: 38),
                    _buildHero(),
                    const SizedBox(height: 28),
                    _buildFeatureCard(),
                    const SizedBox(height: 16),
                    _buildSecurityCard(),
                    const SizedBox(height: 28),
                    _buildContinueButton(context),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopAvatar() {
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(color: _orange, shape: BoxShape.circle),
      child: const Icon(Icons.electric_scooter, color: Colors.white, size: 24),
    );
  }

  Widget _buildHero() {
    return Column(
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: const BoxDecoration(
            color: Color(0xFF25252A),
            shape: BoxShape.circle,
            image: DecorationImage(image: AssetImage('assets/images/icon.jpg'))
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          '欢迎使用 ParrotClaw',
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
          '将此设备变成安全的 OpenClaw 节点，\n用于聊天、语音、摄像头和设备工具。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _mutedText,
            fontSize: 15,
            height: 1.55,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureCard() {
    return _CardContainer(
      child: Column(
        children: const [
          _FeatureRow(icon: Icons.link_rounded, label: '连接到你的网关'),
          // _FeatureDivider(),
          // _FeatureRow(icon: Icons.shield_outlined, label: '选择设备权限'),
          // _FeatureDivider(),
          _FeatureRow(icon: Icons.check_circle_outline_rounded, label: '在手机上使用 OpenClaw'),
        ],
      ),
    );
  }

  Widget _buildSecurityCard() {
    return _CardContainer(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(top: 1),
            decoration: const BoxDecoration(color: _warning, shape: BoxShape.circle),
            child: const Icon(Icons.priority_high_rounded, color: Colors.black, size: 20),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '安全提示',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '已连接的 OpenClaw 代理可以使用你启用的设备功能。请仅在你信任所连接的网关和代理时继续。',
                  style: TextStyle(color: _mutedText, fontSize: 13, height: 1.55),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: () => context.go(Routes.connGateway),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(48)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: const Text('继续'),
      ),
    );
  }
}

class _CardContainer extends StatelessWidget {
  const _CardContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: LaunchScreen._surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LaunchScreen._surfaceBorder),
      ),
      child: child,
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
          // const Icon(Icons.chevron_right_rounded, color: LaunchScreen._mutedText, size: 20),
        ],
      ),
    );
  }
}

class _FeatureDivider extends StatelessWidget {
  const _FeatureDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, thickness: 1, color: LaunchScreen._surfaceBorder);
  }
}
