


class SessionMessage {
  final String? id;
  final String? role;
  final List<SessionMessageContent> content;
  final int? timestamp;
  final String? stopReason;

  const SessionMessage({
    this.id,
    this.role,
    this.content = const [],
    this.timestamp,
    this.stopReason,
  });

  factory SessionMessage.fromJson(Map<String, dynamic> json) {
    final rawContent = json['content'];

    return SessionMessage(
      id: json['__openclaw']?['id'] as String?,
      role: json['role'] as String?,
      content: rawContent is List
          ? rawContent
              .whereType<Map>()
              .map(
                (item) => SessionMessageContent.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
          : const [],
      timestamp: (json['timestamp'] as num?)?.toInt(),
      stopReason: json['stopReason'] as String?,
    );
  }

  String get text => content
      .where((item) => item.type == SessionMessageContentType.text)
      .map((item) => item.text ?? '')
      .where((value) => value.isNotEmpty)
      .join('\n');

  List<SessionMessageAttachment> get attachments => content
      .map((item) => item.attachment)
      .whereType<SessionMessageAttachment>()
      .toList();

  List<SessionMessageAttachment> get audioAttachments => attachments
      .where((attachment) => attachment.kind == 'audio')
      .toList();
}

enum SessionMessageContentType {
  text,
  attachment,
  unknown;

  static SessionMessageContentType fromValue(String? value) {
    return switch (value) {
      'text' => text,
      'attachment' => attachment,
      _ => unknown,
    };
  }
}

class SessionMessageContent {
  final SessionMessageContentType type;
  final String? text;
  final SessionMessageAttachment? attachment;

  const SessionMessageContent({
    required this.type,
    this.text,
    this.attachment,
  });

  factory SessionMessageContent.fromJson(Map<String, dynamic> json) {
    final rawAttachment = json['attachment'];

    return SessionMessageContent(
      type: SessionMessageContentType.fromValue(json['type'] as String?),
      text: json['text'] as String?,
      attachment: rawAttachment is Map
          ? SessionMessageAttachment.fromJson(
              Map<String, dynamic>.from(rawAttachment),
            )
          : null,
    );
  }
}

class SessionMessageAttachment {
  final String? url;
  final String? kind;
  final String? label;
  final String? mimeType;

  const SessionMessageAttachment({
    this.url,
    this.kind,
    this.label,
    this.mimeType,
  });

  factory SessionMessageAttachment.fromJson(Map<String, dynamic> json) {
    return SessionMessageAttachment(
      url: json['url'] as String?,
      kind: json['kind'] as String?,
      label: json['label'] as String?,
      mimeType: json['mimeType'] as String?,
    );
  }
}