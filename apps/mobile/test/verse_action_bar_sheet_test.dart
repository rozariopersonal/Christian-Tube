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
  group('VerseActionBar 2-Stage Bottom Sheet', () {
    testWidgets('renders Level 1 Expanded state with full actions and 15-color grid on mount', (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool copied = false;
      bool shared = false;
      bool bookmarked = false;
      bool noted = false;
      int? pickedColor;

      await tester.pumpWidget(
        wrapWithTheme(
          VerseActionBar(
            selectedCount: 1,
            verseLabel: 'John 3:16',
            onCopy: () => copied = true,
            onShare: () => shared = true,
            onBookmark: () => bookmarked = true,
            onHighlight: () {},
            onHighlightColor: (c) => pickedColor = c,
            onNote: () => noted = true,
            onClear: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Level 1: Actions, header, and 15-color palette are immediately visible without dragging
      expect(find.byType(VerseActionBar), findsOneWidget);
      expect(find.text('John 3:16'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Bookmark'), findsOneWidget);
      expect(find.text('Note'), findsOneWidget);
      expect(find.text('Highlight'), findsOneWidget);
      expect(find.text('Open Verse Study'), findsOneWidget);

      // Tap Copy
      await tester.tap(find.text('Copy'));
      expect(copied, isTrue);

      // Tap Share
      await tester.tap(find.text('Share'));
      expect(shared, isTrue);

      // Tap Bookmark
      await tester.tap(find.text('Bookmark'));
      expect(bookmarked, isTrue);

      // Tap Note
      await tester.tap(find.text('Note'));
      expect(noted, isTrue);

      // All 15 highlight swatches are rendered
      final colorDots = find.bySemanticsLabel('Highlight color');
      expect(colorDots, findsNWidgets(HighlightPalette.count));

      // Tap first color dot
      await tester.tap(colorDots.first);
      expect(pickedColor, equals(0));
    });

    testWidgets('tapping close [X] or backdrop triggers onClear dismissal', (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      int clearCount = 0;

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
            onClear: () => clearCount++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap [X] (deselect icon)
      await tester.tap(find.byTooltip('Deselect'));
      await tester.pumpAndSettle();
      expect(clearCount, equals(1));

      // Tap backdrop outside sheet container (at top of screen)
      await tester.tapAt(const Offset(180, 50));
      await tester.pumpAndSettle();
      expect(clearCount, equals(2));
    });

    testWidgets('tapping Open Verse Study expands to Level 2 and collapse button returns to Level 1', (tester) async {
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

      // On mount: Level 1 content visible, study content not rendered yet
      expect(find.text('Bookmark'), findsOneWidget);
      expect(find.text('Custom Study Hub View'), findsNothing);

      // Tap prompt to open Level 2 (Study)
      await tester.tap(find.byKey(VerseActionBar.studyPromptKey));
      await tester.pumpAndSettle();

      // Level 2 content visible
      expect(find.text('Study · John 3:16'), findsOneWidget);
      expect(find.text('Custom Study Hub View'), findsOneWidget);
      expect(find.byKey(VerseActionBar.collapseStudyKey), findsOneWidget);

      // Tap collapse returns to Level 1
      await tester.tap(find.byKey(VerseActionBar.collapseStudyKey));
      await tester.pumpAndSettle();

      expect(find.text('Custom Study Hub View'), findsNothing);
      expect(find.text('Bookmark'), findsOneWidget);
    });

    testWidgets('system back gesture in Level 2 collapses to Level 1', (tester) async {
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
            studyContent: const Center(child: Text('Custom Study Hub View')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Level 2
      await tester.tap(find.byKey(VerseActionBar.studyPromptKey));
      await tester.pumpAndSettle();
      expect(find.text('Custom Study Hub View'), findsOneWidget);

      // Trigger system back
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Collapsed back to Level 1, did not unselect verses
      expect(find.text('Custom Study Hub View'), findsNothing);
      expect(find.text('Bookmark'), findsOneWidget);
      expect(cleared, isFalse);
    });

    testWidgets('renders without overflow at 320dp width and in phone landscape (640x360)', (tester) async {
      // 1. Compact portrait 320dp width
      tester.view.physicalSize = const Size(320 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;

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

      // 2. Phone landscape 640x360 (must not throw ArgumentError in clamp)
      tester.view.physicalSize = const Size(640 * 2, 360 * 2);
      await tester.pumpWidget(
        wrapWithTheme(
          VerseActionBar(
            selectedCount: 1,
            verseLabel: 'Romans 8:28',
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

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
