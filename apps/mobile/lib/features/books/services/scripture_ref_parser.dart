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

/// Represents either a chunk of regular prose text or a recognized Bible citation.
class ScriptureSpanToken {
  final String text;
  final ParsedScriptureRef? ref;

  const ScriptureSpanToken.text(this.text) : ref = null;
  const ScriptureSpanToken.reference(this.text, this.ref);

  bool get isReference => ref != null;
}

class ScriptureRefParser {
  /// Matches an offline preprocessed tag like `[ref:43.3.16|John 3:16]` or
  /// `[ref:46.13.4-7|1 Cor 13:4-7]`.
  static final RegExp tagRegex = RegExp(
    r'\[ref:(\d+)\.(\d+)\.(\d+)(?:-(\d+))?\|([^\]]+)\]',
  );

  /// Matches a scripture citation without consuming surrounding whitespace or
  /// trailing punctuation.
  ///
  /// The leading boundary is a non-consuming lookbehind (start of string, a
  /// space, an opening bracket/quote, or a semicolon) and the trailing boundary
  /// is a lookahead, so periods, commas, quotes, closing parens, etc. after the
  /// verse stay part of the surrounding prose rather than being swallowed into
  /// the link.
  ///
  /// Capture groups:
  ///  1 = ordinal prefix (`1`, `2`, `3`, `I`, `II`, `III`) with optional period
  ///  2 = book name (single word, or `X of Y` style phrase)
  ///  3 = chapter
  ///  4 = chapter-range end (e.g. the `7` in `Matthew 5-7`)
  ///  5 = verse expression (`16`, `1-4:4`, `23, 24`, ...)
  static final RegExp scriptureRegex = RegExp(
    r'(?:(?<=^)|(?<=[\s\("\u201C;\[]))((?:[123]|I{1,3})\.?\s*)?([\p{L}\p{M}]{2,30}(?:\s+(?:of|இராஜாக்கள்|சாமுவேல்|நாளாகமம்|கொரிந்தியர்|தெசலோனிக்கேயர்|தீமோத்தேயு|பேதுரு|யோவான்)\s+[\p{L}\p{M}]{2,30})?)(?:\.|\s+)\s*(\d+)(?:[-–](\d+))?(?:[:\.]\s*(\d+(?:[-–]\d+(?:[:\.]\d+)?)?(?:,\s*\d+(?:[-–]\d+)?)*))?(?=\s|$|[.;,!?\\)\u201D"–—]|-(?![\d]))',
    unicode: true,
  );

