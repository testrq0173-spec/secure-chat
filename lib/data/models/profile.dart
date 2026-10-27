class Profile {
  final String id;
  final String displayName;
  final String? username;
  final String? photoPath;
  final bool isIncognito;
  final bool isHidden;
  final int createdAt;

  Profile({
    required this.id,
    required this.displayName,
    this.username,
    this.photoPath,
    this.isIncognito = false,
    this.isHidden = false,
    required this.createdAt,
  });

  Profile copyWith({
    String? id,
    String? displayName,
    String? username,
    String? photoPath,
    bool? isIncognito,
    bool? isHidden,
    int? createdAt,
  }) {
    return Profile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      photoPath: photoPath ?? this.photoPath,
      isIncognito: isIncognito ?? this.isIncognito,
      isHidden: isHidden ?? this.isHidden,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayName': displayName,
      'username': username,
      'photoPath': photoPath,
      'isIncognito': isIncognito ? 1 : 0,
      'isHidden': isHidden ? 1 : 0,
      'createdAt': createdAt,
    };
  }

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      displayName: map['displayName'] as String,
      username: map['username'] as String?,
      photoPath: map['photoPath'] as String?,
      isIncognito: (map['isIncognito'] as int? ?? 0) == 1,
      isHidden: (map['isHidden'] as int? ?? 0) == 1,
      createdAt: map['createdAt'] as int,
    );
  }
}
