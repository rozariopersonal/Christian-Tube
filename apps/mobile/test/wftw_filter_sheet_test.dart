import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/micro_feed/engines/wftw/models/wftw_filter_state.dart';
import 'package:mobile/features/micro_feed/engines/wftw/widgets/wftw_filter_sheet.dart';

void setSurfaceSize(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

ThemeData testTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      extensions: const [AppTokens.light],
    );

const _years = [2024, 2025, 2026];
const _books = [1, 2, 40];

Widget _embed(WftwFilterSheet sheet) {
  return MaterialApp(
    theme: testTheme(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: sheet,
        ),
      ),
    ),
  );
}

void main() {
  for (final width in [320.0, 600.0, 840.0, 1400.0]) {
    testWidgets('WftwFilterSheet renders without overflow at $width logical px',
        (tester) async {
      setSurfaceSize(tester, width, 800);
      await tester.pumpWidget(_embed(WftwFilterSheet(
        currentState: const WftwFilterState(),
        availableYears: _years,
        availableBooks: _books,
        onApply: (_) {},
      )));

      expect(tester.takeException(), isNull,
          reason: 'overflow/exception at $width');
      expect(find.text('Filter & Sort Feed'), findsOneWidget);
      expect(find.text('Latest Date'), findsOneWidget);
      expect(find.text('Canonical Book Order'), findsOneWidget);
      expect(find.text('All Years'), findsOneWidget);
      for (final yr in _years) {
        expect(find.text('$yr'), findsOneWidget);
      }
      expect(find.text('All Books'), findsOneWidget);
      expect(find.text('Genesis'), findsOneWidget);
      expect(find.text('Exodus'), findsOneWidget);
    });
  }

  testWidgets('opening the sheet via showAdaptiveBottomSheet shows a Reset '
      'button when filters are active', (tester) async {
    setSurfaceSize(tester, 600, 800);
    WftwFilterState? applied;
    await tester.pumpWidget(MaterialApp(
      theme: testTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => WftwFilterSheet(
                    currentState: const WftwFilterState(yearFilter: 2024),
                    availableYears: _years,
                    availableBooks: _books,
                    onApply: (state) => applied = state,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Reset'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(applied, isNotNull);
    expect(applied!.yearFilter, isNull);
    expect(applied!.sortBy, 'date');
  });

  testWidgets('selecting Canonical Book Order applies sort and closes',
      (tester) async {
    setSurfaceSize(tester, 320, 640);
    WftwFilterState? applied;
    await tester.pumpWidget(MaterialApp(
      theme: testTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => WftwFilterSheet(
                    currentState: const WftwFilterState(),
                    availableYears: _years,
                    availableBooks: _books,
                    onApply: (state) => applied = state,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Canonical Book Order'));
    await tester.pumpAndSettle();

    expect(applied, isNotNull);
    expect(applied!.sortBy, 'book');
    expect(find.byType(WftwFilterSheet), findsNothing);
  });
}