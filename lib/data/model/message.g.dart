// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ChatMessage _$ChatMessageFromJson(Map<String, dynamic> json) => _ChatMessage(
  id: json['id'] as String? ?? '',
  role: json['role'] as String,
  content:
      (json['content'] as List<dynamic>)
          .map((e) => ChatMessageContent.fromJson(e as Map<String, dynamic>))
          .toList(),
  timestamp: (json['timestamp'] as num?)?.toInt(),
  idempotencyKey: json['idempotencyKey'] as String?,
);

Map<String, dynamic> _$ChatMessageToJson(_ChatMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'role': instance.role,
      'content': instance.content,
      'timestamp': instance.timestamp,
      'idempotencyKey': instance.idempotencyKey,
    };

_ChatMessageContent _$ChatMessageContentFromJson(Map<String, dynamic> json) =>
    _ChatMessageContent(
      type: json['type'] as String? ?? 'text',
      text: json['text'] as String?,
      mimeType: json['mimeType'] as String?,
      fileName: json['fileName'] as String?,
      base64: json['base64'] as String?,
    );

Map<String, dynamic> _$ChatMessageContentToJson(_ChatMessageContent instance) =>
    <String, dynamic>{
      'type': instance.type,
      'text': instance.text,
      'mimeType': instance.mimeType,
      'fileName': instance.fileName,
      'base64': instance.base64,
    };

_ChatPendingToolCall _$ChatPendingToolCallFromJson(Map<String, dynamic> json) =>
    _ChatPendingToolCall(
      toolCallId: json['toolCallId'] as String,
      name: json['name'] as String,
      args: json['args'] as Map<String, dynamic>?,
      startedAtMs: (json['startedAtMs'] as num).toInt(),
      isError: json['isError'] as bool?,
    );

Map<String, dynamic> _$ChatPendingToolCallToJson(
  _ChatPendingToolCall instance,
) => <String, dynamic>{
  'toolCallId': instance.toolCallId,
  'name': instance.name,
  'args': instance.args,
  'startedAtMs': instance.startedAtMs,
  'isError': instance.isError,
};

_ChatSessionEntry _$ChatSessionEntryFromJson(Map<String, dynamic> json) =>
    _ChatSessionEntry(
      key: json['key'] as String,
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt(),
      displayName: json['displayName'] as String?,
    );

Map<String, dynamic> _$ChatSessionEntryToJson(_ChatSessionEntry instance) =>
    <String, dynamic>{
      'key': instance.key,
      'updatedAtMs': instance.updatedAtMs,
      'displayName': instance.displayName,
    };

_ChatHistory _$ChatHistoryFromJson(Map<String, dynamic> json) => _ChatHistory(
  sessionKey: json['sessionKey'] as String,
  sessionId: json['sessionId'] as String?,
  thinkingLevel: json['thinkingLevel'] as String?,
  messages:
      (json['messages'] as List<dynamic>)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
);

Map<String, dynamic> _$ChatHistoryToJson(_ChatHistory instance) =>
    <String, dynamic>{
      'sessionKey': instance.sessionKey,
      'sessionId': instance.sessionId,
      'thinkingLevel': instance.thinkingLevel,
      'messages': instance.messages,
    };

_OutgoingAttachment _$OutgoingAttachmentFromJson(Map<String, dynamic> json) =>
    _OutgoingAttachment(
      type: json['type'] as String,
      mimeType: json['mimeType'] as String,
      fileName: json['fileName'] as String,
      base64: json['base64'] as String,
    );

Map<String, dynamic> _$OutgoingAttachmentToJson(_OutgoingAttachment instance) =>
    <String, dynamic>{
      'type': instance.type,
      'mimeType': instance.mimeType,
      'fileName': instance.fileName,
      'base64': instance.base64,
    };
