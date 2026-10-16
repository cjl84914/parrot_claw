import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/service/gateway_session.dart';
import 'package:parrot_app/data/service/openclaw_protocol.dart';
import 'package:parrot_app/ui/screen/index_screen.dart';
import 'package:parrot_app/ui/view_model/conn_viewmodel.dart';
import 'package:url_launcher/url_launcher.dart';

/// 网关设备配对二维码展示页。
///
/// 交互对齐官方 Control UI 的 *Setup type*（`ui/src/pages/devices/view-pairing.tsx`）：
/// **先选访问级别 → 点「创建配对码」→ 出码后按钮变「刷新配对码」**。
///
/// 三个网关侧事实决定了这里的实现（见 `src/pairing/setup-code.ts`）：
/// 1. 「完整访问」是**不传** `bootstrapProfile`，不是传 `"full"`（官方 enum 没有该值）；
/// 2. 明文 `ws://`（非回环）网关会**自动降级**为受限访问，并回 `accessDowngraded: true`
///    —— 协议字段照收，但界面不再展示降级警告；
/// 3. `access` / `setupId` / `expiresAtMs` 都是可选字段 —— 老网关没有，必须降级显示
///    而不是报错。
class QrCodeScreen extends StatefulWidget {
  final ConnViewModel viewModel;

  const QrCodeScreen({super.key, required this.viewModel});

  @override
  State<QrCodeScreen> createState() => _QrCodeScreenState();
}

/// 页面阶段。刻意不用「有没有 setup 对象」推导：错误态也可能已经拿到过一张码。
enum _Phase { selection, loading, ready, error }

class _QrCodeScreenState extends State<QrCodeScreen> {
  /// 底部说明条里「获取应用」的下载地址。
  static const String downloadUrl = 'https://parrot.geetion.com/#download';

  _Phase _phase = _Phase.selection;
  OpenClawPairSetupAccess _access = OpenClawPairSetupAccess.full;
  OpenClawDevicePairSetupCodeResponse? _setup;
  String? _errorMessage;

  /// 请求代际。切换档位 / 连点刷新时旧响应必须作废，否则会把前一张码覆盖回来。
  int _requestToken = 0;

  Timer? _tick;
  int _nowMs = DateTime.now().millisecondsSinceEpoch;

  /// 「获取应用」的点击识别器。
  ///
  /// 必须在 State 上持有并 `dispose`：`TapGestureRecognizer` 是 `ChangeNotifier`，
  /// 在 `build()` 里现 new 会每次重建都泄漏一个。
  late final TapGestureRecognizer _downloadTap = TapGestureRecognizer()
    ..onTap = _openDownloadPage;

  @override
  void dispose() {
    _tick?.cancel();
    _downloadTap.dispose();
    super.dispose();
  }

