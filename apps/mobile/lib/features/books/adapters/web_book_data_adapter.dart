import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/core/api/github_data_service.dart';
import 'package:mobile/features/books/models/book.dart';
import 'package:mobile/features/books/models/book_chapter.dart';
import 'package:mobile/features/books/models/book_highlight.dart';
import 'package:mobile/features/books/models/book_line.dart';
import 'package:mobile/features/books/models/book_scripture_link.dart';
import 'package:mobile/features/books/models/user_reading_progress.dart';
import 'book_data_adapter.dart';

class WebBookDataAdapter implements BookDataAdapter {
  @override
  final ValueNotifier<double> downloadProgress = ValueNotifier(0.0);
  @override
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  final Map<String, List<BookChapter>> _liveTocCache = {};
  final Map<String, List<BookLine>> _liveChapterLinesCache = {};
  final Map<String, List<BookLine>> _livePageCache = {};
  final Map<String, Map<String, dynamic>> _liveCommentariesCache = {};
  final Map<String, Future<List<BookChapter>>> _inFlightTocFetches = {};
  final Map<String, Future<List<BookLine>>> _inFlightChapterFetches = {};

  @override
  Future<void> initialize() async {}

  @override
  bool isBookDownloading(String bookId) => false;

  @override
  Future<bool> isBookInstalled(String bookId) async => true;

  @override
  List<BookLine>? getCachedPageLines(String bookId, int pageNumber) {
    final key = '${bookId}_$pageNumber';
    return _livePageCache[key];
  }

  @override
  Future<Set<String>> getInstalledBookIds() async {
    final catalog = await getCatalogFromAsset();
    return catalog.map((b) => b.id).toSet();
  }

  @override
  Future<bool> downloadSingleBook(String bookId, {String? language}) async => true;

  @override
  Future<void> removeBookDownload(String bookId) async {}

  @override
  Future<bool> downloadAndInstall({String? language}) async => true;

  @override
  Future<bool> isInstalled() async => true;

  @override
  Future<Book?> getBook(String id) async {
    final catalog = await getCatalogFromAsset();
    return catalog.where((b) => b.id == id).firstOrNull;
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
        books = books.where((b) => b.subject.toLowerCase() == subject.trim().toLowerCase()).toList();
      }

      if (author != null && author.trim().isNotEmpty && author.trim().toLowerCase() != 'all') {
        books = books.where((b) => b.author.toLowerCase() == author.trim().toLowerCase()).toList();
      }

