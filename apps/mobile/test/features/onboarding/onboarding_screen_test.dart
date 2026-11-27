import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/core/api/api_client.dart';
import 'package:mobile/core/models/channel.dart';
import 'package:mobile/core/models/user.dart';
import 'package:mobile/core/services/user_preference_service.dart';
import 'package:mobile/core/services/user_sync_service.dart';
import 'package:mobile/core/theme/theme_service.dart';
import 'package:mobile/features/auth/auth_service.dart';
import 'package:mobile/features/channels/channel_service.dart';
import 'package:mobile/features/onboarding/screens/onboarding_screen.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.onFetch});

  final ResponseBody Function(RequestOptions options)? onFetch;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (onFetch != null) {
      return onFetch!(options);
    }
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeAuthService extends AuthService {
  User? _user;
  User? signInResult;

  _FakeAuthService({User? initialUser})
      : _user = initialUser,
        super(skipInitialLoad: true, registerAsShared: false);

  @override
  User? get currentUser => _user;

  @override
  bool get isAuthenticated => _user != null;

  @override
  bool get canSync => _user != null;

  @override
  Future<User?> signInWithGoogle({
    AccountSwitchConfirmCallback? onConfirmAccountSwitch,
  }) async {
    if (signInResult != null) {
      _user = signInResult;
      notifyListeners();
      return _user;
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Dio buildDio(_StubAdapter adapter) =>
      Dio(BaseOptions(baseUrl: 'http://localhost:3000'))
        ..httpClientAdapter = adapter;

  ApiClient buildApiClient(_StubAdapter adapter) =>
      ApiClient()..dio.httpClientAdapter = adapter;

  Widget buildApp(Widget child, {ThemeService? themeService}) {
    final ts = themeService ?? ThemeService();
    return AnimatedBuilder(
      animation: ts,
      builder: (context, _) {
        return MaterialApp(
          theme: ts.lightTheme,
          darkTheme: ts.darkTheme,
          themeMode: ts.themeMode,
          home: child,
        );
      },
    );
  }

  GoRouter buildRouter({
    required AuthService authService,
    required ThemeService themeService,
    required ChannelService channelService,
    required UserPreferenceService preferenceService,
  }) {
    return GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => OnboardingScreen(
            authService: authService,
            themeService: themeService,
            channelService: channelService,
            preferenceService: preferenceService,
          ),
        ),
        GoRoute(
          path: '/feed',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('Feed Destination')),
          ),
        ),
        GoRoute(
          path: '/bible',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('Bible Destination')),
          ),
        ),
      ],
    );
  }

  group('OnboardingScreen Widget Tests', () {
    testWidgets(
      'renders cleanly without overflow across 320, 600, 840, and 1400 viewports',
      (tester) async {
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final authService = _FakeAuthService();
        final themeService = ThemeService();
        final channelService = ChannelService.forTesting(
          dio: buildDio(_StubAdapter()),
        );
        final prefService = UserPreferenceService.forTesting(
          apiClient: buildApiClient(_StubAdapter()),
        );

        for (final width in [320.0, 600.0, 840.0, 1400.0]) {
          tester.view.physicalSize = Size(width * 2, 800 * 2);
          tester.view.devicePixelRatio = 2.0;

          await tester.pumpWidget(
            buildApp(
              OnboardingScreen(
                authService: authService,
                themeService: themeService,
                channelService: channelService,
                preferenceService: prefService,
              ),
              themeService: themeService,
            ),
          );
          await tester.pumpAndSettle();

          expect(find.textContaining('Welcome to'), findsOneWidget);
          expect(find.text('Sign in with Google'), findsOneWidget);
          expect(find.text('Choose Your Languages'), findsOneWidget);
          expect(find.text('Start Exploring'), findsOneWidget);
          expect(find.textContaining('Guest'), findsNothing);
          expect(find.byIcon(Icons.arrow_back), findsNothing);
          expect(find.byIcon(Icons.arrow_back_ios), findsNothing);
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets('contains zero Continue as Guest button in light and dark mode',
        (tester) async {
      final authService = _FakeAuthService();
      final themeService = ThemeService();
      await themeService.setThemeMode(ThemeMode.dark);
      final channelService = ChannelService.forTesting(
        dio: buildDio(_StubAdapter()),
      );
      final prefService = UserPreferenceService.forTesting(
        apiClient: buildApiClient(_StubAdapter()),
      );

      await tester.pumpWidget(
        buildApp(
          OnboardingScreen(
            authService: authService,
            themeService: themeService,
            channelService: channelService,
            preferenceService: prefService,
          ),
          themeService: themeService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Guest'), findsNothing);
      expect(find.text('Start Exploring'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'toggling language chips auto-derives primary Bible version and tapping Start Exploring completes onboarding',
      (tester) async {
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        tester.view.physicalSize = const Size(400 * 2, 900 * 2);
        tester.view.devicePixelRatio = 2.0;

        final authService = _FakeAuthService();
        final themeService = ThemeService();
        final channelService = ChannelService.forTesting(
          dio: buildDio(_StubAdapter()),
        );
        channelService.setChannelsForTesting(
          List.generate(
            6,
            (i) => Channel(
              id: 'ch_${i + 1}',
              title: 'Channel ${i + 1}',
              avatarUrl: '',
            ),
          ),
        );
        final prefService = UserPreferenceService.forTesting(
          apiClient: buildApiClient(_StubAdapter()),
        );

        final router = buildRouter(
          authService: authService,
          themeService: themeService,
          channelService: channelService,
          preferenceService: prefService,
        );

        await tester.pumpWidget(
          MaterialApp.router(
            theme: themeService.lightTheme,
            routerConfig: router,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Primary Bible: NASB'), findsOneWidget);

        // Select Tamil, then deselect English -> auto-picks TAOBVSI
        final tamilChip = find.text('Tamil (தமிழ்)');
        await tester.ensureVisible(tamilChip);
        await tester.tap(tamilChip);
        await tester.pumpAndSettle();

        final englishChip = find.text('English');
        await tester.ensureVisible(englishChip);
        await tester.tap(englishChip);
        await tester.pumpAndSettle();

        expect(find.textContaining('Primary Bible: TAOBVSI'), findsOneWidget);

        // Tap Start Exploring -> saves prefs, follows top 4 channels, navigates to /feed
        final startButton = find.text('Start Exploring');
        await tester.ensureVisible(startButton);
        await tester.tap(startButton);
        for (var i = 0; i < 40; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump(const Duration(milliseconds: 20));
          if (find.text('Feed Destination').evaluate().isNotEmpty) break;
        }
        await tester.pumpAndSettle();

        expect(find.text('Feed Destination'), findsOneWidget);
        expect(prefService.hasCompletedOnboarding, isTrue);
        expect(prefService.preferences.languages, equals(['ta']));
        expect(prefService.preferences.primaryBibleVersionId, equals('TAOBVSI'));
        expect(
          channelService.subscribedChannelIds,
          equals({'ch_1', 'ch_2', 'ch_3', 'ch_4'}),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'returning user auto-navigates to cloud default route on Google Sign-In',
      (tester) async {
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        tester.view.physicalSize = const Size(400 * 2, 900 * 2);
        tester.view.devicePixelRatio = 2.0;

        const returningUser = User(
          id: 'returning_1',
          email: 'returning@example.com',
          displayName: 'Returning User',
        );
        final authService = _FakeAuthService()..signInResult = returningUser;
        final themeService = ThemeService();

        final adapter = _StubAdapter(
          onFetch: (options) {
            if (options.path.contains('/preferences')) {
              return ResponseBody.fromString(
                jsonEncode({
                  'languages': ['en'],
                  'primaryBibleVersionId': 'NASB',
                  'defaultPage': 'bible',
                  'hasCompletedOnboarding': true,
                }),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            if (options.path.contains('/subscriptions')) {
              return ResponseBody.fromString(
                jsonEncode({
                  'channelIds': ['ch_1'],
                }),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return ResponseBody.fromString(
              '{}',
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          },
        );

        final syncService = UserSyncService.forTesting(
          dio: buildDio(adapter),
          canSyncCheck: () => true,
        );
        final channelService = ChannelService.forTesting(
          dio: buildDio(adapter),
          authService: authService,
          syncService: syncService,
        );
        final prefService = UserPreferenceService.forTesting(
          apiClient: buildApiClient(adapter),
        );

        final router = buildRouter(
          authService: authService,
          themeService: themeService,
          channelService: channelService,
          preferenceService: prefService,
        );

        await tester.pumpWidget(
          MaterialApp.router(
            theme: themeService.lightTheme,
            routerConfig: router,
          ),
        );
        await tester.pumpAndSettle();

        final signInButton = find.text('Sign in with Google');
        await tester.ensureVisible(signInButton);
        await tester.tap(signInButton);
        for (var i = 0; i < 40; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump(const Duration(milliseconds: 20));
          if (find.text('Bible Destination').evaluate().isNotEmpty) break;
        }
        await tester.pumpAndSettle();

        expect(find.text('Bible Destination'), findsOneWidget);
        expect(prefService.hasCompletedOnboarding, isTrue);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('ct_device_onboarding_completed_v1'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
