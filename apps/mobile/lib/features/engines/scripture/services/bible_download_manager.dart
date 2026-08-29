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
    BibleVersionMeta(
      id: 'YLT',
      name: "Young's Literal Translation",
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '4.1 MB',
      description: 'Ultra-literal 1898 translation that preserves the word order of the originals.',
    ),
    BibleVersionMeta(
      id: 'WB',
      name: "Webster's Bible (1833)",
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '4.0 MB',
      description: 'Noah Webster\'s 1833 revision of the King James with modernized grammar.',
    ),

    // German
    BibleVersionMeta(
      id: 'LUTHER1545',
      name: 'Lutherbibel (1545)',
      language: 'German',
      languageCode: 'de',
      sizeDisplay: '4.0 MB',
      description: 'Martin Luther\'s classic 1545 German Bible.',
    ),
    BibleVersionMeta(
      id: 'ELBERFELDER1905',
      name: 'Elberfelder Bibel (1905)',
      language: 'German',
      languageCode: 'de',
      sizeDisplay: '4.2 MB',
      description: 'Highly literal German translation from 1905.',
    ),
    BibleVersionMeta(
      id: 'ELBERFELDER',
      name: 'Elberfelder Bibel (1871)',
      language: 'German',
      languageCode: 'de',
      sizeDisplay: '4.2 MB',
      description: 'The original 1871 Elberfelder translation.',
    ),

    // Spanish
    BibleVersionMeta(
      id: 'SSE',
      name: 'Sagradas Escrituras (1569)',
      language: 'Spanish',
      languageCode: 'es',
      sizeDisplay: '3.8 MB',
      description: 'The classic 1569 Spanish Bible of Casiodoro de Reina.',
    ),

    // French
    BibleVersionMeta(
      id: 'MARTIN',
      name: 'Bible Martin (1744)',
      language: 'French',
      languageCode: 'fr',
      sizeDisplay: '4.4 MB',
      description: 'David Martin\'s faithful 1744 French translation.',
    ),

    // Italian
    BibleVersionMeta(
      id: 'RIVEDUTA',
      name: 'Riveduta (1927)',
      language: 'Italian',
      languageCode: 'it',
      sizeDisplay: '4.1 MB',
      description: 'The 1927 revised Italian Bible.',
    ),
    BibleVersionMeta(
      id: 'DIODATI',
      name: 'Bibbia Diodati',
      language: 'Italian',
      languageCode: 'it',
      sizeDisplay: '4.2 MB',
      description: 'Giovanni Diodati\'s 1607 classic Italian translation.',
    ),

    // Dutch
    BibleVersionMeta(
      id: 'STATENVERTALING',
      name: 'Statenvertaling (1637)',
      language: 'Dutch',
      languageCode: 'nl',
      sizeDisplay: '4.2 MB',
      description: 'The authorized Dutch State Translation of 1637.',
    ),

    // Polish
    BibleVersionMeta(
      id: 'POLGDANSKA',
      name: 'Biblia Gdańska (1881)',
      language: 'Polish',
      languageCode: 'pl',
      sizeDisplay: '3.9 MB',
      description: 'The beloved Polish Gdańsk Bible.',
    ),

    // Hungarian
    BibleVersionMeta(
      id: 'KAROLI',
      name: 'Károlyi Biblia',
      language: 'Hungarian',
      languageCode: 'hu',
      sizeDisplay: '4.1 MB',
      description: 'The classic Hungarian Bible of Gáspár Károlyi (1590).',
    ),

    // Nordic
    BibleVersionMeta(
      id: 'SWEDISH',
      name: 'Svenska Bibeln (1917)',
      language: 'Swedish',
      languageCode: 'sv',
      sizeDisplay: '4.2 MB',
      description: 'The official 1917 Swedish Bible.',
    ),
    BibleVersionMeta(
      id: 'DANISH',
      name: 'Dansk Bibel',
      language: 'Danish',
      languageCode: 'da',
      sizeDisplay: '3.6 MB',
      description: 'The classic Danish Bible translation.',
    ),
    BibleVersionMeta(
      id: 'PYHAAMATTU1933',
      name: 'Pyhä Raamattu (1933/1938)',
      language: 'Finnish',
      languageCode: 'fi',
      sizeDisplay: '4.1 MB',
      description: 'The classical Finnish Bible translation.',
    ),

    // Slavic
    BibleVersionMeta(
      id: 'BKR',
      name: 'Bible kralická',
      language: 'Czech',
      languageCode: 'cs',
      sizeDisplay: '3.8 MB',
      description: 'The historic Czech King James of 1613.',
    ),
    BibleVersionMeta(
      id: 'CROATIA',
      name: 'Biblija (Croatian)',
      language: 'Croatian',
      languageCode: 'hr',
      sizeDisplay: '3.3 MB',
      description: 'A classic Croatian Bible translation.',
    ),

    // Albanian
    BibleVersionMeta(
      id: 'ALB',
      name: 'Bibla Shqipe',
      language: 'Albanian',
      languageCode: 'sq',
      sizeDisplay: '4.2 MB',
      description: 'The 1827 Albanian Bible, the oldest Albanian translation.',
    ),

    // East Asian
    BibleVersionMeta(
      id: 'KOREAN',
      name: 'Korean Bible',
      language: 'Korean',
      languageCode: 'ko',
      sizeDisplay: '4.3 MB',
      description: 'Classic Korean Bible translation.',
    ),
    BibleVersionMeta(
      id: 'VIETNAMESE',
      name: 'Kinh Thánh (1934)',
      language: 'Vietnamese',
      languageCode: 'vi',
      sizeDisplay: '4.9 MB',
      description: 'The 1934 public domain Vietnamese Bible.',
    ),
    BibleVersionMeta(
      id: 'CUT',
      name: 'Union Version (Traditional)',
      language: 'Chinese',
      languageCode: 'zh-Hant',
      sizeDisplay: '3.4 MB',
      description: 'The classic traditional Chinese Union Version.',
    ),
    BibleVersionMeta(
      id: 'JAPKOUGO',
      name: '口語訳聖書 (1954/1955)',
      language: 'Japanese',
      languageCode: 'ja',
      sizeDisplay: '5.1 MB',
      description: 'The Japanese colloquial translation of 1954/1955.',
    ),

    // Southeast Asian
    BibleVersionMeta(
      id: 'TAGALOG',
      name: 'Ang Dating Biblia (1905)',
      language: 'Tagalog',
      languageCode: 'tl',
      sizeDisplay: '4.7 MB',
      description: 'The classic public domain 1905 Tagalog Bible.',
    ),

    // Esperanto
    BibleVersionMeta(
      id: 'ESPERANTO',
      name: 'Esperanta Biblio',
      language: 'Esperanto',
      languageCode: 'eo',
      sizeDisplay: '3.8 MB',
      description: 'A complete Esperanto translation of the Bible.',
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

    // Malayalam (1910)
    BibleVersionMeta(
      id: 'MAL1910',
      name: 'Sathyavedapusthakam (1910)',
      language: 'Malayalam',
      languageCode: 'ml',
      sizeDisplay: '10.5 MB',
      description: 'The historic 1910 Malayalam Bible, Sathyavedapusthakam.',
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