      if (query != null && query.trim().isNotEmpty) {
        final q = query.trim().toLowerCase();
        books = books.where((b) => 
          b.title.toLowerCase().contains(q) || 
          b.author.toLowerCase().contains(q) ||
          b.subject.toLowerCase().contains(q)
        ).toList();
      }
      return books;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveHighlight(BookHighlight highlight) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'highlights_${highlight.bookId}';
    final existing = prefs.getStringList(key) ?? [];
    existing.add(jsonEncode(highlight.toMap()));
    await prefs.setStringList(key, existing);
  }

  @override
  Future<void> deleteHighlight(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('highlights_'));
    for (final key in keys) {
      final list = prefs.getStringList(key) ?? [];
      final filtered = list.where((str) {
        try {
          final map = jsonDecode(str) as Map<String, dynamic>;
          return map['id'] != id;
        } catch (_) {
          return true;
        }
      }).toList();
      await prefs.setStringList(key, filtered);
    }
  }

  @override
  Future<List<BookHighlight>> getHighlightsForBook(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'highlights_$bookId';
    final list = prefs.getStringList(key) ?? [];
    return list.map((str) {
      return BookHighlight.fromMap(jsonDecode(str) as Map<String, dynamic>);
    }).toList();
  }

  @override
  Future<List<BookHighlight>> getHighlightsForPage(String bookId, int pageNumber) async {
    final all = await getHighlightsForBook(bookId);
    return all.where((h) => h.pageNumber == pageNumber).toList();
  }

  @override
  Future<List<BookChapter>> getChapters(String bookId) async {
    if (_liveTocCache.containsKey(bookId) && _liveTocCache[bookId]!.isNotEmpty) {
      return _liveTocCache[bookId]!;
    }
    if (_inFlightTocFetches.containsKey(bookId)) {
      return await _inFlightTocFetches[bookId]!;
    }

    final future = _fetchTocFromNetwork(bookId);
    _inFlightTocFetches[bookId] = future;
    
    try {
      final chapters = await future;
      if (chapters.isNotEmpty) {
        _liveTocCache[bookId] = chapters;
      }
      return chapters;
    } finally {
      _inFlightTocFetches.remove(bookId);
    }
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
              receiveTimeout: const Duration(seconds: 15),
              connectTimeout: const Duration(seconds: 10),
              responseType: ResponseType.json,
            ),
          );
          if (res.statusCode == 200 && res.data != null) {
            final Map<String, dynamic> data = res.data is String ? jsonDecode(res.data as String) : (res.data as Map<String, dynamic>);
            final rawChapters = data['chapters'] as List<dynamic>? ?? [];
            return rawChapters.map((item) {
              final map = item as Map<String, dynamic>;
              map['bookId'] = bookId;
              return BookChapter.fromMap(map);
            }).toList();
          }
        } catch (_) {}
      }
    } catch (_) {}
    return [];
  }

  @override
  Future<List<BookLine>> getPageLines(String bookId, int pageNumber) async {
    final pageKey = '${bookId}_$pageNumber';
    if (_livePageCache.containsKey(pageKey) && _livePageCache[pageKey]!.isNotEmpty) {
      return _livePageCache[pageKey]!;
    }
    return _scanForPage(bookId, pageNumber);
  }

  @override
  Future<List<BookLine>> getPageRangeLines(String bookId, int startPage, int endPage) async {
    final lines = <BookLine>[];
    for (int p = startPage; p <= endPage; p++) {
      lines.addAll(await getPageLines(bookId, p));
    }
    return lines;
  }

  @override
  Future<int?> getPageForLine(String bookId, int lineNumber) async {
    final toc = await getChapters(bookId);
    if (toc.isEmpty) return 1;

    for (final chapter in toc) {
      final chapterLines = await getChapterLines(bookId, chapter.chapterIndex);
      for (final line in chapterLines) {
        if (line.lineNumber == lineNumber) {
          return line.pageNumber;
        }
      }
    }
    return 1;
  }

  @override
  Future<List<BookLine>> getChapterLines(String bookId, int chapterIndex) async {
    final cacheKey = '${bookId}_$chapterIndex';
    if (_liveChapterLinesCache.containsKey(cacheKey) && _liveChapterLinesCache[cacheKey]!.isNotEmpty) {
      return _liveChapterLinesCache[cacheKey]!;
    }
    if (_inFlightChapterFetches.containsKey(cacheKey)) {
      return await _inFlightChapterFetches[cacheKey]!;
    }

    final future = _fetchChapterLinesFromNetwork(bookId, chapterIndex, cacheKey);
    _inFlightChapterFetches[cacheKey] = future;
    try {
      final lines = await future;
      if (lines.isNotEmpty) {
        _liveChapterLinesCache[cacheKey] = lines;
      }
      return lines;
    } finally {
      _inFlightChapterFetches.remove(cacheKey);
    }
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
              receiveTimeout: const Duration(seconds: 20),
              connectTimeout: const Duration(seconds: 10),
              responseType: ResponseType.json,
            ),
          );
          if (res.statusCode == 200 && res.data != null) {
            final List<dynamic> list = res.data is String ? jsonDecode(res.data as String) : (res.data as List<dynamic>);
            final lines = list.map((item) {
              final map = item as Map<String, dynamic>;
              map['bookId'] = bookId;
              map['chapterIndex'] = chapterIndex;
              return BookLine.fromMap(map);
            }).toList();

            if (lines.isNotEmpty) {
              // Pre-populate _livePageCache cleanly without duplicates
              final pageMap = <int, List<BookLine>>{};
              for (final l in lines) {
                (pageMap[l.pageNumber] ??= []).add(l);
              }
              for (final entry in pageMap.entries) {
                entry.value.sort((a, b) => a.lineNumber.compareTo(b.lineNumber));
                final pageKey = '${bookId}_${entry.key}';
                _livePageCache[pageKey] = entry.value;
              }
              return lines;
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
    return [];
  }

  Future<List<BookLine>> _scanForPage(String bookId, int pageNumber) async {
    final pageKey = '${bookId}_$pageNumber';
    if (_livePageCache.containsKey(pageKey) && _livePageCache[pageKey]!.isNotEmpty) {
      return _livePageCache[pageKey]!;
    }

    final toc = await getChapters(bookId);
    if (toc.isEmpty) return [];

    final targetChapters = toc.where(
      (c) => c.startPage <= pageNumber && c.endPage >= pageNumber,
    ).toList();

    final candidates = targetChapters.isNotEmpty
        ? targetChapters
        : (toc.isNotEmpty ? [toc.first] : <BookChapter>[]);

    for (final ch in candidates) {
      await getChapterLines(bookId, ch.chapterIndex);
    }

    if (_livePageCache.containsKey(pageKey) && _livePageCache[pageKey]!.isNotEmpty) {
      return _livePageCache[pageKey]!;
    }

    for (final ch in toc) {
      if (candidates.any((c) => c.chapterIndex == ch.chapterIndex)) continue;
      await getChapterLines(bookId, ch.chapterIndex);
      if (_livePageCache.containsKey(pageKey) && _livePageCache[pageKey]!.isNotEmpty) {
        return _livePageCache[pageKey]!;
      }
    }

    return [];
  }

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

  @override
  Future<UserReadingProgress?> getProgress(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('progress_$bookId');
    if (jsonStr != null) {
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        return UserReadingProgress.fromMap(map);
      } catch (_) {}
    }
    return null;
  }

  @override
  Future<void> saveProgress(
    String bookId,
    int currentPage,
    int currentLine,
    double percent,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final progress = UserReadingProgress(
      bookId: bookId,
      currentPage: currentPage,
      currentLine: currentLine,
      completionPercent: percent,
      lastReadAt: DateTime.now().toIso8601String(),
    );
    await prefs.setString('progress_$bookId', jsonEncode(progress.toMap()));
  }

  @override
  Future<List<UserReadingProgress>> getRecentProgress({int limit = 5}) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('progress_'));
    final list = <UserReadingProgress>[];
    for (final key in keys) {
      final jsonStr = prefs.getString(key);
      if (jsonStr != null) {
        try {
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          list.add(UserReadingProgress.fromMap(map));
        } catch (_) {}
      }
    }
    list.sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
    return list.take(limit).toList();
  }
}
