class BibleVerse {
  final int number;
  final String text;
  final int? endNumber;
  final String? verseSpan;
  final bool isChapterHeader;
  final String? chapterTitle;
  final String? versionLabel;
  final bool isSecondary;

  /// Number of cross-references for this verse. 0 hides the cross-reference
  /// badge and expansion; >0 shows a badge and enables inline expansion.
  final int crossReferenceCount;

  BibleVerse({
    required this.number,
    required this.text,
    this.endNumber,
    this.verseSpan,
    this.isChapterHeader = false,
    this.chapterTitle,
    this.versionLabel,
    this.isSecondary = false,
    this.crossReferenceCount = 0,
  });

  /// The formatted display string for the verse number or combined verse span
  /// (e.g. '9-11' or '9').
  String get verseDisplay =>
      verseSpan ?? (endNumber != null && endNumber! > number ? '$number-$endNumber' : '$number');
}

/// Formats a list or set of verse numbers into grouped ranges
/// (e.g. `[1, 2, 3, 5]` -> `"1-3, 5"`, `[1, 5]` -> `"1, 5"`).
String formatVerseNumbers(Iterable<int> verseNumbers) {
  if (verseNumbers.isEmpty) return '';
  final sorted = verseNumbers.toSet().toList()..sort();
  if (sorted.length == 1) return '${sorted.first}';

  final ranges = <String>[];
  var start = sorted.first;
  var end = start;

  for (var i = 1; i < sorted.length; i++) {
    final v = sorted[i];
    if (v == end + 1) {
      end = v;
    } else {
      ranges.add(start == end ? '$start' : '$start-$end');
      start = v;
      end = v;
    }
  }
  ranges.add(start == end ? '$start' : '$start-$end');

  return ranges.join(', ');
}

