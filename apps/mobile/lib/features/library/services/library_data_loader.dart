import '../../books/models/book.dart';
import '../../books/models/user_reading_progress.dart';
import '../../books/services/book_service.dart';
import '../../songs/models/song.dart';

/// Song catalog loader function, injectable for widget tests.
typedef SongsCatalogLoader = Future<List<Song>> Function();

/// Thin facade over [BookService] so the Library screen stays testable:
/// widget tests inject a fake provider and never open a real SQLite database.
abstract class LibraryDataLoader {
  Future<void> initialize();
  Future<List<Book>> getBooks();
  Future<List<UserReadingProgress>> getRecentProgress({int? limit});
}

/// Default backing of [LibraryDataLoader] — talks to the shared [BookService].
class BookServiceLibraryLoader implements LibraryDataLoader {
  final BookService service;

  BookServiceLibraryLoader([BookService? service])
      : service = service ?? BookService.instance;

  @override
  Future<void> initialize() => service.initialize();

  @override
  Future<List<Book>> getBooks() => service.getBooks();

  @override
  Future<List<UserReadingProgress>> getRecentProgress({int? limit}) =>
      service.getRecentProgress(limit: limit ?? 5);
}