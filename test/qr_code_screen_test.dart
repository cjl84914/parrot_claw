import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_app/data/repository/gateway_repository.dart';
import 'package:parrot_app/data/service/gateway_session.dart';
import 'package:parrot_app/ui/screen/qr_code_screen.dart';
import 'package:parrot_app/ui/view_model/conn_viewmodel.dart';

import 'support/fake_gateway_session.dart';

/// 生成侧「设置类型」界面回归。
///
/// 交互契约（对齐官方 Control UI 的 *Setup type*）：先选访问级别 → 点「创建配对码」
/// → 出码后按钮变「刷新配对码」；切换档位会让已生成的码作废、回到选择态。
///
/// 界面契约（产品要求精简后的形态）：
/// - 页面标题是「配对设备」；
/// - 两个档位**并排一行**，不堆成两张卡片；
/// - 选择态**不显示**出码区域（没码就别留空框）；
/// - 二维码用**白底卡片**，但卡片跟随内容宽度、**不铺满整行**；
/// - 有效期倒计时紧贴二维码**下方**（过期后不再重复显示）；
/// - 主操作按钮宽度跟随文字，同样**不铺满整行**；
/// - 底部说明条文案为「ParrotClaw APP在扫码后会自动连接。获取应用。」，末段可点；
/// - 不再显示「访问级别」徽标与「明文降级」警告。
///
/// 测试注意：本页在「已出码 + 有 expiresAtMs 且未过期」时会起一个 1s 周期定时器
/// 做倒计时，所以用例结束时要把树换掉（触发 `dispose`），否则会报 timer 未清理。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('初始是选择态：不发请求、不显示出码区域、按钮是「创建配对码」', (tester) async {
    final built = await _pumpScreen(tester, respond: _readyResponse);

    expect(find.text('配对设备'), findsOneWidget);
    expect(find.text('设置类型'), findsOneWidget);
    expect(find.text('完整访问'), findsOneWidget);
    expect(find.text('受限访问'), findsOneWidget);
    expect(find.text('创建配对码'), findsOneWidget);

    // 还没点按钮，就不该已经烧掉一张一次性码。
    expect(built.params, isEmpty);
    // 没码就别留出码区域。
    expect(find.byType(Image), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // 按钮宽度跟随文字，不铺满整行（内容区宽 420）。
    final buttonWidth = tester
        .getSize(find.byWidgetPredicate((w) => w is OutlinedButton))
        .width;
    expect(buttonWidth, lessThan(400));

    await _teardown(tester, built);
  });

  testWidgets('完整访问：params 不带 bootstrapProfile，出码后按钮变「刷新配对码」', (
    tester,
  ) async {
    final built = await _pumpScreen(tester, respond: _readyResponse);

    await _tapCreate(tester);

    expect(built.params, hasLength(1));
    expect(built.params.single!.containsKey('bootstrapProfile'), isFalse);
    expect(built.params.single!['includeQr'], isTrue);
    expect(find.text('刷新配对码'), findsOneWidget);
    expect(find.text('创建配对码'), findsNothing);

    // 出码成功即渲染二维码；白底卡片不铺满整行，也不再显示档位徽标。
    expect(find.byType(Image), findsOneWidget);
    final cardWidth = tester
        .getSize(
          find
              .ancestor(
                of: find.byType(Image),
                matching: find.byType(Container),
              )
              .first,
        )
        .width;
    // 页面内容区宽 420；卡片按内容收缩（240 + 16×2），铺满就会是 420。
    expect(cardWidth, lessThan(400));
    expect(find.textContaining('访问级别：'), findsNothing);

    await _teardown(tester, built);
  });

  testWidgets('切到受限访问会作废已出的码，重新创建才带 bootstrapProfile=limited', (
    tester,
  ) async {
    final built = await _pumpScreen(
      tester,
      respond: () => _readyResponse(access: 'limited'),
    );

    await _tapCreate(tester);
    expect(find.text('刷新配对码'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.text('受限访问'));
    await tester.pump();

    // 旧码绑定的是旧档位，必须退回选择态（出码区域一并收起）。
    expect(find.text('创建配对码'), findsOneWidget);
    expect(find.text('刷新配对码'), findsNothing);
    expect(find.byType(Image), findsNothing);

    await _tapCreate(tester);
    expect(built.params, hasLength(2));
    expect(built.params.last!['bootstrapProfile'], 'limited');
    expect(find.byType(Image), findsOneWidget);

    await _teardown(tester, built);
  });

  testWidgets('两个档位并排一行，不堆成两张卡片', (tester) async {
    final built = await _pumpScreen(tester, respond: _readyResponse);

    final full = tester.getCenter(find.text('完整访问'));
    final limited = tester.getCenter(find.text('受限访问'));

    // 同一行 = 纵向位置相同，横向一左一右。
    expect(full.dy, moreOrLessEquals(limited.dy, epsilon: 0.5));
    expect(full.dx, lessThan(limited.dx));

    await _teardown(tester, built);
  });

  testWidgets('过期的码不显示二维码，提示重新生成，且不重复一行倒计时', (tester) async {
    final built = await _pumpScreen(
      tester,
      respond: () => _readyResponse(
        access: 'full',
        expiresAtMs: DateTime.now().millisecondsSinceEpoch - 1000,
      ),
    );

    await _tapCreate(tester);

    // 只该有出码区域那一条「已过期」，倒计时那一行必须收起来。
    expect(find.text('配对码已过期'), findsOneWidget);
    expect(find.textContaining('有效期剩余'), findsNothing);
    expect(find.byType(Image), findsNothing);

    await _teardown(tester, built);
  });

  testWidgets('有效期倒计时紧跟在二维码下方', (tester) async {
    final built = await _pumpScreen(
      tester,
      respond: () => _readyResponse(
        access: 'full',
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 5 * 60 * 1000,
      ),
    );

    await _tapCreate(tester);

    final expiry = find.textContaining('有效期剩余');
    expect(expiry, findsOneWidget);
    expect(
      tester.getCenter(expiry).dy,
      greaterThan(tester.getCenter(find.byType(Image)).dy),
    );

    await _teardown(tester, built);
  });

  testWidgets('权限不足时给人话提示（MISSING_SCOPE 在 details 里，不在外层 code）', (
    tester,
  ) async {
    final built = await _pumpScreen(
      tester,
      respond: () => throw GatewayResponseError(
        method: 'device.pair.setupCode',
        code: 'FORBIDDEN',
        message: 'missing scope: operator.admin',
        details: const <String, dynamic>{
          'code': 'MISSING_SCOPE',
          'missingScope': 'operator.admin',
          'requiredScopes': <String>['operator.admin'],
        },
      ),
    );

    await _tapCreate(tester);

    expect(find.textContaining('权限不足'), findsOneWidget);
    expect(find.textContaining('operator.admin'), findsWidgets);

    await _teardown(tester, built);
  });

  testWidgets('老网关没有 access / expiresAtMs 时不出有效期，仍能出码', (tester) async {
    final built = await _pumpScreen(tester, respond: _readyResponse);

    // _readyResponse 默认带 access，这里换成老网关形态（无 access / 无 expiresAtMs）。
    built.session.handler = (method, params) {
      if (method != 'device.pair.setupCode') return const <String, dynamic>{};
      built.params.add(params);
      return const <String, dynamic>{
        'setupCode': 'setup-code',
        'gatewayUrl': 'ws://192.168.1.10:18789',
        'auth': 'token',
        'urlSource': 'gateway.bind=lan',
        'qrDataUrl': _qrPngDataUrl,
      };
    };

    await _tapCreate(tester);

    expect(find.textContaining('有效期剩余'), findsNothing);
    expect(find.text('刷新配对码'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    await _teardown(tester, built);
  });

  testWidgets('底部说明条：文案正确，「获取应用」挂了点击识别器', (tester) async {
    final built = await _pumpScreen(tester, respond: _readyResponse);

    final banner = tester.widget<Text>(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.textSpan != null &&
            w.textSpan!.toPlainText().contains('获取应用'),
      ),
    );
    expect(banner.textSpan!.toPlainText(), 'ParrotClaw APP在扫码后会自动连接。获取应用。');

    // 「获取应用」必须是单独一段、且挂了 recognizer —— 否则点了没反应。
    final link = (banner.textSpan! as TextSpan).children!
        .whereType<TextSpan>()
        .firstWhere((span) => span.text == '获取应用');
    expect(link.recognizer, isNotNull);

    await _teardown(tester, built);
  });
}

/// 一张真实可解码的 1×1 PNG —— 必须是合法 PNG，否则 `Image.memory` 解码会抛错。
const String _qrPngDataUrl =
    'data:image/png;base64,'
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC';

/// 出码成功的最小响应。
///
/// 默认**不带** `expiresAtMs` —— 带上就会起倒计时定时器，让用例多一层时序负担。
Map<String, dynamic> _readyResponse({
  String? access = 'full',
  bool? accessDowngraded,
  int? expiresAtMs,
  String? qrDataUrl = _qrPngDataUrl,
}) => <String, dynamic>{
  'setupCode': 'setup-code',
  'gatewayUrl': 'ws://192.168.1.10:18789',
  'auth': 'token',
  'urlSource': 'gateway.bind=lan',
  if (access != null) 'access': access,
  if (accessDowngraded != null) 'accessDowngraded': accessDowngraded,
  if (expiresAtMs != null) 'expiresAtMs': expiresAtMs,
  if (qrDataUrl != null) 'qrDataUrl': qrDataUrl,
};

typedef _Screen = ({
  ConnViewModel viewModel,
  GatewayRepository repository,
  FakeGatewaySession session,
  List<Map<String, dynamic>?> params,
});

Future<_Screen> _pumpScreen(
  WidgetTester tester, {
  required Map<String, dynamic> Function() respond,
}) async {
  final built = await buildConnectedRepository();
  final params = <Map<String, dynamic>?>[];
  built.session.handler = (method, handlerParams) {
    if (method != 'device.pair.setupCode') return const <String, dynamic>{};
    params.add(handlerParams);
    return respond();
  };

  final viewModel = ConnViewModel(
    gatewayRepository: built.repository,
    serverRepository: FakeServerRepository(null),
  );

  await tester.pumpWidget(MaterialApp(home: QrCodeScreen(viewModel: viewModel)));
  await tester.pump();

  return (
    viewModel: viewModel,
    repository: built.repository,
    session: built.session,
    params: params,
  );
}

/// 点「创建配对码」并等响应落地。
///
/// 刻意不用 `pumpAndSettle`：加载态里的 `CircularProgressIndicator` 是无限动画，
/// 一旦响应没在预期帧内落地就会一直转下去。按帧 pump 更可控。
Future<void> _tapCreate(WidgetTester tester) async {
  await tester.tap(find.text('创建配对码'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
  await tester.pump(const Duration(milliseconds: 10));
}

/// 把树换掉以触发 `dispose`（取消倒计时定时器），再释放仓库。
Future<void> _teardown(WidgetTester tester, _Screen built) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  built.viewModel.dispose();
  built.repository.dispose();
}
