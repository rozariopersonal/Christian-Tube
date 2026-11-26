import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/models/user.dart';
import '../../core/models/user_preference.dart';
import '../../core/services/user_preference_service.dart';
import '../../core/services/user_sync_service.dart';
import '../../shared/services/reader_fonts_service.dart';
import '../articles/services/articles_download_manager.dart';
import '../audio/services/audio_local_library.dart';
import '../bible/services/study/bible_study_updater.dart';
import '../books/services/book_service.dart';
import '../dictionary/services/dictionary_download_manager.dart';
import '../engines/scripture/services/bible_download_manager.dart';
import '../songs/services/songs_download_manager.dart';
import '../user_items/services/user_item_sync_service.dart';
import 'services/auth_session_client.dart';
import 'services/auth_token_store.dart';
import 'services/refresh_coordinator.dart';
import 'services/refresh_lock_io.dart'
    if (dart.library.html) 'services/refresh_lock_web.dart';
import 'services/session_bootstrap.dart';

typedef AccountSwitchConfirmCallback = Future<bool> Function(
  User currentUser,
  User nextUser,
);

class AuthService extends ChangeNotifier {
  static AuthService? shared;

  final ApiClient _apiClient;
  final AuthTokenStore _tokenStore;
  final AuthSessionClient _sessionClient;
  final RefreshCoordinator _refreshCoordinator;
  final SessionBootstrap _bootstrap;
  late GoogleSignIn _googleSignIn;

  User? _currentUser;
  bool _isAdmin = false;
  bool _isLoading = false;
  bool _sessionExpired = false;
  String? _lastError;
  void Function()? _unsubExternal;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isAdmin => _isAdmin;
  bool get isLoading => _isLoading;
  bool get sessionExpired => _sessionExpired;
  bool get canSync => isAuthenticated && !sessionExpired;
  String? get lastError => _lastError;

  AuthService({
    ApiClient? apiClient,
    AuthTokenStore? tokenStore,
    AuthSessionClient? sessionClient,
    RefreshCoordinator? refreshCoordinator,
    SessionBootstrap? bootstrap,
    bool registerAsShared = true,
    bool skipInitialLoad = false,
    User? initialUserForTesting,
    bool initialSessionExpiredForTesting = false,
  })  : _tokenStore = tokenStore ?? AuthTokenStore.instance,
        _sessionClient = sessionClient ?? AuthSessionClient(),
        _refreshCoordinator = refreshCoordinator ?? RefreshCoordinator.instance,
        _bootstrap = bootstrap ??
            SessionBootstrap(
              store: tokenStore ?? AuthTokenStore.instance,
              client: sessionClient ?? AuthSessionClient(),
            ),
        _apiClient = apiClient ??
            ApiClient(
              tokenStore: tokenStore ?? AuthTokenStore.instance,
              refreshCoordinator:
                  refreshCoordinator ?? RefreshCoordinator.instance,
            ),
        _currentUser = initialUserForTesting,
        _sessionExpired = initialSessionExpiredForTesting {
    if (registerAsShared) {
      shared = this;
    }
    _initGoogleSignIn();
    if (!skipInitialLoad) {
      _refreshCoordinator.addSessionListener(_onCoordinatorSessionChanged);
      _refreshCoordinator.registerSilentGoogleFallback(_trySilentGoogleExchange);
      _unsubExternal = subscribeExternalAuthEvents(_onExternalAuthEvent);
      _loadUserFromStorage();
    }
  }

  @override
  void dispose() {
    _refreshCoordinator.removeSessionListener(_onCoordinatorSessionChanged);
    _unsubExternal?.call();
    _unsubExternal = null;
    if (identical(shared, this)) {
      shared = null;
    }
    super.dispose();
  }

  void _initGoogleSignIn() {
    _googleSignIn = GoogleSignIn(
      clientId: kIsWeb ? AppConfig.googleClientId : null,
      serverClientId: kIsWeb ? null : AppConfig.googleClientId,
      scopes: const ['email', 'profile'],
    );
  }

  void _onCoordinatorSessionChanged({required bool expired}) {
    final wasExpired = _sessionExpired;
    _sessionExpired = expired;
    if (wasExpired != expired) {
      notifyListeners();
      if (wasExpired && !expired && _currentUser != null) {
        unawaited(UserSyncService.instance.pullAndFlush(force: true));
        unawaited(UserItemSyncService.instance.pullAndPush());
      }
    }
  }

