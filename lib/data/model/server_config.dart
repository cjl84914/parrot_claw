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
    /// 网关为**这份凭据**实际授权的 operator scopes（设备令牌才需要）。
    ///
    /// 设备令牌的 scopes 是网关侧决定的，客户端推不出来：请求里多一个不在授权
    /// 范围内的 scope，握手就会被拒（`device token scope mismatch`），而且
    /// **会话权限就是请求列表本身**（网关用 `client.connect.scopes` 做方法鉴权），
    /// 所以既不能多要、也不能不要。
    ///
    /// 维护规则（三条缺一不可）：
    /// - 配对成功时记下网关发的那一份；
    /// - 每次连接成功后用 `hello.auth.scopes`（设备令牌会话返回的就是该令牌的
    ///   真实 scopes）校正，网关侧升/降权后能自愈；
    /// - 凭据变了（token/password 改动、重新配对）必须清空，否则会把旧凭据的
    ///   权限带到新凭据上。
    @HiveField(10) @Default(<String>[]) List<String> operatorScopes,
    /// 网关 TLS 证书指纹（小写十六进制 SHA-256，64 字符）；空串 = 不做固定。
    ///
    /// 只由扫码配对写入：setup code 的 payload 带 `tlsFingerprint` 时，说明网关
    /// 用的是自签证书（直连本地 TLS 或 `gateway.remote.url` 带指纹），此时必须
    /// 固定指纹才连得上 —— 系统信任库不认这张证书。
    ///
    /// 必须持久化：冷启动重连时手上只有这份配置，指纹丢了就会因为证书校验失败
    /// 而连不上，且现象是「扫码时好好的、重启后连不上」，很难排查。
    @HiveField(11) @Default('') String tlsFingerprint,
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

  /// 网关长效 token（openclaw.json 里的共享令牌）。
  static const String authModeToken = 'token';

  /// 网关密码。
  static const String authModePassword = 'password';

  /// 扫码配对（device.pair.setupCode / bootstrap）下发的**设备令牌**。
  ///
  /// 它和长效 token 是两种凭据：网关对设备令牌只授权受限 operator scopes
  /// （无 admin/pairing），所以连接时请求的 scopes 也必须跟着收窄 —— 否则会
  /// 触发 scope-upgrade 审批。凭据种类 + [operatorScopes] 一起决定请求什么，
  /// 见 `GatewayConnectConfig.fromServer`。
  static const String authModeDeviceToken = 'device-token';

  bool get isPasswordAuth => authMode == authModePassword;
  /// 是否扫码配对下发的设备令牌（受限 scopes）。
  bool get isDeviceTokenAuth => authMode == authModeDeviceToken;

  /// 除密码认证外都从 `token` 字段取凭据（含设备令牌）。
  bool get isTokenAuth => !isPasswordAuth;

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
