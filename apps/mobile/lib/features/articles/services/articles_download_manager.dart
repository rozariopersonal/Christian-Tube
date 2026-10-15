import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/api/github_data_service.dart';

/// Manages per-language offline articles downloads (e.g. English, Tamil, German).
class ArticlesDownloadManager extends ChangeNotifier {
  static final ArticlesDownloadManager _instance =
      ArticlesDownloadManager._internal();
  factory ArticlesDownloadManager() => _instance;
  ArticlesDownloadManager._internal();

  final Set<String> _installedLanguages = {};
  final Map<String, double> _downloadProgress = {};
  final Set<String> _downloadingLanguages = {};
  bool _isInitialized = false;

  Set<String> get installedLanguages => Set.unmodifiable(_installedLanguages);

  bool isInstalled(String lang) =>
      _installedLanguages.contains(lang.trim().toLowerCase());

  bool isDownloading(String lang) =>
      _downloadingLanguages.contains(lang.trim().toLowerCase());

  double getProgress(String lang) =>
      _downloadProgress[lang.trim().toLowerCase()] ?? 0.0;

  static Future<String> _dbPath(String lang) async {
    final dir = await getDatabasesPath();
    return p.join(dir, 'articles_${lang.toLowerCase()}.sqlite');
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await refreshInstalled();
  }

  /// Scans databases directory for installed articles SQLite databases.
  Future<void> refreshInstalled() async {
    if (kIsWeb) {
      _installedLanguages.clear();
      notifyListeners();
      return;
    }

    try {
      final dir = Directory(await getDatabasesPath());
      if (await dir.exists()) {
        final files = await dir.list().toList();
        final installed = <String>{};
        for (final f in files) {
          final name = p.basename(f.path);
          if (name.startsWith('articles_') && name.endsWith('.sqlite')) {
            final lang = name.replaceFirst('articles_', '').replaceFirst('.sqlite', '');
            if (lang.isNotEmpty) installed.add(lang);
          }
        }
        _installedLanguages
          ..clear()
          ..addAll(installed);
      }
    } catch (e) {
      debugPrint('ArticlesDownloadManager refresh error: $e');
    }
    notifyListeners();
  }

  /// Downloads and installs the offline articles package for [lang].
  Future<bool> downloadLanguage(String lang) async {
    final code = lang.trim().toLowerCase();
    if (kIsWeb || _downloadingLanguages.contains(code)) return false;

    _downloadingLanguages.add(code);
    _downloadProgress[code] = 0.0;
    notifyListeners();

    final tempDir = await getTemporaryDirectory();
    final tempGz = p.join(
      tempDir.path,
      'articles_${code}_${DateTime.now().millisecondsSinceEpoch}.gz',
    );

    try {
      final urls = GitHubDataService.articlesLanguageSqliteUrls(code);
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
                _downloadProgress[code] = received / total;
                notifyListeners();
              }
            },
          );
          if (await File(tempGz).length() > 500) {
            downloaded = true;
            break;
          }
        } catch (e) {
          debugPrint('Articles download failed from $url: $e');
        }
      }

      if (!downloaded) {
        debugPrint('Articles download failed from all mirrors for $code.');
        return false;
      }

      final compressed = await File(tempGz).readAsBytes();
      final decompressed = gzip.decode(compressed);

      final targetPath = await _dbPath(code);
      final target = File(targetPath);
      if (await target.exists()) await target.delete();
      for (final sfx in const ['-wal', '-shm']) {
        final side = File('$targetPath$sfx');
        if (await side.exists()) await side.delete();
      }

      await target.writeAsBytes(decompressed, flush: true);
      try {
        await File(tempGz).delete();
      } catch (_) {}

      await refreshInstalled();
      return true;
    } catch (e) {
      debugPrint('Articles install error for $code: $e');
      return false;
    } finally {
      _downloadingLanguages.remove(code);
      _downloadProgress.remove(code);
      notifyListeners();
    }
  }

  /// Deletes the installed SQLite database for [lang].
  Future<bool> deleteLanguage(String lang) async {
    final code = lang.trim().toLowerCase();
    if (kIsWeb) return false;

    try {
      final targetPath = await _dbPath(code);
      final target = File(targetPath);
      if (await target.exists()) await target.delete();
      for (final sfx in const ['-wal', '-shm']) {
        final side = File('$targetPath$sfx');
        if (await side.exists()) await side.delete();
      }
      await refreshInstalled();
      return true;
    } catch (e) {
      debugPrint('Articles delete error for $code: $e');
      return false;
    }
  }
}
