import 'dart:async';
import 'package:flutter/material.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/repository/gateway_repository.dart';
import 'package:parrot_app/data/repository/server_repository.dart';
import 'package:parrot_app/data/service/gateway_session.dart';
import 'package:parrot_app/data/service/openclaw_protocol.dart';

class ConnViewModel extends ChangeNotifier {
  String? get sessionKey => _gatewayRepository.sessionKey;

  bool get connected => _gatewayRepository.connected;

  bool get isReconnecting => _gatewayRepository.isReconnecting;

  final GatewayRepository _gatewayRepository;

  final ServerRepository _serverRepository;

  String? get disconnectReason => _gatewayRepository.disconnectReason;

  ConnViewModel({
    required GatewayRepository gatewayRepository,
    required ServerRepository serverRepository,
  }) : _gatewayRepository = gatewayRepository,
       _serverRepository = serverRepository {
    _gatewayRepository.addListener(_notify);
  }

  void _notify() {
    notifyListeners();
  }

  /// 连接服务器（串行化）
  ///
  /// ServerRepository 的每次变更都会触发本方法（添加/选择/更新/删除），
  /// 若不串行化，并发的 connect() 会互相取消订阅、configure 短路返回，
  /// 导致首次握手被提前标记成功或最终超时显示"连接失败"。
  ///
  /// scopes 由 [GatewayConnectConfig.fromServer] 按凭据种类与配置里记录的授权
  /// 集合决定，这里不再从别处读取 —— 见该方法注释。
  Future<void> connect() async {
    final config = _serverRepository.selectedServer;
    if (config == null) {
      notifyListeners();
      return;
    }
    await _gatewayRepository.connect(GatewayConnectConfig.fromServer(config));

    // 网关实际授权的 scopes 与请求值不同（老配置没记录、或网关侧改过权限）时，
    // 用校正后的配置**再连一次**，让本次会话就拿到完整权限；只重试一次，且
    // 第二次拿到的 hello 与记录一致，不会再触发。
    final corrected = await _learnGrantedScopes(config);
    if (corrected != null) {
      await _gatewayRepository.connect(
        GatewayConnectConfig.fromServer(corrected),
      );
    }
  }

  /// 连接成功后，把网关**实际授权**的 scopes 记回配置。
  ///
  /// 设备令牌的 scopes 由网关侧决定，客户端推不出来：请求超集会被拒
  /// （`device token scope mismatch`），请求子集又白白少权限。而网关每次 hello
  /// 都会回带该令牌的真实 scopes，所以连上就校正一次 —— 网关升权/降权、或配置里
  /// 根本没有记录（老配置、走的是兜底请求）时都能自愈。
  ///
  /// 只对设备令牌配置生效：共享 token / 密码会话的 `auth.scopes` 就是请求值本身，
  /// 记回去没有意义，也不该把这类配置改判成设备令牌。
  ///
  /// 返回校正后的配置；无需校正时返回 null。
  Future<ServerConfig?> _learnGrantedScopes(ServerConfig config) async {
    if (!config.isDeviceTokenAuth) return null;
    final granted = _gatewayRepository.grantedScopes;
    if (granted == null || _sameScopes(granted, config.operatorScopes)) {
      return null;
    }
    final corrected = config.copyWith(operatorScopes: granted);
    await _serverRepository.updateServer(config.id, corrected);
    notifyListeners();
    return corrected;
  }

  bool _sameScopes(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final allowed = a.toSet();
    return b.every(allowed.contains);
  }

  /// 主动断开连接（保留服务器配置，可随时重新连接）。
  Future<void> disconnect() async {
    await _gatewayRepository.disconnect();
  }

  Future<void> reconnect() async {
    await _gatewayRepository.reconnect();
  }

  Future<OpenClawDevicePairSetupCodeResponse> devicePairSetupCode({
    String? publicUrl,
  }) async {
    return _gatewayRepository.devicePairSetupCode();
  }

  @override
  void dispose() {
    // GatewayRepository 由根级 Provider 持有，本 ViewModel 只是消费者，
    // 不能在这里 dispose，否则会连带拆掉共享连接。
    _gatewayRepository.removeListener(_notify);
    super.dispose();
  }
}
