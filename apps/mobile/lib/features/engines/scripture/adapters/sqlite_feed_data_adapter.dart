import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:dio/dio.dart';
import 'package:mobile/core/api/github_data_service.dart';
import 'feed_data_adapter.dart';

class SqliteFeedDataAdapter implements FeedDataAdapter {
  Database? _db;
  @override
  final ValueNotifier<double> downloadProgress = ValueNotifier(0.0);

  @override
  Future<void> initialize() async {
    if (_db != null) return;
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

    final urls = GitHubDataService.scripturesFeedUrls();
    Object? lastError;
    for (final url in urls) {
      try {
        await dio.download(
          url,
          jsonPath,
          options: Options(
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
    
    debugPrint('Executing batch insert for \${items.length} records...');
    await batch.commit(noResult: true);

    await File(jsonPath).delete();
    await db.close();
    debugPrint('Offline feed database built successfully!');
  }

  @override
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
    
    return result.map((row) {
      final map = Map<String, dynamic>.from(row);
      map['tags'] = jsonDecode(map['tags'] as String? ?? '[]');
      map['isFeatured'] = (map['isFeatured'] as int) == 1;
      return map;
    }).toList();
  }
}
