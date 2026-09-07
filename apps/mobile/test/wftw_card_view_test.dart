import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/micro_feed/engines/wftw/models/wftw_card.dart';
import 'package:mobile/features/micro_feed/engines/wftw/models/wftw_filter_state.dart';
import 'package:mobile/features/micro_feed/engines/wftw/widgets/wftw_card_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void setSurfaceSize(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

ThemeData testTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      extensions: const [AppTokens.light],
    );

const _gradientPreset = 'gradient_royal_midnight';

WftwCard _verseCard() => WftwCard.fromMap({
      'article_id': '2024_10_26',
      'date_ms': DateTime.utc(2024, 10, 26).millisecondsSinceEpoch,
      'year': 2024,
      'book_number': 40,
      'chapter': 5,
      'start_verse': 3,
      'end_verse': 4,
      'article_title': 'Faith in Trials',
      'fallback_excerpt': 'A verse-backed fallback excerpt.',
    });

WftwCard _fallbackCard() => WftwCard.fromMap({
      'article_id': '2024_11_02',
      'date_ms': DateTime.utc(2024, 11, 2).millisecondsSinceEpoch,
      'year': 2024,
      'book_number': null,
      'chapter': null,
      'start_verse': null,
      'end_verse': null,
      'article_title': 'Titles Matter',
      'fallback_excerpt': 'Sometimes a leader speaks plainly to a waiting crowd.',
    });

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Widget subject(WftwCard card, WftwFilterState state) {
    return MaterialApp(
      theme: testTheme(),
      home: Scaffold(
        body: WftwCardView(
          card: card,
          filterState: state,
          isActive: true,
        ),
      ),
    );
  }

  const filterState = WftwFilterState(backgroundPreset: _gradientPreset);

  for (final width in [320.0, 600.0, 840.0, 1400.0]) {
    testWidgets('verse-backed WftwCardView renders at $width logical px',
        (tester) async {
      setSurfaceSize(tester, width, 700);
      await tester.pumpWidget(subject(_verseCard(), filterState));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'overflow/exception at $width');
      expect(find.textContaining('Faith in Trials'), findsOneWidget);
      expect(find.text('— Matthew 5:3-4'), findsOneWidget);
    });

    testWidgets('fallback WftwCardView renders at $width logical px',
        (tester) async {
      setSurfaceSize(tester, width, 700);
      await tester.pumpWidget(subject(_fallbackCard(), filterState));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'overflow/exception at $width');
      expect(
        find.text('Sometimes a leader speaks plainly to a waiting crowd.'),
        findsOneWidget,
      );
    });
  }

  testWidgets('falls back to the article title when no excerpt exists',
      (tester) async {
    final card = WftwCard.fromMap({
      'article_id': 'a',
      'date_ms': 0,
      'article_title': 'Untitled Devotion',
    });
    setSurfaceSize(tester, 320, 700);
    await tester.pumpWidget(subject(card, filterState));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Untitled Devotion'), findsOneWidget);
  });
}