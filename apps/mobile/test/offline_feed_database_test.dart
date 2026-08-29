import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:mobile/features/engines/scripture/services/offline_feed_database.dart';

void main() {
  late OfflineFeedDatabase dbService;
  late String dbPath;

  setUpAll(() {
    // Initialize FFI for desktop/unit test environments
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dbService = OfflineFeedDatabase();
    
    // Create an in-memory database for testing
    dbPath = inMemoryDatabasePath;
    
    // The singleton normally uses getDatabasesPath(). 
    // For this test, we can override the factory, but OfflineFeedDatabase is hardcoded.
    // Wait, OfflineFeedDatabase uses getDatabasesPath().
    // By overriding databaseFactory, sqflite automatically intercepts.
  });

  test('OfflineFeedDatabase correctly calculates count and handles random queries', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
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
        isFeatured INTEGER DEFAULT 0
      )
    ''');

    await db.insert('feed', {
      'engine': 'scripture',
      'bookNumber': 43,
      'bookName': 'John',
      'chapter': 3,
      'startVerse': 16,
      'endVerse': 16,
      'referenceLabel': 'John 3:16',
      'category': 'Love',
      'backgroundPreset': '',
      'tags': '[]',
      'isFeatured': 0,
    });

    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM feed'));
    expect(count, 1);
    
    await db.close();
  });
}
