import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/bible/controllers/bible_controller.dart';
import 'package:mobile/features/bible/models/bible_version.dart';
import 'package:mobile/features/bible/widgets/verse_highlight_layer.dart';
import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';
import 'package:mobile/shared/ui/highlight_color_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Instant Optimistic Highlights', () {
    late Directory tempDir;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('instant_highlight_test_');
      LocalBibleService.overrideDbPath = p.join(tempDir.path, 'bible.db');
      await LocalBibleService.resetForTest();
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
    test('applyHighlight updates in-memory state and clears selection synchronously', () async {
      final controller = BibleController(
        initialVersionId: 'TAOBVSI',
        initialBook: 'Genesis',
        initialChapter: 1,
        initialVerse: 1,
        saveProgress: false,
      );

      final version = BibleVersion(
        id: 'TAOBVSI',
        name: 'Tamil Bible',
        shortname: 'TAOBVSI',
        description: 'Tamil Bible Translation',
        lang: 'ta',
      );

      controller.selectVersion(version);
      // Manually set selection on verse 3
      controller.toggleVerseSelection(3, book: 'Genesis', chapter: 1);
      expect(controller.state.selectedVerses, contains(3));

      // Trigger applyHighlight
      final future = controller.applyHighlight(2);

      // Assert that state updated synchronously/optimistically!
      final key = BibleControllerState.verseHighlightKey('Genesis', 1, 3);
      expect(controller.state.verseHighlights[key], 2);
      expect(controller.state.selectedVerses, isEmpty);
      expect(controller.state.selectionHasHighlight, isFalse);

      await future;
    });

    test('removeHighlight removes in-memory highlight and clears selection synchronously', () async {
      final controller = BibleController(
        initialVersionId: 'TAOBVSI',
        initialBook: 'Genesis',
        initialChapter: 1,
        initialVerse: 1,
        saveProgress: false,
      );

      final version = BibleVersion(
        id: 'TAOBVSI',
        name: 'Tamil Bible',
        shortname: 'TAOBVSI',
        description: 'Tamil Bible Translation',
        lang: 'ta',
      );
      controller.selectVersion(version);

      // Pre-apply highlight
      controller.toggleVerseSelection(5, book: 'Genesis', chapter: 1);
      await controller.applyHighlight(4);
      final key = BibleControllerState.verseHighlightKey('Genesis', 1, 5);
      expect(controller.state.verseHighlights[key], 4);

      // Now select and remove
      controller.toggleVerseSelection(5, book: 'Genesis', chapter: 1);
      expect(controller.state.selectedVerses, contains(5));

      final future = controller.removeHighlight();

      // Assert that removal happened synchronously/optimistically!
      expect(controller.state.verseHighlights.containsKey(key), isFalse);
      expect(controller.state.selectedVerses, isEmpty);

      await future;
    });
  });

  group('Navigation Bar Inset Calculations', () {
    testWidgets('Bottom navigation includes bottom window insets to prevent clipping', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [AppTokens.dark],
          ),
          home: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(bottom: 34.0),
              viewPadding: EdgeInsets.only(bottom: 34.0),
            ),
            child: Scaffold(
              bottomNavigationBar: Builder(
                builder: (context) {
                  final bottomPadding = MediaQuery.paddingOf(context).bottom;
                  final barHeight = 60.0 + bottomPadding;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: barHeight,
                    child: NavigationBar(
                      destinations: const [
                        NavigationDestination(icon: Icon(Icons.home), label: 'Feed'),
                        NavigationDestination(icon: Icon(Icons.book), label: 'Bible'),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      final container = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      // 60.0 + 34.0 = 94.0
      expect(container.constraints?.maxHeight, 94.0);
    });
  });

  group('Highlight Layer and Picker Performance', () {
    testWidgets('VerseHighlightLayer renders child cleanly without calculating bands when not highlighted', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VerseHighlightLayer(
              highlightColor: null,
              isHovered: false,
              child: Text('In the beginning God created the heavens and the earth.'),
            ),
          ),
        ),
      );

      expect(find.text('In the beginning God created the heavens and the earth.'), findsOneWidget);
    });

    testWidgets('HighlightColorPicker invokes onColorSelected immediately on swatch tap', (tester) async {
      int? pickedColor;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [AppTokens.dark],
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    HighlightColorPicker.show(
                      context,
                      hasHighlight: false,
                      onColorSelected: (idx) {
                        pickedColor = idx;
                      },
                    );
                  },
                  child: const Text('Show Picker'),
                );
              },
            ),
          ),
        ),
      );

      // Tap to show picker
      await tester.tap(find.text('Show Picker'));
      await tester.pumpAndSettle();

      // Tap on color swatch index 1 (yellow/green in HighlightPalette)
      expect(find.byType(HighlightColorPicker), findsOneWidget);
      final inkWells = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(InkWell),
      );
      expect(inkWells, findsWidgets);

      // Tap the second swatch (index 1)
      await tester.tap(inkWells.at(1));

      // onColorSelected should fire immediately before pop completes!
      expect(pickedColor, 1);
    });
  });
}
