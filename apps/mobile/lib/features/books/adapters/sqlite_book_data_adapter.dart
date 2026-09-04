import 'book_data_adapter.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:mobile/core/api/github_data_service.dart';
import '../models/book.dart';
import '../models/book_chapter.dart';
import '../models/book_highlight.dart';
import '../models/book_line.dart';
import '../models/book_scripture_link.dart';
import '../models/user_reading_progress.dart';

/// Service managing the local SQLite books database, reading progress,
/// highlights, and scripture commentary cross-references.
class SqliteBookDataAdapter implements BookDataAdapter {
  
  
  
  

  Database? _db;
  bool _isInitializing = false;
  bool _isDownloading = false;
  @override
  final ValueNotifier<double> downloadProgress = ValueNotifier(0.0);
  @override
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  bool get isDownloading => _isDownloading;
  
  

  /// Optional override for testing.
  String? overrideDbPath;

  Future<Database?> get database async {
    if (_db != null && _db!.isOpen) return _db;
    await initialize();
    return _db;
  }

  final Set<String> _downloadingBookIds = {};

  // In-memory caches for live CDN book data (used on web or when not downloaded yet)
  final Map<String, List<BookChapter>> _liveTocCache = {};
  final Map<String, List<BookLine>> _liveChapterLinesCache = {};
  final Map<String, List<BookLine>> _livePageCache = {};
  final Map<String, Map<String, dynamic>> _liveCommentariesCache = {};
  final Map<String, Future<List<BookChapter>>> _inFlightTocFetches = {};
  final Map<String, Future<List<BookLine>>> _inFlightChapterFetches = {};

  @override
  List<BookLine>? getCachedPageLines(String bookId, int pageNumber) {
    final key = '${bookId}_$pageNumber';
    return _livePageCache[key];
  }

  @override
  bool isBookDownloading(String bookId) => _downloadingBookIds.contains(bookId);

