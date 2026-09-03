import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'bible_data_adapter.dart';

class SqliteBibleDataAdapter implements BibleDataAdapter {
  Database? _db;
  final String? overrideDbPath;

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
  Future<bool> hasVerses(String versionId) async {
    if (_db == null) await initialize();
    if (_db == null) return false;
    final count = Sqflite.firstIntValue(
      await _db!.rawQuery('SELECT COUNT(*) FROM verses WHERE version_id = ?', [versionId]),
    );
    return (count ?? 0) > 0;
  }

  @override
  Future<List<Map<String, dynamic>>> getChapter(String versionId, String bookName, int chapter) async {
    if (_db == null) await initialize();
    if (_db == null || !_db!.isOpen) return [];
    return await _db!.query(
      'verses',
      where: 'version_id = ? AND book_name = ? AND chapter = ?',
      whereArgs: [versionId, bookName, chapter],
      orderBy: 'verse ASC',
    );
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
      where: 'version_id = ? AND book_number = ? AND chapter = ? AND verse >= ? AND verse <= ?',
      whereArgs: [versionId, bookNumber, chapter, startVerse, end],
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
        where: 'version_id = ? AND book_number = ? AND chapter = ? AND verse >= ? AND verse <= ?',
        whereArgs: [versionId, book, chapter, minVerse, maxEnd],
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
      where: 'version_id = ? AND text LIKE ?',
      whereArgs: [versionId, like],
      orderBy: 'book_number ASC, chapter ASC, verse ASC',
      limit: limit,
    );
  }

  @override
  Future<void> insertVerses(String versionId, List<Map<String, dynamic>> verses) async {
    if (_db == null) return;
    await _db!.delete('verses', where: 'version_id = ?', whereArgs: [versionId]);
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
    await _db!.delete('verses', where: 'version_id = ?', whereArgs: [versionId]);
    await _db!.delete('installed_versions', where: 'id = ?', whereArgs: [versionId]);
  }

}
