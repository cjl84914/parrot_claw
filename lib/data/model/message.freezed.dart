// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ChatMessage {

 String get id; String get role; List<ChatMessageContent> get content; int? get timestamp; String? get idempotencyKey;
/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatMessageCopyWith<ChatMessage> get copyWith => _$ChatMessageCopyWithImpl<ChatMessage>(this as ChatMessage, _$identity);

  /// Serializes this ChatMessage to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatMessage&&(identical(other.id, id) || other.id == id)&&(identical(other.role, role) || other.role == role)&&const DeepCollectionEquality().equals(other.content, content)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.idempotencyKey, idempotencyKey) || other.idempotencyKey == idempotencyKey));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,role,const DeepCollectionEquality().hash(content),timestamp,idempotencyKey);

@override
String toString() {
  return 'ChatMessage(id: $id, role: $role, content: $content, timestamp: $timestamp, idempotencyKey: $idempotencyKey)';
}


}

/// @nodoc
abstract mixin class $ChatMessageCopyWith<$Res>  {
  factory $ChatMessageCopyWith(ChatMessage value, $Res Function(ChatMessage) _then) = _$ChatMessageCopyWithImpl;
@useResult
$Res call({
 String id, String role, List<ChatMessageContent> content, int? timestamp, String? idempotencyKey
});




}
/// @nodoc
class _$ChatMessageCopyWithImpl<$Res>
    implements $ChatMessageCopyWith<$Res> {
  _$ChatMessageCopyWithImpl(this._self, this._then);

  final ChatMessage _self;
  final $Res Function(ChatMessage) _then;

/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? role = null,Object? content = null,Object? timestamp = freezed,Object? idempotencyKey = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as List<ChatMessageContent>,timestamp: freezed == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as int?,idempotencyKey: freezed == idempotencyKey ? _self.idempotencyKey : idempotencyKey // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatMessage].
extension ChatMessagePatterns on ChatMessage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatMessage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatMessage value)  $default,){
final _that = this;
switch (_that) {
case _ChatMessage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatMessage value)?  $default,){
final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String role,  List<ChatMessageContent> content,  int? timestamp,  String? idempotencyKey)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
return $default(_that.id,_that.role,_that.content,_that.timestamp,_that.idempotencyKey);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String role,  List<ChatMessageContent> content,  int? timestamp,  String? idempotencyKey)  $default,) {final _that = this;
switch (_that) {
case _ChatMessage():
return $default(_that.id,_that.role,_that.content,_that.timestamp,_that.idempotencyKey);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String role,  List<ChatMessageContent> content,  int? timestamp,  String? idempotencyKey)?  $default,) {final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
return $default(_that.id,_that.role,_that.content,_that.timestamp,_that.idempotencyKey);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChatMessage implements ChatMessage {
  const _ChatMessage({this.id = '', required this.role, required final  List<ChatMessageContent> content, this.timestamp, this.idempotencyKey}): _content = content;
  factory _ChatMessage.fromJson(Map<String, dynamic> json) => _$ChatMessageFromJson(json);

@override@JsonKey() final  String id;
@override final  String role;
 final  List<ChatMessageContent> _content;
@override List<ChatMessageContent> get content {
  if (_content is EqualUnmodifiableListView) return _content;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_content);
}

@override final  int? timestamp;
@override final  String? idempotencyKey;

/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatMessageCopyWith<_ChatMessage> get copyWith => __$ChatMessageCopyWithImpl<_ChatMessage>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChatMessageToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatMessage&&(identical(other.id, id) || other.id == id)&&(identical(other.role, role) || other.role == role)&&const DeepCollectionEquality().equals(other._content, _content)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.idempotencyKey, idempotencyKey) || other.idempotencyKey == idempotencyKey));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,role,const DeepCollectionEquality().hash(_content),timestamp,idempotencyKey);

@override
String toString() {
  return 'ChatMessage(id: $id, role: $role, content: $content, timestamp: $timestamp, idempotencyKey: $idempotencyKey)';
}


}

