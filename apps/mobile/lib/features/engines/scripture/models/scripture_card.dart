class ScriptureCard {
  final String id;
  final int bookNumber;
  final String bookName;
  final int chapter;
  final int startVerse;
  final int endVerse;
  final String referenceLabel;
  final String category;
  final String backgroundPreset;
  final List<String> tags;

  // Live state per card
  String? resolvedText;
  String? resolvedVersion;
  bool isSaved;
  String? customBackgroundPreset;
  String? customFontFamily;

  ScriptureCard({
    required this.id,
    required this.bookNumber,
    required this.bookName,
    required this.chapter,
    required this.startVerse,
    required this.endVerse,
    required this.referenceLabel,
    this.category = 'General',
    this.backgroundPreset = 'mountain_dawn',
    this.tags = const [],
    this.resolvedText,
    this.resolvedVersion,
    this.isSaved = false,
    this.customBackgroundPreset,
    this.customFontFamily,
  });

  String get activeBackground => customBackgroundPreset ?? backgroundPreset;

  factory ScriptureCard.fromJson(Map<String, dynamic> json) {
    return ScriptureCard(
      id: json['id'] ??
          '${json['bookNumber']}_${json['chapter']}_${json['startVerse']}',
      bookNumber: json['bookNumber'] ?? 43,
      bookName: json['bookName'] ?? 'John',
      chapter: json['chapter'] ?? 3,
      startVerse: json['startVerse'] ?? 16,
      endVerse: json['endVerse'] ?? json['startVerse'] ?? 16,
      referenceLabel: json['referenceLabel'] ??
          '${json['bookName']} ${json['chapter']}:${json['startVerse']}',
      category: json['category'] ?? 'General',
      backgroundPreset: json['backgroundPreset'] ?? 'mountain_dawn',
      tags: json['tags'] != null ? List<String>.from(json['tags']) : const [],
      resolvedText: json['text'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookNumber': bookNumber,
        'bookName': bookName,
        'chapter': chapter,
        'startVerse': startVerse,
        'endVerse': endVerse,
        'referenceLabel': referenceLabel,
        'category': category,
        'backgroundPreset': backgroundPreset,
        'tags': tags,
      };
}
