import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile/core/api/release_assets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/bible_version_meta.dart';
import 'local_bible_service.dart';

class BibleDownloadManager extends ChangeNotifier {
  static final BibleDownloadManager _instance =
      BibleDownloadManager._internal();
  factory BibleDownloadManager() => _instance;
  BibleDownloadManager._internal();

  static const String defaultVersionId = 'TAOBVSI';

  final LocalBibleService _localBible = LocalBibleService();

  final Map<String, double> _downloadProgress = {};
  final Set<String> _downloadingIds = {};
  // Bibles are downloaded on demand from the releases repo; nothing ships in
  // the app bundle.
  Set<String> _installedIds = {};

  static const List<BibleVersionMeta> catalog = [
    // English
    BibleVersionMeta(
      id: 'WEB',
      name: 'World English Bible',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1.4 MB',
      description: 'Modern, accurate, and easy to read English translation.',
    ),
    BibleVersionMeta(
      id: 'KJV',
      name: 'King James Version',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1.3 MB',
      description: 'The historic and revered 1611 English Bible.',
    ),
    BibleVersionMeta(
      id: 'ASV',
      name: 'American Standard Version',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1.4 MB',
      description: 'Accurate literal standard American translation.',
    ),
    BibleVersionMeta(
      id: 'BBE',
      name: 'Bible in Basic English',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1.2 MB',
      description: 'Simplified 850-word standard English vocabulary.',
    ),

    // Tamil
    BibleVersionMeta(
      id: 'TAOBVSI',
      name: 'Tamil Old Version (பரிசுத்த வேதாகமம்)',
      language: 'Tamil',
      languageCode: 'tam',
      sizeDisplay: '1.5 MB',
      description: 'The classic Bower revision standard Tamil Bible used across Tamil churches.',
      isDefaultBundled: true,
    ),

    // Malayalam
    BibleVersionMeta(
      id: 'MAL_IRV',
      name: 'Malayalam IRV (മലയാളം IRV)',
      language: 'Malayalam',
      languageCode: 'mal',
      sizeDisplay: '1.5 MB',
      description: 'Indian Revised Version in Malayalam, faithful to original texts.',
    ),

    // Telugu
    BibleVersionMeta(
      id: 'TEL_IRV',
      name: 'Telugu IRV (తెలుగు IRV)',
      language: 'Telugu',
      languageCode: 'tel',
      sizeDisplay: '1.5 MB',
      description: 'Indian Revised Version in Telugu with clear devotional phrasing.',
    ),

    // Kannada
    BibleVersionMeta(
      id: 'KAN_IRV',
      name: 'Kannada IRV (ಕನ್ನಡ IRV)',
      language: 'Kannada',
      languageCode: 'kan',
      sizeDisplay: '1.5 MB',
      description: 'Indian Revised Version in Kannada language.',
    ),

    // Hindi
    BibleVersionMeta(
      id: 'HIN_IRV',
      name: 'Hindi IRV (हिन्दी IRV)',
      language: 'Hindi',
      languageCode: 'hin',
      sizeDisplay: '1.5 MB',
      description: 'Clear modern Hindi translation for everyday devotions.',
    ),
  ];

  Set<String> get installedIds => _installedIds;

  bool isInstalled(String versionId) => _installedIds.contains(versionId);
  bool isDownloading(String versionId) => _downloadingIds.contains(versionId);
  double getProgress(String versionId) => _downloadProgress[versionId] ?? 0.0;

  Future<void> refreshInstalledList() async {
    final ids = await _localBible.getInstalledVersionIds();
    // Only count versions that actually contain verse text as installed.
    final usable = <String>[];
    for (final id in ids) {
      if (await _localBible.hasVerses(id)) {
        usable.add(id);
      }
    }
    _installedIds = usable.toSet();
    notifyListeners();
  }

  /// Ensures the app's default bible (TAOBVSI) is installed, downloading it on
  /// demand from the releases repo on first run when a network is available.
  Future<void> ensureDefaultInstalled() async {
    await _localBible.initialize();
    await refreshInstalledList();
    if (_installedIds.contains(defaultVersionId) ||
        _downloadingIds.contains(defaultVersionId)) {
      return;
    }
    unawaited(downloadVersion(getMeta(defaultVersionId)));
  }