/// @nodoc
abstract mixin class _$ChatMessageCopyWith<$Res> implements $ChatMessageCopyWith<$Res> {
  factory _$ChatMessageCopyWith(_ChatMessage value, $Res Function(_ChatMessage) _then) = __$ChatMessageCopyWithImpl;
@override @useResult
$Res call({
 String id, String role, List<ChatMessageContent> content, int? timestamp, String? idempotencyKey
});




}
/// @nodoc
class __$ChatMessageCopyWithImpl<$Res>
    implements _$ChatMessageCopyWith<$Res> {
  __$ChatMessageCopyWithImpl(this._self, this._then);

  final _ChatMessage _self;
  final $Res Function(_ChatMessage) _then;

/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? role = null,Object? content = null,Object? timestamp = freezed,Object? idempotencyKey = freezed,}) {
  return _then(_ChatMessage(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self._content : content // ignore: cast_nullable_to_non_nullable
as List<ChatMessageContent>,timestamp: freezed == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as int?,idempotencyKey: freezed == idempotencyKey ? _self.idempotencyKey : idempotencyKey // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$ChatMessageContent {

 String get type; String? get text; String? get mimeType; String? get fileName; String? get base64;
/// Create a copy of ChatMessageContent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatMessageContentCopyWith<ChatMessageContent> get copyWith => _$ChatMessageContentCopyWithImpl<ChatMessageContent>(this as ChatMessageContent, _$identity);

  /// Serializes this ChatMessageContent to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatMessageContent&&(identical(other.type, type) || other.type == type)&&(identical(other.text, text) || other.text == text)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.base64, base64) || other.base64 == base64));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,text,mimeType,fileName,base64);

@override
String toString() {
  return 'ChatMessageContent(type: $type, text: $text, mimeType: $mimeType, fileName: $fileName, base64: $base64)';
}


}

/// @nodoc
abstract mixin class $ChatMessageContentCopyWith<$Res>  {
  factory $ChatMessageContentCopyWith(ChatMessageContent value, $Res Function(ChatMessageContent) _then) = _$ChatMessageContentCopyWithImpl;
@useResult
$Res call({
 String type, String? text, String? mimeType, String? fileName, String? base64
});




}
/// @nodoc
class _$ChatMessageContentCopyWithImpl<$Res>
    implements $ChatMessageContentCopyWith<$Res> {
  _$ChatMessageContentCopyWithImpl(this._self, this._then);

  final ChatMessageContent _self;
  final $Res Function(ChatMessageContent) _then;

/// Create a copy of ChatMessageContent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? text = freezed,Object? mimeType = freezed,Object? fileName = freezed,Object? base64 = freezed,}) {
  return _then(_self.copyWith(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,text: freezed == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String?,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,fileName: freezed == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String?,base64: freezed == base64 ? _self.base64 : base64 // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatMessageContent].
extension ChatMessageContentPatterns on ChatMessageContent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatMessageContent value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatMessageContent() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatMessageContent value)  $default,){
final _that = this;
switch (_that) {
case _ChatMessageContent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatMessageContent value)?  $default,){
final _that = this;
switch (_that) {
case _ChatMessageContent() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String type,  String? text,  String? mimeType,  String? fileName,  String? base64)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatMessageContent() when $default != null:
return $default(_that.type,_that.text,_that.mimeType,_that.fileName,_that.base64);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String type,  String? text,  String? mimeType,  String? fileName,  String? base64)  $default,) {final _that = this;
switch (_that) {
case _ChatMessageContent():
return $default(_that.type,_that.text,_that.mimeType,_that.fileName,_that.base64);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String type,  String? text,  String? mimeType,  String? fileName,  String? base64)?  $default,) {final _that = this;
switch (_that) {
case _ChatMessageContent() when $default != null:
return $default(_that.type,_that.text,_that.mimeType,_that.fileName,_that.base64);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChatMessageContent implements ChatMessageContent {
  const _ChatMessageContent({this.type = 'text', this.text, this.mimeType, this.fileName, this.base64});
  factory _ChatMessageContent.fromJson(Map<String, dynamic> json) => _$ChatMessageContentFromJson(json);

@override@JsonKey() final  String type;
@override final  String? text;
@override final  String? mimeType;
@override final  String? fileName;
@override final  String? base64;

/// Create a copy of ChatMessageContent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatMessageContentCopyWith<_ChatMessageContent> get copyWith => __$ChatMessageContentCopyWithImpl<_ChatMessageContent>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChatMessageContentToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatMessageContent&&(identical(other.type, type) || other.type == type)&&(identical(other.text, text) || other.text == text)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.base64, base64) || other.base64 == base64));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,text,mimeType,fileName,base64);

@override
String toString() {
  return 'ChatMessageContent(type: $type, text: $text, mimeType: $mimeType, fileName: $fileName, base64: $base64)';
}


}

/// @nodoc
abstract mixin class _$ChatMessageContentCopyWith<$Res> implements $ChatMessageContentCopyWith<$Res> {
  factory _$ChatMessageContentCopyWith(_ChatMessageContent value, $Res Function(_ChatMessageContent) _then) = __$ChatMessageContentCopyWithImpl;
@override @useResult
$Res call({
 String type, String? text, String? mimeType, String? fileName, String? base64
});




}
/// @nodoc
class __$ChatMessageContentCopyWithImpl<$Res>
    implements _$ChatMessageContentCopyWith<$Res> {
  __$ChatMessageContentCopyWithImpl(this._self, this._then);

  final _ChatMessageContent _self;
  final $Res Function(_ChatMessageContent) _then;

/// Create a copy of ChatMessageContent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? text = freezed,Object? mimeType = freezed,Object? fileName = freezed,Object? base64 = freezed,}) {
  return _then(_ChatMessageContent(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,text: freezed == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String?,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,fileName: freezed == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String?,base64: freezed == base64 ? _self.base64 : base64 // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$ChatPendingToolCall {

 String get toolCallId; String get name; Map<String, dynamic>? get args; int get startedAtMs; bool? get isError;
/// Create a copy of ChatPendingToolCall
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatPendingToolCallCopyWith<ChatPendingToolCall> get copyWith => _$ChatPendingToolCallCopyWithImpl<ChatPendingToolCall>(this as ChatPendingToolCall, _$identity);

  /// Serializes this ChatPendingToolCall to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatPendingToolCall&&(identical(other.toolCallId, toolCallId) || other.toolCallId == toolCallId)&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.args, args)&&(identical(other.startedAtMs, startedAtMs) || other.startedAtMs == startedAtMs)&&(identical(other.isError, isError) || other.isError == isError));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,toolCallId,name,const DeepCollectionEquality().hash(args),startedAtMs,isError);

@override
String toString() {
  return 'ChatPendingToolCall(toolCallId: $toolCallId, name: $name, args: $args, startedAtMs: $startedAtMs, isError: $isError)';
}


}

/// @nodoc
abstract mixin class $ChatPendingToolCallCopyWith<$Res>  {
  factory $ChatPendingToolCallCopyWith(ChatPendingToolCall value, $Res Function(ChatPendingToolCall) _then) = _$ChatPendingToolCallCopyWithImpl;
@useResult
$Res call({
 String toolCallId, String name, Map<String, dynamic>? args, int startedAtMs, bool? isError
});




}
/// @nodoc
class _$ChatPendingToolCallCopyWithImpl<$Res>
    implements $ChatPendingToolCallCopyWith<$Res> {
  _$ChatPendingToolCallCopyWithImpl(this._self, this._then);

  final ChatPendingToolCall _self;
  final $Res Function(ChatPendingToolCall) _then;

/// Create a copy of ChatPendingToolCall
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? toolCallId = null,Object? name = null,Object? args = freezed,Object? startedAtMs = null,Object? isError = freezed,}) {
  return _then(_self.copyWith(
toolCallId: null == toolCallId ? _self.toolCallId : toolCallId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,args: freezed == args ? _self.args : args // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,startedAtMs: null == startedAtMs ? _self.startedAtMs : startedAtMs // ignore: cast_nullable_to_non_nullable
as int,isError: freezed == isError ? _self.isError : isError // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatPendingToolCall].
extension ChatPendingToolCallPatterns on ChatPendingToolCall {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatPendingToolCall value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatPendingToolCall() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatPendingToolCall value)  $default,){
final _that = this;
switch (_that) {
case _ChatPendingToolCall():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatPendingToolCall value)?  $default,){
final _that = this;
switch (_that) {
case _ChatPendingToolCall() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String toolCallId,  String name,  Map<String, dynamic>? args,  int startedAtMs,  bool? isError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatPendingToolCall() when $default != null:
return $default(_that.toolCallId,_that.name,_that.args,_that.startedAtMs,_that.isError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String toolCallId,  String name,  Map<String, dynamic>? args,  int startedAtMs,  bool? isError)  $default,) {final _that = this;
switch (_that) {
case _ChatPendingToolCall():
return $default(_that.toolCallId,_that.name,_that.args,_that.startedAtMs,_that.isError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String toolCallId,  String name,  Map<String, dynamic>? args,  int startedAtMs,  bool? isError)?  $default,) {final _that = this;
switch (_that) {
case _ChatPendingToolCall() when $default != null:
return $default(_that.toolCallId,_that.name,_that.args,_that.startedAtMs,_that.isError);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChatPendingToolCall implements ChatPendingToolCall {
  const _ChatPendingToolCall({required this.toolCallId, required this.name, final  Map<String, dynamic>? args, required this.startedAtMs, this.isError}): _args = args;
  factory _ChatPendingToolCall.fromJson(Map<String, dynamic> json) => _$ChatPendingToolCallFromJson(json);

@override final  String toolCallId;
@override final  String name;
 final  Map<String, dynamic>? _args;
@override Map<String, dynamic>? get args {
  final value = _args;
  if (value == null) return null;
  if (_args is EqualUnmodifiableMapView) return _args;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

@override final  int startedAtMs;
@override final  bool? isError;

/// Create a copy of ChatPendingToolCall
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatPendingToolCallCopyWith<_ChatPendingToolCall> get copyWith => __$ChatPendingToolCallCopyWithImpl<_ChatPendingToolCall>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChatPendingToolCallToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatPendingToolCall&&(identical(other.toolCallId, toolCallId) || other.toolCallId == toolCallId)&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other._args, _args)&&(identical(other.startedAtMs, startedAtMs) || other.startedAtMs == startedAtMs)&&(identical(other.isError, isError) || other.isError == isError));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,toolCallId,name,const DeepCollectionEquality().hash(_args),startedAtMs,isError);

@override
String toString() {
  return 'ChatPendingToolCall(toolCallId: $toolCallId, name: $name, args: $args, startedAtMs: $startedAtMs, isError: $isError)';
}


}

/// @nodoc
abstract mixin class _$ChatPendingToolCallCopyWith<$Res> implements $ChatPendingToolCallCopyWith<$Res> {
  factory _$ChatPendingToolCallCopyWith(_ChatPendingToolCall value, $Res Function(_ChatPendingToolCall) _then) = __$ChatPendingToolCallCopyWithImpl;
@override @useResult
$Res call({
 String toolCallId, String name, Map<String, dynamic>? args, int startedAtMs, bool? isError
});




}
/// @nodoc
class __$ChatPendingToolCallCopyWithImpl<$Res>
    implements _$ChatPendingToolCallCopyWith<$Res> {
  __$ChatPendingToolCallCopyWithImpl(this._self, this._then);

  final _ChatPendingToolCall _self;
  final $Res Function(_ChatPendingToolCall) _then;

/// Create a copy of ChatPendingToolCall
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? toolCallId = null,Object? name = null,Object? args = freezed,Object? startedAtMs = null,Object? isError = freezed,}) {
  return _then(_ChatPendingToolCall(
toolCallId: null == toolCallId ? _self.toolCallId : toolCallId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,args: freezed == args ? _self._args : args // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,startedAtMs: null == startedAtMs ? _self.startedAtMs : startedAtMs // ignore: cast_nullable_to_non_nullable
as int,isError: freezed == isError ? _self.isError : isError // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}


/// @nodoc
mixin _$ChatSessionEntry {

 String get key; int? get updatedAtMs; String? get displayName;
/// Create a copy of ChatSessionEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatSessionEntryCopyWith<ChatSessionEntry> get copyWith => _$ChatSessionEntryCopyWithImpl<ChatSessionEntry>(this as ChatSessionEntry, _$identity);

  /// Serializes this ChatSessionEntry to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatSessionEntry&&(identical(other.key, key) || other.key == key)&&(identical(other.updatedAtMs, updatedAtMs) || other.updatedAtMs == updatedAtMs)&&(identical(other.displayName, displayName) || other.displayName == displayName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,key,updatedAtMs,displayName);

@override
String toString() {
  return 'ChatSessionEntry(key: $key, updatedAtMs: $updatedAtMs, displayName: $displayName)';
}


}

/// @nodoc
abstract mixin class $ChatSessionEntryCopyWith<$Res>  {
  factory $ChatSessionEntryCopyWith(ChatSessionEntry value, $Res Function(ChatSessionEntry) _then) = _$ChatSessionEntryCopyWithImpl;
@useResult
$Res call({
 String key, int? updatedAtMs, String? displayName
});




}
/// @nodoc
class _$ChatSessionEntryCopyWithImpl<$Res>
    implements $ChatSessionEntryCopyWith<$Res> {
  _$ChatSessionEntryCopyWithImpl(this._self, this._then);

  final ChatSessionEntry _self;
  final $Res Function(ChatSessionEntry) _then;

/// Create a copy of ChatSessionEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? updatedAtMs = freezed,Object? displayName = freezed,}) {
  return _then(_self.copyWith(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,updatedAtMs: freezed == updatedAtMs ? _self.updatedAtMs : updatedAtMs // ignore: cast_nullable_to_non_nullable
as int?,displayName: freezed == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatSessionEntry].
extension ChatSessionEntryPatterns on ChatSessionEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatSessionEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatSessionEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatSessionEntry value)  $default,){
final _that = this;
switch (_that) {
case _ChatSessionEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatSessionEntry value)?  $default,){
final _that = this;
switch (_that) {
case _ChatSessionEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String key,  int? updatedAtMs,  String? displayName)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatSessionEntry() when $default != null:
return $default(_that.key,_that.updatedAtMs,_that.displayName);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String key,  int? updatedAtMs,  String? displayName)  $default,) {final _that = this;
switch (_that) {
case _ChatSessionEntry():
return $default(_that.key,_that.updatedAtMs,_that.displayName);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String key,  int? updatedAtMs,  String? displayName)?  $default,) {final _that = this;
switch (_that) {
case _ChatSessionEntry() when $default != null:
return $default(_that.key,_that.updatedAtMs,_that.displayName);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChatSessionEntry implements ChatSessionEntry {
  const _ChatSessionEntry({required this.key, this.updatedAtMs, this.displayName});
  factory _ChatSessionEntry.fromJson(Map<String, dynamic> json) => _$ChatSessionEntryFromJson(json);

@override final  String key;
@override final  int? updatedAtMs;
@override final  String? displayName;

/// Create a copy of ChatSessionEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatSessionEntryCopyWith<_ChatSessionEntry> get copyWith => __$ChatSessionEntryCopyWithImpl<_ChatSessionEntry>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChatSessionEntryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatSessionEntry&&(identical(other.key, key) || other.key == key)&&(identical(other.updatedAtMs, updatedAtMs) || other.updatedAtMs == updatedAtMs)&&(identical(other.displayName, displayName) || other.displayName == displayName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,key,updatedAtMs,displayName);

@override
String toString() {
  return 'ChatSessionEntry(key: $key, updatedAtMs: $updatedAtMs, displayName: $displayName)';
}


}

/// @nodoc
abstract mixin class _$ChatSessionEntryCopyWith<$Res> implements $ChatSessionEntryCopyWith<$Res> {
  factory _$ChatSessionEntryCopyWith(_ChatSessionEntry value, $Res Function(_ChatSessionEntry) _then) = __$ChatSessionEntryCopyWithImpl;
@override @useResult
$Res call({
 String key, int? updatedAtMs, String? displayName
});




}
/// @nodoc
class __$ChatSessionEntryCopyWithImpl<$Res>
    implements _$ChatSessionEntryCopyWith<$Res> {
  __$ChatSessionEntryCopyWithImpl(this._self, this._then);

  final _ChatSessionEntry _self;
  final $Res Function(_ChatSessionEntry) _then;

/// Create a copy of ChatSessionEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? updatedAtMs = freezed,Object? displayName = freezed,}) {
  return _then(_ChatSessionEntry(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,updatedAtMs: freezed == updatedAtMs ? _self.updatedAtMs : updatedAtMs // ignore: cast_nullable_to_non_nullable
as int?,displayName: freezed == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$ChatHistory {

 String get sessionKey; String? get sessionId; String? get thinkingLevel; List<ChatMessage> get messages;
/// Create a copy of ChatHistory
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatHistoryCopyWith<ChatHistory> get copyWith => _$ChatHistoryCopyWithImpl<ChatHistory>(this as ChatHistory, _$identity);

  /// Serializes this ChatHistory to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatHistory&&(identical(other.sessionKey, sessionKey) || other.sessionKey == sessionKey)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.thinkingLevel, thinkingLevel) || other.thinkingLevel == thinkingLevel)&&const DeepCollectionEquality().equals(other.messages, messages));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,sessionKey,sessionId,thinkingLevel,const DeepCollectionEquality().hash(messages));

@override
String toString() {
  return 'ChatHistory(sessionKey: $sessionKey, sessionId: $sessionId, thinkingLevel: $thinkingLevel, messages: $messages)';
}


}

/// @nodoc
abstract mixin class $ChatHistoryCopyWith<$Res>  {
  factory $ChatHistoryCopyWith(ChatHistory value, $Res Function(ChatHistory) _then) = _$ChatHistoryCopyWithImpl;
@useResult
$Res call({
 String sessionKey, String? sessionId, String? thinkingLevel, List<ChatMessage> messages
});




}
/// @nodoc
class _$ChatHistoryCopyWithImpl<$Res>
    implements $ChatHistoryCopyWith<$Res> {
  _$ChatHistoryCopyWithImpl(this._self, this._then);

  final ChatHistory _self;
  final $Res Function(ChatHistory) _then;

/// Create a copy of ChatHistory
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionKey = null,Object? sessionId = freezed,Object? thinkingLevel = freezed,Object? messages = null,}) {
  return _then(_self.copyWith(
sessionKey: null == sessionKey ? _self.sessionKey : sessionKey // ignore: cast_nullable_to_non_nullable
as String,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,thinkingLevel: freezed == thinkingLevel ? _self.thinkingLevel : thinkingLevel // ignore: cast_nullable_to_non_nullable
as String?,messages: null == messages ? _self.messages : messages // ignore: cast_nullable_to_non_nullable
as List<ChatMessage>,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatHistory].
extension ChatHistoryPatterns on ChatHistory {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatHistory value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatHistory() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatHistory value)  $default,){
final _that = this;
switch (_that) {
case _ChatHistory():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatHistory value)?  $default,){
final _that = this;
switch (_that) {
case _ChatHistory() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sessionKey,  String? sessionId,  String? thinkingLevel,  List<ChatMessage> messages)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatHistory() when $default != null:
return $default(_that.sessionKey,_that.sessionId,_that.thinkingLevel,_that.messages);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sessionKey,  String? sessionId,  String? thinkingLevel,  List<ChatMessage> messages)  $default,) {final _that = this;
switch (_that) {
case _ChatHistory():
return $default(_that.sessionKey,_that.sessionId,_that.thinkingLevel,_that.messages);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sessionKey,  String? sessionId,  String? thinkingLevel,  List<ChatMessage> messages)?  $default,) {final _that = this;
switch (_that) {
case _ChatHistory() when $default != null:
return $default(_that.sessionKey,_that.sessionId,_that.thinkingLevel,_that.messages);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChatHistory implements ChatHistory {
  const _ChatHistory({required this.sessionKey, this.sessionId, this.thinkingLevel, required final  List<ChatMessage> messages}): _messages = messages;
  factory _ChatHistory.fromJson(Map<String, dynamic> json) => _$ChatHistoryFromJson(json);

@override final  String sessionKey;
@override final  String? sessionId;
@override final  String? thinkingLevel;
 final  List<ChatMessage> _messages;
@override List<ChatMessage> get messages {
  if (_messages is EqualUnmodifiableListView) return _messages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_messages);
}


/// Create a copy of ChatHistory
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatHistoryCopyWith<_ChatHistory> get copyWith => __$ChatHistoryCopyWithImpl<_ChatHistory>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChatHistoryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatHistory&&(identical(other.sessionKey, sessionKey) || other.sessionKey == sessionKey)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.thinkingLevel, thinkingLevel) || other.thinkingLevel == thinkingLevel)&&const DeepCollectionEquality().equals(other._messages, _messages));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,sessionKey,sessionId,thinkingLevel,const DeepCollectionEquality().hash(_messages));

@override
String toString() {
  return 'ChatHistory(sessionKey: $sessionKey, sessionId: $sessionId, thinkingLevel: $thinkingLevel, messages: $messages)';
}


}

/// @nodoc
abstract mixin class _$ChatHistoryCopyWith<$Res> implements $ChatHistoryCopyWith<$Res> {
  factory _$ChatHistoryCopyWith(_ChatHistory value, $Res Function(_ChatHistory) _then) = __$ChatHistoryCopyWithImpl;
@override @useResult
$Res call({
 String sessionKey, String? sessionId, String? thinkingLevel, List<ChatMessage> messages
});




}
/// @nodoc
class __$ChatHistoryCopyWithImpl<$Res>
    implements _$ChatHistoryCopyWith<$Res> {
  __$ChatHistoryCopyWithImpl(this._self, this._then);

  final _ChatHistory _self;
  final $Res Function(_ChatHistory) _then;

/// Create a copy of ChatHistory
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionKey = null,Object? sessionId = freezed,Object? thinkingLevel = freezed,Object? messages = null,}) {
  return _then(_ChatHistory(
sessionKey: null == sessionKey ? _self.sessionKey : sessionKey // ignore: cast_nullable_to_non_nullable
as String,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,thinkingLevel: freezed == thinkingLevel ? _self.thinkingLevel : thinkingLevel // ignore: cast_nullable_to_non_nullable
as String?,messages: null == messages ? _self._messages : messages // ignore: cast_nullable_to_non_nullable
as List<ChatMessage>,
  ));
}


}


/// @nodoc
mixin _$OutgoingAttachment {

 String get type; String get mimeType; String get fileName; String get base64;
/// Create a copy of OutgoingAttachment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OutgoingAttachmentCopyWith<OutgoingAttachment> get copyWith => _$OutgoingAttachmentCopyWithImpl<OutgoingAttachment>(this as OutgoingAttachment, _$identity);

  /// Serializes this OutgoingAttachment to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OutgoingAttachment&&(identical(other.type, type) || other.type == type)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.base64, base64) || other.base64 == base64));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,mimeType,fileName,base64);

@override
String toString() {
  return 'OutgoingAttachment(type: $type, mimeType: $mimeType, fileName: $fileName, base64: $base64)';
}


}

/// @nodoc
abstract mixin class $OutgoingAttachmentCopyWith<$Res>  {
  factory $OutgoingAttachmentCopyWith(OutgoingAttachment value, $Res Function(OutgoingAttachment) _then) = _$OutgoingAttachmentCopyWithImpl;
@useResult
$Res call({
 String type, String mimeType, String fileName, String base64
});




}
/// @nodoc
class _$OutgoingAttachmentCopyWithImpl<$Res>
    implements $OutgoingAttachmentCopyWith<$Res> {
  _$OutgoingAttachmentCopyWithImpl(this._self, this._then);

  final OutgoingAttachment _self;
  final $Res Function(OutgoingAttachment) _then;

/// Create a copy of OutgoingAttachment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? mimeType = null,Object? fileName = null,Object? base64 = null,}) {
  return _then(_self.copyWith(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,base64: null == base64 ? _self.base64 : base64 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [OutgoingAttachment].
extension OutgoingAttachmentPatterns on OutgoingAttachment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _OutgoingAttachment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _OutgoingAttachment() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _OutgoingAttachment value)  $default,){
final _that = this;
switch (_that) {
case _OutgoingAttachment():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _OutgoingAttachment value)?  $default,){
final _that = this;
switch (_that) {
case _OutgoingAttachment() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String type,  String mimeType,  String fileName,  String base64)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _OutgoingAttachment() when $default != null:
return $default(_that.type,_that.mimeType,_that.fileName,_that.base64);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String type,  String mimeType,  String fileName,  String base64)  $default,) {final _that = this;
switch (_that) {
case _OutgoingAttachment():
return $default(_that.type,_that.mimeType,_that.fileName,_that.base64);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String type,  String mimeType,  String fileName,  String base64)?  $default,) {final _that = this;
switch (_that) {
case _OutgoingAttachment() when $default != null:
return $default(_that.type,_that.mimeType,_that.fileName,_that.base64);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _OutgoingAttachment implements OutgoingAttachment {
  const _OutgoingAttachment({required this.type, required this.mimeType, required this.fileName, required this.base64});
  factory _OutgoingAttachment.fromJson(Map<String, dynamic> json) => _$OutgoingAttachmentFromJson(json);

@override final  String type;
@override final  String mimeType;
@override final  String fileName;
@override final  String base64;

/// Create a copy of OutgoingAttachment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OutgoingAttachmentCopyWith<_OutgoingAttachment> get copyWith => __$OutgoingAttachmentCopyWithImpl<_OutgoingAttachment>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$OutgoingAttachmentToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _OutgoingAttachment&&(identical(other.type, type) || other.type == type)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.base64, base64) || other.base64 == base64));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,mimeType,fileName,base64);

@override
String toString() {
  return 'OutgoingAttachment(type: $type, mimeType: $mimeType, fileName: $fileName, base64: $base64)';
}


}

/// @nodoc
abstract mixin class _$OutgoingAttachmentCopyWith<$Res> implements $OutgoingAttachmentCopyWith<$Res> {
  factory _$OutgoingAttachmentCopyWith(_OutgoingAttachment value, $Res Function(_OutgoingAttachment) _then) = __$OutgoingAttachmentCopyWithImpl;
@override @useResult
$Res call({
 String type, String mimeType, String fileName, String base64
});




}
/// @nodoc
class __$OutgoingAttachmentCopyWithImpl<$Res>
    implements _$OutgoingAttachmentCopyWith<$Res> {
  __$OutgoingAttachmentCopyWithImpl(this._self, this._then);

  final _OutgoingAttachment _self;
  final $Res Function(_OutgoingAttachment) _then;

/// Create a copy of OutgoingAttachment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? mimeType = null,Object? fileName = null,Object? base64 = null,}) {
  return _then(_OutgoingAttachment(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,base64: null == base64 ? _self.base64 : base64 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
