import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/bible/controllers/bible_controller.dart';
import 'package:mobile/features/bible/screens/bible_screen.dart';
import 'package:mobile/features/engines/scripture/services/book_name_service.dart';
import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    await BookNameService().ensureLoaded();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bible_scroll_test_');
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
      for (var v = 1; v <= 30; v++)
        {
          'bookNumber': 43,
          'bookName': 'John',
          'chapter': 3,
          'verse': v,
          'text':
              'Verse text for John 3:$v with multiple words to ensure it takes up significant vertical height in the list view so scrolling is measurable.',
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

  testWidgets(
      'BibleScreen with initialVerse scrolls to and highlights the target verse',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppTokens.dark]),
        home: const BibleScreen(
          initialVersionId: 'WEB',
          initialBook: 'John',
          initialChapter: 3,
          initialVerse: 16,
          saveProgress: false,
        ),
      ),
    );

    // Pump frames to let async initialization complete
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Allow scroll-to-verse transition to complete.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Fast forward past highlight timer (5s) and sqflite lock timer (10s)
    await tester.pump(const Duration(seconds: 12));

    // The target verse must be visible on screen (its item built), and
    // verse 1 must have scrolled out of view.
    final verse16 = find.textContaining('John 3:16');
    expect(verse16, findsOneWidget);
    final verse1 = find.textContaining('John 3:1 ');
    expect(verse1, findsNothing);
    final bodyRect = tester.getRect(
      find.byType(ScrollablePositionedList),
    );
    final verse16Rect = tester.getRect(verse16);
    expect(verse16Rect.top, greaterThanOrEqualTo(bodyRect.top));
    expect(verse16Rect.bottom, lessThanOrEqualTo(bodyRect.bottom + 1));
  });

  testWidgets(
      'Selecting a verse in the book/chapter/verse selector scrolls to and highlights it',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = BibleController(
      initialVersionId: 'WEB',
      initialBook: 'John',
      initialChapter: 3,
      initialVerse: 1,
      saveProgress: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppTokens.dark]),
        home: BibleScreen(controller: controller),
      ),
    );
    controller.init();

    // Let the chapter finish loading.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 500));

    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    // Reader starts near the very top at verse 1.
    expect(scrollable.position.pixels, lessThan(100));

    // Open the book/chapter/verse selector from the bottom chapter nav.
    await tester.tap(find.bySemanticsLabel(RegExp('Book and chapter selector')));
    await tester.pumpAndSettle();

    // BOOKS tab → pick current book John → advances to CHAPTERS.
    await tester.tap(find.text('John'));
    await tester.pumpAndSettle();

    // CHAPTERS tab → pick chapter 3 → loads verses, advances to VERSES.
    await tester.tap(find.text('3'));
    await tester.pump(const Duration(milliseconds: 350));

    // Let the on-demand verse preview load from sqlite.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    // VERSES tab → pick verse 20 (mid-chapter) forces the list to scroll.
    await tester.ensureVisible(find.text('20'));
    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));

    // The reader jumped from verse 1 down to verse 20, which must now be
    // visible on screen while verse 1 scrolled away.
    final verse20 = find.textContaining('John 3:20');
    expect(verse20, findsOneWidget);
    expect(find.textContaining('John 3:1 '), findsNothing);
    final bodyRect = tester.getRect(
      find.byType(ScrollablePositionedList),
    );
    final verse20Rect = tester.getRect(verse20);
    expect(verse20Rect.top, greaterThanOrEqualTo(bodyRect.top));
    expect(verse20Rect.bottom, lessThanOrEqualTo(bodyRect.bottom + 1));

    // ...and the verse was highlighted.
    expect(controller.state.currentBook, 'John');
    expect(controller.state.currentChapter, 3);
    expect(controller.state.highlightedVerse, 20);

    // Fast forward past the highlight timer.
    await tester.pump(const Duration(seconds: 12));
  });
}
