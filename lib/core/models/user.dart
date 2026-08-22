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
    return User(
      id: json['id'] ?? json['userId'] ?? json['_id'] ?? '',
      email: json['email'] ?? '',
      displayName: json['displayName'] ?? json['name'] ?? 'User',
      photoUrl: json['photoUrl'] ?? json['avatarUrl'] ?? json['picture'],
      idToken: json['idToken'] ?? json['token'],
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
