import 'dart:typed_data';

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
  final Map<String, dynamic>? verseMappings;

  // Live state per card
  String? resolvedText;
  String? resolvedVersion;
  bool isSaved;
  String? customBackgroundPreset;
  String? customFontFamily;
  Uint8List? precomputedImageBytes;
  String? precomputedImageKey;

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
    this.verseMappings,
    this.resolvedText,
    this.resolvedVersion,
    this.isSaved = false,
    this.customBackgroundPreset,
    this.customFontFamily,
  });

  String get activeBackground => customBackgroundPreset ?? backgroundPreset;

  factory ScriptureCard.fromJson(Map<String, dynamic> json) {
    return ScriptureCard(
      id: json['id']?.toString() ??
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
      customBackgroundPreset: json['customBackgroundPreset'],
      tags: json['tags'] != null ? List<String>.from(json['tags']) : const [],
      verseMappings: json['verseMappings'] != null ? Map<String, dynamic>.from(json['verseMappings']) : null,
      resolvedText: json['resolvedText'] ?? json['text'],
      resolvedVersion: json['resolvedVersion'],
      isSaved: json['isSaved'] ?? false,
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
        'customBackgroundPreset': customBackgroundPreset,
        'tags': tags,
        'verseMappings': verseMappings,
        'resolvedText': resolvedText,
        'resolvedVersion': resolvedVersion,
        'isSaved': isSaved,
      };
}
