import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:mobile/core/api/github_data_service.dart';

/// Manages the WFTW (Word for the Week) local SQLite database.
/// Responsible for downloading, decompressing, and hot-swapping the DB 
/// based on the remote manifest hash.
class WftwDatabaseService {
  static const String _hashKey = 'wftw_db_manifest_hash';
  static const String _dbName = 'wftw_feed.db';
  
  Database? _db;
  bool _isSyncing = false;
  
  Future<bool> hasDatabase() async {
    final dbPath = await _getDbPath();
    return File(dbPath).exists();
  }

  Future<Database> getDatabase() async {
    if (_db != null && _db!.isOpen) return _db!;
    final dbPath = await _getDbPath();
    final file = File(dbPath);
    if (!await file.exists()) {
      await syncDatabase();
    }
    _db = await openDatabase(dbPath, readOnly: true);
    return _db!;
  }
  
  Future<String> _getDbPath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return p.join(docsDir.path, _dbName);
  }

  /// Queries verses from SQLite with optional year/book filtering and sorting.
  Future<List<Map<String, dynamic>>> queryVerses({
    int offset = 0,
    int limit = 20,
    int? year,
    int? bookNumber,
    String sortBy = 'date', // 'date' or 'book'
  }) async {
    final db = await getDatabase();
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (year != null) {
      whereClauses.add('year = ?');
      whereArgs.add(year);
    }
    if (bookNumber != null) {
      whereClauses.add('book_number = ?');
      whereArgs.add(bookNumber);
    }

    final where = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;
    final orderBy = sortBy == 'book'
        ? 'book_number ASC, chapter ASC, start_verse ASC, date_ms DESC'
        : 'date_ms DESC';

    return await db.query(
      'wftw_verses',
      where: where,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  /// Returns distinct years in the database for the filter sheet.
  Future<List<int>> getAvailableYears() async {
    try {
      final db = await getDatabase();
      final results = await db.rawQuery(
        'SELECT DISTINCT year FROM wftw_verses WHERE year IS NOT NULL ORDER BY year DESC'
      );
      return results.map((r) => r['year'] as int).toList();
    } catch (_) {
      return [];
    }
  }

  /// Returns distinct book numbers in the database for the filter sheet.
  Future<List<int>> getAvailableBooks() async {
    try {
      final db = await getDatabase();
      final results = await db.rawQuery(
        'SELECT DISTINCT book_number FROM wftw_verses WHERE book_number IS NOT NULL ORDER BY book_number ASC'
      );
      return results.map((r) => r['book_number'] as int).toList();
    } catch (_) {
      return [];
    }
  }

  /// Syncs the database in the background based on the manifest.
  /// If the DB does not exist, it will download it.
  /// If it exists, it checks the manifest hash and hot-swaps if there is a new version.
  Future<void> syncDatabase() async {
    if (_isSyncing) return;
    _isSyncing = true;
    
    try {
      final dbPath = await _getDbPath();
      final dbFile = File(dbPath);
      final hasLocalDb = await dbFile.exists();
      
      final prefs = await SharedPreferences.getInstance();
      final localHash = prefs.getString(_hashKey);
      
      final dio = Dio();
      
      // 1. Fetch manifest
      String? remoteHash;
      for (final url in GitHubDataService.wftwManifestUrls()) {
        try {
          final res = await dio.get<String>(
            url,
            options: Options(
              responseType: ResponseType.plain,
              headers: {'Cache-Control': 'no-cache'},
            ),
          );
          if (res.statusCode == 200 && res.data != null) {
            final json = jsonDecode(res.data!);
            remoteHash = json['hash'];
            break;
          }
        } catch (_) {}
      }
      
      // If we can't get manifest, we just use local if it exists.
      if (remoteHash == null) {
        if (!hasLocalDb) throw Exception('No local WFTW database and cannot fetch manifest.');
        return;
      }
      
      // If up to date, do nothing
      if (hasLocalDb && localHash == remoteHash) {
        return;
      }
      
      debugPrint('WFTW Database needs update. Downloading...');
      
      // 2. Download sqlite.gz
      final tempDir = await getTemporaryDirectory();
      final tempGzPath = p.join(tempDir.path, 'wftw_feed_tmp_${DateTime.now().millisecondsSinceEpoch}.gz');
      
      bool downloaded = false;
      for (final url in GitHubDataService.wftwFeedDbUrls()) {
        try {
          await dio.download(
            url, 
            tempGzPath,
            options: Options(
              receiveTimeout: const Duration(minutes: 1),
              connectTimeout: const Duration(seconds: 15),
            ),
          );
          final f = File(tempGzPath);
          if (await f.exists() && await f.length() > 0) {
            downloaded = true;
            break;
          }
        } catch (_) {}
      }
      
      if (!downloaded) {
        throw Exception('Failed to download WFTW database.');
      }
      
      // 3. Decompress and swap
      final compressedBytes = await File(tempGzPath).readAsBytes();
      final decompressed = gzip.decode(compressedBytes);
      
      final tempDbPath = p.join(tempDir.path, 'wftw_feed_tmp.sqlite');
      await File(tempDbPath).writeAsBytes(decompressed, flush: true);
      
      // Close old db
      if (_db != null && _db!.isOpen) {
        await _db!.close();
      }
      
      // Overwrite
      await File(tempDbPath).copy(dbPath);
      await File(tempDbPath).delete();
      await File(tempGzPath).delete();
      
      // Save hash
      await prefs.setString(_hashKey, remoteHash);
      
      // Re-open
      _db = await openDatabase(dbPath, readOnly: true);
      debugPrint('WFTW Database hot-swap complete.');
      
    } catch (e) {
      debugPrint('WFTW Sync Error: $e');
    } finally {
      _isSyncing = false;
    }
  }
}
