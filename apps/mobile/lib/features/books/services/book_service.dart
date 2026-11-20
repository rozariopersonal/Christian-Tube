import 'package:flutter/foundation.dart';
import '../../../shared/annotations/user_item.dart';
import '../../../shared/annotations/user_item_repository.dart';
import '../../user_items/services/user_item_sync_service.dart';
import '../models/book.dart';
import '../models/book_chapter.dart';
import '../models/book_highlight.dart';
import '../models/book_line.dart';
import '../models/book_scripture_link.dart';
import '../models/user_reading_progress.dart';
import '../adapters/book_data_adapter.dart';
import '../adapters/sqlite_book_data_adapter.dart';
import '../adapters/web_book_data_adapter.dart';

class BookService extends ChangeNotifier {
  static final BookService _instance = BookService._internal();
  static BookService get instance => _instance;
  factory BookService() => _instance;
  
  late final BookDataAdapter _adapter;
  
  bool _isInitializing = false;
  String? _lastError;

  bool get isDownloading => _adapter.downloadProgress.value > 0 && _adapter.downloadProgress.value < 1;
  double get downloadProgress => _adapter.downloadProgress.value;
  String? get lastError => _lastError ?? _adapter.lastError.value;
  
  String? _overrideDbPath;
  String? get overrideDbPath => _overrideDbPath;
  set overrideDbPath(String? path) {
    _overrideDbPath = path;
    if (!kIsWeb) {
      (_adapter as SqliteBookDataAdapter).overrideDbPath = path;
    }
  }

  BookService._internal() {
    if (kIsWeb) {
      _adapter = WebBookDataAdapter();
    } else {
      _adapter = SqliteBookDataAdapter();
    }

    _adapter.downloadProgress.addListener(() => notifyListeners());
    _adapter.lastError.addListener(() => notifyListeners());
  }

