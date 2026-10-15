import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/highlight_palette.dart';
import 'package:mobile/features/bible/widgets/verse_action_bar.dart';

Widget wrapWithTheme(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: child,
    ),
  );
}

void main() {
  group('VerseActionBar 3-Stage Bottom Sheet', () {
    testWidgets('renders Stage 1 Peek state with quick colors and share/copy buttons', (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool copied = false;
      bool shared = false;
      int? pickedColor;

      await tester.pumpWidget(
        wrapWithTheme(
          VerseActionBar(
            selectedCount: 1,
            verseLabel: 'John 3:16',
            onCopy: () => copied = true,
            onShare: () => shared = true,
            onBookmark: () {},
            onHighlight: () {},
            onHighlightColor: (c) => pickedColor = c,
            onNote: () {},
            onClear: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Stage 1 elements
      expect(find.byType(VerseActionBar), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);

      // Tap Copy
      await tester.tap(find.text('Copy'));
      expect(copied, isTrue);

      // Tap Share
      await tester.tap(find.text('Share'));
      expect(shared, isTrue);

      // Tap first color dot (Mustard - index 0)
      final colorDots = find.bySemanticsLabel('Highlight color');
      expect(colorDots, findsWidgets);
      await tester.tap(colorDots.first);
      expect(pickedColor, equals(0));
    });

    testWidgets('swiping down from Peek triggers onClear dismissal', (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool cleared = false;

      await tester.pumpWidget(
        wrapWithTheme(
          VerseActionBar(
            selectedCount: 1,
            verseLabel: 'John 3:16',
            onCopy: () {},
            onShare: () {},
            onBookmark: () {},
            onHighlight: () {},
            onNote: () {},
            onClear: () => cleared = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Drag downward on the sheet by 60px
      await tester.drag(find.text('Share'), const Offset(0, 60));
      await tester.pumpAndSettle();

      expect(cleared, isTrue);
    });

    testWidgets('expanding to Stage 2 reveals actions row and full 15-color grid', (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      int? pickedColor;
      bool removedHighlight = false;

      await tester.pumpWidget(
        wrapWithTheme(
          VerseActionBar(
            selectedCount: 1,
            verseLabel: 'Romans 8:1',
            hasHighlight: true,
            currentColorIndex: 2,
            onCopy: () {},
            onShare: () {},
            onBookmark: () {},
            onHighlight: () {},
            onHighlightColor: (c) => pickedColor = c,
            onRemoveHighlight: () => removedHighlight = true,
            onNote: () {},
            onClear: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Drag upward on the sheet to expand to Stage 2
      await tester.drag(find.text('Share'), const Offset(0, -280));
      await tester.pumpAndSettle();

      // Header and actions
      expect(find.text('Romans 8:1'), findsOneWidget);
      expect(find.text('Bookmark'), findsOneWidget);
      expect(find.text('Note'), findsOneWidget);
      expect(find.text('Highlight'), findsOneWidget);
      expect(find.text('Remove highlight'), findsOneWidget);

      // All 15 highlight color dots in grid
      final allSwatches = find.bySemanticsLabel('Highlight color');
      expect(allSwatches, findsNWidgets(HighlightPalette.count));

      // Tap remove highlight
      await tester.tap(find.text('Remove highlight'));
      expect(removedHighlight, isTrue);

      // Tap another color
      await tester.tap(allSwatches.at(5));
      expect(pickedColor, equals(5));
    });

    testWidgets('expanding to Stage 3 reveals study content', (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        wrapWithTheme(
          VerseActionBar(
            selectedCount: 1,
            verseLabel: 'John 3:16',
            onCopy: () {},
            onShare: () {},
            onBookmark: () {},
            onHighlight: () {},
            onNote: () {},
            onClear: () {},
            studyContent: const Center(child: Text('Custom Study Hub View')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Expand to Stage 2 via drag up
      await tester.drag(find.text('Share'), const Offset(0, -280));
      await tester.pumpAndSettle();

      // Tap prompt to expand to Stage 3
      await tester.tap(find.byKey(VerseActionBar.studyPromptKey), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Stage 3 content visible
      expect(find.text('Study · John 3:16'), findsOneWidget);
      expect(find.text('Custom Study Hub View'), findsOneWidget);
      expect(find.byKey(VerseActionBar.collapseStudyKey), findsOneWidget);

      // Tap collapse returns to Stage 2
      await tester.tap(find.byKey(VerseActionBar.collapseStudyKey), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Custom Study Hub View'), findsNothing);
      expect(find.text('Bookmark'), findsOneWidget);
    });

    testWidgets('renders without overflow at 320dp width', (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        wrapWithTheme(
          VerseActionBar(
            selectedCount: 3,
            verseLabel: '1 Cor 13:4-7',
            onCopy: () {},
            onShare: () {},
            onBookmark: () {},
            onHighlight: () {},
            onNote: () {},
            onClear: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(VerseActionBar), findsOneWidget);
    });
  });
}
