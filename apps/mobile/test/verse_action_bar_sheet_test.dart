import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/layout/shell_back_handler.dart';
import 'package:mobile/core/theme/highlight_palette.dart';
import 'package:mobile/features/bible/models/bible_verse.dart';
import 'package:mobile/features/bible/widgets/verse_action_bar.dart';

Widget sheet(
    {VoidCallback? onClear,
    VoidCallback? onStudy,
    VoidCallback? onCopy,
    VoidCallback? onShare,
    VoidCallback? onBookmark,
    VoidCallback? onNote,
    ValueChanged<int>? onColor,
    bool hasHighlight = false,
    bool isBookmarked = false,
    String? studyLabel,
    VoidCallback? onRemove}) {
  return VerseActionBar(
    verseLabel: 'John 3:16',
    onCopy: onCopy ?? () {},
    onShare: onShare ?? () {},
    onBookmark: onBookmark ?? () {},
    onHighlight: () {},
    onNote: onNote ?? () {},
    onClear: onClear ?? () {},
    onStudy: onStudy ?? () {},
    onHighlightColor: onColor,
    hasHighlight: hasHighlight,
    isBookmarked: isBookmarked,
    studyLabel: studyLabel,
    onRemoveHighlight: onRemove,
  );
}

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(360, 800),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: ShellBackHandler(path: '/bible', child: Scaffold(body: child)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(ShellBackHandler.resetInterceptors);
  tearDown(ShellBackHandler.resetInterceptors);

  testWidgets('keeps verse actions and all highlight colors available',
      (tester) async {
    final actions = <String>[];
    int? color;
    await mount(
        tester,
        sheet(
          onCopy: () => actions.add('Copy'),
          onShare: () => actions.add('Share'),
          onBookmark: () => actions.add('Bookmark'),
          onNote: () => actions.add('Note'),
          onColor: (value) => color = value,
        ));
    for (final label in ['Copy', 'Share', 'Bookmark', 'Note']) {
      await tester.tap(find.text(label));
    }
    expect(actions, ['Copy', 'Share', 'Bookmark', 'Note']);
    final colors = find.bySemanticsLabel('Highlight color');
    expect(colors, findsNWidgets(HighlightPalette.count));
    await tester.scrollUntilVisible(colors.last, 80);
    await tester.tap(colors.last);
    expect(color, HighlightPalette.count - 1);
    expect(find.text('Open Verse Study'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('Study pushes a page and Back restores the selected verse sheet',
      (tester) async {
    var clearCount = 0;
    var studyCount = 0;
    await mount(
        tester,
        Builder(
            builder: (context) => sheet(
                  onClear: () => clearCount++,
                  onStudy: () {
                    studyCount++;
                    Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                          appBar: AppBar(
                        automaticallyImplyLeading: false,
                        title: const Text('Study (John 3:16)'),
                      )),
                    ));
                  },
                )));
    expect(studyCount, 0);
    await tester.tap(find.byKey(VerseActionBar.studyPromptKey));
    await tester.pumpAndSettle();
    expect(studyCount, 1);
    expect(find.text('Study (John 3:16)'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Open Verse Study'), findsOneWidget);
    expect(clearCount, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(clearCount, greaterThan(0));
  });

  testWidgets('upward swipe does not expand or open Study', (tester) async {
    var studyCount = 0;
    var clearCount = 0;
    await mount(tester,
        sheet(onStudy: () => studyCount++, onClear: () => clearCount++));
    final before = tester.getSize(find.byType(BottomSheet));
    await tester.drag(find.text('John 3:16'), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(studyCount, 0);
    expect(clearCount, 0);
    expect(tester.getSize(find.byType(BottomSheet)), before);
    expect(find.text('Highlight'), findsOneWidget);
  });

  testWidgets('downward swipe dismisses once even when grabbed during exit',
      (tester) async {
    var clearCount = 0;
    await mount(tester, sheet(onClear: () => clearCount++));
    final header = tester.getCenter(find.text('John 3:16'));
    await tester.flingFrom(header, const Offset(0, 100), 1000);
    await tester.pump(const Duration(milliseconds: 16));
    final gesture = await tester.startGesture(header + const Offset(0, 110));
    await gesture.moveBy(const Offset(0, 30));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(clearCount, 1);
  });

  testWidgets('canceled drag returns fully open and remains interactive',
      (tester) async {
    var clearCount = 0;
    await mount(tester, sheet(onClear: () => clearCount++));
    final before = tester.getTopLeft(find.text('John 3:16'));
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('John 3:16')));
    await gesture.moveBy(const Offset(0, 70));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(
        tester.getTopLeft(find.text('John 3:16')).dy, greaterThan(before.dy));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('John 3:16')), before);
    expect(clearCount, 0);
    await tester.tap(find.byKey(VerseActionBar.closeButtonKey));
    await tester.pumpAndSettle();
    expect(clearCount, 1);
  });

  test('formatVerseNumbers groups consecutive numbers and comma-separates non-consecutive', () {
    expect(formatVerseNumbers([]), '');
    expect(formatVerseNumbers([1]), '1');
    expect(formatVerseNumbers([1, 2, 3]), '1-3');
    expect(formatVerseNumbers([1, 5]), '1, 5');
    expect(formatVerseNumbers([1, 2, 4, 5, 6, 9]), '1-2, 4-6, 9');
    expect(formatVerseNumbers([5, 1, 3, 2]), '1-3, 5');
  });

  testWidgets('displays Bookmarked and filled icon when isBookmarked is true', (tester) async {
    await mount(tester, sheet(isBookmarked: true));
    expect(find.text('Bookmarked'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    expect(find.text('Bookmark'), findsNothing);
  });

  testWidgets('renders custom multi-verse studyLabel when provided', (tester) async {
    await mount(tester, sheet(studyLabel: 'Open Verse Study (v. 16)'));
    expect(find.text('Open Verse Study (v. 16)'), findsOneWidget);
  });

  testWidgets('highlight color swatches expose accessible names', (tester) async {
    await mount(tester, sheet());
    expect(HighlightPalette.names.length, 15);
    expect(HighlightPalette.nameFor(0), 'Mustard');
    expect(HighlightPalette.nameFor(14), 'Navy');
    expect(find.byTooltip('Mustard'), findsOneWidget);
  });

  for (final width in [320.0, 600.0, 840.0, 1400.0]) {
    testWidgets('scrolls without overflow at width $width with enlarged text',
        (tester) async {
      var studied = false;
      var removed = false;
      await mount(
          tester,
          sheet(
            hasHighlight: true,
            onRemove: () => removed = true,
            onStudy: () => studied = true,
          ),
          size: Size(width, 640),
          textScale: 2);
      expect(tester.takeException(), isNull);
      final surface = find
          .descendant(
              of: find.byType(BottomSheet), matching: find.byType(Material))
          .first;
      expect(tester.getSize(surface).width, lessThanOrEqualTo(640));
      expect(tester.getCenter(surface).dx, closeTo(width / 2, 1));
      await tester.scrollUntilVisible(find.text('Remove highlight'), 100);
      await tester.tap(find.text('Remove highlight'));
      expect(removed, isTrue);
      await tester.scrollUntilVisible(
          find.byKey(VerseActionBar.studyPromptKey), 100);
      await tester.tap(find.byKey(VerseActionBar.studyPromptKey));
      expect(studied, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('landscape body scrolls while the drag handle stays reachable',
      (tester) async {
    var studied = false;
    await mount(tester, sheet(onStudy: () => studied = true),
        size: const Size(640, 320));
    await tester.scrollUntilVisible(
        find.byKey(VerseActionBar.studyPromptKey), 100);
    await tester.tap(find.byKey(VerseActionBar.studyPromptKey));
    expect(studied, isTrue);
    expect(find.byKey(VerseActionBar.closeButtonKey).hitTestable(),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
