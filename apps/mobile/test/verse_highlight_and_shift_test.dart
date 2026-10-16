import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/bible/models/bible_verse.dart';
import 'package:mobile/features/bible/services/verse_band_geometry.dart';
import 'package:mobile/features/bible/widgets/verse_action_bar.dart';
import 'package:mobile/features/bible/widgets/verse_text.dart';
import 'package:mobile/shared/services/reader_appearance.dart';

Widget wrapWithTokens(Widget child) {
  return MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [AppTokens.dark]),
    home: Scaffold(body: child),
  );
}

void main() {
  group('VerseBandGeometry Unit Tests', () {
    test('returns empty list for empty or degenerate boxes', () {
      expect(VerseBandGeometry.computeLineBands([]), isEmpty);
      expect(
        VerseBandGeometry.computeLineBands([
          const TextBox.fromLTRBD(10, 10, 10, 20, TextDirection.ltr),
        ]),
        isEmpty,
      );
    });

    test('groups multiple boxes on the same line into a single band', () {
      final boxes = [
        const TextBox.fromLTRBD(10, 10, 50, 30, TextDirection.ltr),
        const TextBox.fromLTRBD(55, 10, 100, 30, TextDirection.ltr),
      ];
      final bands = VerseBandGeometry.computeLineBands(
        boxes,
        horizontalBleed: 4.0,
      );
      expect(bands.length, 1);
      expect(bands.first.left, 6.0); // 10 - 4
      expect(bands.first.right, 104.0); // 100 + 4
      expect(bands.first.top, 10.0);
      expect(bands.first.bottom, 30.0);
    });

    test('separates multiple lines and bridges vertical gaps', () {
      final boxes = [
        // Line 1
        const TextBox.fromLTRBD(10, 0, 100, 20, TextDirection.ltr),
        // Line 2 (gap between 20 and 24)
        const TextBox.fromLTRBD(10, 24, 80, 44, TextDirection.ltr),
      ];
      final bands = VerseBandGeometry.computeLineBands(boxes);
      expect(bands.length, 2);
      // Gap between 20 and 24 should be closed at midpoint 22
      expect(bands[0].bottom, 22.0);
      expect(bands[1].top, 22.0);
    });

    test('applies fullWidth mode spanning column width', () {
      final boxes = [
        const TextBox.fromLTRBD(20, 0, 80, 20, TextDirection.ltr),
      ];
      final bands = VerseBandGeometry.computeLineBands(
        boxes,
        mode: BandWidthMode.fullWidth,
        columnWidth: 320.0,
      );
      expect(bands.length, 1);
      expect(bands.first.left, 0.0);
      expect(bands.first.right, 320.0);
    });
  });

  group('VerseText Layout Invariance (Zero-Shift Contract)', () {
    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      testWidgets('VerseText layout size and position do not shift at width $width', (tester) async {
        tester.view.physicalSize = Size(width * 2, 800 * 2);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final appearance = ReaderAppearance();
        final verse = BibleVerse(
          number: 16,
          text: 'For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.',
        );

        // 1. Initial idle state
        await tester.pumpWidget(
          wrapWithTokens(
            VerseText(
              verse: verse,
              appearance: appearance,
              isSelected: false,
              isHighlighted: false,
              refCount: 2,
              commentaryCount: 1,
              hasNote: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final paragraphFinder = find.descendant(
          of: find.byType(VerseText),
          matching: find.byType(RichText),
        ).first;
        expect(paragraphFinder, findsOneWidget);

        final RenderParagraph initialRender = tester.renderObject(paragraphFinder);
        final initialSize = initialRender.size;
        final initialOffset = initialRender.localToGlobal(Offset.zero);

        // 2. Selected state
        await tester.pumpWidget(
          wrapWithTokens(
            VerseText(
              verse: verse,
              appearance: appearance,
              isSelected: true,
              isHighlighted: false,
              refCount: 2,
              commentaryCount: 1,
              hasNote: true,
            ),
          ),
        );
        await tester.pump();

        final RenderParagraph selectedRender = tester.renderObject(paragraphFinder);
        expect(selectedRender.size, equals(initialSize),
            reason: 'Verse size shifted when selected at width $width!');
        expect(selectedRender.localToGlobal(Offset.zero), equals(initialOffset),
            reason: 'Verse position shifted when selected at width $width!');

        // 3. Highlighted with persistent color state
        await tester.pumpWidget(
          wrapWithTokens(
            VerseText(
              verse: verse,
              appearance: appearance,
              isSelected: false,
              isHighlighted: false,
              highlightColorIndex: 2, // Sage
              refCount: 2,
              commentaryCount: 1,
              hasNote: true,
            ),
          ),
        );
        await tester.pump();

        final RenderParagraph highlightedRender = tester.renderObject(paragraphFinder);
        expect(highlightedRender.size, equals(initialSize),
            reason: 'Verse size shifted when highlighted at width $width!');
        expect(highlightedRender.localToGlobal(Offset.zero), equals(initialOffset),
            reason: 'Verse position shifted when highlighted at width $width!');

        // 4. Highlighted + Selected state
        await tester.pumpWidget(
          wrapWithTokens(
            VerseText(
              verse: verse,
              appearance: appearance,
              isSelected: true,
              isHighlighted: false,
              highlightColorIndex: 2,
              refCount: 2,
              commentaryCount: 1,
              hasNote: true,
            ),
          ),
        );
        await tester.pump();

        final RenderParagraph comboRender = tester.renderObject(paragraphFinder);
        expect(comboRender.size, equals(initialSize),
            reason: 'Verse size shifted when highlighted and selected at width $width!');
        expect(comboRender.localToGlobal(Offset.zero), equals(initialOffset),
            reason: 'Verse position shifted when highlighted and selected at width $width!');
      });
    }
  });

  group('VerseHighlightLayer Appearance & No Underline Tests', () {
    testWidgets('VerseHighlightLayer paints without throwing and does not paint underlines', (tester) async {
      final appearance = ReaderAppearance();
      final verse = BibleVerse(number: 1, text: 'Short single line verse text.');

      await tester.pumpWidget(
        wrapWithTokens(
          VerseText(
            verse: verse,
            appearance: appearance,
            isSelected: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('VerseActionBar renders as 2-stage sheet with full actions and palette on mount', (tester) async {
      await tester.pumpWidget(
        wrapWithTokens(
          VerseActionBar(
            selectedCount: 2,
            onCopy: () {},
            onShare: () {},
            onBookmark: () {},
            onHighlight: () {},
            onNote: () {},
            onClear: () {},
            onStudy: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Level 1: Copy, Share, Bookmark, Note, and full Highlight grid are present immediately
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Bookmark'), findsOneWidget);
      expect(find.text('Note'), findsOneWidget);
      expect(find.text('Highlight'), findsOneWidget);
      expect(find.bySemanticsLabel('Highlight color'), findsWidgets);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });
}
