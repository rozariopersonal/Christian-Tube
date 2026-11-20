import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/layout/shell_back_handler.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/core/theme/highlight_palette.dart';
import 'package:mobile/features/bible/models/bible_verse.dart';
import 'package:mobile/features/bible/widgets/verse_action_bar.dart';
import 'package:mobile/shared/services/highlight_usage_service.dart';
import 'package:mobile/shared/ui/floating_selection_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget bar({
  VoidCallback? onClear,
  VoidCallback? onStudy,
  VoidCallback? onCopy,
  VoidCallback? onShare,
  VoidCallback? onBookmark,
  VoidCallback? onNote,
  ValueChanged<int>? onColor,
  VoidCallback? onRemove,
  int selectedCount = 1,
  int? currentColorIndex,
  bool hasHighlight = false,
  bool isBookmarked = false,
}) {
  return VerseActionBar(
    selectedCount: selectedCount,
    onCopy: onCopy ?? () {},
    onShare: onShare ?? () {},
    onBookmark: onBookmark ?? () {},
    onNote: onNote ?? () {},
    onClear: onClear ?? () {},
    onStudy: onStudy ?? () {},
    onHighlightColor: onColor ?? (_) {},
    onRemoveHighlight: onRemove,
    currentColorIndex: currentColorIndex,
    hasHighlight: hasHighlight,
    isBookmarked: isBookmarked,
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
    theme: ThemeData(extensions: const [AppTokens.light]),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: ShellBackHandler(
      path: '/bible',
      child: Scaffold(
        body: Align(alignment: Alignment.bottomCenter, child: child),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    ShellBackHandler.resetInterceptors();
    SharedPreferences.setMockInitialValues({});
    HighlightUsageService.instance.resetForTest();
  });
  tearDown(ShellBackHandler.resetInterceptors);

  testWidgets('shows default swatches then bookmark, share and study icons',
      (tester) async {
    final calls = <String>[];
    int? color;
    await mount(
      tester,
      bar(
        onBookmark: () => calls.add('bookmark'),
        onShare: () => calls.add('share'),
        onStudy: () => calls.add('study'),
        onColor: (c) => color = c,
      ),
    );
    for (final i in HighlightUsageService.defaultOrder) {
      expect(find.byKey(FloatingSelectionBar.swatchKey(i)), findsOneWidget);
    }
    await tester.tap(find.byKey(FloatingSelectionBar.swatchKey(2)));
    await tester.tap(find.byKey(VerseActionBar.bookmarkKey));
    await tester.tap(find.byKey(VerseActionBar.shareKey));
    await tester.tap(find.byKey(VerseActionBar.studyKey));
    expect(color, 2);
    expect(calls, ['bookmark', 'share', 'study']);
  });

  testWidgets('is a single row: swatches, actions share one vertical band',
      (tester) async {
    await mount(tester, bar());
    final swatchY =
        tester.getCenter(find.byKey(FloatingSelectionBar.swatchKey(0))).dy;
    for (final k in [
      FloatingSelectionBar.expandKey,
      VerseActionBar.bookmarkKey,
      VerseActionBar.shareKey,
      VerseActionBar.studyKey,
      FloatingSelectionBar.overflowKey,
    ]) {
      expect(tester.getCenter(find.byKey(k)).dy, closeTo(swatchY, 1));
    }
    expect(find.byKey(FloatingSelectionBar.panelKey), findsNothing);
  });

  testWidgets('chevron expands the full palette and picking collapses it',
      (tester) async {
    int? color;
    await mount(tester, bar(onColor: (c) => color = c));
    await tester.tap(find.byKey(FloatingSelectionBar.expandKey));
    await tester.pumpAndSettle();
    expect(find.byKey(FloatingSelectionBar.panelKey), findsOneWidget);
    for (var i = 0; i < HighlightPalette.count; i++) {
      expect(find.byKey(FloatingSelectionBar.panelSwatchKey(i)),
          findsOneWidget);
    }
    await tester.tap(find.byKey(FloatingSelectionBar.panelSwatchKey(13)));
    await tester.pumpAndSettle();
    expect(color, 13);
    expect(find.byKey(FloatingSelectionBar.panelKey), findsNothing);
  });

  testWidgets('Back collapses the palette first, then clears the selection',
      (tester) async {
    var cleared = 0;
    await mount(tester, bar(onClear: () => cleared++));
    await tester.tap(find.byKey(FloatingSelectionBar.expandKey));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(FloatingSelectionBar.panelKey), findsNothing);
    expect(cleared, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(cleared, 1);
  });

  testWidgets('tapping the active swatch removes the highlight',
      (tester) async {
    var removed = 0;
    int? color;
    await mount(
      tester,
      bar(
        currentColorIndex: 0,
        hasHighlight: true,
        onRemove: () => removed++,
        onColor: (c) => color = c,
      ),
    );
    await tester.tap(find.byKey(FloatingSelectionBar.swatchKey(0)));
    expect(removed, 1);
    expect(color, isNull);
  });

  testWidgets('overflow menu exposes Copy and Note', (tester) async {
    final calls = <String>[];
    await mount(
      tester,
      bar(onCopy: () => calls.add('copy'), onNote: () => calls.add('note')),
    );
    await tester.tap(find.byKey(FloatingSelectionBar.overflowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FloatingSelectionBar.overflowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Note'));
    await tester.pumpAndSettle();
    expect(calls, ['copy', 'note']);
  });

  testWidgets('bookmarked state uses the filled icon', (tester) async {
    await mount(tester, bar(isBookmarked: true));
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
  });

  testWidgets('most-used colours replace defaults after use', (tester) async {
    final usage = HighlightUsageService.instance;
    await usage.load();
    await usage.record(9);
    await usage.record(9);
    await usage.record(12);
    expect(usage.topColors(), [9, 12, 0]);
    await mount(tester, bar());
    expect(find.byKey(FloatingSelectionBar.swatchKey(9)), findsOneWidget);
    expect(find.byKey(FloatingSelectionBar.swatchKey(12)), findsOneWidget);
    expect(find.byKey(FloatingSelectionBar.swatchKey(0)), findsOneWidget);
    expect(find.byKey(FloatingSelectionBar.swatchKey(4)), findsNothing);
  });

  for (final width in [320.0, 600.0, 840.0, 1400.0]) {
    testWidgets('single line without overflow at $width with 2x text',
        (tester) async {
      await mount(
        tester,
        bar(selectedCount: 12, hasHighlight: true, onRemove: () {}),
        size: Size(width, 640),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      final box = tester.getSize(find.byType(FloatingSelectionBar));
      expect(box.width, lessThanOrEqualTo(FloatingSelectionBar.maxBarWidth));
      expect(box.width, lessThanOrEqualTo(width));
      expect(box.height, lessThan(60));
      await tester.tap(find.byKey(FloatingSelectionBar.expandKey));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  test('usage service ties break by recency and persist', () async {
    final usage = HighlightUsageService.instance;
    await usage.load();
    await usage.record(5);
    await usage.record(7);
    expect(usage.topColors(2), [7, 5]);
    usage.resetForTest();
    await usage.load();
    expect(usage.topColors(2), [7, 5]);
  });

  test('formatVerseNumbers groups consecutive numbers', () {
    expect(formatVerseNumbers([]), '');
    expect(formatVerseNumbers([1, 2, 3]), '1-3');
    expect(formatVerseNumbers([1, 5]), '1, 5');
    expect(formatVerseNumbers([5, 1, 3, 2]), '1-3, 5');
  });
}
