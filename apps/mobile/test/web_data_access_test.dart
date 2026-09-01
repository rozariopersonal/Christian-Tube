import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/books/services/book_service.dart';
import 'package:mobile/features/dictionary/services/dictionary_service.dart';
import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Unified Web & Mobile Live Data Access Tests', () {
    test('LocalBibleService handles live chapter queries', () async {
      final service = LocalBibleService();
      // Should not throw and should handle missing/uninstalled gracefully or via live CDN
      final verses = await service.getChapter('kjv', 'John', 3);
      expect(verses, isA<List<Map<String, dynamic>>>());
    });

    test('BookService handles live chapter queries', () async {
      final service = BookService();
      // Should not throw on web/live mode
      final chapters = await service.getChapters('beauty_for_ashes');
      expect(chapters, isA<List>());
    });

    test('BookService handles verse commentaries queries', () async {
      final service = BookService();
      // John 17:23
      final commentaries = await service.getCommentariesForVerse(43, 17, 23);
      expect(commentaries, isA<List>());
    });

    test('DictionaryService cleanWord and live lookup', () async {
      final service = DictionaryService();
      expect(service.cleanWord('__Faith!__'), equals('Faith'));
      expect(service.cleanWord('_விசுவாசம்_'), equals('விசுவாசம்'));

      // Lookup should return a list without throwing
      final results = await service.lookupWord('grace');
      expect(results, isA<List>());
    });
  });
}
