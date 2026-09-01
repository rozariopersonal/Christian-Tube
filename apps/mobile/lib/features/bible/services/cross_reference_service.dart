import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile/core/api/release_assets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/book_abbreviation.dart';
import '../models/cross_reference.dart';
import '../../engines/scripture/services/local_bible_service.dart';

/// Downloads, installs and queries Bible cross-reference data.
///
/// Cross-references come from the OpenBible.info / HelloAO `open-cross-ref`
/// dataset (CC-BY 4.0). They are translation-independent, so a single bundled
/// file serves every bible version the user installs.
///
/// Delivery is a single pre-built `cross_references.json` in the releases
/// repo (mirrors how bible and feed JSONs are shipped). A SHA-256 checksum in
/// the file header guards against truncated/corrupt downloads.
class CrossReferenceService extends ChangeNotifier {
  static final CrossReferenceService _instance =
      CrossReferenceService._internal();
  factory CrossReferenceService() => _instance;
  CrossReferenceService._internal();

  final LocalBibleService _localBible = LocalBibleService();

  static const String _assetPath = 'data/cross_references.json';

  static const String _apiBase =
      'https://bible.helloao.org/api/d/open-cross-ref';

  // In-memory cache of chapters fetched online (opted in per chapter when the
  // bundled dataset is not installed). Keyed "bookNumber_chapter".
  final Map<String, Map<int, List<CrossReference>>> _onlineCache = {};

  bool _isDownloading = false;
  bool _isIndeterminate = false;
  double _progress = 0.0;
  String? _lastError;

  bool get isDownloading => _isDownloading;
  bool get isIndeterminate => _isIndeterminate;
  double get progress => _progress;
  String? get lastError => _lastError;

  /// Whether cross-reference data has been installed.
  Future<bool> isInstalled() async => _localBible.hasCrossReferences();