  @override
  Future<void> initialize() async {
    
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
      lastError.value = e.toString();
    } finally {
      _isInitializing = false;
      
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
  @override
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
  @override
  Future<Set<String>> getInstalledBookIds() async {
    if (kIsWeb) {
      final catalog = await getCatalogFromAsset();
      return catalog.map((b) => b.id).toSet();
    }

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
  @override
  Future<bool> downloadSingleBook(String bookId, {String? language}) async {
    if (_downloadingBookIds.contains(bookId)) return false;
    _downloadingBookIds.add(bookId);

    try {
      final db = await database;
      if (db == null) throw Exception('Database not available');

      final tempDir = await getTemporaryDirectory();
      final tempGz = p.join(tempDir.path, '${bookId}_${DateTime.now().millisecondsSinceEpoch}.gz');
      final tempSqlite = p.join(tempDir.path, '${bookId}_${DateTime.now().millisecondsSinceEpoch}.sqlite');

      final urls = [
        ...GitHubDataService.bookSqliteUrls(bookId, langCode: language),
      ];
      final dio = Dio();
      bool downloaded = false;

      for (final url in urls) {
        try {
          await dio.download(
            url,
            tempGz,
            options: Options(
              receiveTimeout: const Duration(seconds: 45),
              connectTimeout: const Duration(seconds: 15),
            ),
          );
          final f = File(tempGz);
          if (await f.exists() && await f.length() > 0) {
            downloaded = true;
            break;
          }
        } catch (_) {
          try {
            final f = File(tempGz);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
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
      List<Map<String, dynamic>> links = [];
      try {
        links = await sourceDb.query('book_scripture_links');
      } catch (_) {}
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
        if (await File(tempGz).exists()) await File(tempGz).delete();
        if (await File(tempSqlite).exists()) await File(tempSqlite).delete();
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint('Error downloading book $bookId: $e');
      lastError.value = e.toString();
      return false;
    } finally {
      _downloadingBookIds.remove(bookId);
    }
  }

  /// Removes an individual downloaded book from local storage to free space,
  /// preserving user reading progress and highlights.
  @override
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
    } catch (e) {
      debugPrint('Error removing book $bookId: $e');
    }
  }

  /// Downloads and installs `books.sqlite.gz` from release CDN mirrors if not bundled.
  @override
  Future<bool> downloadAndInstall({String? language}) async {
    if (_isDownloading) return false;
    _isDownloading = true;
    downloadProgress.value = 0.0;
    lastError.value = null;

    try {
      final dbPath = overrideDbPath ??
          p.join(await getDatabasesPath(), 'christian_tube_books.db');
      final tempDir = await getTemporaryDirectory();
      final tempGzPath = p.join(tempDir.path, 'books_download_${DateTime.now().millisecondsSinceEpoch}.gz');

      final urls = [
        ...GitHubDataService.allBooksSqliteUrls(langCode: language),
      ];
      final dio = Dio();
      var downloaded = false;

      for (final url in urls) {
        try {
          await dio.download(
            url,
            tempGzPath,
            options: Options(
              receiveTimeout: const Duration(minutes: 5),
              connectTimeout: const Duration(seconds: 20),
            ),
            onReceiveProgress: (received, total) {
              if (total > 0) {
                downloadProgress.value = received / total;
              }
            },
          );
          final f = File(tempGzPath);
          if (await f.exists() && await f.length() > 0) {
            downloaded = true;
            break;
          }
        } catch (_) {
          try {
            final f = File(tempGzPath);
            if (await f.exists()) await f.delete();
          } catch (_) {}
          continue;
        }
      }

      if (!downloaded) {
        throw Exception('Failed to download books database from any mirror.');
      }

      // 1. Backup user reading progress and highlights before replacing/updating the file
      List<Map<String, dynamic>> savedProgress = [];
      List<Map<String, dynamic>> savedHighlights = [];
      if (_db != null && _db!.isOpen) {
        try {
          savedProgress = await _db!.query('user_reading_progress');
        } catch (_) {}
        try {
          savedHighlights = await _db!.query('book_highlights');
        } catch (_) {}
      }

      // Decompress
      final compressedBytes = await File(tempGzPath).readAsBytes();
      final decompressed = gzip.decode(compressedBytes);

      final isAllLanguages = language == null ||
          language.trim().isEmpty ||
          language.trim().toLowerCase() == 'all';

      if (isAllLanguages || !(await File(dbPath).exists())) {
        if (_db != null && _db!.isOpen) {
          await _db!.close();
          _db = null;
        }
        final targetFile = File(dbPath);
        await targetFile.parent.create(recursive: true);
        await targetFile.writeAsBytes(decompressed, flush: true);

        // Re-initialize DB
        await initialize();
      } else {
        // Merge downloaded language bundle into existing database
        final tempSqlite = p.join(tempDir.path, 'temp_lang_${DateTime.now().millisecondsSinceEpoch}.sqlite');
        await File(tempSqlite).writeAsBytes(decompressed, flush: true);
        final sourceDb = await openReadOnlyDatabase(tempSqlite);
        final books = await sourceDb.query('books');
        final chapters = await sourceDb.query('book_chapters');
        final content = await sourceDb.query('book_content');
        List<Map<String, dynamic>> links = [];
        try {
          links = await sourceDb.query('book_scripture_links');
        } catch (_) {}
        await sourceDb.close();
        try {
          await File(tempSqlite).delete();
        } catch (_) {}

        final db = await database;
        if (db != null) {
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
          for (final row in books) {
            batch.insert(
              'installed_books',
              {
                'book_id': row['id'],
                'installed_at': DateTime.now().toIso8601String(),
                'size_bytes': 0,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          await batch.commit(noResult: true);
        }
      }

      // Clean temp
      try {
        await File(tempGzPath).delete();
      } catch (_) {}

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
      lastError.value = e.toString();
      debugPrint('BookService download error: $e');
      return false;
    } finally {
      _isDownloading = false;
    }
  }

  /// Whether books database is installed locally and ready.
  @override
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

  @override
  Future<List<Book>> getCatalogFromAsset({String? query, String? subject, String? author, String? language}) async {
    try {
      final jsonStr = await rootBundle.loadString('assets/books/catalog.json');
      final list = jsonDecode(jsonStr) as List<dynamic>;
      var books = list.map((item) => Book.fromMap(item as Map<String, dynamic>)).toList();

      if (language != null && language.trim().isNotEmpty && language.trim().toLowerCase() != 'all') {
        final l = language.trim().toLowerCase();
        books = books.where((b) => b.language.toLowerCase() == l).toList();
      }

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
  @override
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
  @override
  Future<void> saveHighlight(BookHighlight highlight) async {
    final db = await database;
    if (db == null) return;
    await db.insert(
      'book_highlights',
      highlight.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
  }

  /// Deletes a highlight by ID.
  @override
  Future<void> deleteHighlight(String id) async {
    final db = await database;
    if (db == null) return;
    await db.delete(
      'book_highlights',
      where: 'id = ?',
      whereArgs: [id],
    );
    
  }

  /// Gets all highlights for a book (for TOC / Highlights sheet).
  @override
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
  @override
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
  @override
  Future<List<BookChapter>> getChapters(String bookId) async {
    

    // Fallback to Live CDN chunked fetch
    if (_liveTocCache.containsKey(bookId) && _liveTocCache[bookId]!.isNotEmpty) {
      return _liveTocCache[bookId]!;
    }
    if (_inFlightTocFetches.containsKey(bookId)) {
      return _inFlightTocFetches[bookId]!;
    }

    final future = _fetchTocFromNetwork(bookId);
    _inFlightTocFetches[bookId] = future;
    return future;
  }

  Future<List<BookChapter>> _fetchTocFromNetwork(String bookId) async {
    try {
      final urls = GitHubDataService.booksTocUrls(bookId);
      final dio = Dio();
      for (final url in urls) {
        try {
          final res = await dio.get<dynamic>(
            url,
            options: Options(
              responseType: ResponseType.json,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );
          if (res.statusCode == 200 && res.data != null) {
            final Map<String, dynamic> data = res.data is String ? jsonDecode(res.data as String) : (res.data as Map<String, dynamic>);
            final rawChapters = data['chapters'] as List<dynamic>? ?? [];
            final list = rawChapters.map((c) => BookChapter(
              bookId: bookId,
              chapterIndex: ((c['chapterIndex'] ?? c['chapter_index']) as num?)?.toInt() ?? 1,
              chapterTitle: (c['title'] ?? c['chapter_title'] as String?) ?? 'Chapter ${c['chapterIndex'] ?? 1}',
              startLine: ((c['startLine'] ?? c['start_line']) as num?)?.toInt() ?? 1,
              endLine: ((c['endLine'] ?? c['end_line']) as num?)?.toInt() ?? 1,
              startPage: ((c['startPage'] ?? c['start_page']) as num?)?.toInt() ?? 1,
              endPage: ((c['endPage'] ?? c['end_page']) as num?)?.toInt() ?? 1,
            )).toList();

            if (list.isNotEmpty) {
              _liveTocCache[bookId] = list;
              return list;
            }
          }
        } catch (e) {
          debugPrint('BookService getChapters error from $url: $e');
          continue;
        }
      }
      return [];
    } finally {
      _inFlightTocFetches.remove(bookId);
    }
  }

  /// Gets all lines for a specific page of a book.
  @override
  Future<List<BookLine>> getPageLines(String bookId, int pageNumber) async {
    

    // Fast path: In-memory live page cache
    final pageCacheKey = '${bookId}_$pageNumber';
    if (_livePageCache.containsKey(pageCacheKey) && _livePageCache[pageCacheKey]!.isNotEmpty) {
      return _livePageCache[pageCacheKey]!;
    }

    // Live CDN fallback: resolve chapter(s) from TOC and fetch chapter lines
    final chapters = await getChapters(bookId);
    final targetChapters = chapters.where(
      (c) => c.startPage <= pageNumber && c.endPage >= pageNumber,
    ).toList();

    final candidates = targetChapters.isNotEmpty
        ? targetChapters
        : (chapters.isNotEmpty ? [chapters.first] : <BookChapter>[]);

    for (final ch in candidates) {
      await getChapterLines(bookId, ch.chapterIndex);
    }

    if (_livePageCache.containsKey(pageCacheKey) && _livePageCache[pageCacheKey]!.isNotEmpty) {
      return _livePageCache[pageCacheKey]!;
    }

    // If still not cached, search remaining chapters
    if (chapters.isNotEmpty) {
      for (final ch in chapters) {
        if (candidates.any((c) => c.chapterIndex == ch.chapterIndex)) continue;
        await getChapterLines(bookId, ch.chapterIndex);
        if (_livePageCache.containsKey(pageCacheKey) && _livePageCache[pageCacheKey]!.isNotEmpty) {
          return _livePageCache[pageCacheKey]!;
        }
      }
    }

    return [];
  }

  /// Gets all lines for a range of pages of a book.
  @override
  Future<List<BookLine>> getPageRangeLines(String bookId, int startPage, int endPage) async {
    

    final result = <BookLine>[];
    for (int p = startPage; p <= endPage; p++) {
      final lines = await getPageLines(bookId, p);
      result.addAll(lines);
    }
    return result;
  }

  /// Resolves the page number that contains a specific line number.
  @override
  Future<int?> getPageForLine(String bookId, int lineNumber) async {
    

    final chapters = await getChapters(bookId);
    for (final ch in chapters) {
      if (lineNumber >= ch.startLine && lineNumber <= ch.endLine) {
        final lines = await getChapterLines(bookId, ch.chapterIndex);
        final match = lines.where((l) => l.lineNumber == lineNumber).firstOrNull;
        if (match != null) return match.pageNumber;
        return ch.startPage;
      }
    }
    return null;
  }

  /// Gets all lines for a chapter of a book.
  @override
  Future<List<BookLine>> getChapterLines(String bookId, int chapterIndex) async {
    

    // Fallback to Live CDN chunked fetch
    final cacheKey = '${bookId}_$chapterIndex';
    if (_liveChapterLinesCache.containsKey(cacheKey) && _liveChapterLinesCache[cacheKey]!.isNotEmpty) {
      return _liveChapterLinesCache[cacheKey]!;
    }
    if (_inFlightChapterFetches.containsKey(cacheKey)) {
      return _inFlightChapterFetches[cacheKey]!;
    }

    final future = _fetchChapterLinesFromNetwork(bookId, chapterIndex, cacheKey);
    _inFlightChapterFetches[cacheKey] = future;
    return future;
  }

  Future<List<BookLine>> _fetchChapterLinesFromNetwork(String bookId, int chapterIndex, String cacheKey) async {
    try {
      final urls = GitHubDataService.bookChapterUrls(bookId, chapterIndex);
      final dio = Dio();
      for (final url in urls) {
        try {
          final res = await dio.get<dynamic>(
            url,
            options: Options(
              responseType: ResponseType.json,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );
          if (res.statusCode == 200 && res.data != null) {
            final List<dynamic> list = res.data is String ? jsonDecode(res.data as String) : (res.data as List<dynamic>);
            final lines = list.map((l) => BookLine(
              bookId: bookId,
              lineNumber: ((l['line'] ?? l['lineNumber'] ?? l['line_number']) as num).toInt(),
              pageNumber: ((l['page'] ?? l['pageNumber'] ?? l['page_number']) as num?)?.toInt() ?? 1,
              chapterIndex: chapterIndex,
              contentType: (l['contentType'] ?? l['content_type'] as String?) ?? (l['isHeading'] == true ? 'h2' : 'p'),
              text: (l['text'] as String?) ?? '',
            )).toList();

            if (lines.isNotEmpty) {
              _liveChapterLinesCache[cacheKey] = lines;
              // Pre-populate _livePageCache for every page in this chapter
              for (final l in lines) {
                final pageKey = '${bookId}_${l.pageNumber}';
                (_livePageCache[pageKey] ??= []).add(l);
              }
              final pagesInChapter = lines.map((l) => l.pageNumber).toSet();
              for (final p in pagesInChapter) {
                _livePageCache['${bookId}_$p']?.sort((a, b) => a.lineNumber.compareTo(b.lineNumber));
              }
              return lines;
            }
          }
        } catch (e) {
          debugPrint('BookService getChapterLines error from $url: $e');
          continue;
        }
      }
      return [];
    } finally {
      _inFlightChapterFetches.remove(cacheKey);
    }
  }

  /// Queries all Zac Poonen book commentaries referencing a Bible verse.
  @override
  Future<List<BookScriptureLink>> getCommentariesForVerse(
    int bookNumber,
    int chapter,
    int verse,
  ) async {
    final key = '${bookNumber}_$chapter';
    Map<String, dynamic>? chapterData = _liveCommentariesCache[key];

    if (chapterData == null) {
      final urls = GitHubDataService.commentaryUrls(bookNumber, chapter);
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
            chapterData = res.data is String
                ? (jsonDecode(res.data as String) as Map<String, dynamic>)
                : (res.data as Map<String, dynamic>);
            _liveCommentariesCache[key] = chapterData;
            break;
          }
        } catch (_) {
          continue;
        }
      }
    }

    if (chapterData != null) {
      final vStr = verse.toString();
      final list = chapterData[vStr] as List<dynamic>? ?? [];
      final results = <BookScriptureLink>[];
      for (final item in list) {
        if (item is! Map) continue;
        final bookId = (item['bookId'] as String?) ?? '';
        final pageNum = (item['pageNumber'] as num?)?.toInt() ?? 1;
        final startLine = (item['startLine'] as num?)?.toInt() ?? 1;
        final endLine = (item['endLine'] as num?)?.toInt() ?? 1;
        final chIdx = (item['chapterIndex'] as num?)?.toInt() ?? 1;

        String excerpt = (item['excerpt'] as String?) ?? '';
        if (excerpt.isEmpty && bookId.isNotEmpty) {
          try {
            final chLines = await getChapterLines(bookId, chIdx);
            final matched = chLines.where((l) =>
                l.pageNumber == pageNum &&
                l.lineNumber >= startLine &&
                l.lineNumber <= endLine);
            if (matched.isNotEmpty) {
              excerpt = matched.map((l) => l.text).join(' ').trim();
            }
          } catch (_) {}
        }

        results.add(BookScriptureLink(
          id: 0,
          bookNumber: bookNumber,
          chapter: chapter,
          verse: verse,
          endVerse: (item['endVerse'] as num?)?.toInt() ?? verse,
          bookId: bookId,
          bookTitle: (item['bookTitle'] as String?) ?? '',
          author: (item['author'] as String?)?.isNotEmpty == true
              ? (item['author'] as String)
              : 'Zac Poonen',
          pageNumber: pageNum,
          startLine: startLine,
          endLine: endLine,
          headline: (item['headline'] as String?) ?? '',
          excerpt: excerpt,
        ));
      }
      return results;
    }

    return [];
  }

  /// Retrieves user reading progress for a book.
  @override
  Future<UserReadingProgress?> getProgress(String bookId) async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('book_progress_$bookId');
        if (raw != null) {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          return UserReadingProgress.fromMap(map);
        }
      } catch (_) {}
      return null;
    }

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
  @override
  Future<void> saveProgress(
    String bookId,
    int currentPage,
    int currentLine,
    double percent,
  ) async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final now = DateTime.now().toIso8601String();
        final map = {
          'book_id': bookId,
          'current_page': currentPage,
          'current_line': currentLine,
          'completion_percent': percent.clamp(0.0, 1.0),
          'last_read_at': now,
        };
        await prefs.setString('book_progress_$bookId', jsonEncode(map));
        final recentList = prefs.getStringList('recent_book_ids') ?? [];
        recentList.remove(bookId);
        recentList.insert(0, bookId);
        if (recentList.length > 20) recentList.removeLast();
        await prefs.setStringList('recent_book_ids', recentList);
        
      } catch (_) {}
      return;
    }

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
    
  }

  /// Gets recent reading progress across all books (for "Continue Reading" shelf).
  @override
  Future<List<UserReadingProgress>> getRecentProgress({int limit = 5}) async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final recentList = prefs.getStringList('recent_book_ids') ?? [];
        final results = <UserReadingProgress>[];
        for (final id in recentList.take(limit)) {
          final p = await getProgress(id);
          if (p != null) results.add(p);
        }
        return results;
      } catch (_) {
        return [];
      }
    }

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
