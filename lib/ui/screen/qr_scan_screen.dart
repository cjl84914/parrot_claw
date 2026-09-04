import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/model/gateway_pairing_request.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/service/gateway_channel.dart';
import 'package:parrot_app/data/service/gateway_connection.dart';
import 'package:parrot_app/data/service/gateway_scope_store.dart';
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/view_model/server_viewmodel.dart';

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
  bool _connectionHandedOff = false;
  GatewayPairingRequest? pairing;
  String? _lastPayload;

  /// 官方移动端 bootstrap 静默放行要求 canonical client id；
  /// node-host 只对 node-only profile 静默，兑默认双角色码会被踢进人工审批。
  String get _clientId => canonicalMobileClientId();

  /// 默认 QR（device.pair.setupCode）profile 授权的受限 operator scopes
  /// （BOOTSTRAP_HANDOFF_OPERATOR_SCOPES，无 admin/pairing）。
  static const List<String> _operatorHandoffScopes = [
    'operator.approvals',
    'operator.questions',
    'operator.read',
    'operator.talk.secrets',
    'operator.write',
  ];

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
  // 握手参数
  // ─────────────────────────────────────────────

  /// 第一阶段 node bootstrap：OpenClaw setup-code 配对是 node bootstrap 握手，
  /// role=node + 空 scopes + mode=node 是服务端接受的精确形态；
  /// 客户端身份必须用 canonical id（openclaw-android/ios）。
  GatewayConnectOptions get _bootstrapOptions => GatewayConnectOptions(
    role: 'node',
    scopes: const <String>[],
    scopesAreExplicit: true,
    caps: const <String>[],
    commands: const <String>[],
    permissions: const <String, bool>{},
    clientId: _clientId,
    clientMode: 'node',
    clientDisplayName: 'parrotClaw',
  );

  /// 第二阶段 operator 会话：只请求 bootstrap 实际授权的受限 scopes，
  /// 避免按默认全量（含 admin/pairing）请求触发 scope-upgrade 审批。
  GatewayConnectOptions operatorOptions(List<String> scopes) =>
      GatewayConnectOptions(
        role: 'operator',
        scopes: scopes,
        scopesAreExplicit: true,
        caps: const <String>[],
        commands: const <String>[],
        permissions: const <String, bool>{},
        clientId: _clientId,
        clientMode: 'ui',
        clientDisplayName: 'parrotClaw',
      );

  // ─────────────────────────────────────────────
  // 主流程
  // ─────────────────────────────────────────────

  Future<void> _handlePayload(String payload) async {
    _handling = true;
    _lastPayload = payload;
    try {
      pairing = GatewayPairingRequest.fromSetupCode(payload);
      if (pairing == null) {
        _showInvalidQr();
        return;
      }
      await _controller.stop();
      await _completePairing();
    } catch (error) {
      if (!mounted) return;
      await _handleGatewayFailure(
        gatewayErrorInfoFrom(error, method: 'connect'),
      );
    } finally {
      // 成功后连接已交给首页；仅失败/取消时关闭临时连接。
      if (!_connectionHandedOff) {
        try {
          await GatewayConnection.shared.shutdown();
        } catch (e) {
          print('[ParrotClaw] Failed to close test connection: $e');
        }
      }
    }
  }

  /// node bootstrap → 解析 node/operator 双令牌 → operator 会话 → 落配置。
  /// 返回 true 表示整条链路成功（页面已跳转）。
  Future<bool> _completePairing() async {
    final p = pairing;
    if (p == null) return false;

    final bootstrapResult = await GatewayConnection.shared.configureResult(
      url: p.wsUrl,
      token: p.token,
      password: p.password,
      bootstrapToken: p.bootstrapToken,
      connectOptions: _bootstrapOptions,
    );
    if (!bootstrapResult.ok) {
      await _handleGatewayFailure(bootstrapResult.error!);
      return false;
    }

    if (!mounted) return false;
    final snapshot =
        bootstrapResult.data ?? GatewayConnection.shared.lastSnapshot;
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

    final operatorResult = await GatewayConnection.shared.configureResult(
      url: p.wsUrl,
      token: operatorToken,
      connectOptions: operatorOptions(operatorScopes),
    );
    if (!operatorResult.ok) {
      await _handleGatewayFailure(operatorResult.error!);
      return false;
    }

    if (!mounted) return false;

    // 持久化受限 scopes：冷启动重连复用，避免再触发 scope-upgrade 审批。
    await GatewayScopeStore.saveOperatorScopes(p.wsUrl, operatorScopes);

    final config = ServerConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '${p.host}:${p.port}',
      host: p.host,
      port: p.port,
      useTLS: p.useTLS,
      token: operatorToken,
      authMode: 'token',
    );

    await _saveConfig(config);
    // 配对成功后将已建立的 operator 连接交给首页 ConnViewModel。
    // _handlePayload 的 finally 不能再 shutdown，否则会与首页的 connect()
    // 形成竞态：刚配对成功就被关闭，首页会一直显示连接中。
    _connectionHandedOff = true;
    if (mounted) context.go(Routes.index);
    return true;
  }

  /// 桌面批准后重试：同一 bootstrapToken 重新走完整 node → operator 流程。
  Future<void> _retryPairing() async {
    final payload = _lastPayload;
    if (payload == null || pairing == null) return;
    try {
      await _handlePayload(payload);
    } catch (error) {
      if (!mounted) return;
      await _handleGatewayFailure(
        gatewayErrorInfoFrom(error, method: 'connect'),
      );
    }
  }

  Future<void> _saveConfig(ServerConfig config) async {
    await widget.viewModel.addServer(config);
    widget.viewModel.selectServer(config);
  }

  Future<void> _handleGatewayFailure(GatewayErrorInfo error) async {
    if (!mounted) return;
    if (error.recoveryAction == GatewayRecoveryAction.showPairingPage) {
      final approved = await context.push<bool>(Routes.gatewayPairing);
      if (!mounted) return;
      if (approved == true) {
        // 网关上已授权（openclaw devices/nodes approve <requestId>）。
        await _retryPairing();
      } else {
        // 用户直接返回：复位并恢复相机，等待重新扫码或再次进入。
        await _resetForRescan();
      }
      return;
    }
    await _showHandshakeError(error.userMessage ?? error.message);
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
      final scopes = raw
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无效的二维码，未识别到网关配置')));
    _handling = false;
  }

  Future<void> _showHandshakeError(String message) async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    await _resetForRescan();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫码添加网关'), elevation: 0),
      body: Column(
        children: [
          // 扫描区域
          Expanded(
            child: Stack(
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
          ),
          // 底部说明
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                // Icon(
                //   Icons.qr_code_scanner,
                //   size: 28,
                //   color: AppColors.textSecondary,
                // ),
                // const SizedBox(height: 8),
                // Text(
                //   '将其他设备的网关配置二维码对准扫描框',
                //   style: AppTextStyles.caption,
                // ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
