import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/model/gateway_pairing_request.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/service/gateway_connector.dart';
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/view_model/server_viewmodel.dart';
import 'package:parrot_app/ui/widget/my_snack_bar.dart';

/// 扫码导入网关配置页
class QrScanScreen extends StatefulWidget {
  final ServerViewModel viewModel;

  const QrScanScreen({super.key, required this.viewModel});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  final Logger _log = Logger('QrScanScreen');

  bool _handling = false;
  GatewayPairingRequest? pairing;

  /// bootstrap 会话专用的客户端标识（移动端 canonical id，桌面端 `node-host`）。
  ///
  /// 官方移动端 bootstrap 静默放行要求 canonical client id；
  /// node-host 只对 node-only profile 静默，兑默认双角色码会被踢进人工审批。
  /// **只有这一条 node 角色的 bootstrap 会话用它** —— 后面那条 operator 探测
  /// 会话走平台默认（`gatewayClientIdForPlatform`），必须和正式连接完全一致，
  /// 否则"探测通过"不等于"连得上"。
  String get _clientId => canonicalMobileClientId();

  /// 默认 QR（device.pair.setupCode）profile 授权的受限 operator scopes
  /// （BOOTSTRAP_HANDOFF_OPERATOR_SCOPES，无 admin/pairing）。
  ///
  /// 只在网关没有逐条回带 scopes 时用作兜底（见 [_scopesFromEntry]）。真正生效的
  /// 是配对时记进 [ServerConfig.operatorScopes] 的那一份，连接时原样请求 ——
  /// 设备令牌会话多要一个 scope 就会被网关拒掉。
  static const List<String> _operatorHandoffScopes = openClawDeviceTokenScopes;

  /// 配对用的会话都是用完即弃的：每次 [probeGateway] 都会在返回前把它关掉，
  /// 因此这里不需要再手工收尾。
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

  // ─────────────────────────────────────────────
  // 主流程
  // ─────────────────────────────────────────────

  Future<void> _handlePayload(String payload) async {
    _handling = true;
    try {
      pairing = GatewayPairingRequest.fromSetupCode(payload);
      if (pairing == null) {
        _showInvalidQr();
        return;
      }
      await _controller.stop();
      final paired = await _completePairing();
      if (!paired && mounted) {
        await _resetForRescan();
      }
    } catch (error) {
      if (!mounted) return;
      await _showHandshakeError(error);
    }
  }

  /// node bootstrap → 解析 node/operator 双令牌 → operator 会话 → 落配置。
  /// 返回 true 表示整条链路成功（页面已跳转）。
  Future<bool> _completePairing() async {
    final p = pairing;
    if (p == null) return false;

    final bootstrapResult = await probeGateway(
      GatewayConnectConfig(
        url: p.wsUrl,
        token: p.token,
        password: p.password,
        bootstrapToken: p.bootstrapToken,
        clientId: _clientId,
        clientMode: 'node',
        role: 'node',
        scopes: const <String>[],
        caps: const <String>[],
        commands: const <String>[],
        permissions: const <String, bool>{},
      ),
    );
    if (!bootstrapResult.ok) {
      await _showHandshakeError(bootstrapResult.error!);
      return false;
    }

    if (!mounted) return false;
    final snapshot = bootstrapResult.data;
    final auth = snapshot?.auth ?? const <String, dynamic>{};
    _log.info('gateway bootstrap handshake completed');

    // auth.deviceToken 属于首握角色（node），不可复用于 operator 会话；
    // operator 凭据在 auth.deviceTokens 中按 role 区分。
    final operatorEntry = _operatorTokenEntry(auth);
    if (operatorEntry == null) {
      throw StateError('网关未返回 operator 设备授权令牌');
    }
    final operatorToken = (operatorEntry['deviceToken'] as String?)?.trim();
    if (operatorToken == null || operatorToken.isEmpty) {
      throw StateError('网关未返回 operator 设备授权令牌');
    }
    final operatorScopes = _scopesFromEntry(operatorEntry);

    // 这条探测会话必须和正式连接（`GatewayConnectConfig.fromServer`）完全同构：
    // 不显式传 clientId / clientDisplayName，走平台默认。
    final operatorResult = await probeGateway(
      GatewayConnectConfig(
        url: p.wsUrl,
        token: operatorToken,
        clientMode: 'ui',
        role: 'operator',
        scopes: operatorScopes,
        // 与正式连接同构：聊天渲染也走 `chat` 投影，能力声明必须一致，
        // 否则「探测通过」不代表正式连接的行为一致。
        caps: openClawClientCaps,
        commands: const <String>[],
        permissions: const <String, bool>{},
      ),
    );
    if (!operatorResult.ok) {
      await _showHandshakeError(operatorResult.error!);
      return false;
    }

    if (!mounted) return false;

    final config = ServerConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '${p.host}:${p.port}',
      host: p.host,
      port: p.port,
      useTLS: p.useTLS,
      token: operatorToken,
      // 关键：这份凭据是设备令牌而不是网关长效 token，网关只授权受限 scopes。
      // 记成 device-token 后连接时会请求受限集合；而**具体是哪几个**只有网关
      // 知道（请求超集会被 `device token scope mismatch` 拒掉），所以把这次
      // 握手拿到的 operator scopes 一并记下来，连接时原样复用。
      authMode: ServerConfig.authModeDeviceToken,
      operatorScopes: operatorScopes,
    );

