import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/core/api/api_client.dart';
import 'package:mobile/core/models/user.dart';
import 'package:mobile/core/services/user_sync_service.dart';
import 'package:mobile/features/auth/auth_service.dart';
import 'package:mobile/features/auth/services/auth_session_client.dart';
import 'package:mobile/features/auth/services/auth_token_store.dart';
import 'package:mobile/features/auth/services/refresh_coordinator.dart';
import 'package:mobile/features/auth/services/session_bootstrap.dart';

class MockAuthSessionClient extends Mock implements AuthSessionClient {}

class _FakeDioAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;
  _FakeDioAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthTokenStore.instance.resetForTesting();
  });

  group('AuthService State and Storage', () {
    test('initializes with unauthenticated state', () {
      final authService = AuthService(registerAsShared: false);
      expect(authService.isAuthenticated, isFalse);
      expect(authService.currentUser, isNull);
      expect(authService.isAdmin, isFalse);
      expect(authService.isLoading, isFalse);
      expect(authService.sessionExpired, isFalse);
      expect(authService.canSync, isFalse);
      expect(authService.lastError, isNull);
    });

    test('loads cached user from storage on creation and migrates legacy auth_token', () async {
      const mockUser = User(
        id: '12345',
        email: 'test@example.com',
        displayName: 'Test User',
        idToken: 'mock_token',
      );
      SharedPreferences.setMockInitialValues({
        'current_user': jsonEncode(mockUser.toJson()),
        'auth_token': 'mock_token',
      });

      final authService = AuthService(registerAsShared: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(authService.isAuthenticated, isTrue);
      expect(authService.currentUser?.email, 'test@example.com');
      expect(authService.currentUser?.displayName, 'Test User');
      expect(await AuthTokenStore.instance.getAccessToken(), 'mock_token');
    });

    test(
      'signOut clears user and tokens while preserving auth_device_id and ct_device_onboarding_completed_v1',
      () async {
      const mockUser = User(
        id: '12345',
        email: 'test@example.com',
        displayName: 'Test User',
      );
      await AuthTokenStore.instance.saveSession(
        user: mockUser,
        accessToken: 'acc_1',
        refreshToken: 'ref_1',
        sessionId: 'sid_1',
      );
      final deviceId = await AuthTokenStore.instance.getOrCreateDeviceId();
      final prefsBefore = await SharedPreferences.getInstance();
      await prefsBefore.setBool('ct_device_onboarding_completed_v1', true);

      final mockClient = MockAuthSessionClient();
      when(() => mockClient.logout(accessToken: any(named: 'accessToken')))
          .thenAnswer((_) async {});

      final authService = AuthService(
        sessionClient: mockClient,
        registerAsShared: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(authService.isAuthenticated, isTrue);

      await authService.signOut();

      expect(authService.isAuthenticated, isFalse);
      expect(authService.currentUser, isNull);
      expect(authService.sessionExpired, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AuthTokenStore.keyUser), isNull);
      expect(prefs.getString(AuthTokenStore.keyAccessToken), isNull);
      expect(prefs.getString(AuthTokenStore.keyDeviceId), deviceId);
      expect(prefs.getBool('ct_device_onboarding_completed_v1'), isTrue);
    });

    test('AuthService clears legacy guest cached user on startup', () async {
      SharedPreferences.setMockInitialValues({
        AuthTokenStore.keyUser: jsonEncode({
          'id': 'guest_legacy_1',
          'email': '',
          'displayName': 'Legacy Guest',
          'isGuest': true,
        }),
        AuthTokenStore.keyAccessToken: 'old_guest_jwt',
        AuthTokenStore.keyDeviceId: 'dev_keep_1',
        'ct_device_onboarding_completed_v1': true,
      });

      final authService = AuthService(registerAsShared: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(authService.isAuthenticated, isFalse);
      expect(authService.currentUser, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AuthTokenStore.keyUser), isNull);
      expect(prefs.getString(AuthTokenStore.keyAccessToken), isNull);
      expect(prefs.getString(AuthTokenStore.keyDeviceId), 'dev_keep_1');
      expect(prefs.getBool('ct_device_onboarding_completed_v1'), isTrue);
    });
  });

  group('RefreshCoordinator', () {
    test('coalesces concurrent refresh calls into a single backend request', () async {
      await AuthTokenStore.instance.saveSession(
        accessToken: 'old_acc',
        refreshToken: 'old_ref',
        sessionId: 'sid_1',
      );
      final mockClient = MockAuthSessionClient();
      final gate = Completer<AuthSessionResult>();
      when(() => mockClient.refresh(sessionId: 'sid_1', refreshToken: 'old_ref'))
          .thenAnswer((_) => gate.future);

      final coordinator = RefreshCoordinator.forTesting(client: mockClient);
      final f1 = coordinator.refresh();
      final f2 = coordinator.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      gate.complete(const AuthSessionResult(
        accessToken: 'new_acc',
        refreshToken: 'new_ref',
        sessionId: 'sid_1',
        expiresIn: 900,
      ));

      expect(await f1, 'new_acc');
      expect(await f2, 'new_acc');
      verify(() => mockClient.refresh(sessionId: 'sid_1', refreshToken: 'old_ref'))
          .called(1);
    });

    test('marks sessionExpired on 401/403 while preserving current_user', () async {
      const user = User(id: 'u1', email: 'u1@example.com', displayName: 'U1');
      await AuthTokenStore.instance.saveSession(
        user: user,
        accessToken: 'old_acc',
        refreshToken: 'bad_ref',
        sessionId: 'sid_1',
      );
      final mockClient = MockAuthSessionClient();
      when(() => mockClient.refresh(sessionId: 'sid_1', refreshToken: 'bad_ref'))
          .thenThrow(SessionUnrecoverableException(401, 'Revoked'));

      bool? listenerExpired;
      final coordinator = RefreshCoordinator.forTesting(client: mockClient);
      coordinator.addSessionListener(({required expired}) => listenerExpired = expired);

      final tok = await coordinator.refresh();
      expect(tok, isNull);
      expect(listenerExpired, isTrue);
      expect(await AuthTokenStore.instance.readSessionExpired(), isTrue);
      expect((await AuthTokenStore.instance.readUser())?.id, 'u1');
    });

    test('does NOT expire session on transient network error and backs off', () async {
      await AuthTokenStore.instance.saveSession(
        accessToken: 'old_acc',
        refreshToken: 'ref_1',
        sessionId: 'sid_1',
      );
      final mockClient = MockAuthSessionClient();
      when(() => mockClient.refresh(sessionId: 'sid_1', refreshToken: 'ref_1'))
          .thenThrow(SessionTransientException('Timeout'));

      bool listenerCalled = false;
      final coordinator = RefreshCoordinator.forTesting(
        client: mockClient,
        backoffDuration: const Duration(seconds: 30),
      );
      coordinator.addSessionListener(({required expired}) => listenerCalled = true);

      expect(await coordinator.refresh(), isNull);
      expect(listenerCalled, isFalse);
      expect(await AuthTokenStore.instance.readSessionExpired(), isFalse);

      // Second immediate call hits 30s backoff without hitting client again
      expect(await coordinator.refresh(), isNull);
      verify(() => mockClient.refresh(sessionId: 'sid_1', refreshToken: 'ref_1'))
          .called(1);
    });
  });

  group('SessionBootstrap', () {
    test('clears legacy guest_ and user_ cached sessions cleanly while preserving local preferences, channels, device id and onboarding flag', () async {
      for (final legacyId in ['guest_1', 'user_legacy_1']) {
        SharedPreferences.setMockInitialValues({
          AuthTokenStore.keyUser: jsonEncode({'id': legacyId, 'email': '', 'displayName': 'Old Guest'}),
          AuthTokenStore.keyAccessToken: 'old_acc',
          AuthTokenStore.keyDeviceId: 'device_123',
          'ct_device_onboarding_completed_v1': true,
          'ct_user_preferences_v1': jsonEncode({'languages': ['ta'], 'primaryBibleVersionId': 'TAOBVSI'}),
          'subscribed_channel_ids': ['ch_1', 'ch_2'],
          'mobile_last_guest_id_v1': legacyId,
          'mobile_sync_pending_v2_$legacyId': '{"k":"v"}',
        });
        final mockClient = MockAuthSessionClient();
        final bootstrap = SessionBootstrap(client: mockClient);
        final res = await bootstrap.bootstrapIfNeeded(
          cachedUser: User(
            id: legacyId,
            email: '',
            displayName: 'Old Guest',
          ),
          fetchSilentGoogleIdToken: () async => null,
        );

        expect(res.cleared, isTrue);
        expect(res.migrated, isFalse);
        expect(res.user, isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(AuthTokenStore.keyUser), isNull);
        expect(prefs.getString(AuthTokenStore.keyAccessToken), isNull);
        expect(prefs.getString('mobile_last_guest_id_v1'), isNull);
        expect(prefs.getString('mobile_sync_pending_v2_$legacyId'), isNull);
        expect(prefs.getString(AuthTokenStore.keyDeviceId), 'device_123');
        expect(prefs.getBool('ct_device_onboarding_completed_v1'), isTrue);
        expect(prefs.getString('ct_user_preferences_v1'), isNotNull);
        expect(prefs.getStringList('subscribed_channel_ids'), ['ch_1', 'ch_2']);
      }
    });

    test('exchanges silent Google idToken for upgraded Google users', () async {
      final mockClient = MockAuthSessionClient();
      when(
        () => mockClient.exchangeGoogle(
          idToken: 'silent.google.jwt',
          deviceId: any(named: 'deviceId'),
          deviceLabel: any(named: 'deviceLabel'),
        ),
      ).thenAnswer(
        (_) async => const AuthSessionResult(
          accessToken: 'acc_new',
          refreshToken: 'ref_new',
          sessionId: 'sid_new',
          expiresIn: 900,
          user: User(id: 'g_1', email: 'g@example.com', displayName: 'G'),
        ),
      );

      final bootstrap = SessionBootstrap(client: mockClient);
      final res = await bootstrap.bootstrapIfNeeded(
        cachedUser: const User(id: 'g_1', email: 'g@example.com', displayName: 'G'),
        fetchSilentGoogleIdToken: () async => 'silent.google.jwt',
      );

      expect(res.migrated, isTrue);
      expect(res.sessionExpired, isFalse);
      expect(await AuthTokenStore.instance.getAccessToken(), 'acc_new');
    });
  });

  group('ApiClient 401 retry & UserSyncService gating', () {
    test('ApiClient refreshes once on 401 and retries the request', () async {
      await AuthTokenStore.instance.saveSession(
        accessToken: 'stale_jwt',
        refreshToken: 'ref_1',
        sessionId: 'sid_1',
      );
      final mockClient = MockAuthSessionClient();
      when(() => mockClient.refresh(sessionId: 'sid_1', refreshToken: 'ref_1'))
          .thenAnswer(
        (_) async => const AuthSessionResult(
          accessToken: 'fresh_jwt',
          refreshToken: 'ref_2',
          sessionId: 'sid_1',
          expiresIn: 900,
        ),
      );

      final coordinator = RefreshCoordinator.forTesting(client: mockClient);
      final api = ApiClient(refreshCoordinator: coordinator);
      final seenAuthHeaders = <String?>[];

      api.dio.httpClientAdapter = _FakeDioAdapter((options) async {
        seenAuthHeaders.add(options.headers['Authorization'] as String?);
        if (options.headers['Authorization'] == 'Bearer stale_jwt') {
          return ResponseBody.fromString('{"message":"expired"}', 401, headers: {
            Headers.contentTypeHeader: ['application/json'],
          });
        }
        return ResponseBody.fromString('{"ok":true}', 200, headers: {
          Headers.contentTypeHeader: ['application/json'],
        });
      });

      final response = await api.dio.get('/api/videos');
      expect(response.statusCode, 200);
      expect(seenAuthHeaders, ['Bearer stale_jwt', 'Bearer fresh_jwt']);
    });

    test('UserSyncService does not hit network when canSync is false', () async {
      bool canSync = false;
      final dio = Dio();
      int networkCalls = 0;
      dio.httpClientAdapter = _FakeDioAdapter((options) async {
        networkCalls++;
        return ResponseBody.fromString('{"serverTime":1000}', 200, headers: {
          Headers.contentTypeHeader: ['application/json'],
        });
      });

      final sync = UserSyncService.forTesting(
        dio: dio,
        canSyncCheck: () => canSync,
      );
      sync.setActiveUserForTesting('u_1');
      await sync.enqueuePreference('themeMode', 'dark');
      await sync.pullAndFlush(force: true);
      expect(networkCalls, 0);

      canSync = true;
      await sync.pullAndFlush(force: true);
      expect(networkCalls, greaterThan(0));
    });
  });
}
