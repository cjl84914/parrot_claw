import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 麦克风不可用时的提示弹框。
///
/// Windows 的「允许桌面应用访问你的麦克风」被关闭时，MediaFoundation 会枚举到
/// 0 个采集设备，表现为「未检测到可用麦克风输入设备」。这是权限问题而不是硬件问题，
/// 所以给一个直接跳到系统麦克风隐私设置页的入口。
Future<void> showMicDeviceDialog(
  BuildContext context, {
  String message = '未检测到可用麦克风输入设备',
}) {
  final canOpenSettings = Platform.isWindows || Platform.isMacOS;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('未检测到麦克风'),
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
