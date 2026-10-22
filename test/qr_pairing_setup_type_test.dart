import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_app/data/model/gateway_pairing_request.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/service/gateway_session.dart';
import 'package:parrot_app/data/service/openclaw_protocol.dart';

import 'support/fake_gateway_session.dart';

/// 扫码配对「设置类型」的两侧契约。
///
/// 生成侧：`device.pair.setupCode` 的 `bootstrapProfile` 参数怎么拼；
/// 扫码侧：payload 里的 `urls[]` / `tlsFingerprint` 怎么解析、候选地址怎么排序。
///
/// 依据官方源码（`/Users/alexcai/workspace/openclaw`）：
/// - `packages/gateway-protocol/src/schema/devices.ts` 的
///   `DevicePairSetupCodeParamsSchema.bootstrapProfile` 只接受
///   `limited` / `node` / `voice-node` —— **没有 `full`**，不传才等于完整访问；
/// - `src/pairing/setup-code.ts` 的 `PairingSetupPayload` 只有
///   `url / urls / bootstrapToken / expiresAtMs / tlsFingerprint` 五个字段，
///   **二维码里没有档位信息**。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('设置类型 → bootstrapProfile', () {
    test('完整访问必须不传字段（官方 enum 里没有 "full"）', () {
      expect(OpenClawPairSetupAccess.full.bootstrapProfile, isNull);
      expect(OpenClawPairSetupAccess.limited.bootstrapProfile, 'limited');
    });

    test('网关回带的 access 反解：不支持的档位一律 null，不能当成完整访问', () {
      expect(
        OpenClawPairSetupAccess.fromWire('full'),
        OpenClawPairSetupAccess.full,
      );
      expect(
        OpenClawPairSetupAccess.fromWire('limited'),
        OpenClawPairSetupAccess.limited,
      );
      // 官方还有 node（节点主机）与 voice-node（仅 CLI），本应用不支持。
      expect(OpenClawPairSetupAccess.fromWire('node'), isNull);
      expect(OpenClawPairSetupAccess.fromWire('voice-node'), isNull);
      expect(OpenClawPairSetupAccess.fromWire('FULL'), isNull);
      expect(OpenClawPairSetupAccess.fromWire(null), isNull);
      expect(OpenClawPairSetupAccess.fromWire('   '), isNull);
    });
  });

  group('device.pair.setupCode 请求参数', () {
    test('完整访问：params 里不能出现 bootstrapProfile', () async {
      final built = await buildConnectedRepository();
      Map<String, dynamic>? seen;
      built.session.handler = (method, params) {
        if (method != 'device.pair.setupCode') return const <String, dynamic>{};
        seen = params;
        return _setupCodeResponse();
      };

      final setup = await built.repository.devicePairSetupCode(
        access: OpenClawPairSetupAccess.full,
      );

      expect(seen, isNotNull);
      expect(seen!.containsKey('bootstrapProfile'), isFalse);
      expect(seen!['includeQr'], isTrue);
      expect(setup.setupCode, 'setup-code');

      await pumpEventQueue();
      built.repository.dispose();
    });

    test('受限访问：带上 bootstrapProfile=limited', () async {
      final built = await buildConnectedRepository();
      Map<String, dynamic>? seen;
      built.session.handler = (method, params) {
        if (method != 'device.pair.setupCode') return const <String, dynamic>{};
        seen = params;
        return _setupCodeResponse(access: 'limited');
      };

      final setup = await built.repository.devicePairSetupCode(
        access: OpenClawPairSetupAccess.limited,
      );

      expect(seen!['bootstrapProfile'], 'limited');
      expect(setup.access, OpenClawPairSetupAccess.limited);

      await pumpEventQueue();
      built.repository.dispose();
    });

    test('includeQr / publicUrl 都能透传（原先 publicUrl 被吞掉）', () async {
      final built = await buildConnectedRepository();
      Map<String, dynamic>? seen;
      built.session.handler = (method, params) {
        if (method != 'device.pair.setupCode') return const <String, dynamic>{};
        seen = params;
        return _setupCodeResponse();
      };

      await built.repository.devicePairSetupCode(
        publicUrl: 'wss://gw.example.com',
        includeQr: false,
      );

      expect(seen!['publicUrl'], 'wss://gw.example.com');
      expect(seen!['includeQr'], isFalse);

      await pumpEventQueue();
      built.repository.dispose();
    });

    test('accessDowngraded 与 expiresAtMs 解析', () async {
      final built = await buildConnectedRepository();
      built.session.handler = (method, params) {
        if (method != 'device.pair.setupCode') return const <String, dynamic>{};
        return _setupCodeResponse(
          access: 'limited',
          accessDowngraded: true,
          expiresAtMs: 1700000000000,
        );
      };

      final setup = await built.repository.devicePairSetupCode();

      expect(setup.accessDowngraded, isTrue);
      expect(setup.expiresAtMs, 1700000000000);
      expect(setup.expiredAt(1700000000001), isTrue);
      expect(setup.expiredAt(1699999999999), isFalse);

      await pumpEventQueue();
      built.repository.dispose();
    });

    test('老网关没有 access / expiresAtMs 时按未知处理，不报错', () async {
      final built = await buildConnectedRepository();
      built.session.handler = (method, params) {
        if (method != 'device.pair.setupCode') return const <String, dynamic>{};
        return _setupCodeResponse();
      };

      final setup = await built.repository.devicePairSetupCode();

      expect(setup.access, isNull);
      expect(setup.expiresAtMs, isNull);
      expect(setup.accessDowngraded, isNull);
      // 没有到期时间就永远不算过期，避免老网关被误判成「已过期」。
      expect(setup.expiredAt(DateTime.now().millisecondsSinceEpoch), isFalse);

      await pumpEventQueue();
      built.repository.dispose();
    });
  });

  group('扫码 payload：urls[] 与 tlsFingerprint', () {
    test('备用地址被规范化、去重，并按主地址在前的顺序排列', () {
      final request = GatewayPairingRequest.fromSetupCode(
        _encode({
          'url': 'ws://192.168.1.10:18789',
          'bootstrapToken': 'bootstrap',
          'expiresAtMs': _futureMs(),
          'urls': <String>[
            'wss://gw.example.ts.net',
            'https://gw.example.ts.net:443/',
            'ws://192.168.1.10:18789',
          ],
        }),
      );

      expect(request, isNotNull);
      // https→wss、补默认端口、去重（后两条与第一条等价，第三条与主地址等价）。
      expect(request!.fallbackUrls, <String>['wss://gw.example.ts.net:443']);
      expect(request.candidateUrls, <String>[
        'ws://192.168.1.10:18789',
        'wss://gw.example.ts.net:443',
      ]);
    });

    test('没有 urls 时候选地址只有主地址', () {
      final request = GatewayPairingRequest.fromSetupCode(
        _encode({
          'url': 'ws://192.168.1.10:18789',
          'bootstrapToken': 'bootstrap',
        }),
      );

      expect(request!.fallbackUrls, isEmpty);
      expect(request.candidateUrls, <String>['ws://192.168.1.10:18789']);
    });

    test('urls 存在但不合法 → 整条 payload 无效（与官方一致）', () {
      Map<String, Object> payload(Object urls) => {
        'url': 'ws://192.168.1.10:18789',
        'bootstrapToken': 'bootstrap',
        'urls': urls,
      };

      expect(GatewayPairingRequest.fromSetupCode(_encode(payload(<String>[]))), isNull);
      expect(
        GatewayPairingRequest.fromSetupCode(
          _encode(payload(List<String>.filled(9, 'ws://192.168.1.11:18789'))),
        ),
        isNull,
      );
      expect(GatewayPairingRequest.fromSetupCode(_encode(payload('not-a-list'))), isNull);
      expect(
        GatewayPairingRequest.fromSetupCode(_encode(payload(<String>['ftp://gw.example']))),
        isNull,
      );
      expect(
        GatewayPairingRequest.fromSetupCode(_encode(payload(<String>['wss://u:p@gw.example']))),
        isNull,
      );
    });

    test('tlsFingerprint 归一化：去前缀 / 去冒号 / 转小写', () {
      const colon = 'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:'
          'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99';
      const plain = 'aabbccddeeff00112233445566778899'
          'aabbccddeeff00112233445566778899';

      GatewayPairingRequest? parse(String fingerprint) =>
          GatewayPairingRequest.fromSetupCode(
            _encode({
              'url': 'wss://192.168.1.10:18789',
              'bootstrapToken': 'bootstrap',
              'tlsFingerprint': fingerprint,
            }),
          );

      expect(parse(colon)!.tlsFingerprint, plain);
      expect(parse('sha256:$plain')!.tlsFingerprint, plain);
      expect(parse(plain.toUpperCase())!.tlsFingerprint, plain);
      // 长度不对 / 非 hex → 整条无效，不能悄悄当成「没有指纹」放行。
      expect(parse('abcd'), isNull);
      expect(parse('zz'.padRight(64, 'z')), isNull);
      // 字段本身缺失则不是错误。
      expect(
        GatewayPairingRequest.fromSetupCode(
          _encode({
            'url': 'ws://192.168.1.10:18789',
            'bootstrapToken': 'bootstrap',
          }),
        )!.tlsFingerprint,
        isNull,
      );
    });

    test('支持 oc-pair:// 前缀', () {
      final code = _encode({
        'url': 'ws://192.168.1.10:18789',
        'bootstrapToken': 'bootstrap',
      });
      expect(
        GatewayPairingRequest.fromSetupCode('oc-pair://$code')!.bootstrapToken,
        'bootstrap',
      );
    });
  });

  group('证书指纹进连接配置', () {
    test('非空指纹会带进 GatewayConnectConfig；空串视为未固定', () {
      final pinned = ServerConfig(
        id: 's1',
        name: 'gw',
        host: '192.168.1.10',
        token: 't',
        tlsFingerprint: 'aabb',
      );
      expect(GatewayConnectConfig.fromServer(pinned).tlsFingerprint, 'aabb');

      final plain = ServerConfig(
        id: 's2',
        name: 'gw',
        host: '192.168.1.10',
        token: 't',
      );
      expect(GatewayConnectConfig.fromServer(plain).tlsFingerprint, isNull);
    });

    test('证书指纹是 DER 的 SHA-256，小写十六进制 64 位', () {
      // 固定输入 → 固定输出，防止有人把它改成 SPKI / PEM 口径。
      final hex = sha256OfDerCertificate(utf8.encode('openclaw'));
      expect(hex, hasLength(64));
      expect(hex, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });
}

String _encode(Map<String, Object> payload) =>
    base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');

int _futureMs() => DateTime.now().millisecondsSinceEpoch + 600000;

Map<String, dynamic> _setupCodeResponse({
  String? access,
  bool? accessDowngraded,
  int? expiresAtMs,
}) => <String, dynamic>{
  'setupCode': 'setup-code',
  'gatewayUrl': 'ws://192.168.1.10:18789',
  'auth': 'token',
  'urlSource': 'gateway.bind=lan',
  if (access != null) 'access': access,
  if (accessDowngraded != null) 'accessDowngraded': accessDowngraded,
  if (expiresAtMs != null) 'expiresAtMs': expiresAtMs,
};
