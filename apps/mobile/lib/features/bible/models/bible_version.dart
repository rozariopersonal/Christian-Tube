class BibleVersion {
  final String id;
  final String name;
  final String shortname;
  final String description;
  final String lang;

  BibleVersion({
    required this.id,
    required this.name,
    required this.shortname,
    required this.description,
    required this.lang,
  });

  factory BibleVersion.fromJson(String id, Map<String, dynamic> json) {
    return BibleVersion(
      id: id,
      name: json['name'] ?? '',
      shortname: json['shortname'] ?? '',
      description: json['description'] ?? '',
      lang: json['lang'] ?? 'English',
    );
  }
}
