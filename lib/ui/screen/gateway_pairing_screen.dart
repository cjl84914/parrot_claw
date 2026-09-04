import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/service/gateway_connection.dart';
import 'package:parrot_app/main.dart';

class GatewayPairingScreen extends StatelessWidget {
  const GatewayPairingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final id = GatewayConnection.shared.pairingDeviceId;
    final command = id == null ? null : 'openclaw devices approve $id';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        // title: const Text('配对网关'),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _RadarIcon(),
                      const SizedBox(height: 24),
                      const Text('正在配对网关', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 14),
                      const Text('请在网关上批准此手机。\n然后重试连接。', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 16, height: 1.6)),
                      const SizedBox(height: 28),
                      _CommandCard(command: command),
                      const SizedBox(height: 28),
                      _StepRow(active: false, text: '网关需要设备授权'),
                      const SizedBox(height: 18),
                      _StepRow(active: false, text: '在网关上运行授权命令'),
                      const SizedBox(height: 18),
                      // TextButton(
                      //   onPressed: () => showDialog<void>(
                      //     context: context,
                      //     builder: (context) => AlertDialog(
                      //       title: const Text('配对说明'),
                      //       content: const Text('请在运行 OpenClaw Gateway 的终端中执行授权命令，然后返回本页面重试连接。'),
                      //       actions: [TextButton(onPressed: () => context.pop(), child: const Text('知道了'))],
                      //     ),
                      //   ),
                      //   child: const Text('查看详情', style: TextStyle(color: Colors.white, fontSize: 15)),
                      // ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: () => context.pop(true),
                  icon: const Icon(Icons.radar),
                  label: const Text('重试连接', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadarIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 72, height: 72,
    decoration: const BoxDecoration(color: Color(0xFF332B0A), shape: BoxShape.circle),
    child: const Icon(Icons.radar, color: AppColors.secondary, size: 42),
  );
}

class _CommandCard extends StatelessWidget {
  final String? command;
  const _CommandCard({this.command});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
    decoration: BoxDecoration(color: const Color(0xFF202020), borderRadius: BorderRadius.circular(14)),
    child: Row(children: [
      Expanded(child: SelectableText(command ?? '未获取到设备 ID，请返回后重试', style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5, fontFamily: 'monospace'))),
      IconButton(
        tooltip: '复制命令',
        onPressed: command == null ? null : () async {
          await Clipboard.setData(ClipboardData(text: command!));
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('授权命令已复制')));
        },
        icon: const Icon(Icons.copy, color: Colors.white),
      ),
    ]),
  );
}

class _StepRow extends StatelessWidget {
  final bool active;
  final String text;
  const _StepRow({required this.active, required this.text});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 12, height: 12, decoration: BoxDecoration(color: active ? AppColors.secondary : const Color(0xFF666666), shape: BoxShape.circle)),
    const SizedBox(width: 12),
    Expanded(child: Text(text, style: TextStyle(color: active ? Colors.white : const Color(0xFF999999), fontSize: 15))),
  ]);
}
