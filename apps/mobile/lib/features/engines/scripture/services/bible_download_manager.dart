import 'dart:async';
import 'package:flutter/foundation.dart';
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
  Set<String> _installedIds = {'WEB', 'KJV', 'TAOBVSI'};

  static const List<BibleVersionMeta> catalog = [
    // English
    BibleVersionMeta(
      id: 'WEB',
      name: 'World English Bible',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1.4 MB',
      description: 'Modern, accurate, and easy to read English translation.',
      isDefaultBundled: true,
    ),
    BibleVersionMeta(
      id: 'KJV',
      name: 'King James Version',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1.3 MB',
      description: 'The historic and revered 1611 English Bible.',
      isDefaultBundled: true,
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

    // Telugu
    BibleVersionMeta(
      id: 'TEL_IRV',
      name: 'Telugu IRV (తెలుగు IRV)',
      language: 'Telugu',
      languageCode: 'tel',
      sizeDisplay: '1.5 MB',
      description: 'Modern Telugu translation.',
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
    _installedIds = ids.toSet();
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
      // Smooth progress animation for seamless UX
      for (int i = 1; i <= 10; i++) {
        await Future.delayed(const Duration(milliseconds: 120));
        _downloadProgress[meta.id] = i / 10.0;
        notifyListeners();
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

  Future<void> removeVersion(String versionId) async {
    if (versionId == 'WEB') return; // Do not delete default fallback
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
