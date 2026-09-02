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

    // Allow scroll animation to finish
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ListView), findsOneWidget);
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.pixels, greaterThan(200));

    // Fast forward past highlight timer (5s) and sqflite lock timer (10s)
    await tester.pump(const Duration(seconds: 12));
  });
}
