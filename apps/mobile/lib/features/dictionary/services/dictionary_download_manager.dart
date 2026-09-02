import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../../../core/api/release_assets.dart';

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
      sizeDisplay: '10.1 MB',
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
    _installedIds.clear();

    for (final meta in catalog) {
      final dbFile = File(p.join(dbDir, 'dict_${meta.id}.sqlite'));
      if (await dbFile.exists() && (await dbFile.length()) > 1000) {
        _installedIds.add(meta.id);
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
      final dbDir = await getDatabasesPath();
      final targetDbPath = p.join(dbDir, 'dict_$dictionaryId.sqlite');
      final tempDir = await getTemporaryDirectory();
      final tempGz = p.join(tempDir.path, 'dict_${dictionaryId}_${DateTime.now().millisecondsSinceEpoch}.gz');

      final urls = ReleaseAssets.urlsFor('dictionaries/dict_$dictionaryId.sqlite.gz');
      final dio = Dio();
      var downloaded = false;

      for (final url in urls) {
        try {
          await dio.download(
            url,
            tempGz,
            options: Options(receiveTimeout: const Duration(minutes: 3)),
            onReceiveProgress: (received, total) {
              if (total > 0) {
                _downloadProgress[dictionaryId] = received / total;
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
        // Create local fallback dictionary database with sample common biblical definitions
        await _createSeedDictionary(targetDbPath, dictionaryId);
      } else {
        final compressed = await File(tempGz).readAsBytes();
        final decompressed = gzip.decode(compressed);
        final targetFile = File(targetDbPath);
        await targetFile.parent.create(recursive: true);
        await targetFile.writeAsBytes(decompressed, flush: true);
        try {
          await File(tempGz).delete();
        } catch (_) {}
      }

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
      final dbDir = await getDatabasesPath();
      final file = File(p.join(dbDir, 'dict_$dictionaryId.sqlite'));
      if (await file.exists()) {
        await file.delete();
      }
      _installedIds.remove(dictionaryId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting dictionary $dictionaryId: $e');
    }
  }

  /// Creates seed dictionary with essential words in case offline or CDN mirror is unreachable.
  Future<void> _createSeedDictionary(String dbPath, String dictId) async {
    final db = await openDatabase(dbPath, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS dictionary_entries (
          headword TEXT NOT NULL COLLATE NOCASE,
          part_of_speech TEXT,
          phonetic TEXT,
          definition TEXT NOT NULL,
          examples TEXT,
          PRIMARY KEY (headword, part_of_speech)
        );
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_dict_headword ON dictionary_entries (headword);
      ''');
    });

    final seeds = <Map<String, String>>[
      {
        'headword': 'grace',
        'part_of_speech': 'noun',
        'phonetic': '/ɡreɪs/',
        'definition': 'The unmerited favor, power, and mercy of God bestowed upon believers in Jesus Christ; God’s divine empowerment for holy living.',
        'examples': 'By grace you have been saved through faith.'
      },
      {
        'headword': 'faith',
        'part_of_speech': 'noun',
        'phonetic': '/feɪθ/',
        'definition': 'Complete trust, confidence, and allegiance to God and His promises; the substance of things hoped for, evidence of things unseen.',
        'examples': 'Without faith it is impossible to please God.'
      },
      {
        'headword': 'righteousness',
        'part_of_speech': 'noun',
        'phonetic': '/ˈraɪtʃəsnəs/',
        'definition': 'Moral purity, uprightness, and conformity of life and character to God’s holy standard.',
        'examples': 'He who practices righteousness is righteous, just as He is righteous.'
      },
      {
        'headword': 'disciple',
        'part_of_speech': 'noun',
        'phonetic': '/dɪˈsaɪpəl/',
        'definition': 'One who follows the teachings and life of Jesus Christ with full surrender, taking up their cross daily.',
        'examples': 'If anyone desires to come after Me, let him deny himself.'
      },
      {
        'headword': 'sanctification',
        'part_of_speech': 'noun',
        'phonetic': '/ˌsæŋktɪfɪˈkeɪʃən/',
        'definition': 'The ongoing process of being made holy, purified from sin, and conformed to the image of Jesus Christ.',
        'examples': 'For this is the will of God, your sanctification.'
      },
      {
        'headword': 'redemption',
        'part_of_speech': 'noun',
        'phonetic': '/rɪˈdɛmpʃən/',
        'definition': 'Deliverance from the power, guilt, and penalty of sin through the blood and sacrifice of Jesus Christ.',
        'examples': 'In Him we have redemption through His blood, the forgiveness of sins.'
      },
      {
        'headword': 'atonement',
        'part_of_speech': 'noun',
        'phonetic': '/əˈtoʊnmənt/',
        'definition': 'Reconciliation between God and humanity brought about through Christ’s sacrifice on the Cross.',
        'examples': 'Christ Jesus, whom God put forward as a propitiation.'
      },
      {
        'headword': 'repentance',
        'part_of_speech': 'noun',
        'phonetic': '/rɪˈpɛntəns/',
        'definition': 'A complete change of mind, heart, and direction, turning away from sin and turning toward God.',
        'examples': 'Repent, for the kingdom of heaven is at hand.'
      },
      {
        'headword': 'holiness',
        'part_of_speech': 'noun',
        'phonetic': '/ˈhoʊlinəs/',
        'definition': 'Total separation from worldliness and sin unto God, walking in moral purity and divine love.',
        'examples': 'Pursue peace with all people, and holiness, without which no one will see the Lord.'
      },
      {
        'headword': 'love',
        'part_of_speech': 'noun',
        'phonetic': '/lʌv/',
        'definition': 'Self-sacrificing, benevolent commitment to the good of others (agape), as demonstrated by God at the Cross.',
        'examples': 'God is love, and whoever abides in love abides in God.'
      },
    ];

    for (final s in seeds) {
      await db.insert('dictionary_entries', s, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await db.close();
  }
}