    await _saveConfig(config);
    // 这里只需要跳转：新服务器会改 `main.dart` 里 `IndexScreen` 的
    // `ValueKey(selectedServer.id)`，壳因此重建，`initState` 里的 connect()
    // 会按刚保存的配置连一次。
    //
    // 别指望"ServerRepository 变更自动驱动连接" —— `GatewayRepository` 里的
    // `_onServerChanged` 没有任何地方注册，是死代码。所以**改同一个服务器**
    // （id 不变 → key 不变 → 壳不重建）不会触发重连，新写入的 scopes 要等
    // 下一次 connect()（冷启动进首页）才生效。
    if (mounted) context.go(Routes.index);
    return true;
  }

  Future<void> _saveConfig(ServerConfig config) async {
    await widget.viewModel.addServer(config);
    widget.viewModel.selectServer(config);
  }

  Future<void> _resetForRescan() async {
    if (!mounted) return;
    _handling = false;
    try {
      await _controller.start();
    } catch (_) {
      // 页面可能已销毁。
    }
  }

  /// 从 hello-ok auth.deviceTokens 取指定角色的条目（含 scopes）。
  Map<String, dynamic>? _operatorTokenEntry(Map<String, dynamic> auth) {
    final entries = auth['deviceTokens'];
    if (entries is! List) return null;
    for (final entry in entries) {
      if (entry is! Map) continue;
      if (entry['role']?.toString() != 'operator') continue;
      return entry.cast<String, dynamic>();
    }
    return null;
  }

  List<String> _scopesFromEntry(Map<String, dynamic> entry) {
    final raw = entry['scopes'];
    if (raw is List) {
      final scopes =
          raw
              .whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
      if (scopes.isNotEmpty) return scopes;
    }
    // 服务端未逐条回带 scopes 时，回退到默认受限集合（与 QR profile 一致）。
    return _operatorHandoffScopes;
  }

  void _showInvalidQr() {
    MySnackBar.showError(context, '无效的二维码，未识别到网关配置');
    _handling = false;
  }

  Future<void> _showHandshakeError(error) async {
    if (error is GatewayResponseError) {
      if (gatewayErrorCodeFromRaw(error.code) ==
          GatewayErrorCode.deviceNotPaired) {
        final details = GatewayErrorDetails.fromJson(error.details);
        await context.push(Routes.gatewayPairing, extra: details.requestId);
      } else {
        MySnackBar.showError(context, error.message);
      }
    }
    await Future.delayed(const Duration(seconds: 2));
    await _resetForRescan();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫码连接网关'), elevation: 0),
      body:
      Container(
        width: double.infinity,
        height: double.infinity,
        child:
      Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
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
    ));
  }
}
