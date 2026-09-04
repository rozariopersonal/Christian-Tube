import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/bible/screens/bible_screen.dart';
import 'package:mobile/features/engines/scripture/services/book_name_service.dart';
import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';

Widget wrapWithApp(Widget child) {
  return MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [AppTokens.dark]),
    home: child,
  );
}

Future<void> _pumpAndWaitForLoad(WidgetTester tester) async {
  await tester.pumpWidget(
    wrapWithApp(
      const BibleScreen(
        initialVersionId: 'WEB',
        initialBook: 'John',
        initialChapter: 3,
        saveProgress: false,
      ),
    ),
  );

  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 50));
  }

  await tester.pump(const Duration(seconds: 12));
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    await BookNameService().ensureLoaded();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bible_viewport_test_');
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

  group('BibleScreen responsive viewport rendering', () {
    testWidgets('renders without overflow at 320dp (compact)', (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpAndWaitForLoad(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('John 3'), findsOneWidget);
      expect(find.text('Prev'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('renders without overflow at 600dp (medium)', (tester) async {
      tester.view.physicalSize = const Size(600 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpAndWaitForLoad(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('John 3'), findsOneWidget);
      expect(find.text('Prev'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('renders without overflow at 840dp (expanded)', (tester) async {
      tester.view.physicalSize = const Size(840 * 2, 1024 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpAndWaitForLoad(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('John 3'), findsOneWidget);
      expect(find.text('Prev'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('renders without overflow at 1400dp (large desktop)', (tester) async {
      tester.view.physicalSize = const Size(1400 * 2, 900 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpAndWaitForLoad(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('John 3'), findsOneWidget);
      expect(find.text('Prev'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });
  });

  group('BibleScreen responsive navigation', () {
    testWidgets('AppBar actions do not overflow at 320dp', (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpAndWaitForLoad(tester);

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('More'), findsOneWidget);
      expect(find.byTooltip('Search Bible'), findsOneWidget);
    });

    testWidgets('Prev/Next navigation reachable at 320dp landscape', (tester) async {
      tester.view.physicalSize = const Size(640 * 2, 320 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpAndWaitForLoad(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Prev'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });
  });
}
