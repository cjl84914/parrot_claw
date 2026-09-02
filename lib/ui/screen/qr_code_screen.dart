import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/service/gateway_connection.dart';
import 'package:parrot_app/ui/screen/index_screen.dart';

/// 网关设备配对二维码展示页。
class QrCodeScreen extends StatefulWidget {
  final ServerConfig config;

  const QrCodeScreen({super.key, required this.config});

  @override
  State<QrCodeScreen> createState() => _QrCodeScreenState();
}

class _QrCodeScreenState extends State<QrCodeScreen> {
  late Future<DevicePairSetupCodeResponse> _pairSetupFuture;

  @override
  void initState() {
    super.initState();
    _pairSetupFuture = GatewayConnection.shared.devicePairSetupCode();
  }

  void _refreshPairSetup() {
    setState(() {
      _pairSetupFuture = GatewayConnection.shared.devicePairSetupCode();
    });
  }

  Uint8List _decodeQrPng(String dataUrl) {
    const prefix = 'data:image/png;base64,';
    if (!dataUrl.startsWith(prefix)) {
      throw const FormatException('无效的配对二维码格式');
    }
    return base64Decode(dataUrl.substring(prefix.length));
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: '打开侧边栏',
          onPressed: () => indexScaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('分享网关配置'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            // 二维码
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.xlarge),
              ),
              child: FutureBuilder<DevicePairSetupCodeResponse>(
                future: _pairSetupFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      width: 240,
                      height: 240,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return SizedBox(
                      width: 240,
                      height: 240,
                      child: Center(
                        child: Text(
                          '二维码生成失败',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black),
                        ),
                      ),
                    );
                  }
                  final qrDataUrl = snapshot.data?.qrDataUrl;
                  if (qrDataUrl == null || qrDataUrl.isEmpty) {
                    return const SizedBox(
                      width: 240,
                      height: 240,
                      child: Center(child: Text('网关未返回二维码')),
                    );
                  }
                  return Image.memory(
                    _decodeQrPng(qrDataUrl),
                    width: 240,
                    height: 240,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<DevicePairSetupCodeResponse>(
              future: _pairSetupFuture,
              builder: (context, snapshot) {
                final isRefreshing =
                    snapshot.connectionState == ConnectionState.waiting;
                return OutlinedButton.icon(
                  onPressed: isRefreshing ? null : _refreshPairSetup,
                  icon:
                      isRefreshing
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.refresh),
                  label: Text(isRefreshing ? '刷新中...' : '刷新二维码'),
                );
              },
            ),
            const SizedBox(height: 24),

            // 服务器信息
            Text(config.name, style: AppTextStyles.titleLarge),
            const SizedBox(height: 6),
            Text(config.displayAddress, style: AppTextStyles.caption),
            const SizedBox(height: 6),
            Text(
              config.isPasswordAuth ? '密码认证' : 'Token 认证',
              style: AppTextStyles.captionSmall,
            ),

            // localhost 替换提示
            // if (hostReplaced) ...[
            //   const SizedBox(height: 16),
            //   Container(
            //     padding: const EdgeInsets.all(12),
            //     decoration: BoxDecoration(
            //       color: AppColors.warning.withValues(alpha: 0.1),
            //       borderRadius: BorderRadius.circular(AppRadius.large),
            //     ),
            //     child: Row(
            //       children: [
            //         Icon(
            //           Icons.info_outline,
            //           size: 18,
            //           color: AppColors.warning,
            //         ),
            //         const SizedBox(width: 8),
            //         Expanded(
            //           child: Text(
            //             '原配置为 localhost，已自动替换为本机局域网 IP，'
            //             '扫码设备与当前设备需在同一网络。',
            //             style: AppTextStyles.caption.copyWith(
            //               color: AppColors.warning,
            //             ),
            //           ),
            //         ),
            //       ],
            //     ),
            //   ),
            // ],
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.large),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ParrotClaw应用在扫描后会自动连接。',
                      style: AppTextStyles.caption.copyWith(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
