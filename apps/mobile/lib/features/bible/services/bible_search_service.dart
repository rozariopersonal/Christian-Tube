import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../books/services/scripture_ref_parser.dart';
import '../../engines/scripture/services/local_bible_service.dart';
import '../models/bible_book.dart';
import '../models/bible_search_hit.dart';

/// Queries backend hybrid Bible search (`/api/bible/search`) and falls back to
/// local SQLite substring search when offline or unavailable.
class BibleSearchService {
  final Dio Function() _dioProvider;
  final LocalBibleService _localBible;

  BibleSearchService({
    Dio? dio,
    LocalBibleService? localBible,
  })  : _dioProvider = dio != null ? (() => dio) : (() => ApiClient().dio),
        _localBible = localBible ?? LocalBibleService();

  /// Parses a direct scripture citation like "John 3:16" or "1 Cor 13:4".
  ParsedScriptureRef? parseDirectReference(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;
    for (final token in ScriptureRefParser.tokenize(trimmed)) {
      if (token.ref != null) return token.ref;
    }
    return null;
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
        final hits = rawResults
            .whereType<Map<String, dynamic>>()
            .map(BibleSearchHit.fromJson)
            .where((h) => h.chapter != null && h.verse != null)
            .toList();
        if (hits.isNotEmpty) return hits;
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

  static int? _bookNumberForName(String? name) {
    if (name == null || name.isEmpty) return null;
    final idx = bibleBooks.keys.toList().indexOf(name);
    return idx >= 0 ? idx + 1 : null;
  }
}
