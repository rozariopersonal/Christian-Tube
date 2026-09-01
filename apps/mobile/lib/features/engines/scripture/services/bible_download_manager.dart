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
  // Versions whose download does not advertise a total byte count (so the bar
  // must render indeterminate instead of a frozen 0-progress bar).
  final Set<String> _indeterminateIds = {};
  final Set<String> _downloadingIds = {};
  // Bibles are downloaded on demand from the releases repo; nothing ships in
  // the app bundle.
  Set<String> _installedIds = {};

  static const List<BibleVersionMeta> catalog = [
    // English
    BibleVersionMeta(
      id: 'BSB',
      name: 'Berean Standard Bible',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1.4 MB',
      description:
          'Modern, accurate English translation dedicated to the public domain by Bible Hub and Berean Bible Translation Committee.',
      license: 'Public Domain (CC0)',
      licenseUrl: 'https://berean.bible/licensing.htm',
      copyrightHolder: 'Bible Hub / Berean.Bible',
      attributionText:
          'The Holy Bible, Berean Standard Bible, BSB is produced in cooperation with Bible Hub, Discovery Bible, OpenBible.com, and the Berean Bible Translation Committee. Dedicated to the Public Domain.',
      sourceUrl: 'https://berean.bible',
    ),
    BibleVersionMeta(
      id: 'WEB',
      name: 'World English Bible',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1.4 MB',
      description: 'Modern, accurate, and easy to read English translation.',
      license: 'Public Domain',
      licenseUrl: 'https://ebible.org/web/',
      copyrightHolder: 'Rainbow Missions, Inc.',
      attributionText:
          'The World English Bible is in the Public Domain (not copyrighted). Dedicated to God.',
      sourceUrl: 'https://ebible.org/web/',
    ),
    BibleVersionMeta(
      id: 'KJV',
      name: 'King James Version',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1.3 MB',
      description: 'The historic and revered 1611 English Bible.',
      license: 'Public Domain',
      copyrightHolder: 'Public Domain (Crown rights in UK only)',
      attributionText: 'King James Version 1611 Authorized Version. In the Public Domain.',
      sourceUrl: 'https://ebible.org/kjv/',
    ),
    BibleVersionMeta(
      id: 'ASV',
      name: 'American Standard Version',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1.4 MB',
      description: 'Accurate literal standard American translation.',
      license: 'Public Domain',
      copyrightHolder: 'Thomas Nelson & Sons (1901)',
      attributionText: 'American Standard Version (1901). In the Public Domain.',
      sourceUrl: 'https://ebible.org/asv/',
    ),
    BibleVersionMeta(
      id: 'BBE',
      name: 'Bible in Basic English',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1.2 MB',
      description: 'Simplified 850-word standard English vocabulary.',
      license: 'Public Domain',
      copyrightHolder: 'S. H. Hooke / Cambridge University Press',
      attributionText: 'Bible in Basic English (1949/1964). In the Public Domain.',
      sourceUrl: 'https://ebible.org/bbe/',
    ),
    BibleVersionMeta(
      id: 'YLT',
      name: "Young's Literal Translation",
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '4.1 MB',
      description:
          'Ultra-literal 1898 translation that preserves the word order of the originals.',
      license: 'Public Domain',
      copyrightHolder: 'Robert Young (1898)',
      attributionText: 'Young\'s Literal Translation (1898 revision). Public Domain.',
      sourceUrl: 'https://api.getbible.net/v2/ylt.json',
    ),
    BibleVersionMeta(
      id: 'WB',
      name: "Webster's Bible (1833)",
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '4.0 MB',
      description:
          'Noah Webster\'s 1833 revision of the King James with modernized grammar.',
      license: 'Public Domain',
      copyrightHolder: 'Noah Webster (1833)',
      attributionText: 'Webster\'s Bible (1833). Public Domain.',
      sourceUrl: 'https://api.getbible.net/v2/wb.json',
    ),

    // German
    BibleVersionMeta(
      id: 'LUTHER1545',
      name: 'Lutherbibel (1545)',
      language: 'German',
      languageCode: 'de',
      sizeDisplay: '4.0 MB',
      description: 'Martin Luther\'s classic 1545 German Bible.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/luther1545.json',
    ),
    BibleVersionMeta(
      id: 'ELBERFELDER1905',
      name: 'Elberfelder Bibel (1905)',
      language: 'German',
      languageCode: 'de',
      sizeDisplay: '4.2 MB',
      description: 'Highly literal German translation from 1905.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/elberfelder1905.json',
    ),
    BibleVersionMeta(
      id: 'ELBERFELDER',
      name: 'Elberfelder Bibel (1871)',
      language: 'German',
      languageCode: 'de',
      sizeDisplay: '4.2 MB',
      description: 'The original 1871 Elberfelder translation.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/elberfelder.json',
    ),

    // Spanish
    BibleVersionMeta(
      id: 'SSE',
      name: 'Sagradas Escrituras (1569)',
      language: 'Spanish',
      languageCode: 'es',
      sizeDisplay: '3.8 MB',
      description: 'The classic 1569 Spanish Bible of Casiodoro de Reina.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/sse.json',
    ),

    // French
    BibleVersionMeta(
      id: 'MARTIN',
      name: 'Bible Martin (1744)',
      language: 'French',
      languageCode: 'fr',
      sizeDisplay: '4.4 MB',
      description: 'David Martin\'s faithful 1744 French translation.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/martin.json',
    ),

    // Italian
    BibleVersionMeta(
      id: 'RIVEDUTA',
      name: 'Riveduta (1927)',
      language: 'Italian',
      languageCode: 'it',
      sizeDisplay: '4.1 MB',
      description: 'The 1927 revised Italian Bible.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/riveduta.json',
    ),
    BibleVersionMeta(
      id: 'DIODATI',
      name: 'Bibbia Diodati',
      language: 'Italian',
      languageCode: 'it',
      sizeDisplay: '4.2 MB',
      description: 'Giovanni Diodati\'s 1607 classic Italian translation.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/diodati.json',
    ),

    // Dutch
    BibleVersionMeta(
      id: 'STATENVERTALING',
      name: 'Statenvertaling (1637)',
      language: 'Dutch',
      languageCode: 'nl',
      sizeDisplay: '4.2 MB',
      description: 'The authorized Dutch State Translation of 1637.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/statenvertaling.json',
    ),

    // Polish
    BibleVersionMeta(
      id: 'POLGDANSKA',
      name: 'Biblia Gdańska (1881)',
      language: 'Polish',
      languageCode: 'pl',
      sizeDisplay: '3.9 MB',
      description: 'The beloved Polish Gdańsk Bible.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/polgdanska.json',
    ),

    // Hungarian
    BibleVersionMeta(
      id: 'KAROLI',
      name: 'Károlyi Biblia',
      language: 'Hungarian',
      languageCode: 'hu',
      sizeDisplay: '4.1 MB',
      description: 'The classic Hungarian Bible of Gáspár Károlyi (1590).',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/karoli.json',
    ),

    // Nordic
    BibleVersionMeta(
      id: 'SWEDISH',
      name: 'Svenska Bibeln (1917)',
      language: 'Swedish',
      languageCode: 'sv',
      sizeDisplay: '4.2 MB',
      description: 'The official 1917 Swedish Bible.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/swedish.json',
    ),
    BibleVersionMeta(
      id: 'DANISH',
      name: 'Dansk Bibel',
      language: 'Danish',
      languageCode: 'da',
      sizeDisplay: '3.6 MB',
      description: 'The classic Danish Bible translation.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/danish.json',
    ),
    BibleVersionMeta(
      id: 'PYHAAMATTU1933',
      name: 'Pyhä Raamattu (1933/1938)',
      language: 'Finnish',
      languageCode: 'fi',
      sizeDisplay: '4.1 MB',
      description: 'The classical Finnish Bible translation.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/pyharaamattu1933.json',
    ),

    // Slavic
    BibleVersionMeta(
      id: 'BKR',
      name: 'Bible kralická',
      language: 'Czech',
      languageCode: 'cs',
      sizeDisplay: '3.8 MB',
      description: 'The historic Czech King James of 1613.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/bkr.json',
    ),
    BibleVersionMeta(
      id: 'CROATIA',
      name: 'Biblija (Croatian)',
      language: 'Croatian',
      languageCode: 'hr',
      sizeDisplay: '3.3 MB',
      description: 'A classic Croatian Bible translation.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/croatia.json',
    ),

    // Albanian
    BibleVersionMeta(
      id: 'ALB',
      name: 'Bibla Shqipe',
      language: 'Albanian',
      languageCode: 'sq',
      sizeDisplay: '4.2 MB',
      description: 'The 1827 Albanian Bible, the oldest Albanian translation.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/alb.json',
    ),

    // East Asian
    BibleVersionMeta(
      id: 'KOREAN',
      name: 'Korean Bible',
      language: 'Korean',
      languageCode: 'ko',
      sizeDisplay: '4.3 MB',
      description: 'Classic Korean Bible translation.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/korean.json',
    ),
    BibleVersionMeta(
      id: 'VIETNAMESE',
      name: 'Kinh Thánh (1934)',
      language: 'Vietnamese',
      languageCode: 'vi',
      sizeDisplay: '4.9 MB',
      description: 'The 1934 public domain Vietnamese Bible.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/vietnamese.json',
    ),
    BibleVersionMeta(
      id: 'CUT',
      name: 'Union Version (Traditional)',
      language: 'Chinese',
      languageCode: 'zh-Hant',
      sizeDisplay: '3.4 MB',
      description: 'The classic traditional Chinese Union Version.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/cut.json',
    ),
    BibleVersionMeta(
      id: 'JAPKOUGO',
      name: '口語訳聖書 (1954/1955)',
      language: 'Japanese',
      languageCode: 'ja',
      sizeDisplay: '5.1 MB',
      description: 'The Japanese colloquial translation of 1954/1955.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/japkougo.json',
    ),

    // Southeast Asian
    BibleVersionMeta(
      id: 'TAGALOG',
      name: 'Ang Dating Biblia (1905)',
      language: 'Tagalog',
      languageCode: 'tl',
      sizeDisplay: '4.7 MB',
      description: 'The classic public domain 1905 Tagalog Bible.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/tagalog.json',
    ),

    // Esperanto
    BibleVersionMeta(
      id: 'ESPERANTO',
      name: 'Esperanta Biblio',
      language: 'Esperanto',
      languageCode: 'eo',
      sizeDisplay: '3.8 MB',
      description: 'A complete Esperanto translation of the Bible.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/esperanto.json',
    ),

    // Tamil
    BibleVersionMeta(
      id: 'TAOBVSI',
      name: 'Tamil Old Version (பரிசுத்த வேதாகமம்)',
      language: 'Tamil',
      languageCode: 'tam',
      sizeDisplay: '1.5 MB',
      description:
          'The classic Bower revision standard Tamil Bible used across Tamil churches.',
      isDefaultBundled: true,
      license: 'Public Domain (India)',
      sourceUrl: 'https://github.com/berinaniesh/bible-tamil',
      attributionText: 'Tamil Old Version Bible (Bower-Balfour Revision). In the Public Domain in India.',
    ),

    // Malayalam
    BibleVersionMeta(
      id: 'MAL_IRV',
      name: 'Malayalam IRV (മലയാളം IRV)',
      language: 'Malayalam',
      languageCode: 'mal',
      sizeDisplay: '1.5 MB',
      description:
          'Indian Revised Version in Malayalam, faithful to original texts.',
      license: 'CC BY-SA 4.0',
      licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
      copyrightHolder: 'Bridge Connectivity Solutions Pvt. Ltd.',
      attributionText:
          'Indian Revised Version (IRV) Malayalam © 2017 by Bridge Connectivity Solutions Pvt. Ltd. is licensed under a Creative Commons Attribution-ShareAlike 4.0 International License.',
      sourceUrl: 'https://ebible.org/mal/',
    ),

    // Telugu
    BibleVersionMeta(
      id: 'TEL_IRV',
      name: 'Telugu IRV (తెలుగు IRV)',
      language: 'Telugu',
      languageCode: 'tel',
      sizeDisplay: '1.5 MB',
      description:
          'Indian Revised Version in Telugu with clear devotional phrasing.',
      license: 'CC BY-SA 4.0',
      licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
      copyrightHolder: 'Bridge Connectivity Solutions Pvt. Ltd.',
      attributionText:
          'Indian Revised Version (IRV) Telugu © 2019 by Bridge Connectivity Solutions Pvt. Ltd. is licensed under a Creative Commons Attribution-ShareAlike 4.0 International License.',
      sourceUrl: 'https://ebible.org/tel2017/',
    ),

    // Kannada
    BibleVersionMeta(
      id: 'KAN_IRV',
      name: 'Kannada IRV (ಕನ್ನಡ IRV)',
      language: 'Kannada',
      languageCode: 'kan',
      sizeDisplay: '1.5 MB',
      description: 'Indian Revised Version in Kannada language.',
      license: 'CC BY-SA 4.0',
      licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
      copyrightHolder: 'Bridge Connectivity Solutions Pvt. Ltd.',
      attributionText:
          'Indian Revised Version (IRV) Kannada © 2017 by Bridge Connectivity Solutions Pvt. Ltd. is licensed under a Creative Commons Attribution-ShareAlike 4.0 International License.',
      sourceUrl: 'https://ebible.org/kanirv/',
    ),

    // Hindi
    BibleVersionMeta(
      id: 'HIN_IRV',
      name: 'Hindi IRV (हिन्दी IRV)',
      language: 'Hindi',
      languageCode: 'hin',
      sizeDisplay: '1.5 MB',
      description: 'Clear modern Hindi translation for everyday devotions.',
      license: 'CC BY-SA 4.0',
      licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
      copyrightHolder: 'Bridge Connectivity Solutions Pvt. Ltd.',
      attributionText:
          'Indian Revised Version (IRV) Hindi © 2017 by Bridge Connectivity Solutions Pvt. Ltd. is licensed under a Creative Commons Attribution-ShareAlike 4.0 International License.',
      sourceUrl: 'https://ebible.org/hin2017/',
    ),

    // Malayalam (1910)
    BibleVersionMeta(
      id: 'MAL1910',
      name: 'Sathyavedapusthakam (1910)',
      language: 'Malayalam',
      languageCode: 'ml',
      sizeDisplay: '10.5 MB',
      description: 'The historic 1910 Malayalam Bible, Sathyavedapusthakam.',
      license: 'Public Domain',
      sourceUrl: 'https://api.getbible.net/v2/mal1910.json',
      attributionText: 'Sathyavedapusthakam (1910). In the Public Domain.',
    ),
  ];

  Set<String> get installedIds => _installedIds;

  bool isInstalled(String versionId) => _installedIds.contains(versionId);
  bool isDownloading(String versionId) => _downloadingIds.contains(versionId);
  double getProgress(String versionId) => _downloadProgress[versionId] ?? 0.0;

  /// True when the running download for [versionId] has no known total byte
  /// count, so the UI must show an indeterminate progress bar.
  bool isIndeterminate(String versionId) =>
      _indeterminateIds.contains(versionId);

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
      _indeterminateIds.remove(meta.id);
      notifyListeners();
    }
  }

  Future<bool> _downloadVersionText(BibleVersionMeta meta) async {
    final tempDir = await getTemporaryDirectory();
    final filePath = p.join(tempDir.path,
        'bible_${meta.id.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}.json');
    final urls =
        ReleaseAssets.urlsFor('bibles/bible_${meta.id.toLowerCase()}.json');
    final dio = Dio();
    var downloaded = false;
    for (final url in urls) {
      _downloadProgress[meta.id] = 0.0;
      _indeterminateIds.add(meta.id);
      notifyListeners();
      try {
        await dio.download(
          url,
          filePath,
          options: Options(
            // Large payloads can take a while on slow networks.
            receiveTimeout: const Duration(minutes: 5),
          ),
          onReceiveProgress: (received, total) {
            if (total != -1 && total > 0) {
              // The server told us the total size -> determinate progress.
              _indeterminateIds.remove(meta.id);
              _downloadProgress[meta.id] = received / total;
            } else {
              // Unknown total (chunked/no content-length) -> keep the bar in
              // an animated indeterminate state so progress is always visible.
              _indeterminateIds.add(meta.id);
            }
            notifyListeners();
          },
        );
        downloaded = true;
        _indeterminateIds.remove(meta.id);
        _downloadProgress[meta.id] = 1.0;
        notifyListeners();
        break;
      } catch (e) {
        debugPrint('Failed to download ${meta.id} from $url: $e');
      }
    }
    if (!downloaded) return false;

    try {
      final jsonStr = await File(filePath).readAsString();
      await File(filePath).delete();

      final books = (jsonDecode(jsonStr) as Map<String, dynamic>)['books']
          as List<dynamic>;
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
