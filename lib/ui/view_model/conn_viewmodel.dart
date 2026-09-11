import 'dart:async';
import 'package:flutter/material.dart';
import 'package:parrot_app/data/repository/gateway_repository.dart';
import 'package:parrot_app/data/service/openclaw_protocol.dart';

class ConnViewModel extends ChangeNotifier {
  String? get sessionKey => _gatewayRepository.sessionKey;

  bool get connected => _gatewayRepository.connected;

  bool get isReconnecting => _gatewayRepository.isReconnecting;

  final GatewayRepository _gatewayRepository;

  String? get disconnectReason => _gatewayRepository.disconnectReason;

  ConnViewModel({required GatewayRepository gatewayRepository})
    : _gatewayRepository = gatewayRepository {
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
  Future<void> connect() async {
    await _gatewayRepository.connect();
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
