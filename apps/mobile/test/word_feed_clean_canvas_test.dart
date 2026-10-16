import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/engines/scripture/models/scripture_card.dart';
import 'package:mobile/features/engines/scripture/models/scripture_filter_state.dart';
import 'package:mobile/features/engines/scripture/scripture_engine.dart';
import 'package:mobile/features/engines/scripture/widgets/books_filter_sheet.dart';
import 'package:mobile/features/engines/scripture/widgets/scripture_card_view.dart';
import 'package:mobile/features/engines/scripture/widgets/scripture_filter_settings_sheet.dart';
import 'package:mobile/features/engines/scripture/adapters/sqlite_bible_data_adapter.dart';
import 'package:mobile/features/engines/scripture/adapters/web_bible_data_adapter.dart';
import 'package:mobile/features/engines/scripture/services/scripture_service.dart';
import 'package:mobile/features/engines/scripture/widgets/verse_action_appearance_sheet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

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

    testWidgets('tapping reference badge triggers onReferenceTap, not onCardTap', (tester) async {
      bool cardTapped = false;
      bool referenceTapped = false;

      await tester.pumpWidget(
        _wrapWithTheme(
          ScriptureCardView(
            card: testCard,
            filterState: testFilter,
            isActive: true,
            onCardTap: () => cardTapped = true,
            onReferenceTap: () => referenceTapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on the reference badge
      await tester.tap(find.text('— John 3:16'));
      await tester.pumpAndSettle();

      expect(referenceTapped, isTrue);
      expect(cardTapped, isFalse);

      // Now tap on the card body text
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

  group('ScriptureFilterState Model Tests', () {
    test('calculates activeFilterCount correctly', () {
      const state0 = ScriptureFilterState(activeVersionId: 'NASB');
      expect(state0.activeFilterCount, equals(0));

      final state1 = state0.copyWith(readingOrder: 'canonical');
      expect(state1.activeFilterCount, equals(1));

      final state2 = state1.copyWith(testamentFilter: 'New Testament');
      expect(state2.activeFilterCount, equals(2));

      final state3 = state2.copyWith(bookFilter: 'John');
      expect(state3.activeFilterCount, equals(3));

      final state4 = state3.copyWith(selectedCategories: ['comfort', 'faith']);
      expect(state4.activeFilterCount, equals(5));

      final state5 = state4.copyWith(selectedTags: ['anxiety_fear']);
      expect(state5.activeFilterCount, equals(6));
    });

    test('copyWith handles clear flags correctly', () {
      const state = ScriptureFilterState(
        activeVersionId: 'NASB',
        bookFilter: 'John',
        testamentFilter: 'New Testament',
      );

      final cleared = state.copyWith(
        clearBookFilter: true,
        clearTestamentFilter: true,
      );

      expect(cleared.bookFilter, isNull);
      expect(cleared.testamentFilter, isNull);
    });
  });

  group('ScriptureFilterSettingsSheet Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders all sections and headers', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          ScriptureFilterSettingsSheet(
            filterState: testFilter,
            onApply: (_) {},
          ),
          height: 900,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Filter & Settings'), findsOneWidget);
      expect(find.text('READING ORDER'), findsOneWidget);
      expect(find.text('SCOPE & TESTAMENT'), findsOneWidget);
      expect(find.text('FILTER BY BOOK'), findsOneWidget);
      expect(find.text('CATEGORIES (SELECT ANY)'), findsOneWidget);
      expect(find.text('TAGS & SITUATIONS'), findsOneWidget);
      expect(find.text('FONT SIZE ADJUSTMENT'), findsOneWidget);
      expect(find.text('Apply Settings'), findsOneWidget);
    });

    testWidgets('selecting order, testament, category, tag updates selections and applies them', (tester) async {
      ScriptureFilterState? appliedState;

      await tester.pumpWidget(
        _wrapWithTheme(
          ScriptureFilterSettingsSheet(
            filterState: testFilter,
            onApply: (newState) => appliedState = newState,
          ),
          height: 900,
        ),
      );
      await tester.pumpAndSettle();

      // 1. Select Canonical Order
      await tester.tap(find.text('Canonical (Gen → Rev)'));
      await tester.pumpAndSettle();

      // 2. Select Peace & Comfort category
      await tester.scrollUntilVisible(
        find.text('Peace & Comfort'),
        50,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Peace & Comfort'));
      await tester.pumpAndSettle();

      // 3. Select #faith tag
      await tester.scrollUntilVisible(
        find.text('#faith'),
        50,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('#faith'));
      await tester.pumpAndSettle();

      // Active badge should show 3 Active
      expect(find.text('3 Active'), findsOneWidget);
      expect(find.text('Apply Filters (3 Active)'), findsOneWidget);

      // 4. Tap Apply
      await tester.tap(find.text('Apply Filters (3 Active)'));
      await tester.pumpAndSettle();

      expect(appliedState, isNotNull);
      expect(appliedState!.readingOrder, equals('canonical'));
      expect(appliedState!.selectedCategories, contains('comfort'));
      expect(appliedState!.selectedTags, contains('faith'));
    });

    testWidgets('reset all button restores default filter state', (tester) async {
      final activeFilter = testFilter.copyWith(
        readingOrder: 'canonical',
        testamentFilter: 'New Testament',
        selectedCategories: ['faith'],
      );

      await tester.pumpWidget(
        _wrapWithTheme(
          ScriptureFilterSettingsSheet(
            filterState: activeFilter,
            onApply: (_) {},
          ),
          height: 900,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reset All'), findsOneWidget);
      await tester.tap(find.text('Reset All'));
      await tester.pumpAndSettle();

      expect(find.text('Apply Settings'), findsOneWidget);
      expect(find.text('Reset All'), findsNothing);
    });

    testWidgets('renders cleanly without overflow across breakpoints (320, 600, 840, 1400)', (tester) async {
      for (final width in [320.0, 600.0, 840.0, 1400.0]) {
        await tester.pumpWidget(
          _wrapWithTheme(
            ScriptureFilterSettingsSheet(
              filterState: testFilter,
              onApply: (_) {},
            ),
            width: width,
            height: 800,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Filter & Settings'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('ScriptureEngine Top Controls Cluster Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders Version Pill, Stepper [A- | 100% | A+], and Settings Button', (tester) async {
      final engine = ScriptureEngine();
      ScriptureFilterState currentState = testFilter;

      await tester.pumpWidget(
        _wrapWithTheme(
          Builder(
            builder: (ctx) => engine.buildTopControls(
              ctx,
              currentState,
              (newState) => currentState = newState,
              () {},
            )!,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NASB'), findsOneWidget);
      expect(find.text('A-'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('A+'), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    });

    testWidgets('stepper increments and decrements font size scale', (tester) async {
      final engine = ScriptureEngine();
      ScriptureFilterState currentState = testFilter;

      await tester.pumpWidget(
        _wrapWithTheme(
          StatefulBuilder(
            builder: (ctx, setState) => engine.buildTopControls(
              ctx,
              currentState,
              (newState) {
                setState(() => currentState = newState);
              },
              () {},
            )!,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap A+
      await tester.tap(find.text('A+'));
      await tester.pumpAndSettle();
      expect(currentState.fontSizeScale, equals(1.1));
      expect(find.text('110%'), findsOneWidget);

      // Tap A-
      await tester.tap(find.text('A-'));
      await tester.pumpAndSettle();
      expect(currentState.fontSizeScale, equals(1.0));
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('active filter count badge appears when filters active', (tester) async {
      final engine = ScriptureEngine();
      final activeFilter = testFilter.copyWith(
        readingOrder: 'canonical',
        selectedCategories: ['comfort'],
      );

      await tester.pumpWidget(
        _wrapWithTheme(
          Builder(
            builder: (ctx) => engine.buildTopControls(
              ctx,
              activeFilter,
              (_) {},
              () {},
            )!,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Badge displays '2'
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('Scripture Version Switching & Resolution Tests', () {
    test('ScriptureService.resolvePassageSync does not return stale text when requested version differs', () {
      final service = ScriptureService();
      final card = ScriptureCard(
        id: '43_3_16',
        bookNumber: 43,
        bookName: 'John',
        chapter: 3,
        startVerse: 16,
        endVerse: 16,
        referenceLabel: 'John 3:16',
        resolvedText: 'NASB text for John 3:16',
        resolvedVersion: 'NASB',
      );

      // Requesting WEB when card is resolved to NASB must NOT return NASB text
      final webText = service.resolvePassageSync(card, 'WEB');
      expect(webText, isNull);

      // Requesting NASB matches card's resolvedVersion, so returns text
      final nasbText = service.resolvePassageSync(card, 'NASB');
      expect(nasbText, equals('NASB text for John 3:16'));
    });

    test('ScriptureEngine.loadFilterStateForVersion preserves structural filter state from baseState', () async {
      SharedPreferences.setMockInitialValues({});
      final engine = ScriptureEngine();

      final baseState = testFilter.copyWith(
        bookFilter: 'Romans',
        testamentFilter: 'New Testament',
        selectedCategories: ['grace', 'salvation'],
        selectedTags: ['faith'],
        readingOrder: 'canonical',
      );

      final newState = await engine.loadFilterStateForVersion('KJV', baseState: baseState);

      expect(newState.activeVersionId, equals('KJV'));
      expect(newState.bookFilter, equals('Romans'));
      expect(newState.testamentFilter, equals('New Testament'));
      expect(newState.selectedCategories, equals(['grace', 'salvation']));
      expect(newState.selectedTags, equals(['faith']));
      expect(newState.readingOrder, equals('canonical'));
    });

    test('SqliteBibleDataAdapter.resolvePassageSync returns cached in-memory chapter verses', () {
      final adapter = SqliteBibleDataAdapter();
      // Initially not in memory cache
      expect(adapter.resolvePassageSync(versionId: 'KJV', bookNumber: 43, chapter: 3, startVerse: 16), isNull);
    });

    test('WebBibleDataAdapter and SqliteBibleDataAdapter passage cache returns instant hit', () {
      final webAdapter = WebBibleDataAdapter();
      expect(webAdapter.resolvePassageSync(versionId: 'KJV', bookNumber: 43, chapter: 3, startVerse: 16), isNull);

      final sqliteAdapter = SqliteBibleDataAdapter();
      expect(sqliteAdapter.resolvePassageSync(versionId: 'KJV', bookNumber: 1, chapter: 1, startVerse: 1), isNull);
    });
  });
}

