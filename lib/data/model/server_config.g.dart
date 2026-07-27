// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ServerConfig _$ServerConfigFromJson(Map<String, dynamic> json) =>
    _ServerConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: (json['port'] as num?)?.toInt() ?? 18789,
      token: json['token'] as String? ?? '',
      useTLS: json['useTLS'] as bool? ?? false,
      isDefault: json['isDefault'] as bool? ?? false,
      lastConnected:
          json['lastConnected'] == null
              ? null
              : DateTime.parse(json['lastConnected'] as String),
      authMode: json['authMode'] as String? ?? 'token',
      password: json['password'] as String? ?? '',
    );

Map<String, dynamic> _$ServerConfigToJson(_ServerConfig instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'host': instance.host,
      'port': instance.port,
      'token': instance.token,
      'useTLS': instance.useTLS,
      'isDefault': instance.isDefault,
      'lastConnected': instance.lastConnected?.toIso8601String(),
      'authMode': instance.authMode,
      'password': instance.password,
    };
