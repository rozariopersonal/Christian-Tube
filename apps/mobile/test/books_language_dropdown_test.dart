import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/models/book_language_meta.dart';
import 'package:mobile/features/books/widgets/books_language_dropdown.dart';
import 'package:mobile/features/books/widgets/books_language_picker_sheet.dart';

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
      String selectedLanguage = 'en',
      ValueChanged<String>? onSelected,
      VoidCallback? onDownloadAll,
    }) {
      return MaterialApp(
        theme: testTheme(),
        home: Scaffold(
          body: Center(
            child: BooksLanguageDropdown(
              selectedLanguage: selectedLanguage,
              availableLanguages: languages,
              bookCounts: counts,
              onLanguageSelected: onSelected ?? (_) {},
              onDownloadAll: onDownloadAll,
            ),
          ),
        ),
      );
    }

    testWidgets('renders active language name and book count badge', (tester) async {
      await tester.pumpWidget(buildSubject(selectedLanguage: 'ta'));
      await tester.pumpAndSettle();

      expect(find.text('Tamil'), findsOneWidget);
      expect(find.text('தமிழ்'), findsOneWidget);
      expect(find.text('45 books'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    });

    testWidgets('tapping dropdown opens BooksLanguagePickerSheet modal', (tester) async {
      await tester.pumpWidget(buildSubject(selectedLanguage: 'en'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BooksLanguageDropdown));
      await tester.pumpAndSettle();

      expect(find.byType(BooksLanguagePickerSheet), findsOneWidget);
      expect(find.text('Library Language'), findsOneWidget);
      expect(find.text('Tamil'), findsOneWidget);
      expect(find.text('தமிழ்'), findsOneWidget);
      expect(find.text('Hindi'), findsOneWidget);
    });

    testWidgets('selecting a language calls callback and dismisses sheet', (tester) async {
      String? selected;
      await tester.pumpWidget(buildSubject(
        selectedLanguage: 'en',
        onSelected: (code) => selected = code,
      ));
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.byType(BooksLanguageDropdown));
      await tester.pumpAndSettle();

      // Select Tamil
      await tester.tap(find.text('Tamil'));
      await tester.pumpAndSettle();

      expect(selected, 'ta');
      expect(find.byType(BooksLanguagePickerSheet), findsNothing);
    });

    testWidgets('search filters language list in modal sheet', (tester) async {
      await tester.pumpWidget(buildSubject(selectedLanguage: 'en'));
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

    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      testWidgets('renders dropdown and modal without overflow at width $width', (tester) async {
        setSurfaceSize(tester, width, 800);
        await tester.pumpWidget(buildSubject(selectedLanguage: 'ta'));
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
