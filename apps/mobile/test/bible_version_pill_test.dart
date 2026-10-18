import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/shared/ui/bible_version_native_names.dart';
import 'package:mobile/shared/ui/bible_version_pill.dart';
import 'package:shared_preferences/shared_preferences.dart';

void setSurfaceSize(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

ThemeData testTheme({Brightness brightness = Brightness.light}) => ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: brightness,
      ),
      extensions: [
        brightness == Brightness.light ? AppTokens.light : AppTokens.dark,
      ],
    );

Widget _embed(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: testTheme(brightness: brightness),
    home: Scaffold(
      body: Center(
        child: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('BibleVersionNativeNames', () {
    test('resolves native scripts for key translations accurately', () {
      expect(BibleVersionNativeNames.getNativeScript('TAOBVSI'), 'தமிழ்');
      expect(BibleVersionNativeNames.getNativeScript('BSB'), 'English');
      expect(BibleVersionNativeNames.getNativeScript('KJV'), 'English');
      expect(BibleVersionNativeNames.getNativeScript('HIN_IRV'), 'हिन्दी');
      expect(BibleVersionNativeNames.getNativeScript('TEL_IRV'), 'తెలుగు');
      expect(BibleVersionNativeNames.getNativeScript('MAL_IRV'), 'മലയാളം');
      expect(BibleVersionNativeNames.getNativeScript('KAN_IRV'), 'ಕನ್ನಡ');
      expect(BibleVersionNativeNames.getNativeScript('ELBERFELDER1905'), 'Deutsch');
      expect(BibleVersionNativeNames.getNativeScript('JAPKOUGO'), '日本語');
    });

    test('returns empty string for unknown codes without crashing', () {
      expect(BibleVersionNativeNames.getNativeScript('UNKNOWN_XYZ'), '');
      expect(BibleVersionNativeNames.getNativeScript(''), '');
    });
  });

  group('BibleVersionPill visual and responsive tests', () {
    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      testWidgets('renders cleanly without overflow at ${width}px', (tester) async {
        setSurfaceSize(tester, width, 600);
        await tester.pumpWidget(_embed(
          const BibleVersionPill(
            activeVersionId: 'TAOBVSI',
          ),
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'overflow at $width');
        expect(find.text('TAOBVSI'), findsOneWidget);
        expect(find.text('தமிழ்'), findsOneWidget);
        expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
      });
    }

    testWidgets('respects customization flags (no leading icon, no chevron, no native script)',
        (tester) async {
      await tester.pumpWidget(_embed(
        const BibleVersionPill(
          activeVersionId: 'BSB',
          showLeadingIcon: false,
          showDropdownChevron: false,
          showNativeScript: false,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('BSB'), findsOneWidget);
      expect(find.text('English'), findsNothing);
      expect(find.byIcon(Icons.menu_book_rounded), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    });

    testWidgets('supports dark and frosted modes without exceptions', (tester) async {
      await tester.pumpWidget(_embed(
        const BibleVersionPill(
          activeVersionId: 'HIN_IRV',
          isFrosted: true,
        ),
        brightness: Brightness.dark,
      ));
      await tester.pumpAndSettle();

      expect(find.text('HIN_IRV'), findsOneWidget);
      expect(find.text('हिन्दी'), findsOneWidget);
    });

    testWidgets('tapping opens the bottom sheet picker modal', (tester) async {
      setSurfaceSize(tester, 400, 800);
      String? selected;
      await tester.pumpWidget(_embed(
        BibleVersionPill(
          activeVersionId: 'TAOBVSI',
          installedIdsOverride: const {'TAOBVSI', 'NASB'},
          onSelectVersion: (v) => selected = v,
        ),
      ));
      await tester.pumpAndSettle();

      // Tap the pill
      await tester.tap(find.byType(BibleVersionPill));
      await tester.pumpAndSettle();

      // The sheet should appear with "Bible Translation" title
      expect(find.text('Bible Translation'), findsOneWidget);

      // Tap on NASB tile ('New American Standard Bible (1995)')
      final nasbFinder = find.widgetWithText(InkWell, 'New American Standard Bible (1995)');
      expect(nasbFinder, findsOneWidget);
      await tester.tap(nasbFinder);
      await tester.pumpAndSettle();

      expect(selected, 'NASB');
    });
  });
}
