import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/model/gateway_pairing_request.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/service/gateway_connector.dart';
import 'package:parrot_app/data/service/openclaw_protocol.dart';
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

/// 一次 bootstrap 探测的结果：握手快照 + 命中的候选地址。
///
/// 地址要带回来 —— setup code 可能同时广告 LAN 明文地址与 Tailscale Serve 的
/// wss 地址，落配置时必须用**真正连上的那一条**，否则会出现「扫码成功但连不上」。
class _BootstrapProbe {
  const _BootstrapProbe({required this.hello, required this.url});

  final HelloOk? hello;
  final String url;
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

    final bootstrap = await _probeBootstrap(p);
    if (bootstrap == null) return false; // 内部已经提示过失败原因

    final auth = bootstrap.hello?.auth ?? const <String, dynamic>{};
    _log.info('gateway bootstrap handshake completed');

    // auth.deviceToken 属于首握角色（node），不可复用于 operator 会话；
    // operator 凭据在 auth.deviceTokens 中按 role 区分。
    final operatorEntry = _operatorTokenEntry(auth);
    if (operatorEntry == null) {
      // 官方还有一档 `node` 设置类型（`bootstrapProfile: "node"`）：那种码只下发
      // node 角色、没有 operator 令牌，产物是给电脑用的
      // `openclaw node run --pair "oc-pair://…"` 命令。本应用不能作为节点接入，
      // 必须明说 —— 原来的实现在这里 `throw StateError`，而错误处理只认
      // GatewayResponseError，于是扫这种码表现为「扫了一下、什么都没发生」。
      await _failWith('这是节点主机（Node host）配对码，需要在电脑上执行 '
          'openclaw node run --pair 命令，本应用不能作为节点接入。');
      return false;
    }
    final operatorToken = (operatorEntry['deviceToken'] as String?)?.trim();
    if (operatorToken == null || operatorToken.isEmpty) {
      await _failWith('网关未返回 operator 设备授权令牌，无法建立聊天会话。');
      return false;
    }
    final operatorScopes = _scopesFromEntry(operatorEntry);

