import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../articles/services/articles_download_manager.dart';
import '../../bible/services/study/bible_study_updater.dart';
import '../../books/services/book_service.dart';
import '../../dictionary/services/dictionary_download_manager.dart';
import '../../engines/scripture/services/bible_download_manager.dart';
import '../../songs/services/songs_download_manager.dart';
import '../models/downloads_state.dart';
import '../models/storage_breakdown.dart';

/// Calculates real on-disk byte sizes for offline assets across Christian Tube.
class StorageCalculatorService {
  static final StorageCalculatorService instance = StorageCalculatorService._internal();
  factory StorageCalculatorService() => instance;
  StorageCalculatorService._internal();

  Future<int> _fileSizeWithWal(String path) async {
    if (kIsWeb) return 0;
    var total = 0;
    try {
      final f = File(path);
      if (await f.exists()) total += await f.length();
      for (final sfx in const ['-wal', '-shm']) {
        final side = File('$path$sfx');
        if (await side.exists()) total += await side.length();
      }
    } catch (_) {}
    return total;
  }

  /// Calculates the entire [StorageBreakdown] across all download services.
  Future<StorageBreakdown> calculateBreakdown({
    BibleDownloadManager? bibleManager,
    DictionaryDownloadManager? dictManager,
    BookService? bookService,
    SongsDownloadManager? songsManager,
    ArticlesDownloadManager? articlesManager,
  }) async {
    if (kIsWeb) return const StorageBreakdown();

    final bManager = bibleManager ?? BibleDownloadManager();
    final dManager = dictManager ?? DictionaryDownloadManager();
    final bService = bookService ?? BookService.instance;
    final sManager = songsManager ?? SongsDownloadManager();
    final aManager = articlesManager ?? ArticlesDownloadManager();

    final dbDir = await getDatabasesPath();
    final docsDir = await getApplicationDocumentsDirectory();

    // 1. Bibles
    final biblesDbPath = p.join(dbDir, 'christian_tube_bibles.db');
    final biblesBytes = await _fileSizeWithWal(biblesDbPath);
    final biblesCount = BibleDownloadManager.catalog
        .where((b) => bManager.isInstalled(b.id))
        .length;

    // 2. Dictionaries
    var dictionariesBytes = 0;
    for (final meta in DictionaryDownloadManager.catalog) {
      if (dManager.isInstalled(meta.id)) {
        final dictPath = p.join(dbDir, 'dict_${meta.id}.sqlite');
        dictionariesBytes += await _fileSizeWithWal(dictPath);
      }
    }
    final dictsCount = dManager.installedIds.length;

    // 3. Books
    final booksDbPath = p.join(dbDir, 'christian_tube_books.db');
    final booksBytes = await _fileSizeWithWal(booksDbPath);
    final installedBookIds = await bService.getInstalledBookIds();
    final booksCount = installedBookIds.length;

    // 4. Songs
    final songsDbPath = p.join(dbDir, 'songs.sqlite');
    final songsBytes = await _fileSizeWithWal(songsDbPath);
    final songsInstalled = sManager.isInstalled;

    // 5. Articles
    var articlesBytes = 0;
    for (final lang in aManager.installedLanguages) {
      final artPath = p.join(dbDir, 'articles_$lang.sqlite');
      articlesBytes += await _fileSizeWithWal(artPath);
    }
    final articlesCount = aManager.installedLanguages.length;

    // 6. Study DB
    final studyDbPath = await BibleStudyUpdater.getDatabasePath();
    var studyDbBytes = 0;
    if (studyDbPath != null) {
      studyDbBytes = await _fileSizeWithWal(studyDbPath);
    }
    final studyDbInstalled = await BibleStudyUpdater.isDownloaded();

    // 7. Audio
    var audioBytes = 0;
    var audioTracksCount = 0;
    var audioSeriesCount = 0;
    final audioDir = Directory(p.join(docsDir.path, 'downloads', 'audio'));
    if (await audioDir.exists()) {
      try {
        final seriesEntities = audioDir.listSync();
        for (final entity in seriesEntities) {
          if (entity is Directory) {
            audioSeriesCount++;
            final trackFiles = entity.listSync();
            for (final track in trackFiles) {
              if (track is File && !track.path.endsWith('.part')) {
                audioTracksCount++;
                audioBytes += await track.length();
              }
            }
          }
        }
      } catch (e) {
        debugPrint('StorageCalculatorService audio error: $e');
      }
    }

    return StorageBreakdown(
      biblesBytes: biblesBytes,
      dictionariesBytes: dictionariesBytes,
      booksBytes: booksBytes,
      audioBytes: audioBytes,
      songsBytes: songsBytes,
      articlesBytes: articlesBytes,
      studyDbBytes: studyDbBytes,
      biblesCount: biblesCount,
      dictsCount: dictsCount,
      booksCount: booksCount,
      audioTracksCount: audioTracksCount,
      audioSeriesCount: audioSeriesCount,
      songsInstalled: songsInstalled,
      articlesCount: articlesCount,
      studyDbInstalled: studyDbInstalled,
    );
  }

  /// Scans audio directories to return items for each downloaded series.
  Future<List<AudioDownloadedSeriesItem>> scanDownloadedAudioSeries() async {
    if (kIsWeb) return const [];
    final items = <AudioDownloadedSeriesItem>[];
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final audioDir = Directory(p.join(docsDir.path, 'downloads', 'audio'));
      if (!await audioDir.exists()) return items;

      final entities = audioDir.listSync();
      for (final entity in entities) {
        if (entity is Directory) {
          final seriesId = p.basename(entity.path);
          var trackCount = 0;
          var totalBytes = 0;
          final tracks = entity.listSync();
          for (final t in tracks) {
            if (t is File && !t.path.endsWith('.part')) {
              trackCount++;
              totalBytes += await t.length();
            }
          }
          if (trackCount > 0) {
            items.add(AudioDownloadedSeriesItem(
              seriesId: seriesId,
              title: _formatSeriesTitle(seriesId),
              trackCount: trackCount,
              totalBytes: totalBytes,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning downloaded audio series: $e');
    }
    return items;
  }

  String _formatSeriesTitle(String id) {
    if (id.isEmpty) return 'Audio Series';
    final parts = id.replaceAll('_', ' ').replaceAll('-', ' ').split(' ');
    return parts
        .map((p) => p.isEmpty ? '' : '${p[0].toUpperCase()}${p.substring(1)}')
        .join(' ');
  }
}
