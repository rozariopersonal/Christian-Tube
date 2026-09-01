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
  final String license;
  final String? licenseUrl;
  final String? copyrightHolder;
  final String? attributionText;
  final String? sourceUrl;

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
    this.license = 'Public Domain',
    this.licenseUrl,
    this.copyrightHolder,
    this.attributionText,
    this.sourceUrl,
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
        'license': license,
        'licenseUrl': licenseUrl,
        'copyrightHolder': copyrightHolder,
        'attributionText': attributionText,
        'sourceUrl': sourceUrl,
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
        license: json['license'] ?? 'Public Domain',
        licenseUrl: json['licenseUrl'],
        copyrightHolder: json['copyrightHolder'],
        attributionText: json['attributionText'],
        sourceUrl: json['sourceUrl'],
      );
}
