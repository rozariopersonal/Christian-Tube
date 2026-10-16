import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/engines/scripture/models/scripture_card.dart';
import 'package:mobile/features/engines/scripture/models/scripture_filter_state.dart';
import 'package:mobile/features/engines/scripture/widgets/books_filter_sheet.dart';
import 'package:mobile/features/engines/scripture/widgets/scripture_card_view.dart';
import 'package:mobile/features/engines/scripture/widgets/verse_action_appearance_sheet.dart';

ThemeData testTheme({bool isDark = true}) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: isDark ? Brightness.dark : Brightness.light,
      ),
      extensions: [isDark ? AppTokens.dark : AppTokens.light],
    );

Widget _wrapWithTheme(Widget child, {bool isDark = true, double width = 360, double height = 740}) {
  return MaterialApp(
    theme: testTheme(isDark: false),
    darkTheme: testTheme(isDark: true),
    themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, height),
        padding: const EdgeInsets.only(top: 24, bottom: 16),
      ),
      child: Scaffold(
        body: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testCard = ScriptureCard(
    id: '43_3_16',
    bookNumber: 43,
    bookName: 'John',
    chapter: 3,
    startVerse: 16,
    endVerse: 16,
    referenceLabel: 'John 3:16',
    resolvedText: 'For God so loved the world that He gave His only begotten Son.',
    resolvedVersion: 'NASB',
  );

  const testFilter = ScriptureFilterState(
    activeVersionId: 'NASB',
    fontSizeScale: 1.0,
    activeFontFamily: 'sans-serif',
    textColorHex: '#FFFFFF',
    isBold: false,
    isItalic: false,
    textAlign: 'center',
    backgroundPreset: 'pure_dark',
  );

  group('BooksFilterSheet Widget Tests', () {
    testWidgets('renders books list, search field, and segment chips', (tester) async {
      String? selectedBook;

      await tester.pumpWidget(
        _wrapWithTheme(
          BooksFilterSheet(
            activeBook: 'Genesis',
            activeTestament: null,
            onSelectBook: (b) => selectedBook = b,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Filter by Book'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('All (66)'), findsOneWidget);
      expect(find.text('Old Testament (39)'), findsOneWidget);
      expect(find.text('New Testament (27)'), findsOneWidget);
      expect(find.text('Genesis'), findsOneWidget);

      // Tap Reset to All
      expect(find.text('Reset to All'), findsOneWidget);
      await tester.tap(find.text('Reset to All'));
      await tester.pumpAndSettle();
      expect(selectedBook, isNull);
    });

    testWidgets('search filters list of books in real-time', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          BooksFilterSheet(
            activeBook: null,
            activeTestament: null,
            onSelectBook: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'John');
      await tester.pumpAndSettle();

      expect(
          find.widgetWithText(InkWell, 'John'),
          findsOneWidget);
      expect(find.text('1 John'), findsOneWidget);
      expect(find.text('Genesis'), findsNothing);
    });

    testWidgets('segment tabs filter books by testament', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          BooksFilterSheet(
            activeBook: null,
            activeTestament: null,
            onSelectBook: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap New Testament segment
      await tester.tap(find.text('New Testament (27)'));
      await tester.pumpAndSettle();

      expect(find.text('Matthew'), findsOneWidget);
      expect(find.text('Genesis'), findsNothing);
    });
  });

  group('VerseActionAppearanceSheet Widget Tests', () {
    testWidgets('renders quick action buttons and appearance controls', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          VerseActionAppearanceSheet(
            card: testCard,
            filterState: testFilter,
            onFilterChanged: (_) {},
            onRefreshCard: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('John 3:16'), findsOneWidget);
      expect(find.text('Share Story'), findsOneWidget);
      expect(find.text('Copy Text'), findsOneWidget);
      expect(find.text('Bookmark'), findsOneWidget);
      expect(find.text('Compare'), findsOneWidget);
      expect(find.text('Read Chapter'), findsOneWidget);

      // Section titles
      expect(find.text('BACKGROUND THEME'), findsOneWidget);
      expect(find.textContaining('FONT FAMILY'), findsOneWidget);
      expect(find.text('TEXT COLOR'), findsOneWidget);
      expect(find.text('FORMAT & ALIGNMENT'), findsOneWidget);
    });
  });

  group('ScriptureCardView Widget Tests', () {
    testWidgets('renders verse text and pinned bottom reference badge', (tester) async {
      bool cardTapped = false;

      await tester.pumpWidget(
        _wrapWithTheme(
          ScriptureCardView(
            card: testCard,
            filterState: testFilter,
            isActive: true,
            onCardTap: () => cardTapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('loved the world'), findsOneWidget);
      expect(find.text('— John 3:16'), findsOneWidget);
      expect(find.text('NASB'), findsOneWidget);

      // Tap anywhere on the verse text
      await tester.tap(find.textContaining('loved the world'));
      await tester.pumpAndSettle();
      expect(cardTapped, isTrue);
    });

    testWidgets('renders cleanly across breakpoints (320, 600, 840, 1400) without overflow', (tester) async {
      for (final width in [320.0, 600.0, 840.0, 1400.0]) {
        await tester.pumpWidget(
          _wrapWithTheme(
            ScriptureCardView(
              card: testCard,
              filterState: testFilter,
              isActive: true,
            ),
            width: width,
            height: 800,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('loved the world'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('edge-margin swipe zones trigger onEdgePageShift', (tester) async {
      int? shiftDirection;

      await tester.pumpWidget(
        _wrapWithTheme(
          ScriptureCardView(
            card: testCard,
            filterState: testFilter,
            isActive: true,
            onEdgePageShift: (dir) => shiftDirection = dir,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fling vertically in left 44dp margin (swipe up = next page)
      await tester.flingFrom(const Offset(20, 400), const Offset(0, -300), 1000);
      await tester.pumpAndSettle();

      expect(shiftDirection, equals(1));
    });
  });
}