  void _onExternalAuthEvent(String eventType) {
    if (!kIsWeb) return;
    Future.microtask(() async {
      final storedUser = await _tokenStore.readUser();
      final expired = await _tokenStore.readSessionExpired();
      final wasExpired = _sessionExpired;
      _currentUser = storedUser;
      _sessionExpired = expired;
      if (storedUser == null) {
        _isAdmin = false;
      }
      notifyListeners();
      if (wasExpired && !expired && storedUser != null) {
        unawaited(UserSyncService.instance.pullAndFlush(force: true));
        unawaited(UserItemSyncService.instance.pullAndPush());
      }
    });
  }

  Future<void> _loadUserFromStorage() async {
    final user = await _tokenStore.readUser();
    if (user == null) return;

    _currentUser = user;
    _sessionExpired = await _tokenStore.readSessionExpired();
    unawaited(UserSyncService.instance.onUserChanged(user.id));
    if (!user.isGuest && user.email.isNotEmpty) {
      await checkIsAdmin(user.email);
    }
    notifyListeners();

    final result = await _bootstrap.bootstrapIfNeeded(
      cachedUser: user,
      fetchSilentGoogleIdToken: _fetchSilentGoogleIdToken,
    );
    if (result.migrated && result.user != null) {
      _currentUser = result.user;
      _sessionExpired = result.sessionExpired;
      unawaited(UserSyncService.instance.onUserChanged(result.user!.id));
      notifyListeners();
    } else if (result.sessionExpired && !_sessionExpired) {
      _sessionExpired = true;
      notifyListeners();
    }
  }

  Future<String?> _fetchSilentGoogleIdToken() async {
    try {
      final account = await _googleSignIn.signInSilently();
      if (account == null) return null;
      final auth = await account.authentication;
      return auth.idToken;
    } on MissingPluginException {
      // In unit tests without GoogleSignIn platform channel, skip gracefully
      return 'test_plugin_unavailable';
    } catch (e) {
      debugPrint('Silent Google sign-in skipped: $e');
      return null;
    }
  }