  static const Map<String, int> _abbrevToBookNum = {
    'gen': 1, 'genesis': 1, 'ge': 1, 'gn': 1,
    'ex': 2, 'exod': 2, 'exodus': 2, 'exo': 2,
    'lev': 3, 'leviticus': 3, 'le': 3, 'lv': 3,
    'num': 4, 'numbers': 4, 'nu': 4, 'nm': 4,
    'deut': 5, 'deuteronomy': 5, 'deu': 5, 'dt': 5,
    'josh': 6, 'joshua': 6, 'jos': 6,
    'judg': 7, 'judges': 7, 'jdg': 7,
    'ruth': 8, 'rut': 8,
    '1 sam': 9, '1 samuel': 9, '1sam': 9, '1sa': 9,
    '2 sam': 10, '2 samuel': 10, '2sam': 10, '2sa': 10,
    'i sam': 9, 'i samuel': 9, 'isam': 9,
    'ii sam': 10, 'ii samuel': 10, 'iisam': 10,
    '1 kings': 11, '1 kgs': 11, '1 ki': 11, '1kings': 11, '1ki': 11, '1kgs': 11,
    '2 kings': 12, '2 kgs': 12, '2 ki': 12, '2kings': 12, '2ki': 12, '2kgs': 12,
    'i kings': 11, 'i kgs': 11, 'ikings': 11,
    'ii kings': 12, 'ii kgs': 12, 'iikings': 12,
    '1 chron': 13, '1 chronicles': 13, '1 chr': 13, '1ch': 13, '1chron': 13,
    '2 chron': 14, '2 chronicles': 14, '2 chr': 14, '2ch': 14, '2chron': 14,
    'i chron': 13, 'i chronicles': 13, 'ichron': 13,
    'ii chron': 14, 'ii chronicles': 14, 'iichron': 14,
    'ezra': 15, 'ezr': 15,
    'neh': 16, 'nehemiah': 16,
    'esth': 17, 'esther': 17, 'est': 17,
    'job': 18,
    'ps': 19, 'psalm': 19, 'psalms': 19, 'psa': 19, 'pss': 19,
    'prov': 20, 'proverbs': 20, 'pro': 20, 'prv': 20,
    'eccl': 21, 'ecclesiastes': 21, 'ecc': 21, 'eccles': 21,
    'song': 22, 'song of solomon': 22, 'song of songs': 22, 'sng': 22, 'sos': 22, 'canticles': 22,
    'isa': 23, 'isaiah': 23,
    'jer': 24, 'jeremiah': 24,
    'lam': 25, 'lamentations': 25,
    'ezek': 26, 'ezekiel': 26, 'ezk': 26,
    'dan': 27, 'daniel': 27,
    'hos': 28, 'hosea': 28,
    'joel': 29, 'joe': 29,
    'amos': 30, 'am': 30,
    'obad': 31, 'obadiah': 31, 'oba': 31,
    'jonah': 32, 'jon': 32,
    'mic': 33, 'micah': 33,
    'nah': 34, 'nahum': 34, 'nam': 34,
    'hab': 35, 'habakkuk': 35,
    'zeph': 36, 'zephaniah': 36, 'zep': 36,
    'hag': 37, 'haggai': 37,
    'zech': 38, 'zechariah': 38, 'zec': 38,
    'mal': 39, 'malachi': 39,
    'matt': 40, 'matthew': 40, 'mat': 40, 'mt': 40,
    'mark': 41, 'mrk': 41, 'mk': 41,
    'luke': 42, 'luk': 42, 'lk': 42,
    'john': 43, 'jhn': 43, 'jn': 43,
    'acts': 44, 'act': 44,
    'rom': 45, 'romans': 45, 'ro': 45,
    '1 cor': 46, '1 corinthians': 46, '1cor': 46, '1co': 46,
    '2 cor': 47, '2 corinthians': 47, '2cor': 47, '2co': 47,
    'i cor': 46, 'i corinthians': 46, 'icor': 46,
    'ii cor': 47, 'ii corinthians': 47, 'iicor': 47,
    'gal': 48, 'galatians': 48,
    'eph': 49, 'ephesians': 49,
    'phil': 50, 'philippians': 50, 'php': 50,
    'col': 51, 'colossians': 51,
    '1 thess': 52, '1 thessalonians': 52, '1thess': 52, '1th': 52, '1 th': 52,
    '2 thess': 53, '2 thessalonians': 53, '2thess': 53, '2th': 53, '2 th': 53,
    'i thess': 52, 'i thessalonians': 52, 'ithess': 52,
    'ii thess': 53, 'ii thessalonians': 53, 'iithess': 53,
    '1 tim': 54, '1 timothy': 54, '1tim': 54, '1ti': 54, '1 ti': 54,
    '2 tim': 55, '2 timothy': 55, '2tim': 55, '2ti': 55, '2 ti': 55,
    'i tim': 54, 'i timothy': 54, 'itim': 54,
    'ii tim': 55, 'ii timothy': 55, 'iitim': 55,
    'titus': 56, 'tit': 56,
    'phlm': 57, 'philemon': 57, 'phm': 57, 'philem': 57,
    'heb': 58, 'hebrews': 58,
    'jas': 59, 'james': 59,
    '1 pet': 60, '1 peter': 60, '1pet': 60, '1pe': 60, '1 pe': 60,
    '2 pet': 61, '2 peter': 61, '2pet': 61, '2pe': 61, '2 pe': 61,
    'i pet': 60, 'i peter': 60, 'ipet': 60,
    'ii pet': 61, 'ii peter': 61, 'iipet': 61,
    '1 john': 62, '1 jhn': 62, '1 jn': 62, '1jn': 62, '1john': 62,
    '2 john': 63, '2 jhn': 63, '2 jn': 63, '2jn': 63, '2john': 63,
    '3 john': 64, '3 jhn': 64, '3 jn': 64, '3jn': 64, '3john': 64,
    'i john': 62, 'i jhn': 62, 'i jn': 62, 'ijohn': 62,
    'ii john': 63, 'ii jhn': 63, 'ii jn': 63, 'iijohn': 63,
    'iii john': 64, 'iii jhn': 64, 'iii jn': 64, 'iiijohn': 64,
    'jude': 65, 'jud': 65,
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
    '1 சாமுவேல்': 9, '1சாமுவேல்': 9, '1 சாமு': 9, '1சாமு': 9,
    '2 சாமுவேல்': 10, '2சாமுவேல்': 10, '2 சாமு': 10, '2சாமு': 10,
    '1 இராஜாக்கள்': 11, '1இராஜாக்கள்': 11, '1 இராஜா': 11, '1இராஜா': 11,
    '2 இராஜாக்கள்': 12, '2இராஜாக்கள்': 12, '2 இராஜா': 12, '2இராஜா': 12,
    '1 நாளாகமம்': 13, '1நாளாகமம்': 13, '1 நாளா': 13, '1நாளா': 13,
    '2 நாளாகமம்': 14, '2நாளாகமம்': 14, '2 நாளா': 14, '2நாளா': 14,
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
    '1 கொரிந்தியர்': 46, '1கொரிந்தியர்': 46, '1 கொரி': 46, '1கொரி': 46,
    '2 கொரிந்தியர்': 47, '2கொரிந்தியர்': 47, '2 கொரி': 47, '2கொரி': 47,
    'கலாத்தியர்': 48, 'கலா': 48,
    'எபேசியர்': 49, 'எபே': 49,
    'பிலிப்பியர்': 50, 'பிலி': 50,
    'கொலோசெயர்': 51, 'கொலோ': 51,
    '1 தெசலோனிக்கேயர்': 52, '1தெசலோனிக்கேயர்': 52, '1 தெச': 52, '1தெச': 52,
    '2 தெசலோனிக்கேயர்': 53, '2தெசலோனிக்கேயர்': 53, '2 தெச': 53, '2தெச': 53,
    '1 தீமோத்தேயு': 54, '1தீமோத்தேயு': 54, '1 தீமோ': 54, '1தீமோ': 54,
    '2 தீமோத்தேயு': 55, '2தீமோத்தேயு': 55, '2 தீமோ': 55, '2தீமோ': 55,
    'தீத்து': 56,
    'பிலேமோன்': 57, 'பிலே': 57,
    'எபிரெயர்': 58, 'எபி': 58,
    'யாக்கோபு': 59, 'யாக்': 59,
    '1 பேதுரு': 60, '1பேதுரு': 60, '1 பேது': 60, '1பேது': 60,
    '2 பேதுரு': 61, '2பேதுரு': 61, '2 பேது': 61, '2பேது': 61,
    '1 யோவான்': 62, '1யோவான்': 62, '1 யோவா': 62, '1யோவா': 62,
    '2 யோவான்': 63, '2யோவான்': 63, '2 யோவா': 63, '2யோவா': 63,
    '3 யோவான்': 64, '3யோவான்': 64, '3 யோவா': 64, '3யோவா': 64,
    'யூதா': 65,
    'வெளிப்படுத்தின விசேஷம்': 66, 'வெளிப்படுத்தல்': 66, 'வெளி': 66,
  };