  Future<void> initialize() async {
    if (_isInitializing) return;
    _isInitializing = true;
    try {
      if (!kIsWeb && overrideDbPath != null) {
        (_adapter as SqliteBookDataAdapter).overrideDbPath = overrideDbPath;
      }
      await _adapter.initialize();
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  @visibleForTesting
  Future<dynamic> get database => !kIsWeb ? (_adapter as SqliteBookDataAdapter).database : Future.value(null);

  bool isBookDownloading(String bookId) => _adapter.isBookDownloading(bookId);
  Future<bool> isBookInstalled(String bookId) => _adapter.isBookInstalled(bookId);
  List<BookLine>? getCachedPageLines(String bookId, int pageNumber) => _adapter.getCachedPageLines(bookId, pageNumber);
  Future<Set<String>> getInstalledBookIds() => _adapter.getInstalledBookIds();
  Future<bool> downloadSingleBook(String bookId, {String? language}) =>
      _adapter.downloadSingleBook(bookId, language: language);
  Future<void> removeBookDownload(String bookId) =>
      _adapter.removeBookDownload(bookId);
  Future<void> removeAllBooks() =>
      _adapter.removeAllBooks();
  Future<bool> downloadAndInstall({String? language}) =>
      _adapter.downloadAndInstall(language: language);
  Future<bool> isInstalled() => _adapter.isInstalled();
  Future<Book?> getBook(String id) => _adapter.getBook(id);
  Future<void> saveHighlight(BookHighlight highlight) async {
    await _adapter.saveHighlight(highlight);
    if (UserItemSyncService.instance.isUserTierActive) {
      final uid = UserItemSyncService.instance.currentUserId!;
      final now = DateTime.now().toUtc();
      final item = UserItem(
        userId: uid,
        id: 'book_hl:${highlight.id}',
        itemType: UserItem.typeTextRange,
        feature: UserItem.featureBook,
        targetId: 'book:${highlight.bookId}:${highlight.chapterIndex}:${highlight.pageNumber}',
        book: highlight.bookId,
        chapter: highlight.chapterIndex,
        verseStart: highlight.pageNumber,
        startOffset: highlight.startChar,
        endOffset: highlight.endChar,
        colorIndex: highlight.color,
        text: highlight.text,
        createdAt: DateTime.tryParse(highlight.createdAt) ?? now,
        updatedAt: now,
      );
      await UserItemRepository.instance.insertOrReplace(uid, [item]);
      UserItemSyncService.instance.schedulePush();
    }
  }

  Future<void> deleteHighlight(String id) async {
    await _adapter.deleteHighlight(id);
    if (UserItemSyncService.instance.isUserTierActive) {
      final uid = UserItemSyncService.instance.currentUserId!;
      final now = DateTime.now().toUtc();
      final tombstone = UserItem(
        userId: uid,
        id: 'book_hl:$id',
        itemType: UserItem.typeTextRange,
        feature: UserItem.featureBook,
        targetId: '',
        createdAt: now,
        updatedAt: now,
        deleted: true,
      );
      await UserItemRepository.instance.insertOrReplace(uid, [tombstone]);
      UserItemSyncService.instance.schedulePush();
    }
  }

  Future<List<BookHighlight>> getHighlightsForBook(String bookId) async {
    final local = await _adapter.getHighlightsForBook(bookId);
    if (!UserItemSyncService.instance.isUserTierActive) return local;

    final uid = UserItemSyncService.instance.currentUserId!;
    final remoteItems = await UserItemRepository.instance
        .loadForType(uid, UserItem.typeTextRange);
    final byId = <String, BookHighlight>{
      for (final h in local) h.id: h,
    };
    for (final item in remoteItems) {
      if (item.feature != UserItem.featureBook || item.book != bookId) continue;
      final rawId = item.id.startsWith('book_hl:')
          ? item.id.substring('book_hl:'.length)
          : item.id;
      byId[rawId] = BookHighlight(
        id: rawId,
        bookId: item.book,
        chapterIndex: item.chapter,
        pageNumber: item.verseStart > 0 ? item.verseStart : 1,
        startChar: item.startOffset,
        endChar: item.endOffset,
        text: item.text,
        color: item.colorIndex ?? 0,
        createdAt: item.createdAt.toIso8601String(),
      );
    }
    return byId.values.toList();
  }

  Future<List<BookHighlight>> getHighlightsForPage(
      String bookId, int pageNumber) async {
    final all = await getHighlightsForBook(bookId);
    return all.where((h) => h.pageNumber == pageNumber).toList();
  }
  Future<List<BookChapter>> getChapters(String bookId) => _adapter.getChapters(bookId);
  Future<List<BookLine>> getPageLines(String bookId, int pageNumber) => _adapter.getPageLines(bookId, pageNumber);
  Future<List<BookLine>> getPageRangeLines(String bookId, int startPage, int endPage) => _adapter.getPageRangeLines(bookId, startPage, endPage);
  Future<int?> getPageForLine(String bookId, int lineNumber) => _adapter.getPageForLine(bookId, lineNumber);
  Future<List<BookLine>> getChapterLines(String bookId, int chapterIndex) => _adapter.getChapterLines(bookId, chapterIndex);
  Future<List<BookScriptureLink>> getCommentariesForVerse(int bookNumber, int chapter, int verse) => _adapter.getCommentariesForVerse(bookNumber, chapter, verse);
  Future<UserReadingProgress?> getProgress(String bookId) => _adapter.getProgress(bookId);
  Future<void> saveProgress(String bookId, int currentPage, int currentLine, double percent) => _adapter.saveProgress(bookId, currentPage, currentLine, percent);
  Future<List<UserReadingProgress>> getRecentProgress({int limit = 5}) => _adapter.getRecentProgress(limit: limit);

  // Expose these helpers that were present in BookService
  Future<List<Book>> getBooks({String? query, String? subject, String? author, String? language}) async {
    return _adapter.getCatalogFromAsset(query: query, subject: subject, author: author, language: language);
  }
  
  Future<List<Book>> getCatalogFromAsset({String? query, String? subject, String? author, String? language}) async {
    return _adapter.getCatalogFromAsset(query: query, subject: subject, author: author, language: language);
  }

  Future<List<String>> getLanguages() async {
    final books = await getCatalogFromAsset();
    final set = <String>{};
    for (final b in books) {
      if (b.language.isNotEmpty) set.add(b.language.toLowerCase());
    }
    final sorted = set.toList()..sort();
    return ['All', ...sorted];
  }

  Future<List<String>> getSubjects() async {
    final books = await getCatalogFromAsset();
    final set = <String>{};
    for (final b in books) {
      if (b.subject.isNotEmpty) set.add(b.subject);
    }
    final sorted = set.toList()..sort();
    return sorted;
  }

  Future<Map<String, List<Book>>> getBooksGroupedBySubject({String? query, String? language}) async {
    final books = await getCatalogFromAsset(query: query, language: language);
    final map = <String, List<Book>>{};
    for (final b in books) {
      final s = b.subject.isEmpty ? 'Other' : b.subject;
      map.putIfAbsent(s, () => []).add(b);
    }
    return map;
  }
}
