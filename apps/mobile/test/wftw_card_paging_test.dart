import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/micro_feed/engines/wftw/models/wftw_card.dart';
import 'package:mobile/features/micro_feed/engines/wftw/models/wftw_filter_state.dart';
import 'package:mobile/features/micro_feed/engines/wftw/widgets/wftw_card_view.dart';

ThemeData testTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      extensions: const [AppTokens.light],
    );

WftwCard _plainCard(String title, String excerpt) => WftwCard.fromMap({
      'article_id': title.toLowerCase(),
      'date_ms': DateTime.utc(2024, 10, 26).millisecondsSinceEpoch,
      'article_title': title,
      'fallback_excerpt': excerpt,
    });

const _gradientPreset = 'gradient_royal_midnight';

class _PagingHost extends StatefulWidget {
  final List<WftwCard> cards;
  final WftwFilterState state;
  final PageController controller;
  final ValueChanged<int> onShift;
  const _PagingHost(
      {required this.cards,
      required this.state,
      required this.controller,
      required this.onShift});

  @override
  State<_PagingHost> createState() => _PagingHostState();
}

class _PagingHostState extends State<_PagingHost> {
  double pixels = 0;
  double maxExtent = 0;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        // Track only the card's own scrollable: the outer PageView's extent
        // (2 * viewportHeight) never matches the inner overflow extent.
        if (n.metrics.maxScrollExtent > maxExtent) {
          maxExtent = n.metrics.maxScrollExtent;
        }
        if (n.metrics.maxScrollExtent > 0 &&
            (maxExtent == 0 ||
                (n.metrics.maxScrollExtent - maxExtent).abs() < 1.0)) {
          pixels = n.metrics.pixels;
        }
        return false;
      },
      child: PageView.builder(
        controller: widget.controller,
        scrollDirection: Axis.vertical,
        itemCount: widget.cards.length,
        itemBuilder: (context, index) => WftwCardView(
          card: widget.cards[index],
          filterState: widget.state,
          isActive: true,
          onEdgePageShift: widget.onShift,
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
      'short (fitting) cards swipe up to advance and down to go back',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const state = WftwFilterState(backgroundPreset: _gradientPreset);
    final cards = [
      _plainCard('Alpha', 'A short excerpt that fits comfortably.'),
      _plainCard('Beta', 'Another compact excerpt that fits.'),
      _plainCard('Gamma', 'A third compact excerpt that fits.'),
    ];

    await tester.pumpWidget(MaterialApp(
      theme: testTheme(),
      home: Scaffold(
        body: _PagingHost(
          cards: cards,
          state: state,
          controller: PageController(),
          onShift: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Alpha'), findsOneWidget);

    // Natural upward swipe -> next card
    await tester.fling(find.byType(PageView), const Offset(0, -300), 1000);
    await tester.pumpAndSettle();
    expect(find.textContaining('Beta'), findsOneWidget,
        reason: 'swipe up should advance to the next card');

    // Natural downward swipe -> previous card
    await tester.fling(find.byType(PageView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(find.textContaining('Alpha'), findsOneWidget,
        reason: 'swipe down should go back to the previous card');
  });

  testWidgets('long (overflowing) cards page on edge-push both directions',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const state = WftwFilterState(
      backgroundPreset: _gradientPreset,
      fontSizeScale: 3.0,
    );
    final longExcerpt = List.filled(24, 'The quick brown fox jumps over the lazy dog near the quiet river.').join(' ');
    final cards = [
      _plainCard('Alpha', longExcerpt),
      _plainCard('Beta', longExcerpt),
      _plainCard('Gamma', longExcerpt),
    ];

    final controller = PageController();
    await tester.pumpWidget(MaterialApp(
      theme: testTheme(),
      home: Scaffold(
        body: _PagingHost(
          cards: cards,
          state: state,
          controller: controller,
          onShift: (d) {
            final next = (controller.page! + d).clamp(0.0, 2.0);
            controller.animateToPage(
              next.round(),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
            );
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final host = tester.state<_PagingHostState>(find.byType(_PagingHost));
    expect(host.maxExtent, greaterThan(0), reason: 'text must overflow');
    expect(find.textContaining('Alpha'), findsOneWidget);

    // One continuous drag: reach the card bottom, then keep pushing.
    final gesture = await tester.startGesture(const Offset(160, 350));
    var guard = 0;
    while (host.pixels < host.maxExtent - 1 && guard++ < 60) {
      await gesture.moveBy(const Offset(0, -600));
      await tester.pump();
    }
    await gesture.moveBy(const Offset(0, -180));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.textContaining('Beta'), findsOneWidget,
        reason: 'push past the bottom edge should page to the next card');

    // Let the 600 ms edge-shift debounce expire before running the reverse.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );

    // Beta starts at its top: a downward fling past the top edge pages back
    // (OverscrollNotification path).
    await tester.fling(find.textContaining('Beta'), const Offset(0, 300), 1200);
    await tester.pumpAndSettle();
    expect(find.textContaining('Alpha'), findsOneWidget,
        reason: 'push past the top edge should page back to the previous card');
  });
}