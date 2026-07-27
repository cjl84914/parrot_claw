// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'server_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ServerConfig {

@HiveField(0) String get id;@HiveField(1) String get name;@HiveField(2) String get host;@HiveField(3) int get port;@HiveField(4) String get token;@HiveField(5) bool get useTLS;@HiveField(6) bool get isDefault;@HiveField(7) DateTime? get lastConnected;@HiveField(8) String get authMode;@HiveField(9) String get password;
/// Create a copy of ServerConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ServerConfigCopyWith<ServerConfig> get copyWith => _$ServerConfigCopyWithImpl<ServerConfig>(this as ServerConfig, _$identity);

  /// Serializes this ServerConfig to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ServerConfig&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.host, host) || other.host == host)&&(identical(other.port, port) || other.port == port)&&(identical(other.token, token) || other.token == token)&&(identical(other.useTLS, useTLS) || other.useTLS == useTLS)&&(identical(other.isDefault, isDefault) || other.isDefault == isDefault)&&(identical(other.lastConnected, lastConnected) || other.lastConnected == lastConnected)&&(identical(other.authMode, authMode) || other.authMode == authMode)&&(identical(other.password, password) || other.password == password));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,host,port,token,useTLS,isDefault,lastConnected,authMode,password);

@override
String toString() {
  return 'ServerConfig(id: $id, name: $name, host: $host, port: $port, token: $token, useTLS: $useTLS, isDefault: $isDefault, lastConnected: $lastConnected, authMode: $authMode, password: $password)';
}


}

