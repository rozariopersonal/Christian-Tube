import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../../../../core/api/release_assets.dart';
import 'dictionary_service.dart';

class DictionaryMeta {
  final String id;
  final String name;
  final String language;
  final String languageCode;
  final String sizeDisplay;
  final String description;
  final bool isBiblical;

  const DictionaryMeta({
    required this.id,
    required this.name,
    required this.language,
    required this.languageCode,
    required this.sizeDisplay,
    required this.description,
    this.isBiblical = false,
  });
}

class DictionaryDownloadManager extends ChangeNotifier {
  static final DictionaryDownloadManager _instance = DictionaryDownloadManager._internal();
  factory DictionaryDownloadManager() => _instance;
  DictionaryDownloadManager._internal();

  final Map<String, double> _downloadProgress = {};
  final Set<String> _downloadingIds = {};
  final Set<String> _installedIds = {};
  bool _isInitialized = false;

  Map<String, double> get downloadProgress => _downloadProgress;
  Set<String> get downloadingIds => _downloadingIds;
  Set<String> get installedIds => _installedIds;

  static const List<DictionaryMeta> catalog = [
    // General English
    DictionaryMeta(
      id: 'en',
      name: 'English Dictionary',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '12.5 MB',
      description: 'Standard English vocabulary and biblical terms.',
    ),
    // Biblical Dictionaries
    DictionaryMeta(
      id: 'eastons',
      name: "Easton's Bible Dictionary",
      language: 'English (Biblical)',
      languageCode: 'en',
      sizeDisplay: '1.8 MB',
      description: 'Over 4,000 biblical terms, persons, places, customs, and doctrines.',
      isBiblical: true,
    ),
    DictionaryMeta(
      id: 'strongs',
      name: "Strong's Greek & Hebrew Lexicon",
      language: 'Biblical Languages',
      languageCode: 'biblical',
      sizeDisplay: '2.1 MB',
      description: 'Hebrew and Greek concordances with root definitions and Strong numbers.',
      isBiblical: true,
    ),
    // Easily supportable global languages
    DictionaryMeta(
      id: 'es',
      name: 'Diccionario Español',
      language: 'Spanish',
      languageCode: 'es',
      sizeDisplay: '3.1 MB',
      description: 'Definiciones en español para lectura general y bíblica.',
    ),
    DictionaryMeta(
      id: 'fr',
      name: 'Dictionnaire Français',
      language: 'French',
      languageCode: 'fr',
      sizeDisplay: '3.2 MB',
      description: 'Définitions complètes en langue française.',
    ),
    DictionaryMeta(
      id: 'de',
      name: 'Deutsches Wörterbuch',
      language: 'German',
      languageCode: 'de',
      sizeDisplay: '3.0 MB',
      description: 'Worterklärungen und Definitionen auf Deutsch.',
    ),
    DictionaryMeta(
      id: 'pt',
      name: 'Dicionário Português',
      language: 'Portuguese',
      languageCode: 'pt',
      sizeDisplay: '2.9 MB',
      description: 'Definições em português para leitura fluida.',
    ),
    DictionaryMeta(
      id: 'ru',
      name: 'Толковый словарь',
      language: 'Russian',
      languageCode: 'ru',
      sizeDisplay: '3.5 MB',
      description: 'Словарь русского языка для чтения книг и Библии.',
    ),
    DictionaryMeta(
      id: 'hi',
      name: 'हिंदी शब्दकोश (Hindi Dictionary)',
      language: 'Hindi',
      languageCode: 'hi',
      sizeDisplay: '2.4 MB',
      description: 'हिंदी में शब्दार्थ एवं परिभाषाएँ।',
    ),
    DictionaryMeta(
      id: 'ta',
      name: 'தமிழ் அகராதி',
      language: 'Tamil',
      languageCode: 'ta',
      sizeDisplay: '26.1 MB',
      description: 'தமிழ் சத்யவேத அகராதி மற்றும் ஆவிக்குரிய விளக்கங்கள் (Tamil Bible Dictionary).',
    ),
    DictionaryMeta(
      id: 'ml',
      name: 'മലയാളം നിഘണ്ടു (Malayalam Dictionary)',
      language: 'Malayalam',
      languageCode: 'ml',
      sizeDisplay: '2.5 MB',
      description: 'മലയാളം സത്യവേദപുസ്തക പദാവലിയും ആത്മീയ അർത്ഥങ്ങളും (Malayalam Bible).',
    ),
    DictionaryMeta(
      id: 'te',
      name: 'తెలుగు నిఘంటువు (Telugu Dictionary)',
      language: 'Telugu',
      languageCode: 'te',
      sizeDisplay: '2.5 MB',
      description: 'తెలుగు పరిశుద్ధ గ్రంథ పదకోశము మరియు వివరణలు (Telugu Bible).',
    ),
    DictionaryMeta(
      id: 'kn',
      name: 'ಕನ್ನಡ ನಿಘಂಟು (Kannada Dictionary)',
      language: 'Kannada',
      languageCode: 'kn',
      sizeDisplay: '2.4 MB',
      description: 'ಕನ್ನಡ ಸತ್ಯವೇದ ಪದಕೋಶ ಮತ್ತು ಆಧ್ಯಾತ್ಮಿಕ ವಿವರಣೆಗಳು (Kannada Bible).',
    ),
  ];

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await refreshInstalled();
  }

  Future<void> refreshInstalled() async {
    if (kIsWeb) return;
    final dbDir = await getDatabasesPath();
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}

    _installedIds.clear();

    for (final meta in catalog) {
      final dbFile = File(p.join(dbDir, 'dict_${meta.id}.sqlite'));
      if (await dbFile.exists()) {
        final len = await dbFile.length();

        // Auto-purge ONLY genuinely stale dummy/truncated dictionaries (< 20MB)
        if (meta.id == 'ta' && len < 20 * 1024 * 1024) {
          debugPrint('Stale/incomplete Tamil dictionary detected (${len}B). Purging...');
          await deleteDictionary(meta.id);
          continue;
        }
        if (meta.id == 'ta' && len >= 50 * 1024 * 1024) {
          await prefs?.setInt('dict_ver_${meta.id}', 4);
        }

        if (len > 10000) {
          _installedIds.add(meta.id);
        }
      }
    }
    notifyListeners();
  }

  bool isInstalled(String dictionaryId) => _installedIds.contains(dictionaryId);
  bool isDownloading(String dictionaryId) => _downloadingIds.contains(dictionaryId);

  double getProgress(String dictionaryId) => _downloadProgress[dictionaryId] ?? 0.0;

  Future<bool> downloadDictionary(String dictionaryId) async {
    if (_downloadingIds.contains(dictionaryId)) return false;

    _downloadingIds.add(dictionaryId);
    _downloadProgress[dictionaryId] = 0.0;
    notifyListeners();

    try {
      await DictionaryService().closeDatabase(dictionaryId);

      final dbDir = await getDatabasesPath();
      final targetDbPath = p.join(dbDir, 'dict_$dictionaryId.sqlite');
      final tempDir = await getTemporaryDirectory();
      final tempGz = p.join(tempDir.path, 'dict_${dictionaryId}_${DateTime.now().millisecondsSinceEpoch}.gz');

      final urls = ReleaseAssets.urlsFor('dictionaries/dict_$dictionaryId.sqlite.gz');
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 5),
      ));
      var downloaded = false;

      for (final url in urls) {
        try {
          await dio.download(
            url,
            tempGz,
            onReceiveProgress: (received, total) {
              if (total > 0) {
                _downloadProgress[dictionaryId] = received / total;
                notifyListeners();
              }
            },
          );
          if (await File(tempGz).length() > 5000) {
            downloaded = true;
            break;
          }
        } catch (e) {
          debugPrint('Failed downloading from $url: $e');
          continue;
        }
      }

      if (!downloaded) {
        debugPrint('Dictionary download failed for $dictionaryId from all mirrors.');
        return false;
      }

      final compressed = await File(tempGz).readAsBytes();
      final decompressed = gzip.decode(compressed);

      final targetFile = File(targetDbPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      final wal = File('$targetDbPath-wal');
      if (await wal.exists()) await wal.delete();
      final shm = File('$targetDbPath-shm');
      if (await shm.exists()) await shm.delete();

      await targetFile.parent.create(recursive: true);
      await targetFile.writeAsBytes(decompressed, flush: true);

      try {
        await File(tempGz).delete();
      } catch (_) {}

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('dict_ver_$dictionaryId', 4);
      } catch (_) {}

      _installedIds.add(dictionaryId);
      return true;
    } catch (e) {
      debugPrint('DictionaryDownloadManager error: $e');
      return false;
    } finally {
      _downloadingIds.remove(dictionaryId);
      notifyListeners();
    }
  }

  /// Removes an installed dictionary database from local storage.
  Future<void> deleteDictionary(String dictionaryId) async {
    try {
      await DictionaryService().closeDatabase(dictionaryId);
      final dbDir = await getDatabasesPath();
      final file = File(p.join(dbDir, 'dict_$dictionaryId.sqlite'));
      if (await file.exists()) {
        await file.delete();
      }
      final wal = File(p.join(dbDir, 'dict_$dictionaryId.sqlite-wal'));
      if (await wal.exists()) await wal.delete();
      final shm = File(p.join(dbDir, 'dict_$dictionaryId.sqlite-shm'));
      if (await shm.exists()) await shm.delete();

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('dict_ver_$dictionaryId');
      } catch (_) {}

      _installedIds.remove(dictionaryId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting dictionary $dictionaryId: $e');
    }
  }
}
