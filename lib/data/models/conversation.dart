enum ConversationType { direct, group, notes }

class Conversation {
  final String id;
  final ConversationType type;
  final String title;
  final String? avatarUrl;
  final String? lastMessageText;
  final int? lastMessageTime;
  final int unreadCount;
  final bool isMuted;
  final bool isArchived;
  final int disappearingDurationSeconds;
  final String? draftText;
  final String? contactId;
  final String? groupId;
  final bool isVerified;

  Conversation({
    required this.id,
    required this.type,
    required this.title,
    this.avatarUrl,
    this.lastMessageText,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isMuted = false,
    this.isArchived = false,
    this.disappearingDurationSeconds = 0,
    this.draftText,
    this.contactId,
    this.groupId,
    this.isVerified = false,
  });

  Conversation copyWith({
    String? id,
    ConversationType? type,
    String? title,
    String? avatarUrl,
    String? lastMessageText,
    int? lastMessageTime,
    int? unreadCount,
    bool? isMuted,
    bool? isArchived,
    int? disappearingDurationSeconds,
    String? draftText,
    String? contactId,
    String? groupId,
    bool? isVerified,
  }) {
    return Conversation(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isMuted: isMuted ?? this.isMuted,
      isArchived: isArchived ?? this.isArchived,
      disappearingDurationSeconds: disappearingDurationSeconds ?? this.disappearingDurationSeconds,
      draftText: draftText ?? this.draftText,
      contactId: contactId ?? this.contactId,
      groupId: groupId ?? this.groupId,
      isVerified: isVerified ?? this.isVerified,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'avatarUrl': avatarUrl,
      'lastMessageText': lastMessageText,
      'lastMessageTime': lastMessageTime,
      'unreadCount': unreadCount,
      'isMuted': isMuted ? 1 : 0,
      'isArchived': isArchived ? 1 : 0,
      'disappearingDurationSeconds': disappearingDurationSeconds,
      'draftText': draftText,
      'contactId': contactId,
      'groupId': groupId,
      'isVerified': isVerified ? 1 : 0,
    };
  }

  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      id: map['id'] as String,
      type: ConversationType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => ConversationType.direct,
      ),
      title: map['title'] as String,
      avatarUrl: map['avatarUrl'] as String?,
      lastMessageText: map['lastMessageText'] as String?,
      lastMessageTime: map['lastMessageTime'] as int?,
      unreadCount: map['unreadCount'] as int? ?? 0,
      isMuted: (map['isMuted'] as int? ?? 0) == 1,
      isArchived: (map['isArchived'] as int? ?? 0) == 1,
      disappearingDurationSeconds: map['disappearingDurationSeconds'] as int? ?? 0,
      draftText: map['draftText'] as String?,
      contactId: map['contactId'] as String?,
      groupId: map['groupId'] as String?,
      isVerified: (map['isVerified'] as int? ?? 0) == 1,
    );
  }
}
