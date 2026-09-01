import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile/core/api/release_assets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/bible_background_note.dart';
import '../models/book_abbreviation.dart';
import '../../engines/scripture/services/local_bible_service.dart';

/// Downloads, installs and queries Bible historical and cultural background notes.
///
/// Data originates from unfoldingWord's open Translation Notes (CC BY-SA 4.0),
/// filtered strictly for ancient Near Eastern customs, Greco-Roman cultural
/// conventions, archaeological details, ancient idioms, and historical geography.
///
/// Delivery is a single pre-built `bible_backgrounds.json` via ReleaseAssets,
/// with online per-chapter fallback when not fully installed.
class BibleBackgroundService extends ChangeNotifier {
  static final BibleBackgroundService _instance =
      BibleBackgroundService._internal();
  factory BibleBackgroundService() => _instance;
  BibleBackgroundService._internal();

  final LocalBibleService _localBible = LocalBibleService();

  static const String _assetPath = 'data/bible_backgrounds.json';

  // In-memory cache of chapters fetched online (keyed "bookNumber_chapter").
  final Map<String, Map<int, List<BibleBackgroundNote>>> _onlineCache = {};

  bool _isDownloading = false;
  bool _isIndeterminate = false;
  double _progress = 0.0;
  String? _lastError;

  bool get isDownloading => _isDownloading;
  bool get isIndeterminate => _isIndeterminate;
  double get progress => _progress;
  String? get lastError => _lastError;

  /// Whether background data has been installed locally.
  Future<bool> isInstalled() async => _localBible.hasBibleBackgrounds();

