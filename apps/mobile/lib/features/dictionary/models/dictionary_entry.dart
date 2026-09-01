/// Model representing a dictionary definition or lexical entry.
class DictionaryEntry {
  final String headword;
  final String partOfSpeech;
  final String phonetic;
  final String definition;
  final String examples;
  final String source;

  const DictionaryEntry({
    required this.headword,
    this.partOfSpeech = '',
    this.phonetic = '',
    required this.definition,
    this.examples = '',
    this.source = 'Dictionary',
  });

  factory DictionaryEntry.fromMap(Map<String, dynamic> map, {String source = 'Dictionary'}) {
    return DictionaryEntry(
      headword: map['headword'] as String? ?? map['word'] as String? ?? '',
      partOfSpeech: map['part_of_speech'] as String? ?? map['pos'] as String? ?? '',
      phonetic: map['phonetic'] as String? ?? map['pronunciation'] as String? ?? '',
      definition: map['definition'] as String? ?? map['meaning'] as String? ?? '',
      examples: map['examples'] as String? ?? '',
      source: source,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'headword': headword,
      'part_of_speech': partOfSpeech,
      'phonetic': phonetic,
      'definition': definition,
      'examples': examples,
      'source': source,
    };
  }
}
