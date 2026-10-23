import 'dart:convert';

enum MessageType { text, image, file, voice, video }
enum MessageStatus { sending, sent, delivered, failed }

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final MessageType type;
  final String content;
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final int? mediaDurationMs; // for voice & video
  final MessageStatus status;
  final int timestamp;
  final int? expiresAt;
  final String? replyToId;
  final String? replyToText;
  final String? replyToSender;
  final bool isEdited;
  final List<String>? editHistory;
  final bool isDeleted;
  final bool isSavedNote;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.type,
    required this.content,
    this.filePath,
    this.fileName,
    this.fileSize,
    this.mediaDurationMs,
    required this.status,
    required this.timestamp,
    this.expiresAt,
    this.replyToId,
    this.replyToText,
    this.replyToSender,
    this.isEdited = false,
    this.editHistory,
    this.isDeleted = false,
    this.isSavedNote = false,
  });

  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? senderName,
    MessageType? type,
    String? content,
    String? filePath,
    String? fileName,
    int? fileSize,
    int? mediaDurationMs,
    MessageStatus? status,
    int? timestamp,
    int? expiresAt,
    String? replyToId,
    String? replyToText,
    String? replyToSender,
    bool? isEdited,
    List<String>? editHistory,
    bool? isDeleted,
    bool? isSavedNote,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      type: type ?? this.type,
      content: content ?? this.content,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mediaDurationMs: mediaDurationMs ?? this.mediaDurationMs,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      expiresAt: expiresAt ?? this.expiresAt,
      replyToId: replyToId ?? this.replyToId,
      replyToText: replyToText ?? this.replyToText,
      replyToSender: replyToSender ?? this.replyToSender,
      isEdited: isEdited ?? this.isEdited,
      editHistory: editHistory ?? this.editHistory,
      isDeleted: isDeleted ?? this.isDeleted,
      isSavedNote: isSavedNote ?? this.isSavedNote,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversationId': conversationId,
      'senderId': senderId,
      'senderName': senderName,
      'type': type.name,
      'content': content,
      'filePath': filePath,
      'fileName': fileName,
      'fileSize': fileSize,
      'mediaDurationMs': mediaDurationMs,
      'status': status.name,
      'timestamp': timestamp,
      'expiresAt': expiresAt,
      'replyToId': replyToId,
      'replyToText': replyToText,
      'replyToSender': replyToSender,
      'isEdited': isEdited ? 1 : 0,
      'editHistory': editHistory != null ? jsonEncode(editHistory) : null,
      'isDeleted': isDeleted ? 1 : 0,
      'isSavedNote': isSavedNote ? 1 : 0,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    List<String>? history;
    if (map['editHistory'] != null && (map['editHistory'] as String).isNotEmpty) {
      try {
        history = List<String>.from(jsonDecode(map['editHistory'] as String) as List);
      } catch (_) {}
    }

    return Message(
      id: map['id'] as String,
      conversationId: map['conversationId'] as String,
      senderId: map['senderId'] as String,
      senderName: map['senderName'] as String,
      type: MessageType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => MessageType.text,
      ),
      content: map['content'] as String? ?? '',
      filePath: map['filePath'] as String?,
      fileName: map['fileName'] as String?,
      fileSize: map['fileSize'] as int?,
      mediaDurationMs: map['mediaDurationMs'] as int?,
      status: MessageStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MessageStatus.sent,
      ),
      timestamp: map['timestamp'] as int,
      expiresAt: map['expiresAt'] as int?,
      replyToId: map['replyToId'] as String?,
      replyToText: map['replyToText'] as String?,
      replyToSender: map['replyToSender'] as String?,
      isEdited: (map['isEdited'] as int? ?? 0) == 1,
      editHistory: history,
      isDeleted: (map['isDeleted'] as int? ?? 0) == 1,
      isSavedNote: (map['isSavedNote'] as int? ?? 0) == 1,
    );
  }
}

class Reaction {
  final String id;
  final String messageId;
  final String contactId;
  final String emoji;
  final int timestamp;

  Reaction({
    required this.id,
    required this.messageId,
    required this.contactId,
    required this.emoji,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'messageId': messageId,
    'contactId': contactId,
    'emoji': emoji,
    'timestamp': timestamp,
  };

  factory Reaction.fromMap(Map<String, dynamic> map) => Reaction(
    id: map['id'] as String,
    messageId: map['messageId'] as String,
    contactId: map['contactId'] as String,
    emoji: map['emoji'] as String,
    timestamp: map['timestamp'] as int,
  );
}
