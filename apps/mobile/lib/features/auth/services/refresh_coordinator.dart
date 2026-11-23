import 'dart:async';
import 'package:flutter/foundation.dart';
import 'auth_session_client.dart';
import 'auth_token_store.dart';
import 'refresh_lock_io.dart'
    if (dart.library.html) 'refresh_lock_web.dart';

typedef SilentGoogleFallback = Future<String?> Function();
typedef SessionStateListener = void Function({required bool expired});

class RefreshCoordinator {
  static final RefreshCoordinator instance = RefreshCoordinator._internal();

  final AuthTokenStore _store;
  final AuthSessionClient _client;
  final Duration _backoffDuration;

  Completer<String?>? _inFlight;
  DateTime? _lastFailureAt;
  SilentGoogleFallback? _silentGoogleFallback;
  final Set<SessionStateListener> _listeners = <SessionStateListener>{};

  RefreshCoordinator._internal({
    AuthTokenStore? store,
    AuthSessionClient? client,
    Duration backoffDuration = const Duration(seconds: 30),
  })  : _store = store ?? AuthTokenStore.instance,
        _client = client ?? AuthSessionClient(),
        _backoffDuration = backoffDuration;

  @visibleForTesting
  RefreshCoordinator.forTesting({
    AuthTokenStore? store,
    AuthSessionClient? client,
    Duration backoffDuration = const Duration(seconds: 30),
  }) : this._internal(
          store: store,
          client: client,
          backoffDuration: backoffDuration,
        );

  void registerSilentGoogleFallback(SilentGoogleFallback? fallback) {
    _silentGoogleFallback = fallback;
  }

  void addSessionListener(SessionStateListener listener) {
    _listeners.add(listener);
  }

  void removeSessionListener(SessionStateListener listener) {
    _listeners.remove(listener);
  }

  void clearBackoff() {
    _lastFailureAt = null;
  }

  void _notifyListeners({required bool expired}) {
    for (final listener in _listeners.toList()) {
      listener(expired: expired);
    }
  }

  Future<String?> refresh() async {
    if (_inFlight != null) {
      return _inFlight!.future;
    }
    final lastFail = _lastFailureAt;
    if (lastFail != null &&
        DateTime.now().difference(lastFail) < _backoffDuration) {
      return null;
    }

    final completer = Completer<String?>();
    _inFlight = completer;

    try {
      final tokenBeforeWait = await _store.getAccessToken();
      final result = await runWithCrossTabLock<String?>('auth_refresh', () async {
        // Another tab may have rotated the tokens while we waited for the lock.
        final latestAccess = await _store.getAccessToken();
        final isExpiredFlag = await _store.readSessionExpired();
        if (latestAccess != null &&
            latestAccess.isNotEmpty &&
            latestAccess != tokenBeforeWait &&
            !isExpiredFlag) {
          _notifyListeners(expired: false);
          return latestAccess;
        }

        final refreshToken = await _store.getRefreshToken();
        final sessionId = await _store.getSessionId();

        if (refreshToken == null ||
            refreshToken.isEmpty ||
            sessionId == null ||
            sessionId.isEmpty) {
          final silentToken = await _silentGoogleFallback?.call();
          if (silentToken != null && silentToken.isNotEmpty) {
            _lastFailureAt = null;
            broadcastAuthEvent('session_updated');
            _notifyListeners(expired: false);
            return silentToken;
          }
          await _store.clearSessionTokensOnly();
          broadcastAuthEvent('session_expired');
          _notifyListeners(expired: true);
          return null;
        }

        try {
          final res = await _client.refresh(
            sessionId: sessionId,
            refreshToken: refreshToken,
          );
          if (res.accessToken.isEmpty) {
            _lastFailureAt = DateTime.now();
            return null;
          }
          await _store.saveSession(
            accessToken: res.accessToken,
            refreshToken: res.refreshToken,
            sessionId: res.sessionId,
          );
          _lastFailureAt = null;
          broadcastAuthEvent('session_updated');
          _notifyListeners(expired: false);
          return res.accessToken;
        } on SessionUnrecoverableException {
          await _store.clearSessionTokensOnly();
          broadcastAuthEvent('session_expired');
          _notifyListeners(expired: true);
          return null;
        } on SessionTransientException {
          _lastFailureAt = DateTime.now();
          return null;
        } catch (_) {
          _lastFailureAt = DateTime.now();
          return null;
        }
      });

      completer.complete(result);
      return result;
    } catch (e, st) {
      completer.completeError(e, st);
      return null;
    } finally {
      _inFlight = null;
    }
  }
}
