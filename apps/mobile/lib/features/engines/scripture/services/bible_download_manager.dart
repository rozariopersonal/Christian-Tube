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

  final LocalBibleService _localBible = LocalBibleService();

  final Map<String, double> _downloadProgress = {};
  final Set<String> _downloadingIds = {};
  // Only the public domain versions bundled with the app are pre-installed.
  static const Set<String> _bundledVersions = {
    'TAOBVSI',
    'MAL_IRV',
    'TEL_IRV',
    'KAN_IRV',
    'HIN_IRV',
  };
  Set<String> _installedIds = {..._bundledVersions};

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
      id: 'MSG',
      name: 'The Message (MSG)',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1.6 MB',
      description: 'Eugene Peterson’s vibrant contemporary paraphrase bringing scripture to life.',
    ),
    BibleVersionMeta(
      id: 'TLB',
      name: 'The Living Bible (TLB)',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1.5 MB',
      description: 'Kenneth N. Taylor’s beloved thought-for-thought English translation.',
    ),
    BibleVersionMeta(
      id: 'NASB',
      name: 'New American Standard Bible (NASB)',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1.4 MB',
      description: 'Strict word-for-word accuracy based on original Hebrew and Greek manuscripts.',
    ),
    BibleVersionMeta(
      id: 'BSB',
      name: 'Berean Standard Bible',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1.4 MB',
      description: 'Faithful, modern word-for-word translation based on original Greek/Hebrew.',
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
    BibleVersionMeta(
      id: 'TAM_IRV',
      name: 'Tamil IRV (இந்தியத் திருத்தப்பட்ட வேதாகமம்)',
      language: 'Tamil',
      languageCode: 'tam',
      sizeDisplay: '1.6 MB',
      description: 'Clear, modern contemporary Tamil revision.',
    ),

    // Malayalam
    BibleVersionMeta(
      id: 'MAL_IRV',
      name: 'Malayalam IRV (മലയാളം IRV)',
      language: 'Malayalam',
      languageCode: 'mal',
      sizeDisplay: '1.5 MB',
      description: 'Indian Revised Version in Malayalam, faithful to original texts.',
      isDefaultBundled: true,
    ),

    // Telugu
    BibleVersionMeta(
      id: 'TEL_IRV',
      name: 'Telugu IRV (తెలుగు IRV)',
      language: 'Telugu',
      languageCode: 'tel',
      sizeDisplay: '1.5 MB',
      description: 'Indian Revised Version in Telugu with clear devotional phrasing.',
      isDefaultBundled: true,
    ),

    // Kannada
    BibleVersionMeta(
      id: 'KAN_IRV',
      name: 'Kannada IRV (ಕನ್ನಡ IRV)',
      language: 'Kannada',
      languageCode: 'kan',
      sizeDisplay: '1.5 MB',
      description: 'Indian Revised Version in Kannada language.',
      isDefaultBundled: true,
    ),

    // Hindi
    BibleVersionMeta(
      id: 'HIN_IRV',
      name: 'Hindi IRV (हिन्दी IRV)',
      language: 'Hindi',
      languageCode: 'hin',
      sizeDisplay: '1.5 MB',
      description: 'Clear modern Hindi translation for everyday devotions.',
      isDefaultBundled: true,
    ),

    // Spanish
    BibleVersionMeta(
      id: 'RVR09',
      name: 'Reina-Valera 1909',
      language: 'Spanish',
      languageCode: 'es',
      sizeDisplay: '1.4 MB',
      description: 'Classic Spanish Protestant Bible.',
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

  Future<void> downloadVersion(BibleVersionMeta meta) async {
    if (_installedIds.contains(meta.id) || _downloadingIds.contains(meta.id)) {
      return;
    }

    _downloadingIds.add(meta.id);
    _downloadProgress[meta.id] = 0.0;
    notifyListeners();

    try {
      final downloaded = await _downloadVersionText(meta);
      if (!downloaded) {
        // No servable data source for this version (e.g. copyrighted), so do
        // not mark it installed.
        debugPrint('Version ${meta.id} is not available for download.');
        return;
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
    } catch (e) {
      debugPrint('Error downloading version ${meta.id}: $e');
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
        final chapters = book['ch'] as List<dynamic>;
        for (var c = 0; c < chapters.length; c++) {
          final chapterVerses = chapters[c] as List<dynamic>;
          for (var v = 0; v < chapterVerses.length; v++) {
            verses.add({
              'bookNumber': bookNumber,
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

  Future<void> removeVersion(String versionId) async {
    if (_bundledVersions.contains(versionId)) return;
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
