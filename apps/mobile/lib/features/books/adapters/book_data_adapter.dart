import 'package:flutter/foundation.dart';
import 'package:mobile/features/books/models/book.dart';
import 'package:mobile/features/books/models/book_chapter.dart';
import 'package:mobile/features/books/models/book_highlight.dart';
import 'package:mobile/features/books/models/book_line.dart';
import 'package:mobile/features/books/models/book_scripture_link.dart';
import 'package:mobile/features/books/models/user_reading_progress.dart';

abstract class BookDataAdapter {
  ValueNotifier<double> get downloadProgress;
  ValueNotifier<String?> get lastError;

  Future<void> initialize();
  bool isBookDownloading(String bookId);
  Future<bool> isBookInstalled(String bookId);
  List<BookLine>? getCachedPageLines(String bookId, int pageNumber);
  Future<Set<String>> getInstalledBookIds();
  Future<bool> downloadSingleBook(String bookId);
  Future<void> removeBookDownload(String bookId);
  Future<bool> downloadAndInstall();
  Future<bool> isInstalled();
  Future<Book?> getBook(String id);
  Future<List<Book>> getCatalogFromAsset({String? query, String? subject, String? author});
  Future<void> saveHighlight(BookHighlight highlight);
  Future<void> deleteHighlight(String id);
  Future<List<BookHighlight>> getHighlightsForBook(String bookId);
  Future<List<BookHighlight>> getHighlightsForPage(String bookId, int pageNumber);
  Future<List<BookChapter>> getChapters(String bookId);
  Future<List<BookLine>> getPageLines(String bookId, int pageNumber);
  Future<List<BookLine>> getPageRangeLines(String bookId, int startPage, int endPage);
  Future<int?> getPageForLine(String bookId, int lineNumber);
  Future<List<BookLine>> getChapterLines(String bookId, int chapterIndex);
  Future<List<BookScriptureLink>> getCommentariesForVerse(int bookNumber, int chapter, int verse);
  Future<UserReadingProgress?> getProgress(String bookId);
  Future<void> saveProgress(String bookId, int currentPage, int currentLine, double percent);
  Future<List<UserReadingProgress>> getRecentProgress({int limit = 5});
}
