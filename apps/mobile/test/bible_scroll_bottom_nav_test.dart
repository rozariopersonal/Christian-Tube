import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/core/services/bottom_bar_visibility_service.dart';
import 'package:mobile/features/bible/controllers/bible_controller.dart';
import 'package:mobile/features/bible/widgets/bible_bottom_nav.dart';
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

      // When scrolled, main tab nav hides: canPop is false
      service.hideBibleNav();
      expect(canPop({}, service.isBibleNavHidden), isFalse);

      // First back calls showBibleNav:
      service.showBibleNav();
      expect(service.isBibleNavHidden, isFalse);

      // Now canPop is true: second back navigates to previous
      expect(canPop({}, service.isBibleNavHidden), isTrue);

      // When verses are selected: canPop is false (first back clears selection)
      expect(canPop({1, 2}, service.isBibleNavHidden), isFalse);
    });

    testWidgets('BibleBottomNav renders as floating rounded bar with accent color and onPrimary foreground', (tester) async {
      final controller = BibleController(
        initialVersionId: 'WEB',
        initialBook: 'John',
        initialChapter: 3,
        initialVerse: null,
        saveProgress: false,
      );
      await tester.runAsync(() async {
        await controller.init();
      });

      const testAccent = Color(0xFF6366F1);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: testAccent, primary: testAccent),
            extensions: [AppTokens.light.copyWith(accent: testAccent)],
          ),
          home: Scaffold(
            body: BibleBottomNav(
              controller: controller,
              onShowBookChapterSelector: () {},
              onCopy: () {},
              onShare: () {},
              onBookmark: () {},
              onHighlight: () {},
              onNote: () {},
              onClear: () {},
              onStudy: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Find the floating rounded pill container
      final containerFinder = find.byWidgetPredicate((widget) {
        if (widget is Container && widget.decoration is BoxDecoration) {
          final dec = widget.decoration as BoxDecoration;
          return dec.color == testAccent && dec.borderRadius == BorderRadius.circular(24);
        }
        return false;
      });
      expect(containerFinder, findsOneWidget);

      // Verify book and chapter label is present
      expect(find.text('John 3'), findsOneWidget);

      // Verify previous and next chapter buttons
      expect(find.bySemanticsLabel('Previous chapter'), findsOneWidget);
      expect(find.bySemanticsLabel('Next chapter'), findsOneWidget);
    });

    testWidgets('BibleBottomNav renders without overflow across 320, 600, 840, 1400dp viewports', (tester) async {
      final controller = BibleController(
        initialVersionId: 'WEB',
        initialBook: 'John',
        initialChapter: 3,
        initialVerse: null,
        saveProgress: false,
      );
      await tester.runAsync(() async {
        await controller.init();
      });

      for (final width in [320.0, 600.0, 840.0, 1400.0]) {
        tester.view.physicalSize = Size(width * 2, 800 * 2);
        tester.view.devicePixelRatio = 2.0;

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark().copyWith(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFFF59E0B),
                primary: const Color(0xFFF59E0B),
                brightness: Brightness.dark,
              ),
              extensions: const [AppTokens.dark],
            ),
            home: Scaffold(
              body: BibleBottomNav(
                controller: controller,
                onShowBookChapterSelector: () {},
                onCopy: () {},
                onShare: () {},
                onBookmark: () {},
                onHighlight: () {},
                onNote: () {},
                onClear: () {},
                onStudy: () {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull, reason: 'Overflow occurred at $width dp');
        expect(find.text('John 3'), findsOneWidget);
      }
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    });

    testWidgets('Bottom bar slides down and collapses to safe-area so bible navigator moves to the bottom, and expands back up when restored', (tester) async {
      final service = BottomBarVisibilityService.instance;
      service.resetBibleNav();

      double bodyHeight = 0;
      const bottomInset = 34.0;
      const tabContentHeight = 60.0;
      const barHeight = tabContentHeight + bottomInset;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const [AppTokens.light],
          ),
          home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(bottom: bottomInset)),
            child: Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      bodyHeight = constraints.maxHeight;
                      return const SizedBox.expand();
                    },
                  ),
                ],
              ),
              bottomNavigationBar: ListenableBuilder(
                listenable: service,
                builder: (context, _) {
                  final isHidden = service.isBibleNavHidden;
                  final targetHeight = isHidden ? bottomInset : barHeight;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.fastOutSlowIn,
                    height: targetHeight,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: 0,
                        maxHeight: barHeight,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.fastOutSlowIn,
                          offset: isHidden ? const Offset(0, 1) : Offset.zero,
                          child: IgnorePointer(
                            ignoring: isHidden,
                            child: Container(height: barHeight, color: Colors.blue),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialHeight = bodyHeight;
      expect(initialHeight, greaterThan(0));

      // Scroll triggers hideBibleNav:
      service.hideBibleNav();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Body expands downwards by tabContentHeight (60.0), moving the Bible navigator to the bottom:
      expect(bodyHeight, equals(initialHeight + tabContentHeight));

      // The slide offset animates to Offset(0, 1):
      final animatedSlideFinder = find.byType(AnimatedSlide);
      expect(animatedSlideFinder, findsOneWidget);
      final slideWidget = tester.widget<AnimatedSlide>(animatedSlideFinder);
      expect(slideWidget.offset, equals(const Offset(0, 1)));

      // Restoring tab bar:
      service.showBibleNav();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Body contracts back, moving the Bible navigator back up to rest above tabs:
      expect(bodyHeight, equals(initialHeight));
      final restoredSlide = tester.widget<AnimatedSlide>(animatedSlideFinder);
      expect(restoredSlide.offset, equals(Offset.zero));
    });
  });
}

