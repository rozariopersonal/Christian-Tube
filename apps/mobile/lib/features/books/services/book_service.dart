import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../core/api/release_assets.dart';
import '../models/book.dart';
import '../models/book_chapter.dart';
import '../models/book_highlight.dart';
import '../models/book_line.dart';
import '../models/book_scripture_link.dart';
import '../models/user_reading_progress.dart';

/// Service managing the local SQLite books database, reading progress,
/// highlights, and scripture commentary cross-references.
class BookService extends ChangeNotifier {
  static final BookService _instance = BookService._internal();
  static BookService get instance => _instance;
  factory BookService() => _instance;
  BookService._internal();

  Database? _db;
  bool _isInitializing = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _lastError;

  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String? get lastError => _lastError;

  /// Optional override for testing.
  String? overrideDbPath;

  Future<Database?> get database async {
    if (_db != null && _db!.isOpen) return _db;
    await initialize();
    return _db;
  }

  final Set<String> _downloadingBookIds = {};

  bool isBookDownloading(String bookId) => _downloadingBookIds.contains(bookId);

  Future<void> initialize() async {
    if (kIsWeb) return;
    if (_db != null && _db!.isOpen) return;
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      final dbPath = overrideDbPath ??
          p.join(await getDatabasesPath(), 'christian_tube_books.db');

      _db = await openDatabase(
        dbPath,
        version: 3,
        onCreate: (db, version) async {
          await _createTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _createTables(db);
        },
      );

      await _createTables(_db!);
    } catch (e) {
      debugPrint('BookService initialize error: $e');
      _lastError = e.toString();
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS books (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        author TEXT NOT NULL,
        subject TEXT NOT NULL DEFAULT '',
        categories TEXT NOT NULL DEFAULT '[]',
        description TEXT,
        cover_file TEXT,
        total_pages INTEGER NOT NULL,
        total_lines INTEGER NOT NULL,
        download_size_formatted TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS book_chapters (
        book_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        chapter_title TEXT NOT NULL,
        start_page INTEGER NOT NULL,
        start_line INTEGER NOT NULL,
        end_page INTEGER NOT NULL,
        end_line INTEGER NOT NULL,
        PRIMARY KEY (book_id, chapter_index)
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS book_content (
        book_id TEXT NOT NULL,
        page_number INTEGER NOT NULL,
        line_number INTEGER NOT NULL,
        chapter_index INTEGER NOT NULL,
        content_type TEXT NOT NULL DEFAULT 'p',
        text TEXT NOT NULL,
        PRIMARY KEY (book_id, page_number, line_number)
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS book_scripture_links (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_number INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        end_verse INTEGER NOT NULL,
        book_id TEXT NOT NULL,
        page_number INTEGER NOT NULL,
        start_line INTEGER NOT NULL,
        end_line INTEGER NOT NULL,
        headline TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_reading_progress (
        book_id TEXT PRIMARY KEY,
        current_page INTEGER NOT NULL DEFAULT 1,
        current_line INTEGER NOT NULL DEFAULT 1,
        completion_percent REAL NOT NULL DEFAULT 0.0,
        last_read_at TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS book_highlights (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        page_number INTEGER NOT NULL,
        start_char INTEGER NOT NULL,
        end_char INTEGER NOT NULL,
        text TEXT NOT NULL,
        color INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS installed_books (
        book_id TEXT PRIMARY KEY,
        installed_at TEXT NOT NULL,
        size_bytes INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_book_page ON book_content (book_id, page_number);
      CREATE INDEX IF NOT EXISTS idx_highlights_book ON book_highlights(book_id, page_number);
      CREATE INDEX IF NOT EXISTS idx_book_links ON book_scripture_links (book_number, chapter, verse);
    ''');
  }

  /// Checks whether an individual book is installed locally.
  Future<bool> isBookInstalled(String bookId) async {
    final db = await database;
    if (db == null) return false;

    try {
      final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM book_content WHERE book_id = ? LIMIT 1',
        [bookId],
      ));
      return (count ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }

  /// Returns the Set of all book IDs currently downloaded and readable offline.
  Future<Set<String>> getInstalledBookIds() async {
    final db = await database;
    if (db == null) return {};

    try {
      final rows = await db.rawQuery('SELECT DISTINCT book_id FROM book_content');
      return rows.map((r) => r['book_id'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Downloads a single book's SQLite package and merges it into the unified local database.
  Future<bool> downloadSingleBook(String bookId) async {
    if (_downloadingBookIds.contains(bookId)) return false;
    _downloadingBookIds.add(bookId);
    notifyListeners();

    try {
      final db = await database;
      if (db == null) throw Exception('Database not available');

      final tempDir = await getTemporaryDirectory();
      final tempGz = p.join(tempDir.path, '${bookId}_${DateTime.now().millisecondsSinceEpoch}.gz');
      final tempSqlite = p.join(tempDir.path, '${bookId}_${DateTime.now().millisecondsSinceEpoch}.sqlite');

      final urls = [
        ...ReleaseAssets.urlsFor('books/published/$bookId.sqlite.gz'),
        ...ReleaseAssets.urlsFor('data/books_published/$bookId.sqlite.gz'),
      ];
      final dio = Dio();
      bool downloaded = false;

      for (final url in urls) {
        try {
          await dio.download(
            url,
            tempGz,
            options: Options(receiveTimeout: const Duration(seconds: 45)),
          );
          downloaded = true;
          break;
        } catch (_) {}
      }

      // Check local repo path for development/test fallbacks
      if (!downloaded) {
        final localPub = p.join(Directory.current.path, 'data', 'books_published', '$bookId.sqlite.gz');
        final localFile = File(localPub);
        if (await localFile.exists()) {
          await localFile.copy(tempGz);
          downloaded = true;
        }
      }

      if (!downloaded) {
        throw Exception('Failed to download book package for "$bookId" from server.');
      }

      // Decompress
      final compressedBytes = await File(tempGz).readAsBytes();
      final decompressed = gzip.decode(compressedBytes);
      await File(tempSqlite).writeAsBytes(decompressed, flush: true);

      // Read from single book SQLite
      final sourceDb = await openReadOnlyDatabase(tempSqlite);
      final books = await sourceDb.query('books');
      final chapters = await sourceDb.query('book_chapters');
      final content = await sourceDb.query('book_content');
      final links = await sourceDb.query('book_scripture_links');
      await sourceDb.close();

      // Batch insert into main database
      final batch = db.batch();
      for (final row in books) {
        batch.insert('books', row, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final row in chapters) {
        batch.insert('book_chapters', row, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final row in content) {
        batch.insert('book_content', row, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final row in links) {
        batch.insert('book_scripture_links', row, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      batch.insert(
        'installed_books',
        {
          'book_id': bookId,
          'installed_at': DateTime.now().toIso8601String(),
          'size_bytes': compressedBytes.length,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await batch.commit(noResult: true);

      // Clean temp files
      try {
        await File(tempGz).delete();
        await File(tempSqlite).delete();
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint('Error downloading book $bookId: $e');
      _lastError = e.toString();
      return false;
    } finally {
      _downloadingBookIds.remove(bookId);
      notifyListeners();
    }
  }

  /// Removes an individual downloaded book from local storage to free space,
  /// preserving user reading progress and highlights.
  Future<void> removeBookDownload(String bookId) async {
    final db = await database;
    if (db == null) return;

    try {
      final batch = db.batch();
      batch.delete('book_content', where: 'book_id = ?', whereArgs: [bookId]);
      batch.delete('book_chapters', where: 'book_id = ?', whereArgs: [bookId]);
      batch.delete('book_scripture_links', where: 'book_id = ?', whereArgs: [bookId]);
      batch.delete('installed_books', where: 'book_id = ?', whereArgs: [bookId]);
      await batch.commit(noResult: true);
      notifyListeners();
    } catch (e) {
      debugPrint('Error removing book $bookId: $e');
    }
  }

  /// Downloads and installs `books.sqlite.gz` from release CDN mirrors if not bundled.
  Future<bool> downloadAndInstall() async {
    if (_isDownloading) return false;
    _isDownloading = true;
    _downloadProgress = 0.0;
    _lastError = null;
    notifyListeners();

    try {
      final dbPath = overrideDbPath ??
          p.join(await getDatabasesPath(), 'christian_tube_books.db');
      final tempDir = await getTemporaryDirectory();
      final tempGzPath = p.join(tempDir.path, 'books_download_${DateTime.now().millisecondsSinceEpoch}.gz');

      final urls = [
        ...ReleaseAssets.urlsFor('books/books.sqlite.gz'),
        ...ReleaseAssets.urlsFor('data/books.sqlite.gz'),
      ];
      final dio = Dio();
      var downloaded = false;

      for (final url in urls) {
        try {
          await dio.download(
            url,
            tempGzPath,
            options: Options(receiveTimeout: const Duration(minutes: 5)),
            onReceiveProgress: (received, total) {
              if (total > 0) {
                _downloadProgress = received / total;
                notifyListeners();
              }
            },
          );
          downloaded = true;
          break;
        } catch (_) {
          continue;
        }
      }

      if (!downloaded) {
        throw Exception('Failed to download books database from any mirror.');
      }

      // 1. Backup user reading progress and highlights before replacing the file
      List<Map<String, dynamic>> savedProgress = [];
      List<Map<String, dynamic>> savedHighlights = [];
      if (_db != null && _db!.isOpen) {
        try {
          savedProgress = await _db!.query('user_reading_progress');
        } catch (_) {}
        try {
          savedHighlights = await _db!.query('book_highlights');
        } catch (_) {}
        await _db!.close();
        _db = null;
      }

      // Decompress
      final compressedBytes = await File(tempGzPath).readAsBytes();
      final decompressed = gzip.decode(compressedBytes);

      final targetFile = File(dbPath);
      await targetFile.parent.create(recursive: true);
      await targetFile.writeAsBytes(decompressed, flush: true);

      // Clean temp
      try {
        await File(tempGzPath).delete();
      } catch (_) {}

      // Re-initialize DB
      await initialize();

      // 2. Restore user progress & highlights
      if (_db != null && _db!.isOpen && (savedProgress.isNotEmpty || savedHighlights.isNotEmpty)) {
        final batch = _db!.batch();
        for (final row in savedProgress) {
          batch.insert('user_reading_progress', row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final row in savedHighlights) {
          batch.insert('book_highlights', row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      }
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('BookService download error: $e');
      return false;
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  /// Whether books database is installed locally and ready.
  Future<bool> isInstalled() async {
    final db = await database;
    if (db == null) return false;
    try {
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM books'),
      );
      return (count ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }

  /// Retrieves all books, optionally filtered by query, subject, or author.
  Future<List<Book>> getBooks({String? query, String? subject, String? author}) async {
    return getCatalogFromAsset(query: query, subject: subject, author: author);
  }

  /// Reads books metadata from `assets/books/catalog.json`.
  Future<List<Book>> getCatalogFromAsset({String? query, String? subject, String? author}) async {
    try {
      final jsonStr = await rootBundle.loadString('assets/books/catalog.json');
      final list = jsonDecode(jsonStr) as List<dynamic>;
      var books = list.map((item) => Book.fromMap(item as Map<String, dynamic>)).toList();

      if (subject != null && subject.trim().isNotEmpty && subject.trim().toLowerCase() != 'all') {
        final s = subject.trim().toLowerCase();
        books = books.where((b) => b.subject.toLowerCase() == s).toList();
      }

      if (author != null && author.trim().isNotEmpty && author.trim().toLowerCase() != 'all') {
        final a = author.trim().toLowerCase();
        books = books.where((b) => b.author.toLowerCase().contains(a)).toList();
      }

      if (query != null && query.trim().isNotEmpty) {
        final q = query.trim().toLowerCase();
        books = books.where((b) =>
          b.title.toLowerCase().contains(q) ||
          b.description.toLowerCase().contains(q) ||
          b.author.toLowerCase().contains(q) ||
          b.subject.toLowerCase().contains(q) ||
          b.categories.any((c) => c.toLowerCase().contains(q))
        ).toList();
      }
      return books;
    } catch (e) {
      debugPrint('BookService: Error reading catalog.json: $e');
      return [];
    }
  }

  /// Returns the distinct list of all subjects in the catalog.
  Future<List<String>> getSubjects() async {
    final books = await getCatalogFromAsset();
    final set = <String>{};
    for (final b in books) {
      if (b.subject.isNotEmpty) set.add(b.subject);
    }
    final list = set.toList()..sort();
    return ['All', ...list];
  }

  /// Returns books grouped by their primary subject.
  Future<Map<String, List<Book>>> getBooksGroupedBySubject({String? query}) async {
    final books = await getCatalogFromAsset(query: query);
    final map = <String, List<Book>>{};
    for (final b in books) {
      final s = b.subject.isNotEmpty ? b.subject : 'Christian Living';
      map.putIfAbsent(s, () => []).add(b);
    }
    return map;
  }

  /// Gets a single book by ID.
  Future<Book?> getBook(String id) async {
    final db = await database;
    if (db != null) {
      final rows = await db.query(
        'books',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) return Book.fromMap(rows.first);
    }
    // Fallback to catalog.json
    final catalog = await getCatalogFromAsset();
    return catalog.where((b) => b.id == id).firstOrNull;
  }

  /// Saves a text highlight.
  Future<void> saveHighlight(BookHighlight highlight) async {
    final db = await database;
    if (db == null) return;
    await db.insert(
      'book_highlights',
      highlight.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  /// Deletes a highlight by ID.
  Future<void> deleteHighlight(String id) async {
    final db = await database;
    if (db == null) return;
    await db.delete(
      'book_highlights',
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyListeners();
  }

  /// Gets all highlights for a book (for TOC / Highlights sheet).
  Future<List<BookHighlight>> getHighlightsForBook(String bookId) async {
    final db = await database;
    if (db == null) return [];
    final rows = await db.query(
      'book_highlights',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'page_number ASC, start_char ASC',
    );
    return rows.map((r) => BookHighlight.fromMap(r)).toList();
  }

  /// Gets highlights for a specific page of a book.
  Future<List<BookHighlight>> getHighlightsForPage(String bookId, int pageNumber) async {
    final db = await database;
    if (db == null) return [];
    final rows = await db.query(
      'book_highlights',
      where: 'book_id = ? AND page_number = ?',
      whereArgs: [bookId, pageNumber],
      orderBy: 'start_char ASC',
    );
    return rows.map((r) => BookHighlight.fromMap(r)).toList();
  }

  /// Gets all chapter entries (TOC) for a book.
  Future<List<BookChapter>> getChapters(String bookId) async {
    final db = await database;
    if (db == null) return [];

    final rows = await db.query(
      'book_chapters',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'chapter_index ASC',
    );
    return rows.map((r) => BookChapter.fromMap(r)).toList();
  }

  /// Gets all lines for a specific page of a book.
  Future<List<BookLine>> getPageLines(String bookId, int pageNumber) async {
    final db = await database;
    if (db == null) return [];

    final rows = await db.query(
      'book_content',
      where: 'book_id = ? AND page_number = ?',
      whereArgs: [bookId, pageNumber],
      orderBy: 'line_number ASC',
    );
    return rows.map((r) => BookLine.fromMap(r)).toList();
  }

  /// Gets all lines for a range of pages of a book.
  Future<List<BookLine>> getPageRangeLines(String bookId, int startPage, int endPage) async {
    final db = await database;
    if (db == null) return [];

    final rows = await db.query(
      'book_content',
      where: 'book_id = ? AND page_number >= ? AND page_number <= ?',
      whereArgs: [bookId, startPage, endPage],
      orderBy: 'page_number ASC, line_number ASC',
    );
    return rows.map((r) => BookLine.fromMap(r)).toList();
  }

  /// Gets all lines for a chapter of a book.
  Future<List<BookLine>> getChapterLines(String bookId, int chapterIndex) async {
    final db = await database;
    if (db == null) return [];

    final rows = await db.query(
      'book_content',
      where: 'book_id = ? AND chapter_index = ?',
      whereArgs: [bookId, chapterIndex],
      orderBy: 'page_number ASC, line_number ASC',
    );
    return rows.map((r) => BookLine.fromMap(r)).toList();
  }

  /// Queries all Zac Poonen book commentaries referencing a Bible verse.
  /// Resolves the exact excerpt lines from the book text automatically.
  Future<List<BookScriptureLink>> getCommentariesForVerse(
    int bookNumber,
    int chapter,
    int verse,
  ) async {
    final db = await database;
    if (db == null) return [];

    final rows = await db.rawQuery('''
      SELECT l.*, b.title, b.author
      FROM book_scripture_links l
      JOIN books b ON l.book_id = b.id
      WHERE l.book_number = ? AND l.chapter = ? AND l.verse = ?
      ORDER BY b.total_pages DESC, l.page_number ASC
    ''', [bookNumber, chapter, verse]);

    if (rows.isEmpty) return [];

    final results = <BookScriptureLink>[];
    for (final row in rows) {
      final bookId = row['book_id'] as String;
      final pageNum = (row['page_number'] as num).toInt();
      final startLine = (row['start_line'] as num).toInt();
      final endLine = (row['end_line'] as num).toInt();

      // Fetch the excerpt lines
      final lineRows = await db.rawQuery('''
        SELECT text FROM book_content
        WHERE book_id = ? AND page_number = ? AND line_number >= ? AND line_number <= ?
        ORDER BY line_number ASC
      ''', [bookId, pageNum, startLine, endLine]);

      final excerpt = lineRows.map((lr) => lr['text'] as String).join(' ');
      results.add(BookScriptureLink.fromMap(row, excerpt: excerpt));
    }

    return results;
  }

  /// Retrieves user reading progress for a book.
  Future<UserReadingProgress?> getProgress(String bookId) async {
    final db = await database;
    if (db == null) return null;

    final rows = await db.query(
      'user_reading_progress',
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return UserReadingProgress.fromMap(rows.first);
  }

  /// Saves user reading progress.
  Future<void> saveProgress(
    String bookId,
    int currentPage,
    int currentLine,
    double percent,
  ) async {
    final db = await database;
    if (db == null) return;

    final now = DateTime.now().toIso8601String();
    await db.insert(
      'user_reading_progress',
      {
        'book_id': bookId,
        'current_page': currentPage,
        'current_line': currentLine,
        'completion_percent': percent.clamp(0.0, 1.0),
        'last_read_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  /// Gets recent reading progress across all books (for "Continue Reading" shelf).
  Future<List<UserReadingProgress>> getRecentProgress({int limit = 5}) async {
    final db = await database;
    if (db == null) return [];

    final rows = await db.query(
      'user_reading_progress',
      orderBy: 'last_read_at DESC',
      limit: limit,
    );
    return rows.map((r) => UserReadingProgress.fromMap(r)).toList();
  }
}