    // 这条探测会话必须和正式连接（`GatewayConnectConfig.fromServer`）完全同构：
    // 不显式传 clientId / clientDisplayName，走平台默认。
    final operatorResult = await probeGateway(
      GatewayConnectConfig(
        url: bootstrap.url,
        token: operatorToken,
        tlsFingerprint: p.tlsFingerprint,
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

    final endpoint = _splitEndpoint(bootstrap.url);
    final config = ServerConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '${endpoint.host}:${endpoint.port}',
      host: endpoint.host,
      port: endpoint.port,
      useTLS: endpoint.useTLS,
      token: operatorToken,
      // 关键：这份凭据是设备令牌而不是网关长效 token，网关只授权受限 scopes。
      // 记成 device-token 后连接时会请求受限集合；而**具体是哪几个**只有网关
      // 知道（请求超集会被 `device token scope mismatch` 拒掉），所以把这次
      // 握手拿到的 operator scopes 一并记下来，连接时原样复用。
      authMode: ServerConfig.authModeDeviceToken,
      operatorScopes: operatorScopes,
      // 自签 TLS 网关必须带上指纹，否则冷启动重连会因为证书校验失败而连不上。
      tlsFingerprint: p.tlsFingerprint ?? '',
    );

    await _saveConfig(config);
    if (mounted) {
      MySnackBar.showSuccess(context, '配对成功（${_accessOf(operatorScopes).label}）');
    }
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

  /// 按候选地址逐个探测，返回第一个握手成功的结果。
  ///
  /// setup code 的 payload 可以广告多条地址（官方只在 `gateway.bind=lan` 且探测到
  /// 持久 Tailscale Serve HTTPS 根时附 `urls[]`）。官方 iOS 客户端就是逐个探测、
  /// 存第一个可达的（`docs/cli/qr.md`），所以这里也按序回退 —— 但**只对「连不上」
  /// 回退**：网关已经明确回话（token 无效、需要审批、权限不匹配）时，换地址也是
  /// 同一个网关、同一个答案，白等一轮还会把真正的错误盖成「地址不通」。
  Future<_BootstrapProbe?> _probeBootstrap(GatewayPairingRequest p) async {
    GatewayResponseError? lastError;
    for (final url in p.candidateUrls) {
      final result = await probeGateway(
        GatewayConnectConfig(
          url: url,
          token: p.token,
          password: p.password,
          bootstrapToken: p.bootstrapToken,
          tlsFingerprint: p.tlsFingerprint,
          clientId: _clientId,
          clientMode: 'node',
          role: 'node',
          scopes: const <String>[],
          caps: const <String>[],
          commands: const <String>[],
          permissions: const <String, bool>{},
        ),
      );
      if (result.ok) {
        if (url != p.wsUrl) {
          _log.info('gateway bootstrap fell back to an advertised route');
        }
        return _BootstrapProbe(hello: result.data, url: url);
      }
      final error = result.error;
      if (error == null) break;
      lastError = error;
      if (!_isTransportFailure(error)) break;
    }

    await _showHandshakeError(lastError ?? '无法连接到网关');
    return null;
  }

  /// 这个失败是不是「连不上」（值得换下一个候选地址再试）。
  ///
  /// `probeGateway` 对非网关错误（socket 异常、TLS 握手失败、连接超时）会合成为
  /// `UNAVAILABLE`，所以它就是传输层失败的主信号。
  bool _isTransportFailure(GatewayResponseError error) =>
      error.code.toUpperCase() == 'UNAVAILABLE';

  /// 从命中的候选地址里取出 [ServerConfig] 需要的字段。
  ///
  /// 已知缺口：`ServerConfig.wsUrl` 只拼 `scheme://host:port`，**不带路径**。
  /// 网关 URL 带 base path（Control UI 挂载点）时保存下来会丢路径 —— 这是既有
  /// 行为，本轮不动，只在这里记一笔。
  ({String host, int port, bool useTLS}) _splitEndpoint(String url) {
    final uri = Uri.parse(url);
    final useTLS = uri.scheme == 'wss';
    final port = uri.hasPort ? uri.port : (useTLS ? 443 : 18789);
    if (uri.path.isNotEmpty && uri.path != '/') {
      _log.warning('gateway route carries a base path; ServerConfig cannot store it');
    }
    return (host: uri.host, port: port, useTLS: useTLS);
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

  /// 网关回带的 operator scopes 才是真相，**不要在这里猜**。
  ///
  /// 原来这里写死 `openClawDeviceTokenScopes`（受限集合，无 admin）当兜底，那是
  /// 官方**旧**默认档；现在默认档已经改成完整访问（含 `operator.admin`），写死
  /// 受限集合会让首连少权限。反过来写死完整集合又会在受限档上多要 scope，
  /// 直接 `device token scope mismatch` 握手被拒。所以真没回带时退到几乎任何
  /// operator 令牌都有的 `operator.read`，连上后由 `ConnViewModel` 的
  /// `_learnGrantedScopes` 用 `hello.auth.scopes` 校正并回写配置，第二次连接即完整。
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
    return openClawMinimalOperatorScopes;
  }

  /// 从网关实际授权的 operator scopes 反推访问档位。
  ///
  /// 二维码 payload 里**没有**档位信息（官方 `PairingSetupPayload` 只有
  /// `url/urls/bootstrapToken/expiresAtMs/tlsFingerprint`），只有握手回来的
  /// `deviceTokens[].scopes` 能说明网关到底给了什么：含 `operator.admin` 就是完整
  /// 访问（官方 `MOBILE_FULL_ACCESS_OPERATOR_SCOPES`），否则是受限访问
  /// （`BOOTSTRAP_HANDOFF_OPERATOR_SCOPES`）。
  OpenClawPairSetupAccess _accessOf(List<String> operatorScopes) =>
      operatorScopes.contains('operator.admin')
      ? OpenClawPairSetupAccess.full
      : OpenClawPairSetupAccess.limited;

  void _showInvalidQr() {
    MySnackBar.showError(context, '无效的配对码，未识别到网关配置');
    _handling = false;
  }

  /// 提示一条失败原因，然后回到扫码态。
  Future<void> _failWith(String message) async {
    if (!mounted) return;
    MySnackBar.showError(context, message);
    await Future.delayed(const Duration(seconds: 2));
    await _resetForRescan();
  }

  Future<void> _showHandshakeError(Object error) async {
    if (!mounted) return;

    if (error is GatewayResponseError) {
      if (gatewayErrorCodeFromRaw(error.code) ==
          GatewayErrorCode.deviceNotPaired) {
        final details = GatewayErrorDetails.fromJson(error.details);
        await context.push(Routes.gatewayPairing, extra: details.requestId);
      } else {
        MySnackBar.showError(context, error.message);
      }
    } else {
      // 非网关错误（socket 异常、解析失败、超时…）。原实现只处理
      // GatewayResponseError，其余分支什么都不显示，扫码的人只看到「扫了一下
      // 没反应」，无从下手 —— 必须给出原因。
      MySnackBar.showError(context, '配对失败：$error');
    }

    await Future.delayed(const Duration(seconds: 2));
    await _resetForRescan();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫描配对码'), elevation: 0),
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
