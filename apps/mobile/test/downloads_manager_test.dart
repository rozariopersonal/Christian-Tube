import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/downloads/screens/downloads_manager_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DownloadsManagerScreen Adaptive UI & Tabs (AGENTS.md)', () {
    Widget buildFrame(Widget child, {Size size = const Size(360, 640)}) {
      return MaterialApp(
        theme: ThemeData(
          extensions: const [AppTokens.dark],
        ),
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: child,
        ),
      );
    }

    testWidgets('DownloadsManagerScreen renders without overflow at 320, 600, 840, and 1400px',
        (tester) async {
      for (final width in [320.0, 600.0, 840.0, 1400.0]) {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          buildFrame(
            const DownloadsManagerScreen(),
            size: Size(width, 800),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Offline Library & Downloads'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Overview'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Bibles & Study Tools'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Dictionaries'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Books & Commentaries'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Audio Sermons'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Songs & Hymns'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Reader Fonts'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('Can switch across all 7 tabs smoothly',
        (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildFrame(
          const DownloadsManagerScreen(),
          size: const Size(800, 800),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Bibles & Study Tools
      await tester.tap(find.widgetWithText(Tab, 'Bibles & Study Tools'));
      await tester.pumpAndSettle();
      expect(find.text('STUDY DATASETS'), findsOneWidget);
      expect(find.text('Treasury of Scripture Knowledge Cross-References'), findsOneWidget);
      expect(find.text('New American Standard Bible (1995)'), findsOneWidget);

      // Search for Tamil to verify protected default translation badge
      await tester.enterText(find.byType(TextField).first, 'Tamil');
      await tester.pumpAndSettle();
      expect(find.text('PROTECTED'), findsOneWidget);

      // Switch to Dictionaries
      await tester.tap(find.widgetWithText(Tab, 'Dictionaries'));
      await tester.pumpAndSettle();
      expect(find.text('English Dictionary'), findsOneWidget);

      // Switch to Books & Commentaries
      await tester.tap(find.widgetWithText(Tab, 'Books & Commentaries'));
      await tester.pumpAndSettle();
      expect(find.text('Complete Books & Commentaries'), findsOneWidget);

      // Switch to Audio Sermons
      await tester.tap(find.widgetWithText(Tab, 'Audio Sermons'));
      await tester.pumpAndSettle();
      expect(find.text('Offline Audio Sermons'), findsOneWidget);

      // Switch to Songs & Hymns
      await tester.tap(find.widgetWithText(Tab, 'Songs & Hymns'));
      await tester.pumpAndSettle();
      expect(find.text('Offline Songbook & Hymns'), findsOneWidget);

      // Switch to Reader Fonts
      await tester.tap(find.widgetWithText(Tab, 'Reader Fonts'));
      await tester.pumpAndSettle();
      expect(find.text('Reader Fonts & Typography'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Downloading items do not render double loaders',
        (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildFrame(
          const DownloadsManagerScreen(),
          size: const Size(800, 800),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(Tab, 'Bibles & Study Tools'));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);

      // Drain internal sqflite connection lock timer
      await tester.pump(const Duration(seconds: 11));
    });
  });
}
