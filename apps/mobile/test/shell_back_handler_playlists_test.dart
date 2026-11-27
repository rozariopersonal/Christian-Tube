import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/layout/shell_back_handler.dart';
import 'package:mobile/core/navigation/navigation_history_service.dart';

Future<String> _triggerBackFrom(WidgetTester tester, String initialPath) async {
  NavigationHistoryService.instance.reset();
  ShellBackHandler.resetInterceptors();

  late GoRouter router;
  router = GoRouter(
    initialLocation: initialPath,
    routes: [
      for (final p in [
        '/feed',
        '/profile',
        '/watch-later',
        '/watch-plans',
        '/watch/:id',
        '/playlists',
        '/playlists/:id',
      ])
        GoRoute(
          path: p,
          builder: (context, state) => ShellBackHandler(
            path: state.uri.path,
            child: Scaffold(body: Text('PAGE:${state.uri.path}')),
          ),
        ),
    ],
  );

  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();

  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();

  return router.routeInformationProvider.value.uri.path;
}

void main() {
  testWidgets('/watch-later falls back to /profile (not /feed)', (tester) async {
    expect(await _triggerBackFrom(tester, '/watch-later'), '/profile');
  });

  testWidgets('/watch-plans falls back to /profile (not /feed)', (tester) async {
    expect(await _triggerBackFrom(tester, '/watch-plans'), '/profile');
  });

  testWidgets('/watch/abc falls back to /feed', (tester) async {
    expect(await _triggerBackFrom(tester, '/watch/abc'), '/feed');
  });

  testWidgets('/playlists/p1 falls back to /playlists', (tester) async {
    expect(await _triggerBackFrom(tester, '/playlists/p1'), '/playlists');
  });

  testWidgets('/playlists falls back to /profile', (tester) async {
    expect(await _triggerBackFrom(tester, '/playlists'), '/profile');
  });
}