  /// Downloads, verifies, parses and installs the background dataset.
  Future<bool> downloadAndInstall() async {
    if (_isDownloading) return false;
    _isDownloading = true;
    _progress = 0.0;
    _lastError = null;
    notifyListeners();

    final tempDir = await getTemporaryDirectory();
    final filePath = p.join(
      tempDir.path,
      'bible_bg_${DateTime.now().millisecondsSinceEpoch}.json',
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
              if (total > 0) {
                _isIndeterminate = false;
                _progress = received / total;
                notifyListeners();
              }
            },
          );
          downloaded = true;
          break;
        } catch (_) {
          continue;
        }
      }

      if (!downloaded) {
        throw Exception(
            'Failed to download Bible background notes from any mirror.');
      }

      _isIndeterminate = true;
      notifyListeners();

      final file = File(filePath);
      final raw = await file.readAsString();
      final parsed = await compute(_parseBackgroundsJson, raw);
      if (parsed == null) {
        throw Exception('Background payload failed SHA-256 integrity check.');
      }

      await _localBible.insertBibleBackgrounds(parsed);
      _onlineCache.clear();
      _isDownloading = false;
      _isIndeterminate = false;
      _progress = 1.0;
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = e.toString();
      _isDownloading = false;
      _isIndeterminate = false;
      notifyListeners();
      return false;
    } finally {
      try {
        final f = File(filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Removes all installed background notes.
  Future<void> removeInstalled() async {
    await _localBible.deleteBibleBackgrounds();
    _onlineCache.clear();
    notifyListeners();
  }

  /// Returns background notes for [bookNumber] [chapter], grouped by verse.
  /// (Verse 0 contains whole-chapter historical overview).
  Future<Map<int, List<BibleBackgroundNote>>> getBackgroundsForChapter(
    int bookNumber,
    int chapter,
  ) async {
    final installed = await isInstalled();
    if (installed) {
      return _localBible.getBackgroundsForChapter(bookNumber, chapter);
    }
    final key = '${bookNumber}_$chapter';
    final cached = _onlineCache[key];
    if (cached != null) return cached;
    return {};
  }

  /// Fetches historical context for [bookNumber] [chapter] on-demand.
  Future<Map<int, List<BibleBackgroundNote>>> fetchChapterOnline(
    int bookNumber,
    int chapter,
  ) async {
    final key = '${bookNumber}_$chapter';
    final cached = _onlineCache[key];
    if (cached != null) return cached;

    final abbrev = BookAbbreviation.abbreviationFor(bookNumber);
    if (abbrev == null) return {};

    try {
      // In bundled or offline mode, load from local asset if available
      final urls = ReleaseAssets.urlsFor(_assetPath);
      final dio = Dio();
      Response<dynamic>? res;
      for (final url in urls) {
        try {
          res = await dio.get(
            url,
            options: Options(
              responseType: ResponseType.json,
              sendTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ),
          );
          if (res.statusCode == 200 && res.data is Map) break;
        } catch (_) {}
      }

      if (res != null && res.data is Map) {
        final bgData = res.data['backgrounds'] as Map<String, dynamic>?;
        final bookData = bgData?[abbrev] as Map<String, dynamic>?;
        final chapterData = bookData?[chapter.toString()] as List<dynamic>?;
        if (chapterData != null) {
          final result = <int, List<BibleBackgroundNote>>{};
          for (final item in chapterData) {
            if (item is! Map) continue;
            final verse = (item['v'] as int?) ?? 0;
            final notesList = item['notes'] as List<dynamic>? ?? [];
            for (final n in notesList) {
              if (n is! Map) continue;
              result.putIfAbsent(verse, () => []).add(BibleBackgroundNote(
                    bookNumber: bookNumber,
                    chapter: chapter,
                    verse: verse,
                    id: n['id'] as String? ?? '',
                    topic: n['topic'] as String? ?? 'Historical Context',
                    quote: n['quote'] as String?,
                    text: n['text'] as String? ?? '',
                    source: res.data['source'] as String? ??
                        'unfoldingWord Cultural Context',
                  ));
            }
          }
          _onlineCache[key] = result;
          return result;
        }
      }
    } catch (_) {}
    return {};
  }
}

/// Runs in a background isolate: verifies the SHA-256 hash and parses the payload.
List<Map<String, dynamic>>? _parseBackgroundsJson(String rawJson) {
  try {
    final root = jsonDecode(rawJson) as Map<String, dynamic>;
    final expectedSha = root['sha256'] as String?;
    final source =
        root['source'] as String? ?? 'unfoldingWord Cultural Context';
    final backgrounds = root['backgrounds'] as Map<String, dynamic>?;
    if (backgrounds == null) return null;

    if (expectedSha != null && expectedSha.isNotEmpty) {
      final canonical = jsonEncode(backgrounds);
      final actualSha = sha256.convert(utf8.encode(canonical)).toString();
      if (actualSha.toLowerCase() != expectedSha.toLowerCase()) {
        return null;
      }
    }

    final flattened = <Map<String, dynamic>>[];
    for (final bookEntry in backgrounds.entries) {
      final bookAbbrev = bookEntry.key;
      final bookNum = BookAbbreviation.bookNumberFor(bookAbbrev);
      if (bookNum == null) continue;
      final chapterMap = bookEntry.value as Map<String, dynamic>;

      for (final chEntry in chapterMap.entries) {
        final ch = int.tryParse(chEntry.key);
        if (ch == null) continue;
        final verseList = chEntry.value as List<dynamic>;

        for (final vItem in verseList) {
          if (vItem is! Map) continue;
          final verse = (vItem['v'] as int?) ?? 0;
          final notes = vItem['notes'] as List<dynamic>? ?? [];

          for (final n in notes) {
            if (n is! Map) continue;
            flattened.add({
              'bookNumber': bookNum,
              'chapter': ch,
              'verse': verse,
              'id': n['id'] ?? '',
              'topic': n['topic'] ?? 'Historical Context',
              'quote': n['quote'],
              'text': n['text'] ?? '',
              'source': source,
            });
          }
        }
      }
    }

    return flattened;
  } catch (_) {
    return null;
  }
}
