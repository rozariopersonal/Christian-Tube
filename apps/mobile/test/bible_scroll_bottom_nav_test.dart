import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/services/bottom_bar_visibility_service.dart';
import 'package:mobile/features/bible/controllers/bible_controller.dart';
import 'package:mobile/features/engines/scripture/services/book_name_service.dart';
import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    await BookNameService().ensureLoaded();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bible_scroll_nav_test_');
    LocalBibleService.overrideDbPath = p.join(tempDir.path, 'bible.db');
    await LocalBibleService.resetForTest();

    final service = LocalBibleService();
    await service.initialize();
    await service.registerInstalledVersion(
      id: 'WEB',
      name: 'World English Bible',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1 MB',
    );
    await service.insertVerses('WEB', [
      for (var v = 1; v <= 10; v++)
        {
          'bookNumber': 43,
          'bookName': 'John',
          'chapter': 3,
          'verse': v,
          'text': 'Verse $v',
        },
      for (var v = 1; v <= 10; v++)
        {
          'bookNumber': 43,
          'bookName': 'John',
          'chapter': 4,
          'verse': v,
          'text': 'Chapter 4 Verse $v',
        },
    ]);
  });

  tearDown(() async {
    LocalBibleService.overrideDbPath = null;
    await LocalBibleService.resetForTest();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('BottomBarVisibilityService Bible Navigation Tests', () {
    setUp(() {
      BottomBarVisibilityService.instance.resetBibleNav();
    });

    test('hideBibleNav, showBibleNav, resetBibleNav notify listeners correctly', () {
      final service = BottomBarVisibilityService.instance;
      expect(service.isBibleNavHidden, isFalse);

      var notifyCount = 0;
      service.addListener(() {
        notifyCount++;
      });

      service.hideBibleNav();
      expect(service.isBibleNavHidden, isTrue);
      expect(notifyCount, 1);

      // Idempotent calls do not trigger extra notifications
      service.hideBibleNav();
      expect(notifyCount, 1);

      service.showBibleNav();
      expect(service.isBibleNavHidden, isFalse);
      expect(notifyCount, 2);

      service.hideBibleNav();
      expect(notifyCount, 3);

      service.resetBibleNav();
      expect(service.isBibleNavHidden, isFalse);
      expect(notifyCount, 4);
    });

    test('BibleController preserves selection across updateVisibleChapter and scrolling', () async {
      final controller = BibleController(
        initialVersionId: 'WEB',
        initialBook: 'John',
        initialChapter: 3,
        initialVerse: null,
        saveProgress: false,
      );
      await controller.init();

      // Select verse 5 in John 3
      controller.toggleVerseSelection(5, book: 'John', chapter: 3);
      expect(controller.state.selectedVerses, {5});
      expect(controller.state.selectedBook, 'John');
      expect(controller.state.selectedChapter, 3);

      // Scroll into John 4
      controller.updateVisibleChapter(43, 4, verse: 1);
      expect(controller.state.currentBook, 'John');
      expect(controller.state.currentChapter, 4);

      // Selection must NOT be cleared!
      expect(controller.state.selectedVerses, {5});
      expect(controller.state.selectedBook, 'John');
      expect(controller.state.selectedChapter, 3);

      // Clear selection explicitly
      controller.clearSelection();
      expect(controller.state.selectedVerses, isEmpty);
      expect(controller.state.selectedBook, isNull);
      expect(controller.state.selectedChapter, isNull);
    });

    test('PopScope logic respects isBibleNavHidden and selection state', () {
      final service = BottomBarVisibilityService.instance;
      service.resetBibleNav();
      expect(service.isBibleNavHidden, isFalse);

      // Selection state and isBibleNavHidden drive canPop:
      bool canPop(Set<int> selectedVerses, bool isNavHidden) {
        return selectedVerses.isEmpty && !isNavHidden;
      }

      // Default: canPop is true
      expect(canPop({}, service.isBibleNavHidden), isTrue);

      // When scrolled, nav hides: canPop is false
      service.hideBibleNav();
      expect(canPop({}, service.isBibleNavHidden), isFalse);

      // First back calls showBibleNav:
      service.showBibleNav();
      expect(service.isBibleNavHidden, isFalse);

      // Now canPop is true: second back navigates to previous
      expect(canPop({}, service.isBibleNavHidden), isTrue);
    });
  });
}
