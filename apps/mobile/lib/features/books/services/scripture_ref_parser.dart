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
    r'(?:^|\s)(?:([123]\s*)?[\p{L}\p{M}]{2,30}(?:\s+(?:of|இராஜாக்கள்|சாமுவேல்|நாளாகமம்|கொரிந்தியர்|தெசலோனிக்கேயர்|தீமோத்தேயு|பேதுரு|யோவான்)\s+[\p{L}\p{M}]{2,30})?\.?)\s+(\d+)[:\.](\d+)(?:[-–](\d+))?(?:\s|$|[,\.;:!?\)])',
    unicode: true,
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
    // Tamil book names and abbreviations
    'ஆதியாகமம்': 1, 'ஆதி': 1,
    'யாத்திராகமம்': 2, 'யாத்': 2,
    'லேவியராகமம்': 3, 'லேவி': 3,
    'எண்ணாகமம்': 4, 'எண்': 4,
    'உபாகமம்': 5, 'உபா': 5,
    'யோசுவா': 6, 'யோசு': 6,
    'நியாயாதிபதிகள்': 7, 'நியா': 7,
    'ரூத்': 8,
    '1 சாமுவேல்': 9, '1சாமுவேல்': 9, '1 சாமு': 9,
    '2 சாமுவேல்': 10, '2சாமுவேல்': 10, '2 சாமு': 10,
    '1 இராஜாக்கள்': 11, '1இராஜாக்கள்': 11, '1 இராஜா': 11,
    '2 இராஜாக்கள்': 12, '2இராஜாக்கள்': 12, '2 இராஜா': 12,
    '1 நாளாகமம்': 13, '1நாளாகமம்': 13, '1 நாளா': 13,
    '2 நாளாகமம்': 14, '2நாளாகமம்': 14, '2 நாளா': 14,
    'எஸ்றா': 15,
    'நெகேமியா': 16, 'நெகே': 16,
    'எஸ்தர்': 17, 'எஸ்த': 17,
    'யோபு': 18,
    'சங்கீதம்': 19, 'சங்': 19,
    'நீதிமொழிகள்': 20, 'நீதி': 20,
    'பிரசங்கி': 21, 'பிர': 21,
    'உன்னதப்பாட்டு': 22, 'உன்னதம்': 22,
    'ஏசாயா': 23, 'ஏசா': 23,
    'எரேமியா': 24, 'எரே': 24,
    'புலம்பல்': 25, 'புல': 25,
    'எசேக்கியேல்': 26, 'எசே': 26,
    'தானியேல்': 27, 'தானி': 27,
    'ஓசியா': 28, 'ஓசி': 28,
    'யோவேல்': 29,
    'ஆமோஸ்': 30,
    'ஒபதியா': 31,
    'யோனா': 32,
    'மீகா': 33,
    'நாகூம்': 34,
    'ஆபகூக்': 35,
    'செப்பனியா': 36,
    'ஆகாய்': 37,
    'சகரியா': 38,
    'மல்கியா': 39,
    'மத்தேயு': 40, 'மத்': 40,
    'மாற்கு': 41, 'மாற்': 41,
    'லூக்கா': 42, 'லூக்': 42,
    'யோவான்': 43, 'யோவா': 43,
    'அப்போஸ்தலர்': 44, 'அப்': 44,
    'ரோமர்': 45, 'ரோம': 45,
    '1 கொரிந்தியர்': 46, '1கொரிந்தியர்': 46, '1 கொரி': 46,
    '2 கொரிந்தியர்': 47, '2கொரிந்தியர்': 47, '2 கொரி': 47,
    'கலாத்தியர்': 48, 'கலா': 48,
    'எபேசியர்': 49, 'எபே': 49,
    'பிலிப்பியர்': 50, 'பிலி': 50,
    'கொலோசெயர்': 51, 'கொலோ': 51,
    '1 தெசலோனிக்கேயர்': 52, '1தெசலோனிக்கேயர்': 52, '1 தெச': 52,
    '2 தெசலோனிக்கேயர்': 53, '2தெசலோனிக்கேயர்': 53, '2 தெச': 53,
    '1 தீமோத்தேயு': 54, '1தீமோத்தேயு': 54, '1 தீமோ': 54,
    '2 தீமோத்தேயு': 55, '2தீமோத்தேயு': 55, '2 தீமோ': 55,
    'தீத்து': 56,
    'பிலேமோன்': 57, 'பிலே': 57,
    'எபிரெயர்': 58, 'எபி': 58,
    'யாக்கோபு': 59, 'யாக்': 59,
    '1 பேதுரு': 60, '1பேதுரு': 60, '1 பேது': 60,
    '2 பேதுரு': 61, '2பேதுரு': 61, '2 பேது': 61,
    '1 யோவான்': 62, '1யோவான்': 62, '1 யோவா': 62,
    '2 யோவான்': 63, '2யோவான்': 63, '2 யோவா': 63,
    '3 யோவான்': 64, '3யோவான்': 64, '3 யோவா': 64,
    'யூதா': 65,
    'வெளிப்படுத்தின விசேஷம்': 66, 'வெளிப்படுத்தல்': 66, 'வெளி': 66,
  };

  static ParsedScriptureRef? parse(String citation) {
    final match = scriptureRegex.firstMatch(citation);
    if (match == null) return null;

    final fullMatch = match.group(0)!;
    int splitIdx = fullMatch.indexOf(':');
    if (splitIdx == -1) splitIdx = fullMatch.lastIndexOf('.');
    if (splitIdx == -1) return null;

    final beforeColon = fullMatch.substring(0, splitIdx).trim();
    final afterColon = fullMatch.substring(splitIdx + 1).trim();

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
