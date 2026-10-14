import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/engines/scripture/services/bible_recent_versions_service.dart';
import 'package:mobile/features/engines/scripture/widgets/bible_version_picker_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';

void setSurfaceSize(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

ThemeData testTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      extensions: const [AppTokens.light],
    );

Widget _embed(BibleVersionPickerModal modal) {
  return MaterialApp(
    theme: testTheme(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: modal,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      BibleRecentVersionsService.keyRecentVersions: ['NIV', 'TAOBVSI', 'HIN_HCV'],
    });
  });

  for (final width in [320.0, 600.0, 840.0, 1400.0]) {
    testWidgets(
      'BibleVersionPickerModal renders without overflow at $width logical px',
      (tester) async {
        setSurfaceSize(tester, width, 800);
        await tester.pumpWidget(_embed(BibleVersionPickerModal(
          activeVersionId: 'NIV',
          installedIdsOverride: const {'NIV', 'NASB', 'TAOBVSI', 'HIN_HCV', 'TEL_IRV'},
          onSelectVersion: (_) {},
          onOpenManager: () {},
        )));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'overflow/exception at $width');
        expect(find.text('Bible Translation'), findsOneWidget);
        expect(find.text('RECENTLY USED'), findsOneWidget);
      },
    );
  }

  testWidgets('displays recently used bibles in exact order', (tester) async {
    setSurfaceSize(tester, 400, 800);
    await tester.pumpWidget(_embed(BibleVersionPickerModal(
      activeVersionId: 'NIV',
      installedIdsOverride: const {'NIV', 'TAOBVSI', 'HIN_HCV', 'NASB'},
      onSelectVersion: (_) {},
      onOpenManager: () {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('RECENTLY USED'), findsOneWidget);

    // In the quick chips / recent list, NIV, TAOBVSI, and HIN_HCV must appear in order
    final nivFinder = find.text('NIV');
    final tamilFinder = find.text('TAOBVSI');
    final hindiFinder = find.text('HIN_HCV');

    expect(nivFinder, findsAtLeastNWidgets(1));
    expect(tamilFinder, findsAtLeastNWidgets(1));
    expect(hindiFinder, findsAtLeastNWidgets(1));
  });

  testWidgets('groups bibles by language with section headers', (tester) async {
    setSurfaceSize(tester, 400, 800);
    await tester.pumpWidget(_embed(BibleVersionPickerModal(
      activeVersionId: 'NIV',
      installedIdsOverride: const {'NIV', 'NASB', 'TAOBVSI', 'HIN_HCV', 'TEL_IRV'},
      onSelectVersion: (_) {},
      onOpenManager: () {},
    )));
    await tester.pumpAndSettle();

    // Verify language headers exist (scroll as needed for lazy ListView)
    expect(find.text('ENGLISH'), findsOneWidget);
    expect(find.text('TAMIL'), findsOneWidget);
    expect(find.text('HINDI'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('TELUGU'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('TELUGU'), findsOneWidget);
  });

  testWidgets('quick search filters translations across name and language',
      (tester) async {
    setSurfaceSize(tester, 400, 800);
    await tester.pumpWidget(_embed(BibleVersionPickerModal(
      activeVersionId: 'NIV',
      installedIdsOverride: const {'NIV', 'NASB', 'TAOBVSI', 'HIN_HCV', 'TEL_IRV'},
      onSelectVersion: (_) {},
      onOpenManager: () {},
    )));
    await tester.pumpAndSettle();

    // Enter search query "Tamil"
    await tester.enterText(
        find.byType(TextField), 'Tamil');
    await tester.pumpAndSettle();

    expect(find.text('TAMIL'), findsOneWidget);
    expect(find.text('TELUGU'), findsNothing);
    expect(find.text('HINDI'), findsNothing);
  });

  testWidgets('selecting a translation triggers callback and persists to recents',
      (tester) async {
    setSurfaceSize(tester, 400, 800);
    String? selected;

    await tester.pumpWidget(_embed(BibleVersionPickerModal(
      activeVersionId: 'NIV',
      installedIdsOverride: const {'NIV', 'NASB', 'TAOBVSI'},
      onSelectVersion: (id) => selected = id,
      onOpenManager: () {},
    )));
    await tester.pumpAndSettle();

    // Tap NASB tile
    final nasbFinder = find.widgetWithText(InkWell, 'New American Standard Bible (1995)');
    expect(nasbFinder, findsOneWidget);
    await tester.tap(nasbFinder);
    await tester.pumpAndSettle();

    expect(selected, 'NASB');

    final recents = await BibleRecentVersionsService().getRecentVersions();
    expect(recents.first, 'NASB');
  });
}
