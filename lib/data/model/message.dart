import 'package:freezed_annotation/freezed_annotation.dart';

part 'message.g.dart';
part 'message.freezed.dart';


@freezed
abstract class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    @Default('') String id,
    required String role,
    required List<ChatMessageContent> content,
    int? timestamp,
    String? idempotencyKey,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);
}

@freezed
abstract class ChatMessageContent with _$ChatMessageContent {
  const factory ChatMessageContent({
    @Default('text') String type,
    String? text,
    String? mimeType,
    String? fileName,
    String? base64, // 对应 Kotlin 的 base64 字段，有时协议中也叫 content
  }) = _ChatMessageContent;

  factory ChatMessageContent.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageContentFromJson(json);
}

@freezed
abstract class ChatPendingToolCall with _$ChatPendingToolCall {
  const factory ChatPendingToolCall({
    required String toolCallId,
    required String name,
    Map<String, dynamic>? args,
    required int startedAtMs,
    bool? isError,
  }) = _ChatPendingToolCall;

  factory ChatPendingToolCall.fromJson(Map<String, dynamic> json) =>
      _$ChatPendingToolCallFromJson(json);
}

@freezed
abstract class ChatSessionEntry with _$ChatSessionEntry {
  const factory ChatSessionEntry({
    required String key,
    int? updatedAtMs,
    String? displayName,
  }) = _ChatSessionEntry;

  factory ChatSessionEntry.fromJson(Map<String, dynamic> json) =>
      _$ChatSessionEntryFromJson(json);
}

@freezed
abstract class ChatHistory with _$ChatHistory {
  const factory ChatHistory({
    required String sessionKey,
    String? sessionId,
    String? thinkingLevel,
    required List<ChatMessage> messages,
  }) = _ChatHistory;

  factory ChatHistory.fromJson(Map<String, dynamic> json) =>
      _$ChatHistoryFromJson(json);
}

@freezed
abstract class OutgoingAttachment with _$OutgoingAttachment {
  const factory OutgoingAttachment({
    required String type,
    required String mimeType,
    required String fileName,
    required String base64,
  }) = _OutgoingAttachment;

  factory OutgoingAttachment.fromJson(Map<String, dynamic> json) =>
      _$OutgoingAttachmentFromJson(json);
}