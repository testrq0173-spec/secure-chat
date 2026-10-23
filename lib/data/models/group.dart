enum GroupRole { owner, admin, member }

class Group {
  final String id;
  final String name;
  final String? avatar;
  final GroupRole myRole;
  final String inviteLink;
  final int createdAt;

  Group({
    required this.id,
    required this.name,
    this.avatar,
    required this.myRole,
    required this.inviteLink,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'avatar': avatar,
    'myRole': myRole.name,
    'inviteLink': inviteLink,
    'createdAt': createdAt,
  };

  factory Group.fromMap(Map<String, dynamic> map) => Group(
    id: map['id'] as String,
    name: map['name'] as String,
    avatar: map['avatar'] as String?,
    myRole: GroupRole.values.firstWhere(
      (e) => e.name == map['myRole'],
      orElse: () => GroupRole.member,
    ),
    inviteLink: map['inviteLink'] as String,
    createdAt: map['createdAt'] as int,
  );
}

class GroupMember {
  final String groupId;
  final String contactId;
  final String displayName;
  final GroupRole role;
  final int joinedAt;

  GroupMember({
    required this.groupId,
    required this.contactId,
    required this.displayName,
    required this.role,
    required this.joinedAt,
  });

  Map<String, dynamic> toMap() => {
    'groupId': groupId,
    'contactId': contactId,
    'displayName': displayName,
    'role': role.name,
    'joinedAt': joinedAt,
  };

  factory GroupMember.fromMap(Map<String, dynamic> map) => GroupMember(
    groupId: map['groupId'] as String,
    contactId: map['contactId'] as String,
    displayName: map['displayName'] as String,
    role: GroupRole.values.firstWhere(
      (e) => e.name == map['role'],
      orElse: () => GroupRole.member,
    ),
    joinedAt: map['joinedAt'] as int,
  );
}
