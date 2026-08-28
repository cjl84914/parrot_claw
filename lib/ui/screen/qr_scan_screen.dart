import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/view_model/server_viewmodel.dart';

/// 扫码导入服务器配置页
class QrScanScreen extends StatefulWidget {
  final ServerViewModel viewModel;

  const QrScanScreen({super.key, required this.viewModel});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handling) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      _handlePayload(raw);
      return;
    }
  }

  Future<void> _handlePayload(String payload) async {
    _handling = true;
    try {
      final config = ServerConfig.fromQrPayload(payload);
      if (config == null) {
        _showInvalidQr();
        return;
      }
      await _controller.stop();
      if (!mounted) return;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('添加服务器'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('名称', config.name),
              const SizedBox(height: 8),
              _infoRow('地址', config.displayAddress),
              const SizedBox(height: 8),
              _infoRow('认证', config.isPasswordAuth ? '密码认证' : 'Token 认证'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('添加'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await widget.viewModel.addServer(config);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已添加服务器 ${config.name}')),
        );
        context.go(Routes.index);
      } else {
        // 用户取消，继续扫描
        await _controller.start();
        _handling = false;
      }
    } catch (_) {
      _handling = false;
    }
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(label, style: AppTextStyles.caption),
        ),
        Expanded(
          child: Text(value, style: AppTextStyles.bodyMedium),
        ),
      ],
    );
  }

  void _showInvalidQr() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('无效的二维码，未识别到服务器配置')),
    );
    _handling = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫二维码连接网关'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // 扫描区域
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                ),
                // 扫描框
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(AppRadius.large),
                  ),
                ),
              ],
            ),
          ),
          // 底部说明
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                Icon(
                  Icons.qr_code_scanner,
                  size: 28,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 8),
                Text(
                  '将其他设备的服务器配置二维码对准扫描框',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
