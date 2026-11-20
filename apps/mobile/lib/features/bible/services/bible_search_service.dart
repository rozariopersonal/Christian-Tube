import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../books/services/scripture_ref_parser.dart';
import '../../engines/scripture/services/book_name_service.dart';
import '../../engines/scripture/services/local_bible_service.dart';
import '../models/bible_book.dart';
import '../models/bible_search_hit.dart';

/// Queries backend hybrid Bible search (`/api/bible/search`), localizes
/// returned verses/passages into the active Bible version, and falls back to
/// local SQLite search when offline.
class BibleSearchService {
  final Dio Function() _dioProvider;
  final LocalBibleService _localBible;

  BibleSearchService({
    Dio? dio,
    LocalBibleService? localBible,
  })  : _dioProvider = dio != null ? (() => dio) : (() => ApiClient().dio),
        _localBible = localBible ?? LocalBibleService();

  /// Parses a direct scripture citation like "John 3:16", "Psalm 23", or
  /// misspelled book queries like "mathew 6:33" / "1 corintians 13:4".
  ParsedScriptureRef? parseDirectReference(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;
    for (final token in ScriptureRefParser.tokenize(trimmed)) {
      if (token.ref != null) return token.ref;
    }
    return _parseFuzzyReference(trimmed);
  }

  ParsedScriptureRef? _parseFuzzyReference(String trimmed) {
    final match = RegExp(
      r'^((?:[123](?:st|nd|rd)?|I{1,3})\.?\s+)?([A-Za-z]{3,20}(?:\s+of\s+(?:solomon|songs))?)\s+(\d{1,3})(?:[:.]\s*(\d{1,3})(?:\s*[-–]\s*(\d{1,3}))?)?$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match == null) return null;

    var ord = (match.group(1) ?? '').trim().replaceAll('.', '').toLowerCase();
    if (ord == 'i' || ord == '1st') ord = '1';
    if (ord == 'ii' || ord == '2nd') ord = '2';
    if (ord == 'iii' || ord == '3rd') ord = '3';
    ord = ord.replaceAll(RegExp(r'(st|nd|rd)$'), '');

    final word = (match.group(2) ?? '').trim().toLowerCase();
    final maxDist = word.length <= 4 ? 0 : (word.length <= 7 ? 1 : 2);

    int? bookNum;
    String? bookName;
    var bestDist = maxDist + 1;
    final keys = bibleBooks.keys.toList();
    for (var i = 0; i < keys.length; i++) {
      final candidate = keys[i];
      final lower = candidate.toLowerCase();
      final numMatch = RegExp(r'^([123])\s+(.+)$').firstMatch(lower);
      final cOrd = numMatch?.group(1) ?? '';
      final cWord = numMatch?.group(2) ?? lower;
      if (ord != cOrd) continue;

      var dist = _damerau(word, cWord);
      if (cWord.length > 4 && cWord.endsWith('s')) {
        final singularDist = _damerau(word, cWord.substring(0, cWord.length - 1));
        if (singularDist < dist) dist = singularDist;
      }
      if (dist <= maxDist && dist < bestDist) {
        bestDist = dist;
        bookNum = i + 1;
        bookName = candidate;
        if (dist == 0) break;
      }
    }

    if (bookNum == null || bookName == null) return null;
    final chapter = int.tryParse(match.group(3) ?? '');
    if (chapter == null || chapter < 1 || chapter > 150) return null;

    return ParsedScriptureRef(
      bookNumber: bookNum,
      bookName: bookName,
      chapter: chapter,
      startVerse: int.tryParse(match.group(4) ?? '') ?? 1,
      endVerse: int.tryParse(match.group(5) ?? ''),
      rawMatch: trimmed,
    );
  }

  static int _damerau(String a, String b) {
    final m = a.length;
    final n = b.length;
    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
    for (var i = 0; i <= m; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= n; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = dp[i - 1][j] + 1;
        if (dp[i][j - 1] + 1 < v) v = dp[i][j - 1] + 1;
        if (dp[i - 1][j - 1] + cost < v) v = dp[i - 1][j - 1] + cost;
        if (i > 1 &&
            j > 1 &&
            a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          final trans = dp[i - 2][j - 2] + 1;
          if (trans < v) v = trans;
        }
        dp[i][j] = v;
      }
    }
    return dp[m][n];
  }

