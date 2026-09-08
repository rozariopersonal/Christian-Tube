import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/color_utils.dart';
import 'package:mobile/core/theme/highlight_palette.dart';
import 'package:mobile/features/bible/models/bible_highlight.dart';
import 'package:mobile/features/bible/services/bible_highlight_service.dart';
import 'package:mobile/features/engines/scripture/adapters/web_bible_data_adapter.dart';
import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BibleHighlightService (SQLite)', () {
    late Directory tempDir;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('bible_highlight_test_');
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

    test('apply + load round-trips a single verse highlight', () async {
      final service = BibleHighlightService();
      await service.apply(
        versionId: 'TAOBVSI',
        book: 'John',
        chapter: 3,
        verses: [16],
        colorIndex: 7,
        text: 'For God so loved the world',
      );

      final all = await service.loadHighlights();
      expect(all.length, 1);
      final h = all.first;
      expect(h.versionId, 'TAOBVSI');
      expect(h.book, 'John');
      expect(h.chapter, 3);
      expect(h.verses, [16]);
      expect(h.colorIndex, 7);
      expect(h.reference, 'John 3:16');
    });

    test('highlights persist in the database across adapter reopen', () async {
      await BibleHighlightService().apply(
        versionId: 'TAOBVSI',
        book: 'John',
        chapter: 3,
        verses: [16],
        colorIndex: 7,
        text: 'For God so loved the world',
      );

      // Reopen the very same database file through a fresh adapter — this is
      // only possible if highlights were written to SQLite, not shared prefs.
      await LocalBibleService.resetForTest();
      final all = await BibleHighlightService().loadHighlights();
      expect(all.length, 1);
      expect(all.first.verses, [16]);
      expect(all.first.colorIndex, 7);
    });

    test('apply supports multiple verses together', () async {
      final service = BibleHighlightService();
      await service.apply(
        versionId: 'TAOBVSI',
        book: 'John',
        chapter: 3,
        verses: [16, 17, 18],
        colorIndex: 5,
        text: 'a\nb\nc',
      );

      final forChapter = await service.getForChapter('John', 3);
      expect(forChapter.length, 1);
      expect(forChapter.first.verses, [16, 17, 18]);
      expect(forChapter.first.reference, 'John 3:16-18');
      expect(await service.getForChapter('John', 1), isEmpty);
    });

    test('applying a new color replaces the old one (replace model)', () async {
      final service = BibleHighlightService();
      await service.apply(
        versionId: 'TAOBVSI',
        book: 'John',
        chapter: 3,
        verses: [16],
        colorIndex: 4,
        text: 'x',
      );
      await service.apply(
        versionId: 'TAOBVSI',
        book: 'John',
        chapter: 3,
        verses: [16],
        colorIndex: 12,
        text: 'x',
      );

      final forChapter = await service.getForChapter('John', 3);
      expect(forChapter.length, 1);
      expect(forChapter.first.colorIndex, 12);
    });

    test('apply with partial overlap keeps unselected verses', () async {
      final service = BibleHighlightService();
      await service.apply(
        versionId: 'TAOBVSI',
        book: 'John',
        chapter: 3,
        verses: [16, 17, 18],
        colorIndex: 7,
        text: 'a\nb\nc',
      );
      // Recolor only verse 16 — verses 17,18 should keep their highlight.
      await service.apply(
        versionId: 'TAOBVSI',
        book: 'John',
        chapter: 3,
        verses: [16],
        colorIndex: 4,
        text: 'a',
      );

      final forChapter = await service.getForChapter('John', 3);
      expect(forChapter.length, 2);
      final green = forChapter.firstWhere((h) => h.colorIndex == 4);
      expect(green.verses, [16]);
      final red = forChapter.firstWhere((h) => h.colorIndex == 7);
      expect(red.verses, [17, 18]);
    });

    test('remove deletes the highlight for the given verses only', () async {
      final service = BibleHighlightService();
      await service.apply(
        versionId: 'TAOBVSI',
        book: 'John',
        chapter: 3,
        verses: [16, 17, 18],
        colorIndex: 9,
        text: 'abc',
      );
      final removed = await service.remove(
        book: 'John',
        chapter: 3,
        verses: [16],
      );
      expect(removed, 1);

      final forChapter = await service.getForChapter('John', 3);
      expect(forChapter.length, 1);
      expect(forChapter.first.verses, [17, 18]);
    });

    test('clearAll empties the store', () async {
      final service = BibleHighlightService();
      await service.apply(
        versionId: 'TAOBVSI',
        book: 'John',
        chapter: 3,
        verses: [16],
        colorIndex: 4,
        text: 'x',
      );
      await service.clearAll();
      expect(await service.loadHighlights(), isEmpty);
    });
  });

  group('WebBibleDataAdapter highlights (SharedPreferences fallback)', () {
    test('persists and loads a highlight', () async {
      SharedPreferences.setMockInitialValues({});
      final adapter = WebBibleDataAdapter();
      await adapter.saveHighlights([
        BibleHighlight(
          versionId: 'TAOBVSI',
          book: 'John',
          chapter: 3,
          verses: [16],
          colorIndex: 4,
          text: 'x',
          savedAt: DateTime.utc(2026, 9, 8),
        ),
      ]);

      final all = await adapter.loadHighlights();
      expect(all.length, 1);
      expect(all.first.verses, [16]);
      expect(all.first.colorIndex, 4);
    });

    test('corrupt JSON is tolerated', () async {
      SharedPreferences.setMockInitialValues({
        'bible_highlights_v1': 'not json at all',
      });
      final adapter = WebBibleDataAdapter();
      expect(await adapter.loadHighlights(), isEmpty);
    });
  });

  group('BibleHighlight model', () {
    test('toJson/fromJson round-trip', () {
      final h = BibleHighlight(
        versionId: 'TAOBVSI',
        book: 'John',
        chapter: 3,
        verses: [16, 17],
        colorIndex: 8,
        text: 'v16\nv17',
        savedAt: DateTime.utc(2026, 9, 8),
      );
      final restored = BibleHighlight.fromJson(h.toJson());
      expect(restored.versionId, h.versionId);
      expect(restored.book, h.book);
      expect(restored.chapter, h.chapter);
      expect(restored.verses, h.verses);
      expect(restored.colorIndex, h.colorIndex);
      expect(restored.text, h.text);
      expect(restored.savedAt, h.savedAt);
    });
  });

  group('HighlightPalette', () {
    test('has 15 colors', () {
      expect(HighlightPalette.count, 15);
      expect(HighlightPalette.colors.length, 15);
    });

    test('dark colors get white foreground, light colors get dark', () {
      // Deep shades → white text.
      for (final i in [10, 11, 12, 13, 14]) {
        expect(
          HighlightPalette.onColorFor(i),
          const Color(0xFFFFFFFF),
          reason: 'deep color $i should render white text',
        );
      }
      // Light shades → dark text (luminance-based contrast).
      for (final i in [0, 1, 2, 4]) {
        expect(
          HighlightPalette.onColorFor(i).computeLuminance(),
          lessThan(0.3),
          reason: 'light color $i should render dark text',
        );
        expect(
          HighlightPalette.colorFor(i).computeLuminance(),
          greaterThan(0.45),
          reason: 'light color $i should be a light background',
        );
      }
    });

    test('every swatch has acceptable contrast', () {
      for (var i = 0; i < HighlightPalette.count; i++) {
        final fg = HighlightPalette.onColorFor(i);
        final bg = HighlightPalette.colorFor(i);
        final contrast = _contrastRatio(bg, fg);
        expect(contrast, greaterThan(1.5),
            reason: 'color $i contrast is too low');
      }
    });
  });

  group('contrastColor', () {
    test('returns white for dark backgrounds', () {
      expect(contrastColor(const Color(0xFF000000)), const Color(0xFFFFFFFF));
      expect(contrastColor(const Color(0xFF3949AB)), const Color(0xFFFFFFFF));
    });

    test('returns dark for light backgrounds', () {
      final c = contrastColor(const Color(0xFFFFFFFF));
      expect(c.computeLuminance(), lessThan(0.5));
      expect(contrastColor(const Color(0xFFFFEB3B)).computeLuminance(),
          lessThan(0.5));
    });
  });
}

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}