/// @nodoc
abstract mixin class $ServerConfigCopyWith<$Res>  {
  factory $ServerConfigCopyWith(ServerConfig value, $Res Function(ServerConfig) _then) = _$ServerConfigCopyWithImpl;
@useResult
$Res call({
@HiveField(0) String id,@HiveField(1) String name,@HiveField(2) String host,@HiveField(3) int port,@HiveField(4) String token,@HiveField(5) bool useTLS,@HiveField(6) bool isDefault,@HiveField(7) DateTime? lastConnected,@HiveField(8) String authMode,@HiveField(9) String password
});




}
/// @nodoc
class _$ServerConfigCopyWithImpl<$Res>
    implements $ServerConfigCopyWith<$Res> {
  _$ServerConfigCopyWithImpl(this._self, this._then);

  final ServerConfig _self;
  final $Res Function(ServerConfig) _then;

/// Create a copy of ServerConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? host = null,Object? port = null,Object? token = null,Object? useTLS = null,Object? isDefault = null,Object? lastConnected = freezed,Object? authMode = null,Object? password = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,token: null == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String,useTLS: null == useTLS ? _self.useTLS : useTLS // ignore: cast_nullable_to_non_nullable
as bool,isDefault: null == isDefault ? _self.isDefault : isDefault // ignore: cast_nullable_to_non_nullable
as bool,lastConnected: freezed == lastConnected ? _self.lastConnected : lastConnected // ignore: cast_nullable_to_non_nullable
as DateTime?,authMode: null == authMode ? _self.authMode : authMode // ignore: cast_nullable_to_non_nullable
as String,password: null == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ServerConfig].
extension ServerConfigPatterns on ServerConfig {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ServerConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ServerConfig() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ServerConfig value)  $default,){
final _that = this;
switch (_that) {
case _ServerConfig():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ServerConfig value)?  $default,){
final _that = this;
switch (_that) {
case _ServerConfig() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@HiveField(0)  String id, @HiveField(1)  String name, @HiveField(2)  String host, @HiveField(3)  int port, @HiveField(4)  String token, @HiveField(5)  bool useTLS, @HiveField(6)  bool isDefault, @HiveField(7)  DateTime? lastConnected, @HiveField(8)  String authMode, @HiveField(9)  String password)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ServerConfig() when $default != null:
return $default(_that.id,_that.name,_that.host,_that.port,_that.token,_that.useTLS,_that.isDefault,_that.lastConnected,_that.authMode,_that.password);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@HiveField(0)  String id, @HiveField(1)  String name, @HiveField(2)  String host, @HiveField(3)  int port, @HiveField(4)  String token, @HiveField(5)  bool useTLS, @HiveField(6)  bool isDefault, @HiveField(7)  DateTime? lastConnected, @HiveField(8)  String authMode, @HiveField(9)  String password)  $default,) {final _that = this;
switch (_that) {
case _ServerConfig():
return $default(_that.id,_that.name,_that.host,_that.port,_that.token,_that.useTLS,_that.isDefault,_that.lastConnected,_that.authMode,_that.password);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@HiveField(0)  String id, @HiveField(1)  String name, @HiveField(2)  String host, @HiveField(3)  int port, @HiveField(4)  String token, @HiveField(5)  bool useTLS, @HiveField(6)  bool isDefault, @HiveField(7)  DateTime? lastConnected, @HiveField(8)  String authMode, @HiveField(9)  String password)?  $default,) {final _that = this;
switch (_that) {
case _ServerConfig() when $default != null:
return $default(_that.id,_that.name,_that.host,_that.port,_that.token,_that.useTLS,_that.isDefault,_that.lastConnected,_that.authMode,_that.password);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()
@HiveType(typeId: 0)
class _ServerConfig extends ServerConfig {
  const _ServerConfig({@HiveField(0) required this.id, @HiveField(1) required this.name, @HiveField(2) required this.host, @HiveField(3) this.port = 18789, @HiveField(4) this.token = '', @HiveField(5) this.useTLS = false, @HiveField(6) this.isDefault = false, @HiveField(7) this.lastConnected, @HiveField(8) this.authMode = 'token', @HiveField(9) this.password = ''}): super._();
  factory _ServerConfig.fromJson(Map<String, dynamic> json) => _$ServerConfigFromJson(json);

@override@HiveField(0) final  String id;
@override@HiveField(1) final  String name;
@override@HiveField(2) final  String host;
@override@JsonKey()@HiveField(3) final  int port;
@override@JsonKey()@HiveField(4) final  String token;
@override@JsonKey()@HiveField(5) final  bool useTLS;
@override@JsonKey()@HiveField(6) final  bool isDefault;
@override@HiveField(7) final  DateTime? lastConnected;
@override@JsonKey()@HiveField(8) final  String authMode;
@override@JsonKey()@HiveField(9) final  String password;

/// Create a copy of ServerConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ServerConfigCopyWith<_ServerConfig> get copyWith => __$ServerConfigCopyWithImpl<_ServerConfig>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ServerConfigToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ServerConfig&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.host, host) || other.host == host)&&(identical(other.port, port) || other.port == port)&&(identical(other.token, token) || other.token == token)&&(identical(other.useTLS, useTLS) || other.useTLS == useTLS)&&(identical(other.isDefault, isDefault) || other.isDefault == isDefault)&&(identical(other.lastConnected, lastConnected) || other.lastConnected == lastConnected)&&(identical(other.authMode, authMode) || other.authMode == authMode)&&(identical(other.password, password) || other.password == password));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,host,port,token,useTLS,isDefault,lastConnected,authMode,password);

@override
String toString() {
  return 'ServerConfig(id: $id, name: $name, host: $host, port: $port, token: $token, useTLS: $useTLS, isDefault: $isDefault, lastConnected: $lastConnected, authMode: $authMode, password: $password)';
}


}

/// @nodoc
abstract mixin class _$ServerConfigCopyWith<$Res> implements $ServerConfigCopyWith<$Res> {
  factory _$ServerConfigCopyWith(_ServerConfig value, $Res Function(_ServerConfig) _then) = __$ServerConfigCopyWithImpl;
@override @useResult
$Res call({
@HiveField(0) String id,@HiveField(1) String name,@HiveField(2) String host,@HiveField(3) int port,@HiveField(4) String token,@HiveField(5) bool useTLS,@HiveField(6) bool isDefault,@HiveField(7) DateTime? lastConnected,@HiveField(8) String authMode,@HiveField(9) String password
});




}
/// @nodoc
class __$ServerConfigCopyWithImpl<$Res>
    implements _$ServerConfigCopyWith<$Res> {
  __$ServerConfigCopyWithImpl(this._self, this._then);

  final _ServerConfig _self;
  final $Res Function(_ServerConfig) _then;

/// Create a copy of ServerConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? host = null,Object? port = null,Object? token = null,Object? useTLS = null,Object? isDefault = null,Object? lastConnected = freezed,Object? authMode = null,Object? password = null,}) {
  return _then(_ServerConfig(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,token: null == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String,useTLS: null == useTLS ? _self.useTLS : useTLS // ignore: cast_nullable_to_non_nullable
as bool,isDefault: null == isDefault ? _self.isDefault : isDefault // ignore: cast_nullable_to_non_nullable
as bool,lastConnected: freezed == lastConnected ? _self.lastConnected : lastConnected // ignore: cast_nullable_to_non_nullable
as DateTime?,authMode: null == authMode ? _self.authMode : authMode // ignore: cast_nullable_to_non_nullable
as String,password: null == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
