class Contact {
  final String id;
  final String profileId;
  final String displayName;
  final String? avatarUrl;
  final bool isVerified;
  final String securityCode;
  final String sendQueueId;
  final String receiveQueueId;
  final String peerPublicKey; // Base64
  final String? ratchetStateJson;
  final int disappearingDurationSeconds; // 0 = off
  final bool isMuted;
  final bool isBlocked;
  final bool isReusableAddress;
  final int createdAt;

  Contact({
    required this.id,
    required this.profileId,
    required this.displayName,
    this.avatarUrl,
    this.isVerified = false,
    required this.securityCode,
    required this.sendQueueId,
    required this.receiveQueueId,
    required this.peerPublicKey,
    this.ratchetStateJson,
    this.disappearingDurationSeconds = 0,
    this.isMuted = false,
    this.isBlocked = false,
    this.isReusableAddress = false,
    required this.createdAt,
  });

  Contact copyWith({
    String? id,
    String? profileId,
    String? displayName,
    String? avatarUrl,
    bool? isVerified,
    String? securityCode,
    String? sendQueueId,
    String? receiveQueueId,
    String? peerPublicKey,
    String? ratchetStateJson,
    int? disappearingDurationSeconds,
    bool? isMuted,
    bool? isBlocked,
    bool? isReusableAddress,
    int? createdAt,
  }) {
    return Contact(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isVerified: isVerified ?? this.isVerified,
      securityCode: securityCode ?? this.securityCode,
      sendQueueId: sendQueueId ?? this.sendQueueId,
      receiveQueueId: receiveQueueId ?? this.receiveQueueId,
      peerPublicKey: peerPublicKey ?? this.peerPublicKey,
      ratchetStateJson: ratchetStateJson ?? this.ratchetStateJson,
      disappearingDurationSeconds: disappearingDurationSeconds ?? this.disappearingDurationSeconds,
      isMuted: isMuted ?? this.isMuted,
      isBlocked: isBlocked ?? this.isBlocked,
      isReusableAddress: isReusableAddress ?? this.isReusableAddress,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'profileId': profileId,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'isVerified': isVerified ? 1 : 0,
      'securityCode': securityCode,
      'sendQueueId': sendQueueId,
      'receiveQueueId': receiveQueueId,
      'peerPublicKey': peerPublicKey,
      'ratchetStateJson': ratchetStateJson,
      'disappearingDurationSeconds': disappearingDurationSeconds,
      'isMuted': isMuted ? 1 : 0,
      'isBlocked': isBlocked ? 1 : 0,
      'isReusableAddress': isReusableAddress ? 1 : 0,
      'createdAt': createdAt,
    };
  }

  factory Contact.fromMap(Map<String, dynamic> map) {
    return Contact(
      id: map['id'] as String,
      profileId: map['profileId'] as String,
      displayName: map['displayName'] as String,
      avatarUrl: map['avatarUrl'] as String?,
      isVerified: (map['isVerified'] as int? ?? 0) == 1,
      securityCode: map['securityCode'] as String? ?? '',
      sendQueueId: map['sendQueueId'] as String,
      receiveQueueId: map['receiveQueueId'] as String,
      peerPublicKey: map['peerPublicKey'] as String,
      ratchetStateJson: map['ratchetStateJson'] as String?,
      disappearingDurationSeconds: map['disappearingDurationSeconds'] as int? ?? 0,
      isMuted: (map['isMuted'] as int? ?? 0) == 1,
      isBlocked: (map['isBlocked'] as int? ?? 0) == 1,
      isReusableAddress: (map['isReusableAddress'] as int? ?? 0) == 1,
      createdAt: map['createdAt'] as int,
    );
  }
}
