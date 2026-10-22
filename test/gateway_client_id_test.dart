import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_app/data/service/gateway_session.dart';

/// 网关侧 `GATEWAY_CLIENT_IDS` 注册表的完整副本
/// （`openclaw/packages/gateway-protocol/src/client-info.ts`）。
///
/// 这里**故意手抄一份**，不引用被测代码自己的常量：本文件要断言的正是"我们发出去
/// 的 id 落在网关的白名单里"，引用同一份常量就变成自证了。
/// 网关侧新增/删除 id 时这份清单要跟着改。
const _gatewayClientIds = <String>{
  'webchat-ui',
  'openclaw-control-ui',
  'openclaw-browser-copilot',
  'openclaw-tui',
  'webchat',
  'cli',
  'gateway-client',
  'openclaw-macos',
  'openclaw-linux',
  'openclaw-ios',
  'openclaw-watchos',
  'openclaw-android',
  'node-host',
  'openclaw-worker',
  'test',
  'fingerprint',
  'openclaw-probe',
};

void main() {
  group('网关客户端标识（client.id）', () {
    test('App 能发出的每个 id 都在网关的封闭注册表里', () {
      // 填注册表外的值不是降级，是整条握手被 INVALID_REQUEST 打回 —— 所以这条
      // 断言防的是"手滑写了个自造字符串"这类会让 App 完全连不上的改动。
      const emitted = <String>[
        openClawAndroidClientId,
        openClawIosClientId,
        openClawMacosClientId,
        openClawLinuxClientId,
        openClawNodeHostClientId,
        openClawGenericClientId,
      ];
      expect(emitted.toSet().difference(_gatewayClientIds), isEmpty);
    });

    test('按平台取到的 id 也在注册表里', () {
      expect(_gatewayClientIds, contains(gatewayClientIdForPlatform()));
      expect(_gatewayClientIds, contains(canonicalMobileClientId()));
    });

    test('id 与上报的 deviceFamily 同源（Windows 例外）', () {
      // 网关会拿 id + platform + deviceFamily 三元组校验，id 与平台不符会让扫码
      // 配对从"静默自动批准"退化成"需要 owner 手动批准"。
      final id = gatewayClientIdForPlatform();
      if (Platform.isWindows) {
        // 注册表里没有 openclaw-windows，只能退到通用标识。
        expect(id, openClawGenericClientId);
      } else {
        expect(id, contains(deviceFamilyForPlatform()!));
      }
    });

    test('displayName 带平台后缀，且非空', () {
      final name = gatewayClientDisplayNameForPlatform();
      expect(name, startsWith('parrotClaw'));
      expect(name.trim(), isNotEmpty);
    });

    test('不显式传 clientId 时落到平台默认值', () {
      // 这是所有生产连接点（fromServer / 本机探测）的实际路径。
      final options =
          const GatewayConnectConfig(url: 'ws://example.test')
              .toGatewayOptions();
      expect(options.clientId, gatewayClientIdForPlatform());
      expect(options.clientDisplayName, gatewayClientDisplayNameForPlatform());
    });

    test('显式传的 clientId 优先于平台默认', () {
      final options =
          const GatewayConnectConfig(
            url: 'ws://example.test',
            clientId: openClawNodeHostClientId,
            clientDisplayName: 'parrotClaw-bootstrap',
          ).toGatewayOptions();
      expect(options.clientId, openClawNodeHostClientId);
      expect(options.clientDisplayName, 'parrotClaw-bootstrap');
    });
  });
}
