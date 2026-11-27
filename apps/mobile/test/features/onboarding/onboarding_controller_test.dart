import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/core/api/api_client.dart';
import 'package:mobile/core/models/channel.dart';
import 'package:mobile/core/models/user.dart';
import 'package:mobile/core/models/user_preference.dart';
import 'package:mobile/core/services/user_preference_service.dart';
import 'package:mobile/core/services/user_sync_service.dart';
import 'package:mobile/features/auth/auth_service.dart';
import 'package:mobile/features/channels/channel_service.dart';
import 'package:mobile/features/onboarding/controllers/onboarding_controller.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.onFetch, this.fail = false});

  final FutureOr<ResponseBody> Function(RequestOptions options)? onFetch;
  final bool fail;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (fail) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    if (onFetch != null) {
      return await onFetch!(options);
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
  String? _error;
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
  String? get lastError => _error;

  void setSignInFailure(String error) {
    signInResult = null;
    _error = error;
  }

  @override
  Future<User?> signInWithGoogle({
    AccountSwitchConfirmCallback? onConfirmAccountSwitch,
  }) async {
    if (signInResult != null) {
      _error = null;
      _user = signInResult;
      notifyListeners();
      return _user;
    }
    notifyListeners();
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

  List<Channel> sampleChannels() => List.generate(
        6,
        (i) => Channel(
          id: 'ch_${i + 1}',
          title: 'Channel ${i + 1}',
          avatarUrl: '',
          hasShorts: i.isEven,
        ),
      );

  group('OnboardingController unit tests', () {
    test('defaults to English language and NASB Bible version', () {
      final auth = _FakeAuthService();
      final channelService = ChannelService.forTesting(
        dio: buildDio(_StubAdapter()),
      );
      final prefService = UserPreferenceService.forTesting(
        apiClient: buildApiClient(_StubAdapter()),
      );

      final controller = OnboardingController(
        authService: auth,
        channelService: channelService,
        preferenceService: prefService,
      );

      expect(controller.state.selectedLanguages, equals({'en'}));
      expect(controller.state.primaryBibleVersionId, equals('NASB'));
      expect(controller.state.isSaving, isFalse);
      expect(controller.state.pendingNavigationRoute, isNull);

      controller.dispose();
    });

    test('toggling languages enforces at least 1 and derives matching Bible',
        () {
      final auth = _FakeAuthService();
      final channelService = ChannelService.forTesting(
        dio: buildDio(_StubAdapter()),
      );
      final prefService = UserPreferenceService.forTesting(
        apiClient: buildApiClient(_StubAdapter()),
      );

      final controller = OnboardingController(
        authService: auth,
        channelService: channelService,
        preferenceService: prefService,
      );

      // Add Tamil while keeping English -> keeps NASB
      expect(controller.toggleLanguage('ta'), isTrue);
      expect(controller.state.selectedLanguages, equals({'en', 'ta'}));
      expect(controller.state.primaryBibleVersionId, equals('NASB'));

      // Remove English -> derives Tamil Bible (TAOBVSI)
      expect(controller.toggleLanguage('en'), isTrue);
      expect(controller.state.selectedLanguages, equals({'ta'}));
      expect(controller.state.primaryBibleVersionId, equals('TAOBVSI'));

      // Cannot remove the last remaining language
      expect(controller.toggleLanguage('ta'), isFalse);
      expect(controller.state.selectedLanguages, equals({'ta'}));

      // Language with no catalog Bible falls back to NASB
      expect(controller.toggleLanguage('ro'), isTrue);
      expect(controller.toggleLanguage('ta'), isTrue);
      expect(controller.state.selectedLanguages, equals({'ro'}));
      expect(controller.state.primaryBibleVersionId, equals('NASB'));

      // Adding Spanish derives SSE
      expect(controller.toggleLanguage('es'), isTrue);
      expect(controller.state.primaryBibleVersionId, equals('SSE'));

      controller.dispose();
    });

    test(
        'startExploring auto-follows top 4 channels, persists preferences, and signals navigation',
        () async {
      final auth = _FakeAuthService();
      final channelService = ChannelService.forTesting(
        dio: buildDio(_StubAdapter()),
      );
      channelService.setChannelsForTesting(sampleChannels());
      final prefService = UserPreferenceService.forTesting(
        apiClient: buildApiClient(_StubAdapter()),
      );

      final controller = OnboardingController(
        authService: auth,
        channelService: channelService,
        preferenceService: prefService,
      );
      await controller.initialize();

      controller.toggleLanguage('ta');
      controller.toggleLanguage('en'); // only 'ta' selected

      final ok = await controller.startExploring();
      expect(ok, isTrue);

      // Auto-followed first 4 popular channels
      expect(
        channelService.subscribedChannelIds,
        equals({'ch_1', 'ch_2', 'ch_3', 'ch_4'}),
      );

      // Persisted preferences and device completion flag
      expect(prefService.hasCompletedOnboarding, isTrue);
      expect(prefService.preferences.hasCompletedOnboarding, isTrue);
      expect(prefService.preferences.languages, equals(['ta']));
      expect(prefService.preferences.primaryBibleVersionId, equals('TAOBVSI'));
      expect(controller.state.pendingNavigationRoute, equals('/feed'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('ct_device_onboarding_completed_v1'), isTrue);

      controller.dispose();
    });

    test('startExploring completes cleanly offline when channels fail to load',
        () async {
      final auth = _FakeAuthService();
      final offlineAdapter = _StubAdapter(fail: true);
      final channelService = ChannelService.forTesting(
        dio: buildDio(offlineAdapter),
      );
      final prefService = UserPreferenceService.forTesting(
        apiClient: buildApiClient(offlineAdapter),
      );

      final controller = OnboardingController(
        authService: auth,
        channelService: channelService,
        preferenceService: prefService,
      );
      await controller.initialize();

      final ok = await controller.startExploring();
      expect(ok, isTrue);
      expect(channelService.subscribedChannelIds, isEmpty);
      expect(prefService.hasCompletedOnboarding, isTrue);
      expect(controller.state.pendingNavigationRoute, equals('/feed'));

      controller.dispose();
    });

    test(
        'returning user signInWithGoogle restores preferences and signals immediate navigation',
        () async {
      const returningUser = User(
        id: 'user_123',
        email: 'reader@example.com',
        displayName: 'Returning Reader',
      );
      final auth = _FakeAuthService()..signInResult = returningUser;

      final adapter = _StubAdapter(
        onFetch: (options) {
          if (options.path.contains('/preferences')) {
            return ResponseBody.fromString(
              jsonEncode({
                'languages': ['en', 'hi'],
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
                'channelIds': ['ch_2', 'ch_5'],
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
        authService: auth,
        syncService: syncService,
      );
      final prefService = UserPreferenceService.forTesting(
        apiClient: buildApiClient(adapter),
      );

      final controller = OnboardingController(
        authService: auth,
        channelService: channelService,
        preferenceService: prefService,
      );
      await controller.initialize();

      final signedIn = await controller.signInWithGoogle();
      expect(signedIn, isTrue);
      expect(controller.state.isReturningUser, isTrue);
      expect(controller.state.pendingNavigationRoute, equals('/bible'));
      expect(prefService.hasCompletedOnboarding, isTrue);
      expect(channelService.subscribedChannelIds, equals({'ch_2', 'ch_5'}));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('ct_device_onboarding_completed_v1'), isTrue);

      controller.dispose();
    });

    test('new Google user stays on Quick Start without auto-navigating',
        () async {
      const newUser = User(
        id: 'user_new',
        email: 'new@example.com',
        displayName: 'New Reader',
      );
      final auth = _FakeAuthService()..signInResult = newUser;

      final adapter = _StubAdapter(
        onFetch: (options) {
          if (options.path.contains('/preferences')) {
            return ResponseBody.fromString(
              jsonEncode(const UserPreference().toJson()),
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

      final channelService = ChannelService.forTesting(
        dio: buildDio(adapter),
        authService: auth,
      );
      final prefService = UserPreferenceService.forTesting(
        apiClient: buildApiClient(adapter),
      );

      final controller = OnboardingController(
        authService: auth,
        channelService: channelService,
        preferenceService: prefService,
      );
      await controller.initialize();

      final signedIn = await controller.signInWithGoogle();
      expect(signedIn, isTrue);
      expect(controller.state.isReturningUser, isFalse);
      expect(controller.state.pendingNavigationRoute, isNull);
      expect(prefService.hasCompletedOnboarding, isFalse);

      controller.dispose();
    });

    test('failed Google sign-in surfaces auth error without crashing', () async {
      final auth = _FakeAuthService()
        ..setSignInFailure('Google Sign-In failed: network error');
      final channelService = ChannelService.forTesting(
        dio: buildDio(_StubAdapter()),
      );
      final prefService = UserPreferenceService.forTesting(
        apiClient: buildApiClient(_StubAdapter()),
      );

      final controller = OnboardingController(
        authService: auth,
        channelService: channelService,
        preferenceService: prefService,
      );

      final signedIn = await controller.signInWithGoogle();
      expect(signedIn, isFalse);
      expect(
        controller.state.errorMessage,
        equals('Google Sign-In failed: network error'),
      );
      expect(controller.state.pendingNavigationRoute, isNull);

      controller.dispose();
    });

    test(
        'signed-in returning user re-opening onboarding from Settings is not auto-redirected and pre-fills preferences',
        () async {
      const returningUser = User(
        id: 'user_cached',
        email: 'cached@example.com',
        displayName: 'Cached Reader',
      );
      final auth = _FakeAuthService(initialUser: returningUser);

      final adapter = _StubAdapter(
        onFetch: (options) {
          if (options.path.contains('/preferences')) {
            return ResponseBody.fromString(
              jsonEncode({
                'languages': ['ta'],
                'primaryBibleVersionId': 'TAOBVSI',
                'defaultPage': 'shorts',
                'hasCompletedOnboarding': true,
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          return ResponseBody.fromString('{"channelIds":[]}', 200, headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          });
        },
      );

      final channelService = ChannelService.forTesting(
        dio: buildDio(adapter),
        authService: auth,
      );
      final prefService = UserPreferenceService.forTesting(
        apiClient: buildApiClient(adapter),
      );
      await prefService.savePreferences(
        const UserPreference(
          languages: ['ta'],
          primaryBibleVersionId: 'TAOBVSI',
          defaultPage: 'shorts',
          hasCompletedOnboarding: true,
        ),
      );

      final controller = OnboardingController(
        authService: auth,
        channelService: channelService,
        preferenceService: prefService,
      );
      await controller.initialize();

      expect(controller.state.isReturningUser, isFalse);
      expect(controller.state.pendingNavigationRoute, isNull);
      expect(controller.state.selectedLanguages, equals({'ta'}));
      expect(controller.state.primaryBibleVersionId, equals('TAOBVSI'));

      // Even if checkReturningUser() is triggered while already signed in on
      // entry, the user must not be kicked out of Settings re-onboarding.
      await controller.checkReturningUser();
      expect(controller.state.pendingNavigationRoute, isNull);

      controller.dispose();
    });

    test(
        'startExploring awaits in-flight fetchChannels and auto-follows popular channels',
        () async {
      final auth = _FakeAuthService();
      final channelsCompleter = Completer<ResponseBody>();

      final adapter = _StubAdapter(
        onFetch: (options) {
          if (options.path.contains('/channels')) {
            return channelsCompleter.future;
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

      final channelService = ChannelService.forTesting(
        dio: buildDio(adapter),
      );
      final prefService = UserPreferenceService.forTesting(
        apiClient: buildApiClient(adapter),
      );

      final controller = OnboardingController(
        authService: auth,
        channelService: channelService,
        preferenceService: prefService,
      );
      await controller.initialize();

      // Channels are still in-flight when the user taps Start Exploring.
      expect(channelService.channels, isEmpty);
      final exploreFuture = controller.startExploring();

      // Complete the in-flight channels request shortly after.
      channelsCompleter.complete(
        ResponseBody.fromString(
          jsonEncode(
            List.generate(
              5,
              (i) => {
                'id': 'ch_${i + 1}',
                'title': 'Channel ${i + 1}',
                'avatarUrl': '',
                'hasShorts': i.isEven,
              },
            ),
          ),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );

      final ok = await exploreFuture;
      expect(ok, isTrue);
      expect(
        channelService.subscribedChannelIds,
        equals({'ch_1', 'ch_2', 'ch_3', 'ch_4'}),
      );
      expect(controller.state.pendingNavigationRoute, equals('/feed'));

      controller.dispose();
    });
  });
}
