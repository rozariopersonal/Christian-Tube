import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../../../../core/api/github_data_service.dart';
import '../../../bible/models/bible_book.dart';
import '../services/book_name_service.dart';
import 'bible_data_adapter.dart';

class SqliteBibleDataAdapter implements BibleDataAdapter {
  Database? _db;
  final String? overrideDbPath;
  final Map<String, List<Map<String, dynamic>>> _liveChapterCache = {};
  final Map<String, List<List<int>>> _liveCountsCache = {};

  SqliteBibleDataAdapter({this.overrideDbPath});

  @override
  Future<void> initialize() async {
    if (_db != null) return;
    
    final path = overrideDbPath ??
        p.join(await getDatabasesPath(), 'christian_tube_bibles.db');

    _db = await openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('DROP TABLE IF EXISTS verses');
          await db.execute('DROP TABLE IF EXISTS installed_versions');
          await _createSchema(db);
          return;
        }
        if (oldVersion < 3) {
          // cross_references table no longer used; skip migration.
        }
        if (oldVersion < 4) {
          // bible_backgrounds table no longer used; skip migration.
        }
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE verses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        version_id TEXT NOT NULL,
        book_number INTEGER NOT NULL,
        book_name TEXT NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        text TEXT NOT NULL
      );
    ''');
    await db.execute('CREATE UNIQUE INDEX idx_bible_lookup ON verses (version_id, book_number, chapter, verse);');

    await db.execute('''
      CREATE TABLE installed_versions (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        language TEXT NOT NULL,
        language_code TEXT NOT NULL,
        size_display TEXT NOT NULL,
        installed_at TEXT NOT NULL
      );
    ''');
  }

  @override
  Future<void> close() async {
    _liveChapterCache.clear();
    _liveCountsCache.clear();
    await _db?.close();
    _db = null;
  }

  @override
  Future<List<String>> getInstalledVersionIds() async {
    if (_db == null) return [];
    final results = await _db!.query('installed_versions', columns: ['id']);
    return results.map((r) => r['id'] as String).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getInstalledVersions() async {
    if (_db == null) return [];
    return await _db!.query('installed_versions');
  }

  @override
  Future<bool> hasVerses(String versionId) async {
    if (_db == null) await initialize();
    if (_db == null) return false;
    final count = Sqflite.firstIntValue(
      await _db!.rawQuery('SELECT COUNT(*) FROM verses WHERE LOWER(version_id) = ?', [versionId.toLowerCase()]),
    );
    return (count ?? 0) > 0;
  }

  @override
  Future<List<Map<String, dynamic>>> getChapter(String versionId, String bookName, int chapter) async {
    final bookNum = BookNameService.englishBookNames.indexOf(bookName) + 1;
    final cacheKey = '${versionId.toLowerCase()}_${bookNum}_$chapter';
    if (_liveChapterCache.containsKey(cacheKey)) {
      return _liveChapterCache[cacheKey]!;
    }

    if (_db == null) await initialize();
    if (_db != null && _db!.isOpen) {
      final localRows = await _db!.query(
        'verses',
        where: 'LOWER(version_id) = ? AND (book_number = ? OR book_name = ?) AND chapter = ?',
        whereArgs: [versionId.toLowerCase(), bookNum, bookName, chapter],
        orderBy: 'verse ASC',
      );
      if (localRows.isNotEmpty) {
        return localRows;
      }
      if (await hasVerses(versionId)) {
        return const [];
      }
    }

    // Fallback: Stream live from GitHub CDN (skip in unit tests with overrideDbPath)
    if (overrideDbPath != null) {
      return const [];
    }
    if (bookNum > 0) {
      final urls = GitHubDataService.bibleChapterUrls(
        versionId, bookNum, chapter,
      );

      final dio = Dio();
      for (final url in urls) {
        try {
          final res = await dio.get<dynamic>(
            url,
            options: Options(
              responseType: ResponseType.json,
              receiveTimeout: const Duration(seconds: 10),
            ),
          );
          if (res.statusCode == 200 && res.data != null) {
            final dynamic rawData = res.data;
            final List<dynamic> list = rawData is String
                ? (jsonDecode(rawData) as List<dynamic>)
                : (rawData as List<dynamic>);
            final List<Map<String, dynamic>> results = [];
            for (final item in list) {
              if (item is Map) {
                final verseNum = (item['verse'] as num?)?.toInt() ?? 1;
                final text = (item['text'] as String?)?.trim() ?? '';
                results.add({
                  'version_id': versionId,
                  'book_name': bookName,
                  'book_number': bookNum,
                  'chapter': chapter,
                  'verse': verseNum,
                  'text': text,
                });
              }
            }
            if (results.isNotEmpty) {
              _liveChapterCache[cacheKey] = results;
              _persistChapterVerses(versionId, results);
              return results;
            }
          }
        } catch (_) {
          continue;
        }
      }
    }

    return [];
  }

  Future<void> _persistChapterVerses(String versionId, List<Map<String, dynamic>> verses) async {
    if (_db == null || !_db!.isOpen) return;
    try {
      final batch = _db!.batch();
      for (final v in verses) {
        batch.insert('verses', {
          'version_id': versionId,
          'book_number': v['book_number'] ?? 0,
          'book_name': v['book_name'] ?? '',
          'chapter': v['chapter'] ?? 0,
          'verse': v['verse'] ?? 0,
          'text': v['text'] ?? '',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    } catch (_) {}
  }

  @override
  Future<List<List<int>>> getChapterVerseCounts(String versionId) async {
    final cacheKey = versionId.toLowerCase();
    if (_liveCountsCache.containsKey(cacheKey)) {
      return _liveCountsCache[cacheKey]!;
    }

    if (_db == null) await initialize();
    if (_db != null && _db!.isOpen) {
      final results = await _db!.rawQuery(
        'SELECT book_number, chapter, COUNT(*) AS row_count FROM verses '
        'WHERE LOWER(version_id) = ? GROUP BY book_number, chapter '
        'ORDER BY book_number, chapter',
        [versionId.toLowerCase()],
      );
      if (results.isNotEmpty) {
        final books = bibleBooks.keys.toList();
        final counts = <List<int>>[];
        for (var bookNumber = 1; bookNumber <= books.length; bookNumber++) {
          final chapters = <int>[];
          for (final r in results.where((r) => r['book_number'] == bookNumber)) {
            final chapter = r['chapter'] as int;
            while (chapters.length < chapter - 1) {
              chapters.add(0);
            }
            chapters.add((r['row_count'] as int?) ?? 0);
          }
          final maxChapters = bibleBooks[books[bookNumber - 1]] ?? 1;
          while (chapters.length < maxChapters) {
            chapters.add(0);
          }
          counts.add(List.unmodifiable(chapters));
        }
        _liveCountsCache[cacheKey] = counts;
        return counts;
      }
      if (await hasVerses(versionId)) {
        return const [];
      }
    }

    // Fallback: Stream live counts from GitHub CDN (skip in unit tests with overrideDbPath)
    if (overrideDbPath != null) {
      return const [];
    }
    final urls = GitHubDataService.bibleCountsUrls(versionId);
    final dio = Dio();
    for (final url in urls) {
      try {
        final res = await dio.get<dynamic>(
          url,
          options: Options(
            responseType: ResponseType.json,
            receiveTimeout: const Duration(seconds: 10),
          ),
        );
        if (res.statusCode == 200 && res.data != null) {
          final dynamic rawData = res.data;
          final List<dynamic> list = rawData is String
              ? (jsonDecode(rawData) as List<dynamic>)
              : (rawData as List<dynamic>);
          final counts = list
              .map((book) =>
                  (book as List).map((c) => (c as num).toInt()).toList())
              .toList();
          if (counts.isNotEmpty) {
            _liveCountsCache[cacheKey] = counts;
            return counts;
          }
        }
      } catch (_) {
        continue;
      }
    }

    return const [];
  }

  @override
  String? resolvePassageSync({
    required String versionId,
    required int bookNumber,
    required int chapter,
    required int startVerse,
    int? endVerse,
  }) {
    return null;
  }

  @override
  Future<String?> resolvePassage({
    required String versionId,
    required int bookNumber,
    required int chapter,
    required int startVerse,
    int? endVerse,
  }) async {
    final end = endVerse ?? startVerse;
    if (_db == null) await initialize();
    if (_db == null) return null;
    final results = await _db!.query(
      'verses',
      columns: ['text'],
      where: 'LOWER(version_id) = ? AND book_number = ? AND chapter = ? AND verse >= ? AND verse <= ?',
      whereArgs: [versionId.toLowerCase(), bookNumber, chapter, startVerse, end],
      orderBy: 'verse ASC',
    );
    if (results.isNotEmpty) {
      return results.map((r) => r['text'] as String).join(' ');
    }
    return null;
  }

  @override
  Future<Map<String, String>> resolvePassages({
    required String versionId,
    required List<(int bookNumber, int chapter, int verse, int? endVerse)> passages,
  }) async {
    final result = <String, String>{};
    if (passages.isEmpty || _db == null) return result;

    final byGroup = <(int, int), List<(int verse, int end)>>{};
    for (final (book, chapter, verse, end) in passages) {
      byGroup.putIfAbsent((book, chapter), () => []).add((verse, end ?? verse));
    }

    for (final entry in byGroup.entries) {
      final (book, chapter) = entry.key;
      int minVerse = entry.value.first.$1;
      int maxEnd = entry.value.first.$2;
      for (final (v, e) in entry.value) {
        if (v < minVerse) minVerse = v;
        if (e > maxEnd) maxEnd = e;
      }
      final rows = await _db!.query(
        'verses',
        columns: ['book_number', 'chapter', 'verse', 'text'],
        where: 'LOWER(version_id) = ? AND book_number = ? AND chapter = ? AND verse >= ? AND verse <= ?',
        whereArgs: [versionId.toLowerCase(), book, chapter, minVerse, maxEnd],
        orderBy: 'verse ASC',
      );
      final textsByVerse = <int, String>{};
      for (final r in rows) {
        textsByVerse[r['verse'] as int] = r['text'] as String;
      }
      for (final (v, e) in entry.value) {
        final key = '${book}_${chapter}_$v';
        final parts = <String>[];
        for (int x = v; x <= e; x++) {
          final t = textsByVerse[x];
          if (t != null && t.isNotEmpty) parts.add(t);
        }
        if (parts.isNotEmpty) result[key] = parts.join(' ');
      }
    }
    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> search(String versionId, String query, {int limit = 100}) async {
    final term = query.trim();
    if (term.isEmpty) return [];
    if (_db == null) await initialize();
    if (_db == null) return [];
    
    final like = '%$term%';
    return _db!.query(
      'verses',
      columns: ['book_name', 'chapter', 'verse', 'text'],
      where: 'LOWER(version_id) = ? AND text LIKE ?',
      whereArgs: [versionId.toLowerCase(), like],
      orderBy: 'book_number ASC, chapter ASC, verse ASC',
      limit: limit,
    );
  }

  @override
  Future<void> insertVerses(String versionId, List<Map<String, dynamic>> verses) async {
    if (_db == null) return;
    await _db!.delete('verses', where: 'LOWER(version_id) = ?', whereArgs: [versionId.toLowerCase()]);
    final batch = _db!.batch();
    for (final v in verses) {
      batch.insert('verses', {
        'version_id': versionId,
        'book_number': v['bookNumber'] ?? v['book_number'] ?? 0,
        'book_name': v['bookName'] ?? v['book_name'] ?? '',
        'chapter': v['chapter'] ?? 0,
        'verse': v['verse'] ?? 0,
        'text': v['text'] ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> registerInstalledVersion({
    required String id,
    required String name,
    required String language,
    required String languageCode,
    required String sizeDisplay,
  }) async {
    if (_db == null) return;
    await _db!.insert('installed_versions', {
      'id': id,
      'name': name,
      'language': language,
      'language_code': languageCode,
      'size_display': sizeDisplay,
      'installed_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteVersion(String versionId) async {
    if (_db == null) await initialize();
    if (_db == null) return;
    await _db!.delete('verses', where: 'LOWER(version_id) = ?', whereArgs: [versionId.toLowerCase()]);
    await _db!.delete('installed_versions', where: 'LOWER(id) = ?', whereArgs: [versionId.toLowerCase()]);
  }
}
