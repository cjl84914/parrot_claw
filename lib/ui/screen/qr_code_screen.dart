import 'package:flutter/material.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 服务器配置二维码展示页
class QrCodeScreen extends StatelessWidget {
  final ServerConfig config;

  const QrCodeScreen({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final hostReplaced = ServerConfig.isLoopbackHost(config.host);
    return Scaffold(
      appBar: AppBar(title: const Text('分享服务器配置'), elevation: 0),
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
              child: FutureBuilder(
                future: config.toQrPayload(),
                builder: (c, s) {
                  if (s.data == null) {
                    return Container();
                  }
                  final String? payload = s.data;
                  return QrImageView(
                    data: payload!,
                    version: QrVersions.auto,
                    size: 240,
                    backgroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    embeddedImage: AssetImage('assets/images/icon.jpg'),
                  );
                },
              ),
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
            if (hostReplaced) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.large),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '原配置为 localhost，已自动替换为本机局域网 IP，'
                        '扫码设备与当前设备需在同一网络。',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // 安全提示
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.large),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.security_outlined,
                    size: 18,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '二维码包含服务器连接凭据，请勿截屏或分享给不可信的人。',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.error,
                      ),
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
