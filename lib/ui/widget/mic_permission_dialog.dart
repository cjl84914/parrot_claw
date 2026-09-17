import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 麦克风不可用时的提示弹框。
///
/// 触发场景（都表现为「设备能打开但读不到音频」）：Windows 未允许桌面应用使用麦克风、
/// 麦克风被其他程序独占、设备被拔掉/切换、音频驱动异常等。文案因此保持中性，
/// 同时提供直达系统麦克风隐私设置页的入口。
Future<void> showMicDeviceDialog(
  BuildContext context, {
  String message =
      '没有收到麦克风音频。可能是系统未允许桌面应用使用麦克风，也可能是麦克风被其他程序占用或设备异常。',
}) {
  final canOpenSettings = Platform.isWindows || Platform.isMacOS;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('麦克风无法使用'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('知道了'),
        ),
        if (canOpenSettings)
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              openMicSettings();
            },
            child: const Text('跳到设置'),
          ),
      ],
    ),
  );
}

/// 打开系统「麦克风」隐私设置页。全部候选都失败时静默返回，用户可自行进设置。
Future<void> openMicSettings() async {
  for (final url in _micSettingsUrls()) {
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (ok) return;
    } catch (_) {
      // 该候选不可用，试下一个
    }
  }
}

List<String> _micSettingsUrls() {
  if (Platform.isWindows) {
    // 设置 - 隐私和安全性 - 麦克风 -「允许桌面应用访问你的麦克风」
    return const ['ms-settings:privacy-microphone'];
  }
  if (Platform.isMacOS) {
    // macOS 13+（含 26）隐私面板为 ExtensionKit 扩展；旧式 URL 只有老系统认，作为兜底。
    return const [
      'x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone',
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone',
    ];
  }
  return const [];
}
