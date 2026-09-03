import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile/core/api/github_data_service.dart';
import '../models/book_abbreviation.dart';
import '../models/cross_reference.dart';

/// Fetches and caches Bible cross-reference data per chapter.
///
/// Cross-references (TSK / OpenBible CC-BY 4.0) are served as small per-chapter
/// JSON files from the releases CDN. No download or local SQLite is required —
/// chapters are fetched on demand and cached in memory for the session.
///
/// URL pattern: `cross_references/{bookNumber}/{chapter}.json`
///
/// Each file is an array of verse entries:
/// ```json
/// [
///   { "v": 27, "refs": [{ "b": 19, "c": 29, "v": 11, "s": 85 }] }
/// ]
/// ```
class CrossReferenceService extends ChangeNotifier {
  static final CrossReferenceService _instance =
      CrossReferenceService._internal();
  factory CrossReferenceService() => _instance;
  CrossReferenceService._internal();

  /// Session cache keyed by "${bookNumber}_${chapter}".
  final Map<String, Map<int, List<CrossReference>>> _cache = {};

  /// In-flight futures to deduplicate concurrent requests for the same chapter.
  final Map<String, Future<Map<int, List<CrossReference>>>> _inFlight = {};

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  bool get isDownloading => false;
  bool get isIndeterminate => false;
  double get progress => 0.0;
  String? get lastError => null;

  /// Cross references are always available on-demand via CDN.
  Future<bool> isInstalled() async => true;

  Future<bool> downloadAndInstall() async => true;

  Future<void> removeAll() async {
    clearCache();
    notifyListeners();
  }

  /// Fetches cross-references for [chapter] of [bookNumber].
  ///
  /// Returns a map from verse number to list of [CrossReference]s.
  /// Returns an empty map on network failure (non-throwing).
  Future<Map<int, List<CrossReference>>> getForChapter(
    int bookNumber,
    int chapter, {
    bool allowOnline = true,
  }) async {
    final key = '${bookNumber}_$chapter';

    if (_cache.containsKey(key)) return _cache[key]!;
    if (_inFlight.containsKey(key)) return _inFlight[key]!;

    final future = _fetchChapter(bookNumber, chapter, key);
    _inFlight[key] = future;
    try {
      final result = await future;
      return result;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<Map<int, List<CrossReference>>> _fetchChapter(
    int bookNumber,
    int chapter,
    String cacheKey,
  ) async {
    final urls = GitHubDataService.crossReferenceChapterUrls(bookNumber, chapter);
    for (final url in urls) {
      try {
        final res = await _dio.get<dynamic>(
          url,
          options: Options(responseType: ResponseType.json),
        );
        if (res.statusCode == 200 && res.data != null) {
          final grouped = _parse(res.data);
          _cache[cacheKey] = grouped;
          return grouped;
        }
      } catch (e) {
        debugPrint('CrossReferenceService: failed $url — $e');
      }
    }
    // Cache empty result so we don''t hammer the CDN on repeated calls.
    _cache[cacheKey] = {};
    return {};
  }

  Map<int, List<CrossReference>> _parse(dynamic raw) {
    final List<dynamic> list = raw is String
        ? jsonDecode(raw) as List<dynamic>
        : (raw as List<dynamic>);

    final grouped = <int, List<CrossReference>>{};
    for (final entry in list) {
      final em = entry as Map<String, dynamic>;
      final verse = (em['v'] as num).toInt();
      final refs = (em['refs'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>();
      final xrefs = <CrossReference>[];
      for (final rf in refs) {
        final rawBook = rf['bt'] ?? rf['b'];
        final int targetBookNumber;
        if (rawBook is num) {
          targetBookNumber = rawBook.toInt();
        } else if (rawBook is String) {
          targetBookNumber = BookAbbreviation.bookNumberFor(rawBook) ??
              int.tryParse(rawBook) ??
              0;
        } else {
          continue;
        }
        if (targetBookNumber <= 0) continue;

        xrefs.add(CrossReference(
          bookNumber: targetBookNumber,
          chapter: (rf['c'] as num).toInt(),
          verse: (rf['v'] as num).toInt(),
          endVerse: rf['e'] == null ? null : (rf['e'] as num).toInt(),
          score: (rf['s'] as num?)?.toInt() ?? 0,
        ));
      }
      if (xrefs.isNotEmpty) grouped[verse] = xrefs;
    }
    return grouped;
  }

  /// Clears the in-memory cache (e.g. on low-memory pressure).
  void clearCache() => _cache.clear();
}
