import 'book_abbreviation.dart';

/// A single historical, cultural, or archaeological background note for a verse
/// or chapter.
///
/// Designed to present objective antiquity, manners & customs, ancient Near
/// Eastern context, Greco-Roman cultural background, geography, and ancient
/// idioms — strictly avoiding theological interpretations.
class BibleBackgroundNote {
  /// Canonical book number (1-66).
  final int bookNumber;

  /// Chapter number.
  final int chapter;

  /// Verse number (0 represents a whole-chapter historical overview).
  final int verse;

  /// Unique identifier of the note from the dataset.
  final String id;

  /// Topic or keyword of the cultural note (e.g. "Roman Mile", "Sabbath Rest").
  final String topic;

  /// Original language phrase or target quote, if present.
  final String? quote;

  /// Explanatory text detailing the historical and cultural context.
  final String text;

  /// Attribution source (e.g. "unfoldingWord Cultural Context").
  final String source;

  const BibleBackgroundNote({
    required this.bookNumber,
    required this.chapter,
    required this.verse,
    required this.id,
    required this.topic,
    this.quote,
    required this.text,
    this.source = 'unfoldingWord Cultural Context',
  });

  /// 3-letter abbreviation of the book (e.g. "GEN", "MAT").
  String get bookAbbreviation =>
      BookAbbreviation.abbreviationFor(bookNumber) ?? bookNumber.toString();

  /// Whether this note provides chapter-level context rather than a single verse.
  bool get isChapterOverview => verse == 0;

  /// Display reference label such as "MAT 5:41" or "MAT 5 (Overview)".
  String get referenceLabel {
    if (isChapterOverview) {
      return '$bookAbbreviation $chapter (Overview)';
    }
    return '$bookAbbreviation $chapter:$verse';
  }

  factory BibleBackgroundNote.fromMap(Map<String, dynamic> map) {
    return BibleBackgroundNote(
      bookNumber: map['book_number'] as int? ?? map['bookNumber'] as int? ?? 1,
      chapter: map['chapter'] as int? ?? 1,
      verse: map['verse'] as int? ?? 0,
      id: map['note_id']?.toString() ?? map['id']?.toString() ?? '',
      topic: map['topic']?.toString() ?? 'Historical Context',
      quote: map['quote']?.toString(),
      text: map['text']?.toString() ?? map['content']?.toString() ?? '',
      source: map['source']?.toString() ?? 'unfoldingWord Cultural Context',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'book_number': bookNumber,
      'chapter': chapter,
      'verse': verse,
      'id': id,
      'topic': topic,
      'quote': quote,
      'content': text,
      'source': source,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is BibleBackgroundNote &&
      other.bookNumber == bookNumber &&
      other.chapter == chapter &&
      other.verse == verse &&
      other.id == id;

  @override
  int get hashCode => Object.hash(bookNumber, chapter, verse, id);
}