  Future<String?> _trySilentGoogleExchange() async {
    try {
      final account = await _googleSignIn.signInSilently();
      if (account == null) return null;
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) return null;

      final deviceId = await _tokenStore.getOrCreateDeviceId();
      final res = await _sessionClient.exchangeGoogle(
        idToken: idToken,
        deviceId: deviceId,
        deviceLabel: _tokenStore.getDeviceLabel(),
      );
      final user = res.user ??
          User(
            id: account.id,
            email: account.email,
            displayName: account.displayName?.isNotEmpty == true
                ? account.displayName!
                : account.email.split('@').first,
            photoUrl: account.photoUrl,
            isGuest: false,
          );
      await _tokenStore.saveSession(
        user: user,
        accessToken: res.accessToken,
        refreshToken: res.refreshToken,
        sessionId: res.sessionId,
      );
      _currentUser = user;
      _sessionExpired = false;
      notifyListeners();
      return res.accessToken;
    } catch (_) {
      return null;
    }
  }

  Future<void> proactiveRefreshIfNearExpiry() async {
    if (_currentUser == null || _sessionExpired) return;
    final token = await _tokenStore.getAccessToken();
    if (token == null || token.isEmpty) return;
    final expMs = _decodeJwtExpMs(token);
    if (expMs == null) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (expMs <= nowMs + 120000) {
      await _refreshCoordinator.refresh();
    }
  }

  int? _decodeJwtExpMs(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final normalized = base64Url.normalize(parts[1]);
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map;
      final exp = (payload['exp'] as num?)?.toInt();
      return exp != null ? exp * 1000 : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> checkIsAdmin([String? email]) async {
    final targetEmail = email ?? _currentUser?.email;
    if (targetEmail == null ||
        targetEmail.isEmpty ||
        (_currentUser?.isGuest ?? false)) {
      _isAdmin = false;
      notifyListeners();
      return false;
    }

    try {
      final response = await _apiClient.dio.get(
        '/channels/check-admin',
        queryParameters: {'email': targetEmail},
      );
      if (response.statusCode == 200 && response.data != null) {
        _isAdmin = response.data['isAdmin'] == true;
        notifyListeners();
        return _isAdmin;
      }
    } catch (e) {
      debugPrint('Admin check error: $e');
    }
    return _isAdmin;
  }

  Future<User?> resumeSync({
    AccountSwitchConfirmCallback? onConfirmAccountSwitch,
  }) {
    return signInWithGoogle(onConfirmAccountSwitch: onConfirmAccountSwitch);
  }

  Future<User?> signInWithGoogle({
    AccountSwitchConfirmCallback? onConfirmAccountSwitch,
  }) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        _lastError = null;
        return null;
      }

      String? idToken;
      try {
        final auth = await account.authentication.timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw Exception('Authentication timeout'),
        );
        idToken = auth.idToken;
      } catch (authErr) {
        debugPrint('Google authentication token fetch warning: $authErr');
      }

      if (idToken == null || idToken.isEmpty) {
        _lastError =
            'Google Sign-In did not return an ID token. Please check OAuth configuration.';
        return null;
      }

      final previewUser = User(
        id: account.id,
        email: account.email,
        displayName: account.displayName != null &&
                account.displayName!.isNotEmpty
            ? account.displayName!
            : account.email.split('@').first,
        photoUrl: account.photoUrl,
        isGuest: false,
      );

      final existing = _currentUser;
      final existingIsGoogle =
          existing != null && !existing.isGuest && !existing.id.startsWith('guest_');

      if (existingIsGoogle && existing.id != account.id) {
        if (onConfirmAccountSwitch != null) {
          final confirmed = await onConfirmAccountSwitch(existing, previewUser);
          if (!confirmed) {
            try {
              await _googleSignIn.signOut();
            } catch (_) {}
            return null;
          }
        }
        await signOut();
      }

      final deviceId = await _tokenStore.getOrCreateDeviceId();
      final res = await _sessionClient.exchangeGoogle(
        idToken: idToken,
        deviceId: deviceId,
        deviceLabel: _tokenStore.getDeviceLabel(),
      );

      final user = res.user ?? previewUser;
      final wasExpired = _sessionExpired;
      _currentUser = user;
      _sessionExpired = false;
      _refreshCoordinator.clearBackoff();

      await _tokenStore.saveSession(
        user: user,
        accessToken: res.accessToken,
        refreshToken: res.refreshToken,
        sessionId: res.sessionId,
      );
      broadcastAuthEvent('session_updated');

      _syncUserWithBackend(user);
      unawaited(UserSyncService.instance.onUserChanged(user.id));
      if (wasExpired) {
        unawaited(UserSyncService.instance.pullAndFlush(force: true));
        unawaited(UserItemSyncService.instance.pullAndPush());
      }
      await checkIsAdmin(user.email);

      return user;
    } on SessionUnrecoverableException catch (e) {
      _lastError = e.message;
      return null;
    } catch (e) {
      debugPrint('Google Sign-In General Error: $e');
      _lastError =
          'Google Sign-In failed: ${e.toString().replaceAll('Exception:', '').trim()}';
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _syncUserWithBackend(User user) {
    Future.microtask(() async {
      try {
        final response = await _apiClient.dio.post(
          '/user/sync',
          data: user.toJson(),
        );
        if ((response.statusCode == 200 || response.statusCode == 201) &&
            response.data != null) {
          final prefData = response.data['preference'];
          if (prefData != null && prefData is Map) {
            final cloudPref = UserPreference.fromJson(
              Map<String, dynamic>.from(prefData),
            );
            await UserPreferenceService.instance.savePreferences(
              cloudPref,
              auth: this,
              syncWithBackend: false,
            );
          } else {
            await UserPreferenceService.instance.fetchPreferences(auth: this);
          }
        }
      } catch (e) {
        debugPrint('Backend user sync non-blocking error: $e');
        UserPreferenceService.instance
            .fetchPreferences(auth: this)
            .catchError((_) => const UserPreference());
      }
    });
  }

  Future<User> signInAsGuest([String? customName, String? ignoredEmail]) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    final fallbackName = customName?.trim().isNotEmpty == true
        ? customName!.trim()
        : '${AppConfig.appName} Member';

    try {
      final deviceId = await _tokenStore.getOrCreateDeviceId();
      final res = await _sessionClient.createGuest(
        deviceId: deviceId,
        deviceLabel: _tokenStore.getDeviceLabel(),
        displayName: fallbackName,
      );

      final user = res.user ??
          User(
            id: 'guest_${DateTime.now().millisecondsSinceEpoch}',
            email: '',
            displayName: fallbackName,
            isGuest: true,
          );

      _currentUser = user;
      _sessionExpired = false;
      _isAdmin = false;
      _refreshCoordinator.clearBackoff();

      await _tokenStore.saveSession(
        user: user,
        accessToken: res.accessToken,
        refreshToken: res.refreshToken,
        sessionId: res.sessionId,
      );
      broadcastAuthEvent('session_updated');

      _syncUserWithBackend(user);
      unawaited(UserSyncService.instance.onUserChanged(user.id));
      return user;
    } catch (e) {
      debugPrint('Offline/fallback guest sign-in: $e');
      final offlineUser = User(
        id: 'guest_${DateTime.now().millisecondsSinceEpoch}',
        email: '',
        displayName: fallbackName,
        isGuest: true,
      );
      _currentUser = offlineUser;
      _sessionExpired = false;
      _isAdmin = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AuthTokenStore.keyUser,
        jsonEncode(offlineUser.toJson()),
      );
      unawaited(UserSyncService.instance.onUserChanged(offlineUser.id));
      return offlineUser;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    final accessToken = await _tokenStore.getAccessToken();
    final sessionId = await _tokenStore.getSessionId();
    if (accessToken != null &&
        accessToken.isNotEmpty &&
        sessionId != null &&
        sessionId.isNotEmpty) {
      unawaited(_sessionClient.logout(accessToken: accessToken));
    }

    try {
      await _googleSignIn.signOut();
    } catch (_) {}

    _currentUser = null;
    _isAdmin = false;
    _sessionExpired = false;
    _lastError = null;
    _refreshCoordinator.clearBackoff();

    await UserSyncService.instance.clearAllDeviceData();
    await UserItemSyncService.instance.clearForSignOut();
    await UserPreferenceService.instance.clearForSignOut();
    await _wipeAllDownloadsAndLocalDatabases();

    try {
      await _tokenStore.clearAllExceptDeviceId();
    } catch (_) {}
    broadcastAuthEvent('signed_out');

    notifyListeners();
  }

  Future<void> _wipeAllDownloadsAndLocalDatabases() async {
    try {
      await AudioLocalLibrary().removeAll();
    } catch (_) {}
    try {
      await ReaderFontsService.instance.removeAllDownloadedFonts();
    } catch (_) {}
    try {
      final articlesMgr = ArticlesDownloadManager();
      for (final lang in articlesMgr.installedLanguages.toList()) {
        await articlesMgr.deleteLanguage(lang);
      }
    } catch (_) {}
    try {
      final dictMgr = DictionaryDownloadManager();
      for (final id in dictMgr.installedIds.toList()) {
        await dictMgr.deleteDictionary(id);
      }
    } catch (_) {}
    try {
      await SongsDownloadManager().delete();
    } catch (_) {}
    try {
      await BookService.instance.removeAllBooks();
    } catch (_) {}
    try {
      final bibleMgr = BibleDownloadManager();
      for (final meta in BibleDownloadManager.catalog) {
        if (bibleMgr.isInstalled(meta.id)) {
          await bibleMgr.removeVersion(meta.id);
        }
      }
    } catch (_) {}
    try {
      await BibleStudyUpdater.removeDownload('taobvsi');
    } catch (_) {}

    if (!kIsWeb) {
      try {
        final dbDirPath = await getDatabasesPath();
        final dbDir = Directory(dbDirPath);
        if (await dbDir.exists()) {
          for (final entity in dbDir.listSync()) {
            if (entity is File &&
                (entity.path.endsWith('.db') ||
                    entity.path.endsWith('.sqlite'))) {
              try {
                await deleteDatabase(entity.path);
              } catch (_) {
                try {
                  await entity.delete();
                } catch (_) {}
              }
            }
          }
        }
      } catch (_) {}

      try {
        final docsDir = await getApplicationDocumentsDirectory();
        final downloadsDir = Directory(p.join(docsDir.path, 'downloads'));
        if (await downloadsDir.exists()) {
          await downloadsDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }
}
