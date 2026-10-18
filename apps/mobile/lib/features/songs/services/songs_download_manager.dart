import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../core/api/github_data_service.dart';
import '../adapters/sqlite_songs_catalog_adapter.dart';

List<int> _gzipDecompress(List<int> bytes) => gzip.decode(bytes);

/// Owns the optional offline songs package lifecycle: download the prebuilt
/// `songs.sqlite.gz` from the releases repo, install it into the app databases
/// directory, detect installation, and delete it on demand.
///
/// Mirrors [DictionaryDownloadManager] for the single, unified songs catalog.
class SongsDownloadManager extends ChangeNotifier {
  static final SongsDownloadManager _instance = SongsDownloadManager._internal();
  factory SongsDownloadManager() => _instance;
  SongsDownloadManager._internal();

  bool _installed = false;
  bool _downloading = false;
  double _progress = 0.0;
  bool _isInitialized = false;

  /// Whether the offline songs database is present on disk.
  bool get isInstalled => _installed;

  /// Whether a download/install is currently in flight.
  bool get isDownloading => _downloading;

  /// Download progress in 0.0..1.0 (partial during the active transfer).
  double get downloadProgress => _progress;

  static Future<String> _dbPath() async {
    final dir = await getDatabasesPath();
    return p.join(dir, SqliteSongsCatalogAdapter.defaultFileName);
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await refreshInstalled();
  }

  /// Re-scans disk (source of truth) after install/delete or on app start.
  Future<void> refreshInstalled() async {
    if (kIsWeb) {
      _installed = false;
    } else {
      try {
        _installed = await File(await _dbPath()).exists();
      } catch (_) {
        _installed = false;
      }
    }
    notifyListeners();
  }

  /// Downloads and installs the offline songs package (CDN first, GitHub
  /// fallback). Supports downloading per-language packages (e.g. Tamil or
  /// English) and merging into the target database.
  Future<bool> download({String? language}) async {
    if (kIsWeb || _downloading) return false;

    _downloading = true;
    _progress = 0.0;
    notifyListeners();

    final tempDir = await getTemporaryDirectory();
    final tempGz = p.join(
      tempDir.path,
      'songs_${DateTime.now().millisecondsSinceEpoch}.gz',
    );

    try {
      await SqliteSongsCatalogAdapter().close();

      final urls = (language != null && language.trim().isNotEmpty && language.toLowerCase() != 'all')
          ? GitHubDataService.songsLanguageSqliteUrls(language)
          : GitHubDataService.songsSqliteUrls();

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
                _progress = received / total;
                notifyListeners();
              }
            },
          );
          if (await File(tempGz).length() > 5000) {
            downloaded = true;
            break;
          }
        } catch (e) {
          debugPrint('Songs download failed from $url: $e');
          continue;
        }
      }
      if (!downloaded) {
        debugPrint('Songs download failed from all mirrors.');
        return false;
      }

      final compressed = await File(tempGz).readAsBytes();
      final decompressed = await compute(_gzipDecompress, compressed);

      final target = File(await _dbPath());
      if (await target.exists()) {
        final tempSqlite = p.join(
          tempDir.path,
          'songs_merge_${DateTime.now().millisecondsSinceEpoch}.sqlite',
        );
        await File(tempSqlite).writeAsBytes(decompressed, flush: true);
        final sourceDb = await openReadOnlyDatabase(tempSqlite);
        final destDb = await openDatabase(target.path);

        final songs = await sourceDb.query('songs');
        final verses = await sourceDb.query('song_verses');

        final batch = destDb.batch();
        for (final s in songs) {
          batch.insert('songs', s, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final v in verses) {
          batch.insert('song_verses', v, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);

        await sourceDb.close();
        await destDb.close();
        try {
          await File(tempSqlite).delete();
        } catch (_) {}
      } else {
        await target.parent.create(recursive: true);
        await target.writeAsBytes(decompressed, flush: true);
      }

      try {
        await File(tempGz).delete();
      } catch (_) {}

      _installed = true;
      return true;
    } catch (e) {
      debugPrint('SongsDownloadManager error: $e');
      return false;
    } finally {
      _downloading = false;
      notifyListeners();
    }
  }

  /// Removes the offline songs database and returns to live streaming.
  Future<void> delete() async {
    if (kIsWeb) return;
    try {
      await SqliteSongsCatalogAdapter().close();
      final file = File(await _dbPath());
      if (await file.exists()) await file.delete();
      for (final sfx in const ['-wal', '-shm']) {
        final side = File('${file.path}$sfx');
        if (await side.exists()) await side.delete();
      }
    } catch (e) {
      debugPrint('Error removing songs database: $e');
    } finally {
      _installed = false;
      notifyListeners();
    }
  }
}