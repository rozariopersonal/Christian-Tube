class BibleVersionMeta {
  final String id;
  final String name;
  final String language;
  final String languageCode;
  final String sizeDisplay;
  final String description;
  final bool isDefaultBundled;
  final bool isOnlineOnly;
  final String? downloadUrl;

  const BibleVersionMeta({
    required this.id,
    required this.name,
    required this.language,
    required this.languageCode,
    required this.sizeDisplay,
    required this.description,
    this.isDefaultBundled = false,
    this.isOnlineOnly = false,
    this.downloadUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'language': language,
        'languageCode': languageCode,
        'sizeDisplay': sizeDisplay,
        'description': description,
        'isDefaultBundled': isDefaultBundled,
        'isOnlineOnly': isOnlineOnly,
        'downloadUrl': downloadUrl,
      };

  factory BibleVersionMeta.fromJson(Map<String, dynamic> json) =>
      BibleVersionMeta(
        id: json['id'],
        name: json['name'],
        language: json['language'],
        languageCode: json['languageCode'],
        sizeDisplay: json['sizeDisplay'],
        description: json['description'],
        isDefaultBundled: json['isDefaultBundled'] ?? false,
        isOnlineOnly: json['isOnlineOnly'] ?? false,
        downloadUrl: json['downloadUrl'],
      );
}
