import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:dio/dio.dart';
import 'package:mobile/core/api/release_assets.dart';

class OfflineFeedDatabase {
  static final OfflineFeedDatabase _instance = OfflineFeedDatabase._internal();
  factory OfflineFeedDatabase() => _instance;
  OfflineFeedDatabase._internal();

  Database? _db;
  bool _isInitializing = false;
  Future<void>? _initFuture;
  
  // Expose initialization state so UI can show a loading spinner
  bool get isInitializing => _isInitializing;
  final ValueNotifier<double> downloadProgress = ValueNotifier(0.0);

  Future<void> initialize() async {
    if (_db != null) return;
    // If an initialization is already in flight, wait for it instead of
    // returning early with a null DB (otherwise callers would see an empty
    // feed because _db is still null when they read it).
    final inFlight = _initFuture;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {}
      return;
    }

    final completer = Completer<void>();
    _initFuture = completer.future;
    _isInitializing = true;
    try {
      await _doInitialize();
      completer.complete();
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _isInitializing = false;
      _initFuture = null;
    }
  }

  Future<void> _doInitialize() async {
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final dbPath = join(appSupportDir.path, 'feed.db');
      final dbExists = await File(dbPath).exists();
      
      bool shouldRebuild = !dbExists;

      if (dbExists) {
        try {
          final tempDb = await openDatabase(dbPath);
          final count = Sqflite.firstIntValue(await tempDb.rawQuery('SELECT COUNT(*) FROM feed'));
          await tempDb.close();
          
          if (count == null || count == 0) {
            shouldRebuild = true;
          }
        } catch (e) {
          // If the table doesn't exist or is corrupted
          shouldRebuild = true;
        }
      }

      if (shouldRebuild) {
        if (dbExists) {
          await deleteDatabase(dbPath);
        }
        await _downloadAndBuildDatabase(dbPath);
      }

      _db = await openDatabase(dbPath);
    } catch (e) {
      debugPrint('Failed to initialize offline feed db: $e');
      rethrow;
    }
  }

  Future<void> _downloadAndBuildDatabase(String dbPath) async {
    debugPrint('Downloading offline feed database payload...');
    downloadProgress.value = 0.0;
    final dio = Dio();
    final jsonPath = join((await getTemporaryDirectory()).path, 'scriptures.json');

    // Try the CDN first, then the raw GitHub source; the payload is served
    // from the releases repo so we never wait on the Render-hosted backend.
    final urls = ReleaseAssets.urlsFor('scriptures.json');
    Object? lastError;
    for (final url in urls) {
      try {
        await dio.download(
          url,
          jsonPath,
          options: Options(
            // Time to download the 7.5MB file on slow networks.
            receiveTimeout: const Duration(minutes: 5),
          ),
          onReceiveProgress: (received, total) {
            if (total != -1) {
              downloadProgress.value = received / total;
            }
          },
        );
        lastError = null;
        break;
      } catch (e) {
        lastError = e;
        debugPrint('Failed to download feed payload from $url: $e');
      }
    }
    if (lastError != null) {
      throw StateError('Unable to download scriptures payload: $lastError');
    }

    debugPrint('Building SQLite database from JSON...');
    final jsonStr = await File(jsonPath).readAsString();
    final List<dynamic> items = jsonDecode(jsonStr);

    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE feed (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            engine TEXT,
            bookNumber INTEGER,
            bookName TEXT,
            chapter INTEGER,
            startVerse INTEGER,
            endVerse INTEGER,
            referenceLabel TEXT,
            category TEXT,
            backgroundPreset TEXT,
            tags TEXT,
            isFeatured INTEGER
          )
        ''');
        
        await db.execute('CREATE INDEX idx_feed_book_name ON feed(bookName)');
        await db.execute('CREATE INDEX idx_feed_book_number ON feed(bookNumber)');
      },
    );

    final batch = db.batch();
    for (var item in items) {
      batch.insert('feed', {
        'engine': item['engine'] ?? 'scripture',
        'bookNumber': item['bookNumber'],
        'bookName': item['bookName'],
        'chapter': item['chapter'],
        'startVerse': item['startVerse'],
        'endVerse': item['endVerse'],
        'referenceLabel': item['referenceLabel'],
        'category': item['category'],
        'backgroundPreset': item['backgroundPreset'],
        'tags': jsonEncode(item['tags'] ?? []),
        'isFeatured': item['isFeatured'] == true ? 1 : 0,
      });
    }
    
    debugPrint('Executing batch insert for ${items.length} records...');
    await batch.commit(noResult: true);

    // Clean up temporary json
    await File(jsonPath).delete();
    await db.close();
    debugPrint('Offline feed database built successfully!');
  }

  Future<List<Map<String, dynamic>>> getRandomItems(
    int limit, {
    String? bookFilter,
    String? testamentFilter,
    List<String>? excludeIds,
  }) async {
    if (_db == null) await initialize();
    if (_db == null) return [];

    String query = 'SELECT * FROM feed WHERE 1=1';
    List<dynamic> args = [];

    if (bookFilter != null && bookFilter.isNotEmpty && bookFilter != 'All Books') {
      query += ' AND bookName = ?';
      args.add(bookFilter);
    }

    if (testamentFilter != null && testamentFilter.isNotEmpty && testamentFilter != 'All') {
      if (testamentFilter == 'Old Testament') {
        query += ' AND bookNumber <= 39';
      } else if (testamentFilter == 'New Testament') {
        query += ' AND bookNumber >= 40';
      }
    }

    if (excludeIds != null && excludeIds.isNotEmpty) {
      query += ' AND id NOT IN (${List.filled(excludeIds.length, '?').join(', ')})';
      args.addAll(excludeIds);
    }

    query += ' ORDER BY RANDOM() LIMIT ?';
    args.add(limit);

    final result = await _db!.rawQuery(query, args);
    
    // Parse tags back to List<String> so it matches the expected model format
    return result.map((row) {
      final map = Map<String, dynamic>.from(row);
      map['tags'] = jsonDecode(map['tags'] as String? ?? '[]');
      map['isFeatured'] = (map['isFeatured'] as int) == 1;
      return map;
    }).toList();
  }
}
