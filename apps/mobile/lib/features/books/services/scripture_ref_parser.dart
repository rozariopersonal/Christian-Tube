import '../../engines/scripture/services/book_name_service.dart';

class ParsedScriptureRef {
  final int bookNumber;
  final String bookName;
  final int chapter;
  final int startVerse;
  final int? endVerse;
  final String rawMatch;

  const ParsedScriptureRef({
    required this.bookNumber,
    required this.bookName,
    required this.chapter,
    required this.startVerse,
    this.endVerse,
    required this.rawMatch,
  });
}

class ScriptureRefParser {
  static final RegExp scriptureRegex = RegExp(
    r'\b(?:([123]\s*)?[A-Z][a-z]+(?:\.|\b))\s+(\d+):(\d+)(?:[-–](\d+))?\b',
  );

  static const Map<String, int> _abbrevToBookNum = {
    'gen': 1, 'genesis': 1,
    'ex': 2, 'exod': 2, 'exodus': 2,
    'lev': 3, 'leviticus': 3,
    'num': 4, 'numbers': 4,
    'deut': 5, 'deuteronomy': 5,
    'josh': 6, 'joshua': 6,
    'judg': 7, 'judges': 7,
    'ruth': 8,
    '1 sam': 9, '1 samuel': 9, '1sam': 9,
    '2 sam': 10, '2 samuel': 10, '2sam': 10,
    '1 kings': 11, '1 kgs': 11, '1kings': 11,
    '2 kings': 12, '2 kgs': 12, '2kings': 12,
    '1 chron': 13, '1 chronicles': 13, '1 chr': 13,
    '2 chron': 14, '2 chronicles': 14, '2 chr': 14,
    'ezra': 15,
    'neh': 16, 'nehemiah': 16,
    'esth': 17, 'esther': 17,
    'job': 18,
    'ps': 19, 'psalm': 19, 'psalms': 19,
    'prov': 20, 'proverbs': 20,
    'eccl': 21, 'ecclesiastes': 21,
    'song': 22, 'song of solomon': 22,
    'isa': 23, 'isaiah': 23,
    'jer': 24, 'jeremiah': 24,
    'lam': 25, 'lamentations': 25,
    'ezek': 26, 'ezekiel': 26,
    'dan': 27, 'daniel': 27,
    'hos': 28, 'hosea': 28,
    'joel': 29,
    'amos': 30,
    'obad': 31, 'obadiah': 31,
    'jonah': 32, 'jon': 32,
    'mic': 33, 'micah': 33,
    'nah': 34, 'nahum': 34,
    'hab': 35, 'habakkuk': 35,
    'zeph': 36, 'zephaniah': 36,
    'hag': 37, 'haggai': 37,
    'zech': 38, 'zechariah': 38,
    'mal': 39, 'malachi': 39,
    'matt': 40, 'matthew': 40, 'mat': 40,
    'mark': 41, 'mrk': 41,
    'luke': 42, 'luk': 42,
    'john': 43, 'jhn': 43,
    'acts': 44, 'act': 44,
    'rom': 45, 'romans': 45,
    '1 cor': 46, '1 corinthians': 46, '1cor': 46,
    '2 cor': 47, '2 corinthians': 47, '2cor': 47,
    'gal': 48, 'galatians': 48,
    'eph': 49, 'ephesians': 49,
    'phil': 50, 'philippians': 50,
    'col': 51, 'colossians': 51,
    '1 thess': 52, '1 thessalonians': 52,
    '2 thess': 53, '2 thessalonians': 53,
    '1 tim': 54, '1 timothy': 54,
    '2 tim': 55, '2 timothy': 55,
    'titus': 56, 'tit': 56,
    'phlm': 57, 'philemon': 57,
    'heb': 58, 'hebrews': 58,
    'jas': 59, 'james': 59,
    '1 pet': 60, '1 peter': 60,
    '2 pet': 61, '2 peter': 61,
    '1 john': 62, '1 jhn': 62,
    '2 john': 63, '2 jhn': 63,
    '3 john': 64, '3 jhn': 64,
    'jude': 65,
    'rev': 66, 'revelation': 66,
  };

  static ParsedScriptureRef? parse(String citation) {
    final match = scriptureRegex.firstMatch(citation);
    if (match == null) return null;

    final fullMatch = match.group(0)!;
    final colonIdx = fullMatch.indexOf(':');
    if (colonIdx == -1) return null;

    final beforeColon = fullMatch.substring(0, colonIdx).trim();
    final afterColon = fullMatch.substring(colonIdx + 1).trim();

    final lastSpace = beforeColon.lastIndexOf(' ');
    if (lastSpace == -1) return null;

    final bookPart = beforeColon.substring(0, lastSpace).trim().toLowerCase().replaceAll('.', '');
    final chapterPart = beforeColon.substring(lastSpace + 1).trim();
    final chapter = int.tryParse(chapterPart) ?? 1;

    int startVerse = 1;
    int? endVerse;

    if (afterColon.contains('-') || afterColon.contains('–')) {
      final dash = afterColon.contains('-') ? '-' : '–';
      final parts = afterColon.split(dash);
      startVerse = int.tryParse(parts[0].trim()) ?? 1;
      if (parts.length > 1) {
        endVerse = int.tryParse(parts[1].trim());
      }
    } else {
      startVerse = int.tryParse(afterColon) ?? 1;
    }

    final bookNum = _abbrevToBookNum[bookPart];
    if (bookNum == null) return null;

    final canonName = BookNameService.englishNameFor(bookNum);

    return ParsedScriptureRef(
      bookNumber: bookNum,
      bookName: canonName,
      chapter: chapter,
      startVerse: startVerse,
      endVerse: endVerse,
      rawMatch: fullMatch,
    );
  }
}