  /// Downloads, verifies, parses and installs the cross-reference dataset.
  /// Returns true on success. Safe to call again to refresh/update.
  Future<bool> downloadAndInstall() async {
    if (_isDownloading) return false;
    _isDownloading = true;
    _progress = 0.0;
    _lastError = null;
    notifyListeners();

    final tempDir = await getTemporaryDirectory();
    final filePath = p.join(
      tempDir.path,
      'cross_refs_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    final urls = ReleaseAssets.urlsFor(_assetPath);
    final dio = Dio();
    var downloaded = false;
    try {
      for (final url in urls) {
        _progress = 0.0;
        _isIndeterminate = true;
        notifyListeners();
        try {
          await dio.download(
            url,
            filePath,
            options: Options(receiveTimeout: const Duration(minutes: 5)),
            onReceiveProgress: (received, total) {
              if (total != -1 && total > 0) {
                _isIndeterminate = false;
                _progress = received / total;
              } else {
                // Unknown total -> keep the bar animating indistinguishably.
                _isIndeterminate = true;
              }
              notifyListeners();
            },
          );
          downloaded = true;
          _isIndeterminate = false;
          _progress = 1.0;
          notifyListeners();
          break;
        } catch (e) {
          debugPrint('CrossReference download failed from $url: $e');
        }
      }
      if (!downloaded) {
        _lastError = 'Could not reach the download server.';
        return false;
      }

      Map<String, dynamic> json;
      String fileContent;
      try {
        fileContent = await File(filePath).readAsString();
        json = jsonDecode(fileContent) as Map<String, dynamic>;
      } finally {
        if (await File(filePath).exists()) {
          try {
            await File(filePath).delete();
          } catch (_) {}
        }
      }

      // Verify integrity: the optional sha256 header is the hash of the
      // canonical `references` payload (build script and this verifier encode
      // it identically), guarding against truncated/corrupt downloads.
      final expectedSha = json['sha256'] as String?;
      if (expectedSha != null && expectedSha.isNotEmpty) {
        final canonical = jsonEncode(json['references']);
        final actualSha = sha256.convert(utf8.encode(canonical)).toString();
        if (actualSha != expectedSha.toLowerCase()) {
          _lastError = 'Downloaded data failed integrity check.';
          return false;
        }
      }

      final references = _parseReferences(json);
      if (references.isEmpty) {
        _lastError = 'No cross-references found in the downloaded data.';
        return false;
      }

      await _localBible.insertCrossReferences(references);
      return true;
    } catch (e) {
      debugPrint('CrossReferenceService error: $e');
      _lastError = 'Could not install cross-references.';
      if (await File(filePath).exists()) {
        try {
          await File(filePath).delete();
        } catch (_) {}
      }
      return false;
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  /// Parses the bundled JSON into a flat list of reference rows for SQLite.
  List<Map<String, dynamic>> _parseReferences(Map<String, dynamic> json) {
    final rows = <Map<String, dynamic>>[];
    final refs = json['references'] as Map<String, dynamic>?;
    if (refs == null) return rows;

    refs.forEach((abbrev, chaptersJson) {
      final bookNumber = BookAbbreviation.bookNumberFor(abbrev);
      if (bookNumber == null) return;
      final chapters = chaptersJson as Map<String, dynamic>;
      chapters.forEach((chapterStr, versesJson) {
        final chapter = int.tryParse(chapterStr);
        if (chapter == null) return;
        final verses = versesJson as List<dynamic>;
        for (final verseEntry in verses) {
          final ve = verseEntry as Map<String, dynamic>;
          final verse = (ve['v'] as num).toInt();
          final refsList = ve['refs'] as List<dynamic>? ?? [];
          for (final rawRef in refsList) {
            final rf = rawRef as Map<String, dynamic>;
            final refBook = BookAbbreviation.bookNumberFor(rf['bt'] as String);
            if (refBook == null) continue;
            rows.add({
              'bookNumber': bookNumber,
              'chapter': chapter,
              'verse': verse,
              'refBookNumber': refBook,
              'refChapter': (rf['c'] as num).toInt(),
              'refVerse': (rf['v'] as num).toInt(),
              'refEndVerse': rf['e'] == null ? null : (rf['e'] as num).toInt(),
              'score': (rf['s'] as num?)?.toInt() ?? 0,
            });
          }
        }
      });
    });
    return rows;
  }

  /// Fetches all cross-references for a chapter, grouped by verse.
  ///
  /// When [allowOnline] is true and the local database has no data for this
  /// chapter (e.g. the bundled dataset was never installed), the chapter is
  /// fetched on demand from the online `open-cross-ref` API so cross-references
  /// still work without the ~14 MB download. Result is cached in memory for the
  /// session.
  Future<Map<int, List<CrossReference>>> getForChapter(
    int bookNumber,
    int chapter, {
    bool allowOnline = true,
  }) async {
    final local =
        await _localBible.getCrossReferencesForChapter(bookNumber, chapter);
    if (local.isNotEmpty || !allowOnline) return local;

    final cacheKey = '${bookNumber}_$chapter';
    final cached = _onlineCache[cacheKey];
    if (cached != null) return cached;

    try {
      final online = await fetchOnlineForChapter(bookNumber, chapter);
      _onlineCache[cacheKey] = online;
      return online;
    } catch (_) {
      return {};
    }
  }

  /// Fetches a single chapter of cross-references from the HelloAO
  /// `open-cross-ref` API and maps it into [CrossReference] rows grouped by
  /// verse. Throws on network/parse failure so callers can decide to fall back.
  Future<Map<int, List<CrossReference>>> fetchOnlineForChapter(
    int bookNumber,
    int chapter,
  ) async {
    final abbrev = BookAbbreviation.abbreviationFor(bookNumber);
    if (abbrev == null) return {};
    final dio = Dio();
    final response = await dio.get<Map<String, dynamic>>(
      '$_apiBase/$abbrev/$chapter.json',
      options: Options(
        responseType: ResponseType.json,
        receiveTimeout: const Duration(seconds: 30),
        connectTimeout: const Duration(seconds: 15),
      ),
    );
    final body = response.data;
    if (body == null) return {};

    final content = (body['chapter'] as Map<String, dynamic>?)?['content']
        as List<dynamic>?;
    if (content == null) return {};

    final grouped = <int, List<CrossReference>>{};
    for (final entry in content) {
      final em = entry as Map<String, dynamic>;
      final verse = (em['verse'] as num).toInt();
      final refs = (em['references'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>();
      final list = <CrossReference>[];
      for (final rf in refs) {
        final refBook =
            BookAbbreviation.bookNumberFor(rf['book'] as String? ?? '');
        if (refBook == null) continue;
        final endVerse =
            rf['endVerse'] == null ? null : (rf['endVerse'] as num).toInt();
        list.add(CrossReference(
          bookNumber: refBook,
          chapter: (rf['chapter'] as num).toInt(),
          verse: (rf['verse'] as num).toInt(),
          endVerse: endVerse,
          score: (rf['score'] as num?)?.toInt() ?? 0,
        ));
      }
      if (list.isNotEmpty) grouped[verse] = list;
    }
    return grouped;
  }

  /// Removes all cross-reference data (reclaims storage).
  Future<void> removeAll() async {
    await _localBible.deleteCrossReferences();
    notifyListeners();
  }
}