  /// Merged localized book names loaded from [BookNameService] (backed by the
  /// releases repo's `book_names.json`). Keyed by a normalized book phrase (a
  /// single word, or `1 कुरिन्थियों` / `1. Mose` / `1 கொரிந்தியர்` style). Kept
  /// `null` until the service has data; an empty refresh leaves it `null` so
  /// the next lookup retries instead of caching a useless map.
  static Map<String, int>? _runtimeBookNumbers;

  /// Rebuilds [_runtimeBookNumbers] from every loaded Bible version's localized
  /// book names. Because canonical book numbers are shared across versions
  /// (and languages), a single merged map safely resolves references in all
  /// languages the app ships a Bible version for (e.g. German `Römer`,
  /// Malayalam `കൊരിന്ത്യർ`, Kannada `ರೋಮಾಪುರದವರಿಗೆ`, Korean `요한복음`, etc.).
  static void refreshRuntimeBookNumbers() {
    final merged = <String, int>{};
    for (final byNum in BookNameService().namesByVersion.values) {
      for (final entry in byNum.entries) {
        final num = int.tryParse(entry.key);
        if (num == null || num < 1 || num > 66) continue;
        final norm = _normalize(entry.value);
        if (norm.isNotEmpty) {
          merged.putIfAbsent(norm, () => num);
        }
      }
    }
    _runtimeBookNumbers = merged.isEmpty ? null : merged;
  }

  static int? _resolveBook(String book) {
    final staticHit = _abbrevToBookNum[book];
    if (staticHit != null) return staticHit;
    if (_runtimeBookNumbers == null) refreshRuntimeBookNumbers();
    return _runtimeBookNumbers?[book];
  }