  /// 打开应用下载页。
  ///
  /// 与 `chat_screen._openUrl` 同款：**不做 `canLaunchUrl` 预检** —— 它在 iOS 上对
  /// 没写进 `LSApplicationQueriesSchemes` 的 scheme 会误报 false，链接会静默点不开。
  /// 直接 launchUrl，真的失败再提示。
  Future<void> _openDownloadPage() async {
    final uri = Uri.tryParse(downloadUrl);
    if (uri == null || uri.scheme.isEmpty) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法打开：$downloadUrl')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开失败：$e')));
      }
    }
  }

  // ─────────────────────────────────────────────
  // 状态流转
  // ─────────────────────────────────────────────

  Future<void> _createSetupCode() async {
    final token = ++_requestToken;
    setState(() {
      _phase = _Phase.loading;
      _errorMessage = null;
    });

    try {
      final setup = await widget.viewModel.devicePairSetupCode(access: _access);
      if (!mounted || token != _requestToken) return;
      setState(() {
        _setup = setup;
        _phase = _Phase.ready;
        _nowMs = DateTime.now().millisecondsSinceEpoch;
      });
    } catch (error) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _setup = null;
        _phase = _Phase.error;
        _errorMessage = _describeError(error);
      });
    }
    _syncTick();
  }

  void _selectAccess(OpenClawPairSetupAccess access) {
    if (access == _access) return;
    // 已经生成的那张码绑定的是旧档位，切档即作废：退回选择态等用户重新创建。
    _requestToken++;
    setState(() {
      _access = access;
      _setup = null;
      _errorMessage = null;
      _phase = _Phase.selection;
    });
    _syncTick();
  }

  /// 只在「有码 + 有到期时间 + 还没过期」时开倒计时，避免常驻定时器。
  void _syncTick() {
    final expiresAtMs = _setup?.expiresAtMs;
    final needsTick =
        _phase == _Phase.ready && expiresAtMs != null && expiresAtMs > _nowMs;

    if (!needsTick) {
      _tick?.cancel();
      _tick = null;
      return;
    }
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _nowMs = DateTime.now().millisecondsSinceEpoch);
      _syncTick();
    });
  }

  /// 权限不足要说人话。
  ///
  /// 网关侧 `device.pair.setupCode` 要求调用方具备 `operator.admin`
  /// （`src/gateway/methods/core-descriptors.ts` 的方法权限策略），而受限设备令牌
  /// 会话没有 admin —— 这时网关会拒，笼统的「二维码生成失败」会让人以为是网络问题。
  ///
  /// 判据用**结构化字段**而不是错误码：网关这里回的是
  /// `{code: "FORBIDDEN", message: "missing scope: operator.admin",
  ///   details: {code: "MISSING_SCOPE", missingScope, requiredScopes}}`
  /// —— 外层 code 是通用的 FORBIDDEN，`gatewayErrorCodeFromRaw` 只会归到
  /// serverError，光看它认不出来。
  String _describeError(Object error) {
    if (error is! GatewayResponseError) {
      return '生成配对码失败：$error';
    }
    final missing =
        GatewayErrorDetails.fromJson(error.details).missingScopeDetails();
    if (missing != null) {
      return '当前连接权限不足：生成配对码需要 '
          '${missing.requiredScopes.join('、')}（缺少 ${missing.missingScope}）。'
          '请改用具备完整访问的服务器配置重新连接后再试。';
    }
    if (gatewayErrorCodeFromRaw(error.code) ==
        GatewayErrorCode.authScopeMismatch) {
      return '当前连接权限不足：生成配对码需要 operator.admin。'
          '请改用具备完整访问的服务器配置重新连接后再试。';
    }
    return error.message;
  }

  // ─────────────────────────────────────────────
  // 视图
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final expiresAtMs = _remainingExpiresAtMs;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: '打开侧边栏',
          onPressed: () => indexController.switchSideBarVisible(),
        ),
        title: const Text('配对设备'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInfoBanner(),
                const SizedBox(height: 24),
                _buildAccessSelector(),
                // 还没创建时不留出码区域 —— 空占位只会把「创建配对码」按钮往下推。
                if (_phase != _Phase.selection) ...[
                  const SizedBox(height: 20),
                  _buildCodeArea(),
                  // 有效期紧贴二维码下方。
                  if (expiresAtMs != null) ...[
                    const SizedBox(height: 12),
                    _buildExpiryLine(expiresAtMs),
                  ],
                ],
                const SizedBox(height: 20),
                _buildPrimaryAction(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 到期时刻（毫秒）；**只在「已出码 + 还没过期」时非空**。
  ///
  /// 过期后由出码区域的提示承担说明，这里返回 null 让倒计时那一行消失 ——
  /// 否则二维码位置会同时出现两行「配对码已过期」。
  int? get _remainingExpiresAtMs {
    if (_phase != _Phase.ready) return null;
    final expiresAtMs = _setup?.expiresAtMs;
    if (expiresAtMs == null || expiresAtMs <= _nowMs) return null;
    return expiresAtMs;
  }

  Widget _buildAccessSelector() {
    final selectable = _phase != _Phase.loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('设置类型', style: AppTextStyles.titleMedium),
        const SizedBox(height: 8),
        // 两个档位并排一行，不堆成两行卡片。
        Row(
          children: [
            for (final access in OpenClawPairSetupAccess.values) ...[
              Expanded(
                child: _AccessOptionTile(
                  access: access,
                  selected: access == _access,
                  enabled: selectable,
                  onTap: () => _selectAccess(access),
                ),
              ),
              if (access != OpenClawPairSetupAccess.values.last)
                const SizedBox(width: 10),
            ],
          ],
        ),
      ],
    );
  }

  /// 出码区域：一张**跟随内容宽度的白底卡片**。
  ///
  /// 白底是给二维码用的 —— 二维码是黑白模块，垫一层白能保证任何主题下都可扫。
  /// 但卡片不铺满整行：外层 `Center` 会吃掉 Column 的 `stretch`，卡片只按内容
  /// 收缩（二维码 240 + 两侧 16 内边距），不会出现一条通栏白条。
  Widget _buildCodeArea() => Center(child: _buildCodeCard());

  Widget _buildCodeCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xlarge),
      ),
      child: _buildCodeContent(),
    );
  }

  Widget _buildCodeContent() {
    switch (_phase) {
      case _Phase.selection:
        // 选择态由 build() 直接隐藏本区域，这里只是兜底。
        return const SizedBox.shrink();
      case _Phase.loading:
        return const SizedBox(
          width: 240,
          height: 240,
          child: Center(child: CircularProgressIndicator()),
        );
      case _Phase.error:
        return SizedBox(
          width: 240,
          child: _MessageBlock(
            icon: Icons.error_outline,
            color: AppColors.error,
            title: '创建失败',
            detail: _errorMessage ?? '未知错误',
          ),
        );
      case _Phase.ready:
        final setup = _setup;
        if (setup == null) {
          return const SizedBox(
            width: 240,
            child: _MessageBlock(
              icon: Icons.error_outline,
              color: AppColors.error,
              title: '创建失败',
              detail: '网关未返回配对码',
            ),
          );
        }
        if (setup.expiredAt(_nowMs)) {
          return const SizedBox(
            width: 240,
            child: _MessageBlock(
              icon: Icons.timer_off_outlined,
              color: AppColors.warning,
              title: '配对码已过期',
              detail: '请点击下方「刷新配对码」重新生成',
            ),
          );
        }
        final qrDataUrl = setup.qrDataUrl;
        if (qrDataUrl == null || qrDataUrl.isEmpty) {
          return const SizedBox(
            width: 240,
            child: _MessageBlock(
              icon: Icons.qr_code_2,
              color: AppColors.textSecondary,
              title: '网关未返回配对码',
              detail: '请改用配对码文本导入',
            ),
          );
        }
        return Image.memory(
          _decodeQrPng(qrDataUrl),
          width: 240,
          height: 240,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        );
    }
  }

  /// 主操作按钮。**宽度跟随文字内容**，不铺满整行 —— 外层 `Center` 会吃掉
  /// Column 的 `stretch`，按钮只按 label + icon 收缩。
  Widget _buildPrimaryAction() {
    final loading = _phase == _Phase.loading;
    final ready = _phase == _Phase.ready;
    return Center(
      child: OutlinedButton.icon(
        onPressed: loading ? null : _createSetupCode,
        icon:
            loading
                ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : Icon(ready ? Icons.refresh : Icons.qr_code_2),
        label: Text(
          loading
              ? '创建中...'
              : ready
              ? '刷新配对码'
              : '创建配对码',
        ),
      ),
    );
  }

  /// 底部说明条。末尾「获取应用」是一段可点链接（识别器见 [_downloadTap]）。
  ///
  /// 用 `Text.rich` 而不是「Text + InkWell」拼两个 widget：整句要能自然折行，
  /// 拆开会变成两个独立的可换行块。
  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      child: Row(
        children: [
          const Icon(Icons.info, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'ParrotClaw APP在扫码后会自动连接。'),
                  TextSpan(
                    text: '获取应用',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.secondary,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.secondary,
                    ),
                    recognizer: _downloadTap,
                  ),
                ],
              ),
              style: AppTextStyles.caption.copyWith(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  /// 有效期倒计时。
  ///
  /// 调用方（[build]）只在 [\_remainingExpiresAtMs] 非空时渲染，所以这里不必再判
  /// 过期 —— 过期态由出码区域的那段提示负责，避免同一个位置出现两行「已过期」。
  Widget _buildExpiryLine(int expiresAtMs) {
    return Text(
      '有效期剩余 ${_formatRemaining(expiresAtMs - _nowMs)}',
      textAlign: TextAlign.center,
      style: AppTextStyles.caption,
    );
  }

  Uint8List _decodeQrPng(String dataUrl) {
    const prefix = 'data:image/png;base64,';
    if (!dataUrl.startsWith(prefix)) {
      throw const FormatException('无效的配对码格式');
    }
    return base64Decode(dataUrl.substring(prefix.length));
  }

  String _formatRemaining(int remainingMs) {
    final totalSeconds = remainingMs <= 0 ? 0 : remainingMs ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes 分 ${seconds.toString().padLeft(2, '0')} 秒';
  }
}

/// 白底卡片里的一段状态说明。
///
/// 文字颜色必须写死深色：卡片是白底，而 App 跑的是深色主题
/// （`AppTextStyles` 的文字色是白字），直接套会得到白字白底。
class _MessageBlock extends StatelessWidget {
  const _MessageBlock({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

/// 「设置类型」单选项：一行放得下的紧凑样式（图标 + 档位名）。
class _AccessOptionTile extends StatelessWidget {
  const _AccessOptionTile({
    required this.access,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final OpenClawPairSetupAccess access;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.large),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.secondary : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(AppRadius.large),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? AppColors.secondary : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  access.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
