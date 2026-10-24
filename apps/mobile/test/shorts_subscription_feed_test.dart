import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/api/api_client.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/auth/auth_service.dart';
import 'package:mobile/features/channels/channel_service.dart';
import 'package:mobile/features/shorts/services/community_shorts_controller.dart';
import 'package:mobile/features/shorts/services/shorts_orchestrator_service.dart';
import 'package:mobile/features/shorts/shorts_feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.path.contains('/subscriptions')) {
      return ResponseBody.fromString(
        jsonEncode({
          'channelIds': ['ch1', 'ch2'],
          'channels': [
            {'id': 'ch1', 'name': 'Channel 1'},
            {'id': 'ch2', 'name': 'Channel 2'},
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('[]', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

class _StubAuth extends AuthService {
  final bool _authed;
  _StubAuth(this._authed);

  @override
  bool get isAuthenticated => _authed;
}

ThemeData _testTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      extensions: const [AppTokens.light],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ShortsOrchestratorService().cancelRetryLoopForTest();
  });

  tearDown(() {
    ShortsOrchestratorService().cancelRetryLoopForTest();
  });

  testWidgets('ShortsFeedScreen queries subscribed channelIds on initial fetch when authenticated', (tester) async {
    final adapter = _RecordingAdapter();
    final apiClient = ApiClient();
    apiClient.dio.httpClientAdapter = adapter;

    final channelDio = Dio();
    channelDio.httpClientAdapter = adapter;

    final auth = _StubAuth(true);
    final channelService = ChannelService.forTesting(
      dio: channelDio,
      authService: auth,
    );
    // Pre-populate subscriptions (simulating cached subscriptions in memory)
    channelService.toggleSubscribe('ch1');
    channelService.toggleSubscribe('ch2');

    final controller = CommunityShortsController(
      apiClient: apiClient,
      isAuthenticated: auth.isAuthenticated,
      subscribedChannelIds: channelService.subscribedChannelIds,
    );

    final router = GoRouter(
      initialLocation: '/shorts',
      routes: [
        GoRoute(
          path: '/shorts',
          builder: (context, state) => ShortsFeedScreen(
            authService: auth,
            channelService: channelService,
            communityController: controller,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: _testTheme(),
        routerConfig: router,
      ),
    );

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final videoRequests =
        adapter.requests.where((r) => r.path == '/videos').toList();
    expect(videoRequests, isNotEmpty);

    // The FIRST /videos request must include channelIds: ch1,ch2 (not null/unfiltered)
    final firstVideoRequest = videoRequests.first;
    final channelIds =
        firstVideoRequest.queryParameters['channelIds'] as String?;
    expect(channelIds, isNotNull);
    expect(channelIds!.split(','), containsAll(['ch1', 'ch2']));
  });

  testWidgets('ShortsFeedScreen delays initial fetch when authenticated and subscriptions are pending', (tester) async {
    final adapter = _RecordingAdapter();
    final apiClient = ApiClient();
    apiClient.dio.httpClientAdapter = adapter;

    final channelDio = Dio();
    channelDio.httpClientAdapter = adapter;

    final auth = _StubAuth(true);
    // Subscriptions initially empty (pending backend fetch)
    final channelService = ChannelService.forTesting(
      dio: channelDio,
      authService: auth,
    );

    final controller = CommunityShortsController(
      apiClient: apiClient,
      isAuthenticated: auth.isAuthenticated,
      subscribedChannelIds: channelService.subscribedChannelIds,
    );

    final router = GoRouter(
      initialLocation: '/shorts',
      routes: [
        GoRoute(
          path: '/shorts',
          builder: (context, state) => ShortsFeedScreen(
            authService: auth,
            channelService: channelService,
            communityController: controller,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: _testTheme(),
        routerConfig: router,
      ),
    );

    // Pump to allow _loadChannelContext to resolve backend subscriptions
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final videoRequests =
        adapter.requests.where((r) => r.path == '/videos').toList();
    expect(videoRequests, isNotEmpty);

    // It should have queried only after resolving channel subscriptions
    for (final req in videoRequests) {
      final channelIds = req.queryParameters['channelIds'] as String?;
      expect(channelIds, isNotNull,
          reason: 'No unfiltered request should be made while subscriptions are pending');
      expect(channelIds!.split(','), containsAll(['ch1', 'ch2']));
    }
  });
}
