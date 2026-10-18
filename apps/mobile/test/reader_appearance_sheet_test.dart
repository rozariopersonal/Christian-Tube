import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/shared/services/reader_appearance.dart';
import 'package:mobile/shared/ui/reader_appearance_sheet.dart';
import 'package:mobile/shared/ui/widgets/font_browser_view.dart';
import 'package:mobile/shared/ui/widgets/font_specimen_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget wrapWithSheetTest(Widget child) {
  return MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [AppTokens.dark]),
    home: child,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('showReaderAppearanceSheet on compact screen hugs content and does not open full screen', (tester) async {
    tester.view.physicalSize = const Size(400 * 2, 850 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final appearance = ReaderAppearance();

    await tester.pumpWidget(
      wrapWithSheetTest(
        Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showReaderAppearanceSheet(context, appearance),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    // Tap to open sheet
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Verify all Level 1 controls appear and are fully visible
    expect(find.text('Reading Appearance'), findsOneWidget);
    expect(find.text('Font Family'), findsOneWidget);
    expect(find.text('Font Size'), findsOneWidget);
    expect(find.text('Line Spacing'), findsOneWidget);
    expect(find.text('Tight'), findsOneWidget);
    expect(find.text('Standard'), findsNWidgets(2)); // Header label + button option
    expect(find.text('Relaxed'), findsOneWidget);

    // Measure the bottom sheet height
    final sheetFinder = find.byType(BottomSheet);
    expect(sheetFinder, findsOneWidget);
    final sheetSize = tester.getSize(sheetFinder);

    // Viewport height is 850. The sheet MUST NOT be full screen!
    // It should hug content at around ~350-520px.
    expect(sheetSize.height, lessThan(540));
    expect(sheetSize.height, greaterThan(250));

    // Tap 'Font Family' to navigate to Level 2 (Typography browser)
    await tester.tap(find.text('Font Family'));
    await tester.pumpAndSettle();

    // Verify Level 2 header and font cards are rendered
    expect(find.text('Typography'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byType(FontBrowserView), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);

    // Tap a font card and verify immediate selection update
    final fontCards = find.byType(FontSpecimenCard);
    expect(fontCards, findsWidgets);
    await tester.tap(fontCards.first);
    await tester.pump();

    // Level 2 should expand smoothly, but still stay within bounds (less than viewport height)
    final level2SheetSize = tester.getSize(sheetFinder);
    expect(level2SheetSize.height, greaterThan(sheetSize.height));
    expect(level2SheetSize.height, lessThan(850));

    // Tap 'Settings' back button to return to Level 1
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Reading Appearance'), findsOneWidget);
    expect(find.text('Font Family'), findsOneWidget);
    expect(find.text('Line Spacing'), findsOneWidget);
  });

  testWidgets('showReaderAppearanceSheet on compact screen with narrow width renders without overflow', (tester) async {
    tester.view.physicalSize = const Size(320 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final appearance = ReaderAppearance();

    await tester.pumpWidget(
      wrapWithSheetTest(
        Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showReaderAppearanceSheet(context, appearance),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Reading Appearance'), findsOneWidget);
    expect(find.text('Line Spacing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('showReaderAppearanceSheet on medium/expanded renders as centered dialog', (tester) async {
    tester.view.physicalSize = const Size(900 * 2, 700 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final appearance = ReaderAppearance();

    await tester.pumpWidget(
      wrapWithSheetTest(
        Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showReaderAppearanceSheet(context, appearance),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // On expanded width >= 840, it must render as a Dialog
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    final constrainedFinder = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(ConstrainedBox),
    ).first;
    final dialogContentSize = tester.getSize(constrainedFinder);
    expect(dialogContentSize.width, lessThanOrEqualTo(520));
    expect(find.text('Line Spacing'), findsOneWidget);
  });
}
