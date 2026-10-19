import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/layout/shell_back_handler.dart';
import 'package:mobile/core/services/bottom_bar_visibility_service.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/bible/screens/bible_screen.dart';
import 'package:mobile/features/books/widgets/scripture_verse_popup.dart';
import 'package:mobile/features/engines/scripture/services/book_name_service.dart';
import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/shared/ui/bible_version_pill.dart';

ThemeData _testTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      extensions: const [AppTokens.light],
    );

class _MockCallerScreen extends StatelessWidget {
  const _MockCallerScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('BOOK_READER_SCREEN'),
            ElevatedButton(
              onPressed: () => context.push('/bible?book=John&chapter=3&verse=16&version=WEB'),
              child: const Text('OPEN_BIBLE_FROM_BOOK'),
            ),
          ],
        ),
      ),
    );
  }
}

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/books/sample_book',
    routes: [
      ShellRoute(
        builder: (context, state, child) => ShellBackHandler(
          path: state.uri.path,
          child: Scaffold(body: child),
        ),
        routes: [
          GoRoute(
            path: '/books/:id',
            builder: (context, state) => const _MockCallerScreen(),
          ),
          GoRoute(
            path: '/bible',
            builder: (context, state) => const BibleScreen(
              initialVersionId: 'WEB',
              initialBook: 'John',
              initialChapter: 3,
              initialVerse: 16,
              saveProgress: false,
            ),
          ),
        ],
      ),
    ],
  );
}

Widget _wrapWithApp(Widget child) => MaterialApp(
      theme: _testTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: child),
    );

void main() {
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    await BookNameService().ensureLoaded();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('popup_bible_back_test_');
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
          'text': 'For God so loved the world in verse $v of John 3.',
        },
    ]);

    BottomBarVisibilityService.instance.resetBibleNav();
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

  group('ScriptureVersePopup UI and Layout Tests', () {
    testWidgets('renders cleanly with safe area bottom inset and unclipped Open in Bible Reader button', (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;
      tester.view.padding = const FakeViewPadding(bottom: 34 * 2);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
      });

      await tester.pumpWidget(
        _wrapWithApp(
          const ScriptureVersePopup(
            bookNumber: 43,
            chapter: 3,
            startVerse: 16,
            rawReference: 'John 3:16',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Open in Bible Reader'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without overflow at narrow 320dp viewport', (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 568 * 2);
      tester.view.devicePixelRatio = 2.0;
      tester.view.padding = const FakeViewPadding(bottom: 24 * 2);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
      });

      await tester.pumpWidget(
        _wrapWithApp(
          const ScriptureVersePopup(
            bookNumber: 1,
            chapter: 1,
            startVerse: 1,
            endVerse: 5,
            rawReference: 'Genesis 1:1-5',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Open in Bible Reader'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('defaults to NASB for English reader when no prior choice was saved', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          const ScriptureVersePopup(
            bookNumber: 43,
            chapter: 3,
            startVerse: 16,
            rawReference: 'John 3:16',
            languageCode: 'en',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('NASB'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('remembers last chosen version and applies it to subsequent English popups', (tester) async {
      await tester.runAsync(() async {
        // 1. First open: verify NASB default
        await tester.pumpWidget(
          _wrapWithApp(
            const ScriptureVersePopup(
              bookNumber: 43,
              chapter: 3,
              startVerse: 16,
              rawReference: 'John 3:16',
              languageCode: 'en',
            ),
          ),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('NASB'), findsOneWidget);

        // 2. Select KJV via BibleVersionPill's onSelectVersion callback
        final pill = tester.widget<BibleVersionPill>(find.byType(BibleVersionPill));
        pill.onSelectVersion?.call('KJV');
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await tester.pump(const Duration(milliseconds: 100));

        // Verify that SharedPreferences saved 'KJV' for 'eng'
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('${ScriptureVersePopup.prefLastVersionPrefix}eng'), 'KJV');

        // Clean up first popup
        await tester.pumpWidget(_wrapWithApp(const SizedBox.shrink()));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 150));

        // 3. Open another verse reference in English reader
        await tester.pumpWidget(
          _wrapWithApp(
            const ScriptureVersePopup(
              key: ValueKey('second_popup'),
              bookNumber: 19,
              chapter: 23,
              startVerse: 1,
              rawReference: 'Psalm 23:1',
              languageCode: 'en',
            ),
          ),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await tester.pump(const Duration(milliseconds: 100));

        // Verifies KJV is now remembered and active!
        expect(find.text('KJV'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Allow any background tasks on isolate to settle before tearDown
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
    });
  });

  group('BibleScreen Back Navigation Tests', () {
    testWidgets('pressing back on BibleScreen pushed from book reader returns to book reader', (tester) async {
      final router = _buildTestRouter();
      await tester.pumpWidget(
        MaterialApp.router(
          theme: _testTheme(),
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('BOOK_READER_SCREEN'), findsOneWidget);

      // Open Bible reader from book reader
      await tester.tap(find.text('OPEN_BIBLE_FROM_BOOK'));
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(BibleScreen), findsOneWidget);

      // Press system back
      final handled = await tester.binding.handlePopRoute();
      expect(handled, isTrue);
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Successfully returned to book reader!
      expect(find.text('BOOK_READER_SCREEN'), findsOneWidget);
      expect(find.byType(BibleScreen), findsNothing);
    });

    testWidgets('system back restores hidden bible navigation first before popping screen', (tester) async {
      final router = _buildTestRouter();
      await tester.pumpWidget(
        MaterialApp.router(
          theme: _testTheme(),
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Open Bible reader
      await tester.tap(find.text('OPEN_BIBLE_FROM_BOOK'));
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(BibleScreen), findsOneWidget);

      // Simulate hide nav on scroll
      BottomBarVisibilityService.instance.hideBibleNav();
      await tester.pump(const Duration(milliseconds: 100));
      expect(BottomBarVisibilityService.instance.isBibleNavHidden, isTrue);

      // First back press restores navigation bar
      final handledFirst = await tester.binding.handlePopRoute();
      expect(handledFirst, isTrue);
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(BottomBarVisibilityService.instance.isBibleNavHidden, isFalse);
      expect(find.byType(BibleScreen), findsOneWidget);

      // Second back press pops back to book reader
      final handledSecond = await tester.binding.handlePopRoute();
      expect(handledSecond, isTrue);
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('BOOK_READER_SCREEN'), findsOneWidget);
      expect(find.byType(BibleScreen), findsNothing);
    });
  });
}