  Future<List<BibleSearchHit>> search(
    String query, {
    String? versionId,
    int limit = 30,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];

    try {
      final response = await _dioProvider().get<Map<String, dynamic>>(
        '/api/bible/search',
        queryParameters: {'q': clean, 'limit': limit},
      );
      final data = response.data;
      final rawResults = data?['results'];
      if (response.statusCode == 200 && rawResults is List) {
        return rawResults
            .whereType<Map<String, dynamic>>()
            .map(BibleSearchHit.fromJson)
            .where((h) => h.chapter != null && h.verse != null)
            .toList();
      }
    } catch (_) {
      // Fall through to local offline search when network/backend fails.
    }

    if (versionId == null || versionId.trim().isEmpty) {
      return const [];
    }

    final localRows =
        await _localBible.search(versionId, clean, limit: limit);
    return localRows.map((row) {
      final bookName = row['book_name'] as String?;
      final bn = _bookNumberForName(bookName);
      return BibleSearchHit.fromJson({
        ...row,
        if (bn != null) 'bookNumber': bn,
      });
    }).toList();
  }

  /// Resolves verse and multi-verse passage hit texts into [versionId] using
  /// offline SQLite, GitHub CDN, or OnlineBibleService transparently.
  Future<List<BibleSearchHit>> localizeHits(
    List<BibleSearchHit> hits, {
    required String versionId,
  }) async {
    final targetVersion = versionId.trim();
    if (hits.isEmpty || targetVersion.isEmpty) return hits;

    try {
      await BookNameService().ensureLoaded();
    } catch (_) {}

    final uniqueChapters = <(int, int), String>{};
    for (final hit in hits) {
      final bn = hit.bookNumber;
      final ch = hit.chapter;
      final key = hit.canonicalBookKey;
      if (bn != null && ch != null && key != null) {
        uniqueChapters.putIfAbsent((bn, ch), () => key);
      }
    }

    final verseMaps = <(int, int), Map<int, String>>{};
    await Future.wait(
      uniqueChapters.entries.map((entry) async {
        final (bn, ch) = entry.key;
        try {
          final rows =
              await _localBible.getChapter(targetVersion, entry.value, ch);
          if (rows.isNotEmpty) {
            final byVerse = <int, String>{};
            for (final row in rows) {
              final vNum = (row['verse'] as num?)?.toInt();
              final text = (row['text'] as String?)?.trim() ?? '';
              if (vNum != null && text.isNotEmpty) {
                byVerse[vNum] = text;
              }
            }
            if (byVerse.isNotEmpty) {
              verseMaps[(bn, ch)] = byVerse;
            }
          }
        } catch (_) {}
      }),
    );

    final bookNames = BookNameService();
    return hits.map((hit) {
      final bn = hit.bookNumber;
      final ch = hit.chapter;
      final v = hit.verse;
      if (bn == null || ch == null || v == null) return hit;

      final localizedBook = bookNames.nameFor(targetVersion, bn);
      final displayBook =
          localizedBook.isNotEmpty ? localizedBook : (hit.bookName ?? '');
      final endV = hit.endVerse;
      final localizedRef = displayBook.isEmpty
          ? hit.displayReference
          : (endV != null && endV > v
              ? '$displayBook $ch:$v-$endV'
              : '$displayBook $ch:$v');

      final byVerse = verseMaps[(bn, ch)];
      String resolvedText = '';
      if (byVerse != null) {
        if (endV != null && endV > v) {
          final parts = <String>[];
          for (var i = v; i <= endV; i++) {
            final t = byVerse[i];
            if (t != null && t.isNotEmpty) {
              parts.add('$i. $t');
            }
          }
          if (parts.isNotEmpty) {
            resolvedText = parts.join(' ');
          }
        } else {
          resolvedText = byVerse[v] ?? '';
        }
      }

      return hit.copyWith(
        bookName: displayBook.isNotEmpty ? displayBook : hit.bookName,
        reference: localizedRef,
        text: resolvedText.isNotEmpty ? resolvedText : hit.text,
      );
    }).toList();
  }

  static int? _bookNumberForName(String? name) {
    if (name == null || name.isEmpty) return null;
    final idx = bibleBooks.keys.toList().indexOf(name);
    return idx >= 0 ? idx + 1 : null;
  }
}
