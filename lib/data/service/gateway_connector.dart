import 'package:logging/logging.dart';
import 'package:parrot_app/data/service/gateway_session.dart';

/// 本文件的 API 以 [GatewayConnectConfig] / [HelloOk] 为出入口，所以把传输层
/// 一并转出：调用方（探测点、扫码页）import 一次就能同时拿到配置与会话类型。
export 'package:parrot_app/data/service/gateway_session.dart';

final _connectorLog = Logger('GatewayConnector');

/// 会话自身的重连退避策略。
///
/// 刻意比 [GatewayRetryPolicy] 的默认值（2s→30s）更激进：网关重启通常几秒内
/// 就回来了，退避到 30s 会让 App 看起来「再也没连上」。
///
/// 这个延迟档位原先由 `OpenClawRuntime` 的守护重连 supervisor 用一套自建定时器
/// 实现。现在直接交给 `GatewaySession` 自己的退避循环 —— 它本来就把退避参数
/// 开放出来了，只是默认值偏保守。同一个目标，少一套机制。
const gatewaySessionRetryPolicy = GatewayRetryPolicy(
  initialDelay: Duration(seconds: 1),
  multiplier: 2,
  maxDelay: Duration(seconds: 30),
);

/// 会话工厂签名：`GatewayRepository` 通过它创建会话，测试也在这里注入假会话。
typedef GatewaySessionFactory =
    GatewaySession Function({
      required GatewayConnectConfig config,
      required void Function(GatewayPush push) onPush,
      required void Function(String reason) onDisconnect,
    });

/// 生产环境的会话工厂。
GatewaySession defaultGatewaySessionFactory({
  required GatewayConnectConfig config,
  required void Function(GatewayPush push) onPush,
  required void Function(String reason) onDisconnect,
}) {
  return GatewaySession(
    url: config.url,
    token: _nonEmpty(config.token),
    password: _nonEmpty(config.password),
    bootstrapToken: _nonEmpty(config.bootstrapToken),
    pushHandler: onPush,
    disconnectHandler: onDisconnect,
    connectOptions: config.toGatewayOptions(),
    retryPolicy: gatewaySessionRetryPolicy,
  );
}

/// 用一条**用完即弃**的会话试连，握手成功后返回 [HelloOk]。
///
/// 这是「测试连接 / 探测」的统一入口。它绝不触碰调用方正在使用的那条会话：
/// 拿共享会话做探测，一旦失败就会把正在工作的连接一起拆掉，并让那条会话
/// 按坏配置无限重试。
///
/// 探测与正式连接共用同一个 [GatewayConnectConfig]，所以「探测通过」就等于
/// 「连得上」—— 包括 scopes 在内的决策只做一次。
Future<GatewayOperationResult<HelloOk>> probeGateway(
  GatewayConnectConfig config,
) async {
  HelloOk? hello;
  final probe = defaultGatewaySessionFactory(
    config: config,
    onPush: (push) {
      if (push is GatewayPushSnapshot) hello = push.snapshot;
    },
    onDisconnect: (_) {},
  );
  try {
    await probe.connect();
    return GatewayOperationResult.success(data: hello);
  } catch (error) {
    if (error is GatewayResponseError) {
      return GatewayOperationResult.failure(error: error);
    }
    return GatewayOperationResult.failure(
      error: GatewayResponseError(
        code: 'UNAVAILABLE',
        message: error.toString(),
        method: 'Connect',
      ),
    );
  } finally {
    // 必须持有引用再 shutdown：探测会话的自动重连也要在这里停掉，
    // 否则它会留在后台一直重试一个已经没人关心的地址。
    try {
      await probe.shutdown();
    } catch (error) {
      _connectorLog.fine('Gateway probe shutdown ignored: $error');
    }
  }
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
