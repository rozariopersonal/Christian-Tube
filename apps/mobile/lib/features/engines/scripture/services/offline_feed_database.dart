import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:mobile/core/api/api_client.dart';

class OfflineFeedDatabase {
  static final OfflineFeedDatabase _instance = OfflineFeedDatabase._internal();
  factory OfflineFeedDatabase() => _instance;
  OfflineFeedDatabase._internal();

  Database? _db;
  bool _isInitializing = false;
  
  // Expose initialization state so UI can show a loading spinner
  bool get isInitializing => _isInitializing;
  final ValueNotifier<double> downloadProgress = ValueNotifier(0.0);

  Future<void> initialize() async {
    if (_db != null || _isInitializing) return;
    _isInitializing = true;
    
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final dbPath = join(appSupportDir.path, 'feed.db');
      final dbExists = await File(dbPath).exists();

      if (!dbExists) {
        await _downloadAndBuildDatabase(dbPath);
      }

      _db = await openDatabase(dbPath);
    } catch (e) {
      debugPrint('Failed to initialize offline feed db: $e');
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _downloadAndBuildDatabase(String dbPath) async {
    debugPrint('Downloading offline feed database payload...');
    final client = ApiClient();
    final jsonPath = join((await getTemporaryDirectory()).path, 'scriptures.json');

    // Download the raw JSON payload
    await client.dio.download(
      '/words/offline-db',
      jsonPath,
      onReceiveProgress: (received, total) {
        if (total != -1) {
          downloadProgress.value = received / total;
        }
      },
    );

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
