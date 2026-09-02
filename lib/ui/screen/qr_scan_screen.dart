import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/model/gateway_pairing_request.dart';
import 'package:parrot_app/data/service/gateway_channel.dart';
import 'package:parrot_app/data/service/gateway_connection.dart';
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/view_model/conn_viewmodel.dart';
import 'package:parrot_app/ui/view_model/server_viewmodel.dart';
import 'package:provider/provider.dart';

/// 扫码导入网关配置页
class QrScanScreen extends StatefulWidget {
  final ServerViewModel viewModel;

  const QrScanScreen({super.key, required this.viewModel});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handling = false;
  final Logger _log = Logger('QrScanScreen');

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
    GatewayPairingRequest? pairing;
    try {
      pairing = GatewayPairingRequest.fromSetupCode(payload);
      if (pairing == null) {
        _showInvalidQr();
        return;
      }
      await _controller.stop();

      // if (confirmed != true) {
      //   await _controller.start();
      //   _handling = false;
      //   return;
      // }

      // if (!mounted) return;
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(content: Text('正在连接网关…')),
      // );

      // OpenClaw setup-code pairing is a node bootstrap handshake, not an
      // operator/UI connection. The server only accepts the exact node shape.
      const bootstrapOptions = GatewayConnectOptions(
        role: 'node',
        scopes: <String>[],
        scopesAreExplicit: true,
        caps: <String>[],
        commands: <String>[],
        permissions: <String, bool>{},
        clientId: 'node-host',
        clientMode: 'node',
        clientDisplayName: 'parrotClaw',
      );

      await GatewayConnection.shared.configure(
        url: pairing.wsUrl,
        token: pairing.token,
        password: pairing.password,
        bootstrapToken: pairing.bootstrapToken,
        connectOptions: bootstrapOptions,
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));
      final snapshot = GatewayConnection.shared.lastSnapshot;

      if (!mounted) return;

      final auth = snapshot?.auth ?? const <String, dynamic>{};
      _log.info(auth.toString());

      final deviceToken = (auth['deviceToken'] as String?)?.trim();
      if (deviceToken != null) {
        // operatorToken = _deviceTokenForRole(auth, 'operator');
        // // 当前页面是 Parrot 的 operator/UI 连接。bootstrap 握手返回的
        // // auth.deviceToken 属于 node 角色，不能拿它重新按 operator 连接；
        // // 优先使用服务端在 auth.deviceTokens 中签发的 operator token。
        // final savedToken = operatorToken ?? (pairing.token?.trim() ?? '');
        //
        // if (savedToken.isEmpty) {
        //   throw StateError(
        //     '握手成功，但网关未返回 operator 长期 token'
        //         '${nodeToken == null ? '' : '（仅收到 node token）'}',
        //   );
        // }

        // const operatorOptions = GatewayConnectOptions(
        //   role: 'operator',
        //   scopes: <String>[
        //     'operator.admin',
        //     'operator.approvals',
        //     'operator.pairing',
        //     'operator.read',
        //     'operator.write',
        //   ],
        //   scopesAreExplicit: true,
        //   caps: <String>[],
        //   commands: <String>[],
        //   permissions: <String, bool>{},
        //   clientId: 'gateway-client',
        //   clientMode: 'ui',
        //   clientDisplayName: 'parrotClaw',
        // );

        // 后续 operator/UI 连接使用服务端签发的 operator deviceToken，
        // 不再使用已经消费的一次性 bootstrapToken。
        await GatewayConnection.shared.configure(
          url: pairing.wsUrl,
          token: deviceToken,
          // connectOptions: operatorOptions,
        );

        if (!mounted) return;

        final config = ServerConfig(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: '${pairing.host}:${pairing.port}',
          host: pairing.host,
          port: pairing.port,
          useTLS: pairing.useTLS,
          token: deviceToken,
          authMode: 'token',
        );

        _saveConfig(config);
        context.go(Routes.index);
      }
    } catch (error) {
      if (!mounted) return;
      if (_isPairingRequiredError(error)) {
        // await _savePairingConfig(pairing, token: operatorToken);
        context.read<ConnViewModel>().capturePairingDeviceId(error);
        context.push(Routes.gatewayPairing).then((_) {
          _controller.start();
          _handling = false;
        });
        return;
      } else {
        _showHandshakeError(error);
      }
    } finally {
      try {
        await GatewayConnection.shared.shutdown();
      } catch (e) {
        print('[ParrotClaw] Failed to close test connection: $e');
      }
    }
  }

  Future<void> _saveConfig(ServerConfig config) async {
    await widget.viewModel.addServer(config);
    widget.viewModel.selectServer(config);
  }

  bool _isPairingRequiredError(Object error) {
    final text = error is GatewayResponseError
        ? '${error.code} ${error.message}'
        : error is GatewayConnectAuthError
        ? error.message
        : error.toString();
    final normalized = text.toLowerCase();
    return normalized.contains('device is not approved yet') ||
        normalized.contains('device_not_approved') ||
        normalized.contains('device not approved');
  }

  Future<void> _savePairingConfig(
      GatewayPairingRequest pairing, {
        String? token,
      }) async {
    final savedToken = token?.trim();
    final config = ServerConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '${pairing.host}:${pairing.port}',
      host: pairing.host,
      port: pairing.port,
      useTLS: pairing.useTLS,
      token:
      savedToken?.isNotEmpty == true
          ? savedToken!
          : pairing.token?.trim() ?? '',
      password: pairing.password?.trim() ?? '',
      authMode:
      pairing.password?.trim().isNotEmpty == true ? 'password' : 'token',
    );
    await widget.viewModel.addServer(config);
    widget.viewModel.selectServer(config);
  }

  String? _deviceTokenForRole(Map<String, dynamic> auth, String role) {
    final entries = auth['deviceTokens'];
    if (entries is! List) return null;
    for (final entry in entries) {
      if (entry is! Map) continue;
      if (entry['role']?.toString() != role) continue;
      final token = entry['deviceToken']?.toString().trim();
      if (token != null && token.isNotEmpty) return token;
    }
    return null;
  }

  void _showInvalidQr() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无效的二维码，未识别到网关配置')));
    _handling = false;
  }

  Future<void> _showHandshakeError(Object error) async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
    _handling = false;
    // The scanner was stopped before the handshake. Restore it after a
    // failed connection so the user can scan a newly generated setup code.
    try {
      await _controller.start();
    } catch (_) {
      // The page may already have been disposed while the connection failed.
    }
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
