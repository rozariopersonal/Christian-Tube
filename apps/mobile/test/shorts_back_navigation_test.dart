import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/layout/shell_back_handler.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/shorts/services/shorts_orchestrator_service.dart';
import 'package:mobile/features/shorts/shorts_feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _short(String id, String channelId) => {
      'id': id,
      'title': 'Short $id',
      'videoUrl': 'https://www.youtube.com/shorts/$id',
      'duration': '0:45',
      'type': 'SHORT',
      'channelId': channelId,
      'channelTitle': 'Creator $channelId',
      'publishedAt': '2026-01-01T00:00:00.000Z',
      'viewCount': 1,
    };

ThemeData testTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      extensions: const [AppTokens.light],
    );

class _FeedStub extends StatelessWidget {
  const _FeedStub();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('FEED_STUB'),
            TextButton(
              onPressed: () => context.push('/shorts'),
              child: const Text('OPEN_SHORTS'),
            ),
          ],
        ),
      ),
    );
  }
}

GoRouter buildRouter(String initialLocation) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        ShellRoute(
          builder: (context, state, child) => ShellBackHandler(
            path: state.uri.path,
            child: Scaffold(body: child),
          ),
          routes: [
            GoRoute(
              path: '/feed',
              builder: (context, state) => const _FeedStub(),
            ),
            GoRoute(
              path: '/shorts',
              builder: (context, state) => const ShortsFeedScreen(),
            ),
          ],
        ),
      ],
    );

/// Bounded pumping: the shorts feed shows an indeterminate progress spinner
/// while loading, so `pumpAndSettle` would hang until the (mocked, failing)
/// network request resolves. Fixed frames keep the test deterministic.
Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'ct_cached_community_shorts': jsonEncode([_short('s1', 'c1')]),
    });
  });

  tearDown(() {
    // The singleton orchestrator keeps a periodic retry timer running; stop it
    // so widget tests do not fail with a leftover pending timer.
    ShortsOrchestratorService().cancelRetryLoopForTest();
  });

  testWidgets(
      'system back on the shorts home page returns to the Videos feed '
      'instead of exiting the app', (tester) async {
    await tester.pumpWidget(MaterialApp.router(
      theme: testTheme(),
      routerConfig: buildRouter('/shorts'),
    ));
    await pumpFrames(tester);

    expect(find.byType(ShortsFeedScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue,
        reason: 'back must be intercepted by PopScope, not bubble to '
            'SystemNavigator.pop (app exit)');
    await pumpFrames(tester);

    expect(find.byType(ShortsFeedScreen), findsNothing);
    expect(find.text('FEED_STUB'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // End-of-body cancel: the binding's pending-timer check runs before the
    // tearDown, so the singleton's periodic retry loop must be stopped here.
    ShortsOrchestratorService().cancelRetryLoopForTest();
  });

  testWidgets(
      'system back from a shorts page pushed above the Videos feed '
      'pops back to it', (tester) async {
    await tester.pumpWidget(MaterialApp.router(
      theme: testTheme(),
      routerConfig: buildRouter('/feed'),
    ));
    await pumpFrames(tester);

    await tester.tap(find.text('OPEN_SHORTS'));
    await pumpFrames(tester);

    expect(find.byType(ShortsFeedScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    await pumpFrames(tester);

    expect(find.byType(ShortsFeedScreen), findsNothing);
    expect(find.text('FEED_STUB'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // End-of-body cancel: the binding's pending-timer check runs before the
    // tearDown, so the singleton's periodic retry loop must be stopped here.
    ShortsOrchestratorService().cancelRetryLoopForTest();
  });
}