  /// Downloads and installs [meta]. Returns true when the version is ready for
  /// offline use; false when it could not be fetched (no data source, or a
  /// network failure on every mirror).
  Future<bool> downloadVersion(BibleVersionMeta meta) async {
    await _localBible.initialize();
    if (_installedIds.contains(meta.id)) return true;
    if (_downloadingIds.contains(meta.id)) return true;

    _downloadingIds.add(meta.id);
    _downloadProgress[meta.id] = 0.0;
    notifyListeners();

    try {
      final downloaded = await _downloadVersionText(meta);
      if (!downloaded) {
        // No servable data source for this version (e.g. copyrighted), so do
        // not mark it installed.
        debugPrint('Version ${meta.id} is not available for download.');
        return false;
      }

      // Register in local SQLite database
      await _localBible.registerInstalledVersion(
        id: meta.id,
        name: meta.name,
        language: meta.language,
        languageCode: meta.languageCode,
        sizeDisplay: meta.sizeDisplay,
      );

      _installedIds.add(meta.id);
      return true;
    } catch (e) {
      debugPrint('Error downloading version ${meta.id}: $e');
      return false;
    } finally {
      _downloadingIds.remove(meta.id);
      _downloadProgress.remove(meta.id);
      notifyListeners();
    }
  }

  Future<bool> _downloadVersionText(BibleVersionMeta meta) async {
    final tempDir = await getTemporaryDirectory();
    final filePath =
        p.join(tempDir.path, 'bible_${meta.id.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}.json');
    final urls = ReleaseAssets.urlsFor('bibles/bible_${meta.id.toLowerCase()}.json');
    final dio = Dio();
    var downloaded = false;
    for (final url in urls) {
      try {
        await dio.download(
          url,
          filePath,
          options: Options(
            // Large payloads can take a while on slow networks.
            receiveTimeout: const Duration(minutes: 5),
          ),
          onReceiveProgress: (received, total) {
            if (total != -1) {
              _downloadProgress[meta.id] = received / total;
              notifyListeners();
            }
          },
        );
        downloaded = true;
        break;
      } catch (e) {
        debugPrint('Failed to download ${meta.id} from $url: $e');
      }
    }
    if (!downloaded) return false;

    try {
      final jsonStr = await File(filePath).readAsString();
      await File(filePath).delete();

      final books =
          (jsonDecode(jsonStr) as Map<String, dynamic>)['books'] as List<dynamic>;
      final verses = <Map<String, dynamic>>[];
      for (final rawBook in books) {
        final book = rawBook as Map<String, dynamic>;
        final bookNumber = book['b'] as int;
        final bookName = book['n'] as String;
        final chapters = book['ch'] as List<dynamic>;
        for (var c = 0; c < chapters.length; c++) {
          final chapterVerses = chapters[c] as List<dynamic>;
          for (var v = 0; v < chapterVerses.length; v++) {
            verses.add({
              'bookNumber': bookNumber,
              'bookName': bookName,
              'chapter': c + 1,
              'verse': v + 1,
              'text': chapterVerses[v],
            });
          }
        }
      }

      await _localBible.insertVerses(meta.id, verses);
      debugPrint('Downloaded ${meta.id} (${verses.length} verses).');
      return true;
    } catch (e) {
      debugPrint('Failed to process ${meta.id}: $e');
      if (await File(filePath).exists()) {
        try {
          await File(filePath).delete();
        } catch (_) {}
      }
      return false;
    }
  }

  /// Wipes any existing (possibly stale/partial) default bible data and
  /// re-downloads it from scratch.
  Future<void> forceRedownloadDefault() async {
    await _localBible.initialize();
    _installedIds.remove(defaultVersionId);
    _downloadingIds.remove(defaultVersionId);
    await _localBible.deleteVersion(defaultVersionId);
    unawaited(downloadVersion(getMeta(defaultVersionId)));
  }

  Future<void> removeVersion(String versionId) async {
    // The default version stays installed so the app always has a working
    // bible; every other version can be removed freely.
    if (versionId == defaultVersionId) return;
    await _localBible.deleteVersion(versionId);
    _installedIds.remove(versionId);
    notifyListeners();
  }

  static BibleVersionMeta getMeta(String id) {
    return catalog.firstWhere(
      (v) => v.id == id,
      orElse: () => catalog.first,
    );
  }
}
