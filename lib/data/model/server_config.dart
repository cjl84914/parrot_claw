import 'dart:convert';
import 'dart:io';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hive/hive.dart';

part 'server_config.g.dart';
part 'server_config.freezed.dart';

@freezed
abstract class ServerConfig with _$ServerConfig {
  @HiveType(typeId: 0)
  const factory ServerConfig({
    @HiveField(0) required String id,
    @HiveField(1) required String name,
    @HiveField(2) required String host,
    @HiveField(3) @Default(18789) int port,
    @HiveField(4) @Default('') String token,
    @HiveField(5) @Default(false) bool useTLS,
    @HiveField(6) @Default(false) bool isDefault,
    @HiveField(7) DateTime? lastConnected,
    @HiveField(8) @Default('token') String authMode,
    @HiveField(9) @Default('') String password,
  }) = _ServerConfig;

  factory ServerConfig.fromJson(Map<String, dynamic> json) =>
      _$ServerConfigFromJson(json);

  const ServerConfig._();

  /// 获取 WebSocket URL
  String get wsUrl => useTLS 
      ? 'wss://$host:$port' 
      : 'ws://$host:$port';

  /// 获取显示地址
  String get displayAddress => '$host:$port';

  bool get isPasswordAuth => authMode == 'password';
  bool get isTokenAuth => authMode != 'password';

  /// 获取当前生效的认证凭证
  String get activeCredential => isPasswordAuth ? password : token;

  /// 创建本地服务器配置
  factory ServerConfig.local({
    required String name,
    required String host,
    int port = 18789,
    required String token,
  }) {
    return ServerConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      host: host,
      port: port,
      token: token,
      useTLS: false,
    );
  }

  /// 创建云服务器配置（密码认证）
  factory ServerConfig.cloud({
    required String name,
    required String domain,
    String? token,
    String? password,
  }) {
    return ServerConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      host: domain,
      port: 443,
      token: token ?? '',
      password: password ?? '',
      authMode: password != null ? 'password' : 'token',
      useTLS: true,
    );
  }

  String get baseUrl => useTLS ? 'https://$host:$port' : 'http://$host:$port';
  /// 构造媒体访问 URL
  String buildMediaUrl(String sourcePath) {
    final encodedPath = Uri.encodeComponent(sourcePath);
    // 使用当前配置中的 token
    return '$baseUrl/__openclaw__/assistant-media?token=$token&source=$encodedPath';
  }

  // ========== 二维码编解码 ==========

  /// 二维码 payload 版本号
  static const int qrPayloadVersion = 1;

  /// 是否为本地回环地址（扫给其他设备时需替换成本机局域网 IP）
  static bool isLoopbackHost(String host) {
    final h = host.trim().toLowerCase();
    return h == 'localhost' || h == '127.0.0.1' || h == '::1' || h == '0.0.0.0';
  }

  /// 获取本机局域网 IPv4 地址（非回环、非链路本地）
  static Future<String?> getLocalIpV4() async{
    try {
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback || addr.isLinkLocal) continue;
          // 排除虚拟网卡常见保留段（0.0.0.0 / 广播）
          final a = addr.address;
          if (a == '0.0.0.0' || a == '255.255.255.255') continue;
          return a;
        }
      }
    } catch (_) {
      // 获取失败时返回 null，调用方保留原 host
    }
    return null;
  }

  /// 生成二维码 payload（紧凑 JSON，短字段名，不含 id/isDefault/lastConnected）
  ///
  /// 若 host 为 localhost/127.0.0.1，且本机能取到局域网 IP，则替换后编码，
  /// 使其他设备扫码后可直接连通本机。
  Future<String> toQrPayload() async{
    var hostForQr = host;
    if (isLoopbackHost(hostForQr)) {
      final localIp = await getLocalIpV4();
      if (localIp != null) hostForQr = localIp;
    }
    final map = <String, dynamic>{
      'v': qrPayloadVersion,
      'n': name,
      'h': hostForQr,
      'p': port,
      'tls': useTLS,
      'am': authMode,
    };
    if (isPasswordAuth) {
      map['pw'] = password;
    } else {
      map['t'] = token;
    }
    return jsonEncode(map);
  }

  /// 从二维码 payload 解析 ServerConfig
  ///
  /// [scannedHost] 可选：外部传入实际扫描到的 host（如扫码端自己的回环地址处理），
  /// 默认为 payload 中的 host。id 重新生成。
  static ServerConfig? fromQrPayload(
    String payload, {
    String? scannedHost,
  }) {
    try {
      final json = jsonDecode(payload);
      if (json is! Map<String, dynamic>) return null;
      final version = json['v'];
      if (version is! int || version != qrPayloadVersion) return null;

      final name = (json['n'] as String?)?.trim() ?? '';
      var host = (json['h'] as String?)?.trim() ?? '';
      if (host.isEmpty) return null;

      // 扫描端如果识别到回环地址但实际有可用 host，优先用 payload 内的
      host = scannedHost ?? host;

      final port = (json['p'] as num?)?.toInt() ?? 18789;
      final authMode = (json['am'] as String?)?.trim() ?? 'token';
      final useTLS = json['tls'] == true;

      return ServerConfig(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        host: host,
        port: port,
        useTLS: useTLS,
        authMode: authMode,
        token: authMode == 'password' ? '' : ((json['t'] as String?) ?? ''),
        password: authMode == 'password' ? ((json['pw'] as String?) ?? '') : '',
      );
    } catch (_) {
      return null;
    }
  }
}
