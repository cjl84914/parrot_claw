import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_app/util/device_identity.dart';

void main() {
  const deviceId = 'aabbccdd';
  const publicKey = 'pub';
  const privateKey = 'prv';

  DeviceIdentity identity() => DeviceIdentity(
    deviceId: deviceId,
    publicKey: publicKey,
    privateKey: privateKey,
  );

  group('DeviceIdentity.buildAuthPayload v3', () {
    test('与服务端 buildDeviceAuthPayloadV3 布局一致（含 ASCII 小写归一）', () {
      final payload = identity().buildAuthPayload(
        clientId: 'openclaw-android',
        clientMode: 'node',
        role: 'node',
        scopes: const <String>[],
        signedAtMs: 1234,
        token: '',
        nonce: 'nonce-1',
        platform: 'Android 14',
        deviceFamily: 'Android',
      );
      // 服务端 packages/gateway-client/src/device-auth.ts:
      // v3|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce|platform|deviceFamily
      expect(
        payload,
        'v3|aabbccdd|openclaw-android|node|node||1234||nonce-1|android 14|android',
      );
    });

    test('非空 scopes 与 token 保留原值，大小写只作用于 platform/deviceFamily', () {
      final payload = identity().buildAuthPayload(
        clientId: 'cli',
        clientMode: 'ui',
        role: 'operator',
        scopes: const ['operator.read', 'operator.admin'],
        signedAtMs: 99,
        token: 'AbC',
        nonce: 'n',
        platform: 'macOS',
        deviceFamily: 'MACOS',
      );
      expect(
        payload,
        'v3|aabbccdd|cli|ui|operator|operator.read,operator.admin|99|AbC|n|macos|macos',
      );
    });

    test('不传 platform/deviceFamily 时保持旧 v2 布局', () {
      final payload = identity().buildAuthPayload(
        clientId: 'cli',
        clientMode: 'ui',
        role: 'operator',
        scopes: const <String>[],
        signedAtMs: 5,
        token: 'T',
        nonce: 'n',
      );
      expect(payload, 'v2|aabbccdd|cli|ui|operator||5|T|n');
    });
  });
}
