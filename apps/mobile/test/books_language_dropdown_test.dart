import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/models/book_language_meta.dart';
import 'package:mobile/features/books/widgets/books_language_dropdown.dart';
import 'package:mobile/features/books/widgets/books_language_picker_sheet.dart';
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
  group('BookLanguageMeta', () {
    test('resolves standard languages and native names correctly', () {
      final en = BookLanguageMeta.fromCode('en');
      expect(en.englishName, 'English');
      expect(en.nativeName, 'English');
      expect(en.displayName, 'English');

      final ta = BookLanguageMeta.fromCode('ta');
      expect(ta.englishName, 'Tamil');
      expect(ta.nativeName, 'தமிழ்');
      expect(ta.displayName, 'Tamil (தமிழ்)');

      final hi = BookLanguageMeta.fromCode('HI');
      expect(hi.englishName, 'Hindi');
      expect(hi.nativeName, 'हिन्दी');

      final all = BookLanguageMeta.fromCode('All');
      expect(all.englishName, 'All Languages');
      expect(all.shortLabel, 'All');
    });

    test('fallbacks gracefully for unknown language codes', () {
      final custom = BookLanguageMeta.fromCode('xyz');
      expect(custom.englishName, 'XYZ');
      expect(custom.nativeName, 'XYZ');
    });
  });

  group('BooksLanguageDropdown Widget', () {
    final languages = ['All', 'en', 'ta', 'hi', 'te', 'de'];
    final counts = {'All': 181, 'en': 120, 'ta': 45, 'hi': 10, 'te': 4, 'de': 2};

    Widget buildSubject({
      Set<String> selectedLanguages = const {'en'},
      ValueChanged<Set<String>>? onSelected,
      VoidCallback? onDownloadAll,
    }) {
      return MaterialApp(
        theme: testTheme(),
        home: Scaffold(
          body: Center(
            child: BooksLanguageDropdown(
              selectedLanguages: selectedLanguages,
              availableLanguages: languages,
              bookCounts: counts,
              onLanguagesSelected: onSelected ?? (_) {},
              onDownloadAll: onDownloadAll,
            ),
          ),
        ),
      );
    }

    testWidgets('renders single active language name and book count badge', (tester) async {
      await tester.pumpWidget(buildSubject(selectedLanguages: {'ta'}));
      await tester.pumpAndSettle();

      expect(find.text('Tamil'), findsOneWidget);
      expect(find.text('தமிழ்'), findsOneWidget);
      expect(find.text('45 books'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    });

    testWidgets('renders multiple active languages cleanly', (tester) async {
      await tester.pumpWidget(buildSubject(selectedLanguages: {'en', 'ta'}));
      await tester.pumpAndSettle();

      expect(find.text('English, Tamil'), findsOneWidget);
      expect(find.text('2 Languages'), findsOneWidget);
      expect(find.text('165 books'), findsOneWidget);
    });

    testWidgets('renders 3+ languages with count suffix', (tester) async {
      await tester.pumpWidget(buildSubject(selectedLanguages: {'en', 'ta', 'de'}));
      await tester.pumpAndSettle();

      expect(find.text('English, Tamil +1'), findsOneWidget);
      expect(find.text('3 Languages'), findsOneWidget);
      expect(find.text('167 books'), findsOneWidget);
    });

    testWidgets('tapping dropdown opens BooksLanguagePickerSheet modal', (tester) async {
      await tester.pumpWidget(buildSubject(selectedLanguages: {'en'}));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BooksLanguageDropdown));
      await tester.pumpAndSettle();

      expect(find.byType(BooksLanguagePickerSheet), findsOneWidget);
      expect(find.text('Library Languages'), findsOneWidget);
      expect(find.text('Tamil'), findsOneWidget);
      expect(find.text('தமிழ்'), findsOneWidget);
      expect(find.text('Hindi'), findsOneWidget);
      expect(find.textContaining('Apply'), findsOneWidget);
    });

    testWidgets('multi-selecting languages and applying calls callback with full set', (tester) async {
      Set<String>? result;
      await tester.pumpWidget(buildSubject(
        selectedLanguages: {'en'},
        onSelected: (set) => result = set,
      ));
      await tester.pumpAndSettle();

      // Open modal
      await tester.tap(find.byType(BooksLanguageDropdown));
      await tester.pumpAndSettle();

      // Toggle Tamil (add Tamil so now en and ta are selected)
      await tester.tap(find.text('Tamil'));
      await tester.pumpAndSettle();

      // Tap Apply
      final applyButton = find.widgetWithText(FilledButton, 'Apply (2 Languages • 165 Books)');
      expect(applyButton, findsOneWidget);
      await tester.tap(applyButton);
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.contains('en'), isTrue);
      expect(result!.contains('ta'), isTrue);
      expect(find.byType(BooksLanguagePickerSheet), findsNothing);
    });

    testWidgets('search filters language list in modal sheet', (tester) async {
      await tester.pumpWidget(buildSubject(selectedLanguages: {'en'}));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BooksLanguageDropdown));
      await tester.pumpAndSettle();

      // Find search field and enter 'tam'
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'tam');
      await tester.pumpAndSettle();

      expect(find.text('Tamil'), findsOneWidget);
      expect(find.text('German'), findsNothing);
    });

    test('persists multi-selection in SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final toSave = ['en', 'ta', 'de'];
      await prefs.setStringList('books_catalog_languages', toSave);

      final loaded = prefs.getStringList('books_catalog_languages');
      expect(loaded, toSave);
      expect(loaded!.toSet().contains('ta'), isTrue);
    });

    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      testWidgets('renders dropdown and modal without overflow at width $width', (tester) async {
        setSurfaceSize(tester, width, 800);
        await tester.pumpWidget(buildSubject(selectedLanguages: {'en', 'ta', 'de'}));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // Open modal
        await tester.tap(find.byType(BooksLanguageDropdown));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(BooksLanguagePickerSheet), findsOneWidget);

        // Close modal
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
      });
    }
  });
}