  /// Lowercases, strips periods (`1. Mose` / `பிலே.`) and collapses whitespace
  /// so a captured phrase matches the same key derived from [refreshRuntimeBookNumbers].
  static String _normalize(String raw) => raw
      .toLowerCase()
      .replaceAll('.', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Tokenizes [text] into prose text chunks and parsed scripture reference links.
  ///
  /// If the text contains `[ref:b.c.v|display]` tags (from offline preprocessing),
  /// they are parsed in an ultra-fast single pass without regex on book names.
  ///
  /// Otherwise, falls back to [scriptureRegex] and verifies each match with
  /// [parse]. Matches that do not resolve to a valid Bible book (such as "Chapter 1",
  /// "Page 23", or "April 15") are retained as regular text, completely preventing
  /// false-positive links.
  static List<ScriptureSpanToken> tokenize(String text) {
    if (text.isEmpty) return const [];

    if (text.contains('[ref:')) {
      final tokens = <ScriptureSpanToken>[];
      int lastEnd = 0;
      for (final match in tagRegex.allMatches(text)) {
        if (match.start > lastEnd) {
          tokens.add(ScriptureSpanToken.text(text.substring(lastEnd, match.start)));
        }
        final bookNum = int.tryParse(match.group(1) ?? '') ?? 0;
        final chapter = int.tryParse(match.group(2) ?? '') ?? 1;
        final startVerse = int.tryParse(match.group(3) ?? '') ?? 1;
        final endVerse = int.tryParse(match.group(4) ?? '');
        final displayText = match.group(5) ?? '';

        if (bookNum >= 1 && bookNum <= 66) {
          final ref = ParsedScriptureRef(
            bookNumber: bookNum,
            bookName: BookNameService.englishNameFor(bookNum),
            chapter: chapter,
            startVerse: startVerse,
            endVerse: endVerse,
            rawMatch: displayText,
          );
          tokens.add(ScriptureSpanToken.reference(displayText, ref));
        } else {
          tokens.add(ScriptureSpanToken.text(displayText));
        }
        lastEnd = match.end;
      }
      if (lastEnd < text.length) {
        tokens.add(ScriptureSpanToken.text(text.substring(lastEnd)));
      }
      return tokens;
    }

    final matches = scriptureRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return [ScriptureSpanToken.text(text)];
    }

    final tokens = <ScriptureSpanToken>[];
    int lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        tokens.add(ScriptureSpanToken.text(text.substring(lastEnd, match.start)));
      }

      final refText = match.group(0)!;
      final parsed = parse(refText);

      if (parsed != null) {
        tokens.add(ScriptureSpanToken.reference(refText, parsed));
      } else {
        // Not a Bible citation (e.g. "Chapter 1", "Page 23", "Rule 4") -> Plain text!
        tokens.add(ScriptureSpanToken.text(refText));
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      tokens.add(ScriptureSpanToken.text(text.substring(lastEnd)));
    }

    return tokens;
  }

  static ParsedScriptureRef? parse(String citation) {
    final match = scriptureRegex.firstMatch(citation);
    if (match == null) return null;

    final bookPhrase = _normalize('${match.group(1) ?? ''}${match.group(2) ?? ''}');
    if (bookPhrase.isEmpty) return null;

    final bookNum = _resolveBook(bookPhrase);
    if (bookNum == null) return null;

    final chapter = int.tryParse(match.group(3) ?? '');
    if (chapter == null) return null;

    int startVerse = 1;
    int? endVerse;

    final verseGroup = match.group(5);
    if (verseGroup != null && verseGroup.isNotEmpty) {
      // Comma-separated verses e.g. "1, 4" or "1-4, 9"
      final primaryChunk = verseGroup.split(',').first.trim();

      if (primaryChunk.contains('-') || primaryChunk.contains('–')) {
        final dash = primaryChunk.contains('-') ? '-' : '–';
        final parts = primaryChunk.split(dash);
        startVerse = int.tryParse(parts[0].trim()) ?? 1;
        if (parts.length > 1) {
          // Cross-chapter verse ranges like "1-4:4" carry the end chapter in
          // the end verse segment; extract the numeric verse number from it.
          final endSegments = parts[1].trim().split(RegExp(r'[:\.]'));
          endVerse = int.tryParse(endSegments.first.trim());
        }
      } else {
        startVerse = int.tryParse(primaryChunk) ?? 1;
      }
    }

    return ParsedScriptureRef(
      bookNumber: bookNum,
      bookName: BookNameService.englishNameFor(bookNum),
      chapter: chapter,
      startVerse: startVerse,
      endVerse: endVerse,
      rawMatch: match.group(0)!,
    );
  }
}
