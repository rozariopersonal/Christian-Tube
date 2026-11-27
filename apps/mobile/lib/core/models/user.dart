class User {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? idToken;
  final DateTime? lastSyncedAt;

  const User({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.idToken,
    this.lastSyncedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? json['userId'] ?? json['_id'] ?? '').toString();
    return User(
      id: id,
      email: (json['email'] ?? '').toString(),
      displayName: (json['displayName'] ?? json['name'] ?? 'User').toString(),
      photoUrl: (json['photoUrl'] ?? json['avatarUrl'] ?? json['picture']) as String?,
      idToken: (json['idToken'] ?? json['token']) as String?,
      lastSyncedAt: json['lastSyncedAt'] != null
          ? DateTime.tryParse(json['lastSyncedAt'].toString())
          : null,
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
    };
  }
}
