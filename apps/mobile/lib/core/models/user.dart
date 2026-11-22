class User {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? idToken;
  final DateTime? lastSyncedAt;
  final bool isGuest;

  const User({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.idToken,
    this.lastSyncedAt,
    this.isGuest = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? json['userId'] ?? json['_id'] ?? '').toString();
    final inferredGuest = id.startsWith('guest_') || id.startsWith('user_');
    return User(
      id: id,
      email: (json['email'] ?? '').toString(),
      displayName: (json['displayName'] ?? json['name'] ?? 'User').toString(),
      photoUrl: (json['photoUrl'] ?? json['avatarUrl'] ?? json['picture']) as String?,
      idToken: (json['idToken'] ?? json['token']) as String?,
      lastSyncedAt: json['lastSyncedAt'] != null
          ? DateTime.tryParse(json['lastSyncedAt'].toString())
          : null,
      isGuest: json['isGuest'] == true || (json['isGuest'] == null && inferredGuest),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'idToken': idToken,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'isGuest': isGuest,
    };
  }
}
