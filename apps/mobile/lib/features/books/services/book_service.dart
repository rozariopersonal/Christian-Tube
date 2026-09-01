import 'dart:async';
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
import '../models/book_line.dart';
import '../models/book_scripture_link.dart';
import '../models/user_reading_progress.dart';

/// Service managing the local SQLite books database, reading progress,
/// and scripture commentary cross-references.
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

  Future<void> initialize() async {
    if (kIsWeb) return;
    if (_db != null && _db!.isOpen) return;
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      final dbPath = overrideDbPath ??
          p.join(await getDatabasesPath(), 'christian_tube_books.db');

      final dbFile = File(dbPath);
      final exists = await dbFile.exists();

      if (!exists || (await dbFile.length()) < 1000) {
        final installed = await _extractFromBundledAssets(dbPath);
        if (!installed) {
          debugPrint('BookService: No local asset found, ready for on-demand download.');
        }
      }

      if (await dbFile.exists() && (await dbFile.length()) > 1000) {
        _db = await openDatabase(
          dbPath,
          version: 1,
          onCreate: (db, version) async {},
        );

        // Ensure user reading progress table exists
        await _db!.execute('''
          CREATE TABLE IF NOT EXISTS user_reading_progress (
            book_id TEXT PRIMARY KEY,
            current_page INTEGER NOT NULL DEFAULT 1,
            current_line INTEGER NOT NULL DEFAULT 1,
            completion_percent REAL NOT NULL DEFAULT 0.0,
            last_read_at TEXT NOT NULL
          );
        ''');
      }
    } catch (e) {
      debugPrint('BookService initialize error: $e');
      _lastError = e.toString();
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Attempts to decompress bundled asset `assets/books/books.sqlite.gz`
  Future<bool> _extractFromBundledAssets(String targetDbPath) async {
    try {
      final byteData = await rootBundle.load('assets/books/books.sqlite.gz');
      final bytes = byteData.buffer.asUint8List();
      final decompressed = gzip.decode(bytes);

      final targetFile = File(targetDbPath);
      await targetFile.parent.create(recursive: true);
      await targetFile.writeAsBytes(decompressed, flush: true);
      debugPrint('BookService: Successfully decompressed bundled database (${decompressed.length} bytes)');
      return true;
    } catch (e) {
      debugPrint('BookService: Could not load bundled assets/books/books.sqlite.gz: $e');
      return false;
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

      final urls = ReleaseAssets.urlsFor('data/books.sqlite.gz');
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
      if (_db != null && _db!.isOpen) {
        await _db!.close();
        _db = null;
      }
      await initialize();
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

  /// Retrieves all books, optionally filtered by query.
  Future<List<Book>> getBooks({String? query}) async {
    final db = await database;
    if (db == null) return [];

    List<Map<String, dynamic>> rows;
    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      rows = await db.query(
        'books',
        where: 'title LIKE ? OR description LIKE ?',
        whereArgs: [q, q],
        orderBy: 'total_pages DESC',
      );
    } else {
      rows = await db.query(
        'books',
        orderBy: 'total_pages DESC',
      );
    }

    return rows.map((r) => Book.fromMap(r)).toList();
  }

  /// Gets a single book by ID.
  Future<Book?> getBook(String id) async {
    final db = await database;
    if (db == null) return null;

    final rows = await db.query(
      'books',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Book.fromMap(rows.first);
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
