import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/models/book_language_meta.dart';
import 'package:mobile/features/audio/widgets/audio_language_dropdown.dart';
import 'package:mobile/features/audio/widgets/audio_language_picker_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void setSurfaceSize(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

ThemeData testTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      extensions: const [AppTokens.dark],
    );

void main() {
  group('BookLanguageMeta name resolution', () {
    test('resolves by English name or code', () {
      final fromName = BookLanguageMeta.fromCode('Tamil');
      expect(fromName.englishName, 'Tamil');
      expect(fromName.nativeName, 'தமிழ்');
      expect(fromName.code, 'ta');

      final fromTelugu = BookLanguageMeta.fromCode('Telugu');
      expect(fromTelugu.englishName, 'Telugu');
      expect(fromTelugu.nativeName, 'తెలుగు');
      expect(fromTelugu.code, 'te');
    });
  });

  group('AudioLanguageDropdown Widget', () {
    final languages = ['All', 'English', 'Telugu', 'Tamil', 'Malayalam', 'Hindi'];
    final counts = {
      'All': 3035,
      'English': 2544,
      'Telugu': 250,
      'Tamil': 140,
      'Malayalam': 53,
      'Hindi': 28,
    };

    Widget buildSubject({
      Set<String> selectedLanguages = const {'English'},
      ValueChanged<Set<String>>? onSelected,
    }) {
      return MaterialApp(
        theme: testTheme(),
        home: Scaffold(
          body: Center(
            child: AudioLanguageDropdown(
              selectedLanguages: selectedLanguages,
              availableLanguages: languages,
              trackCounts: counts,
              onLanguagesSelected: onSelected ?? (_) {},
            ),
          ),
        ),
      );
    }

    testWidgets('renders single active language name and track count badge', (tester) async {
      await tester.pumpWidget(buildSubject(selectedLanguages: {'Tamil'}));
      await tester.pumpAndSettle();

      expect(find.text('Tamil'), findsOneWidget);
      expect(find.text('தமிழ்'), findsOneWidget);
      expect(find.text('140 tracks'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    });

    testWidgets('renders multiple active languages cleanly', (tester) async {
      await tester.pumpWidget(buildSubject(selectedLanguages: {'English', 'Tamil'}));
      await tester.pumpAndSettle();

      expect(find.text('English, Tamil'), findsOneWidget);
      expect(find.text('2 Languages'), findsOneWidget);
      expect(find.text('2684 tracks'), findsOneWidget);
    });

    testWidgets('tapping dropdown opens AudioLanguagePickerSheet modal', (tester) async {
      await tester.pumpWidget(buildSubject(selectedLanguages: {'English'}));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AudioLanguageDropdown));
      await tester.pumpAndSettle();

      expect(find.byType(AudioLanguagePickerSheet), findsOneWidget);
      expect(find.text('Audio Languages'), findsOneWidget);
      expect(find.text('Tamil'), findsOneWidget);
      expect(find.text('தமிழ்'), findsOneWidget);
      expect(find.text('Telugu'), findsOneWidget);
      expect(find.textContaining('Apply'), findsOneWidget);
    });

    testWidgets('multi-selecting languages and applying calls callback with full set', (tester) async {
      Set<String>? result;
      await tester.pumpWidget(buildSubject(
        selectedLanguages: {'English'},
        onSelected: (set) => result = set,
      ));
      await tester.pumpAndSettle();

      // Open modal
      await tester.tap(find.byType(AudioLanguageDropdown));
      await tester.pumpAndSettle();

      // Toggle Tamil (add Tamil so now English and Tamil are selected)
      await tester.tap(find.text('Tamil'));
      await tester.pumpAndSettle();

      // Tap Apply
      final applyButton = find.widgetWithText(FilledButton, 'Apply (2 Languages • 2684 Tracks)');
      expect(applyButton, findsOneWidget);
      await tester.tap(applyButton);
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.contains('English'), isTrue);
      expect(result!.contains('Tamil'), isTrue);
      expect(find.byType(AudioLanguagePickerSheet), findsNothing);
    });

    testWidgets('search filters language list in modal sheet', (tester) async {
      await tester.pumpWidget(buildSubject(selectedLanguages: {'English'}));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AudioLanguageDropdown));
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'tel');
      await tester.pumpAndSettle();

      expect(find.text('Telugu'), findsOneWidget);
      expect(find.text('Tamil'), findsNothing);
    });

    test('persists multi-selection in SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final toSave = ['English', 'Tamil'];
      await prefs.setStringList('audio_library_languages', toSave);

      final loaded = prefs.getStringList('audio_library_languages');
      expect(loaded, toSave);
      expect(loaded!.toSet().contains('Tamil'), isTrue);
    });

    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      testWidgets('renders dropdown and modal without overflow at width $width', (tester) async {
        setSurfaceSize(tester, width, 800);
        await tester.pumpWidget(buildSubject(selectedLanguages: {'English', 'Tamil', 'Telugu'}));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // Open modal
        await tester.tap(find.byType(AudioLanguageDropdown));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(AudioLanguagePickerSheet), findsOneWidget);

        // Close modal
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
      });
    }
  });
}
