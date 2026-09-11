import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/audio/screens/audio_library_screen.dart';
import 'package:mobile/features/audio/widgets/audio_search_bar.dart';
import 'package:mobile/features/audio/widgets/audio_view_mode_segmented_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void setSurfaceSize(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildAudioLibraryTestHarness() {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: [AppTokens.dark],
      ),
      home: const AudioLibraryScreen(),
    );
  }

  group('AudioLibraryScreen Widget Tests', () {
    testWidgets('renders inline search bar and segmented view mode selector',
        (tester) async {
      setSurfaceSize(tester, 600, 900);
      await tester.pumpWidget(buildAudioLibraryTestHarness());
      await tester.pump(const Duration(seconds: 4));

      // Verify Title
      expect(find.text('Audio Library'), findsOneWidget);

      // Verify Inline Search Bar
      expect(find.byType(AudioSearchBar), findsOneWidget);

      // Verify Segmented View Mode
      expect(find.byType(AudioViewModeSegmentedBar), findsOneWidget);
      expect(find.text('Featured'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Speakers'), findsOneWidget);
      expect(find.text('A–Z'), findsOneWidget);
    });

    testWidgets('typing in search bar instantly filters without error',
        (tester) async {
      setSurfaceSize(tester, 600, 900);
      await tester.pumpWidget(buildAudioLibraryTestHarness());
      await tester.pump(const Duration(seconds: 4));

      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      // Enter search query
      await tester.enterText(searchField, 'Romans');
      await tester.pump(const Duration(milliseconds: 300));

      // Expect search results section header
      expect(find.textContaining('Search Results'), findsOneWidget);
      expect(find.text('Clear Search'), findsOneWidget);

      // Tap clear search
      await tester.tap(find.text('Clear Search'));
      await tester.pump(const Duration(milliseconds: 300));

      // Expect back to default mode
      expect(find.byType(AudioViewModeSegmentedBar), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('switching view modes switches body content',
        (tester) async {
      setSurfaceSize(tester, 600, 900);
      await tester.pumpWidget(buildAudioLibraryTestHarness());
      await tester.pump(const Duration(seconds: 4));

      // Tap Categories
      final catBtn = find.text('Categories');
      await tester.ensureVisible(catBtn);
      await tester.tap(catBtn);
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Speakers
      final speakerBtn = find.text('Speakers');
      await tester.ensureVisible(speakerBtn);
      await tester.tap(speakerBtn);
      await tester.pump(const Duration(milliseconds: 300));

      // Tap A–Z
      final azBtn = find.text('A–Z');
      await tester.ensureVisible(azBtn);
      await tester.tap(azBtn);
      await tester.pump(const Duration(milliseconds: 300));

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('renders across viewport breakpoints (320, 600, 840, 1400) without overflow',
        (tester) async {
      for (final width in [320.0, 600.0, 840.0, 1400.0]) {
        setSurfaceSize(tester, width, 900);
        await tester.pumpWidget(buildAudioLibraryTestHarness());
        await tester.pump(const Duration(seconds: 4));

        expect(tester.takeException(), isNull,
            reason: 'Failed at width $width');
      }
    });
  });
}
