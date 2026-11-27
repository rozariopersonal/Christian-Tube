import 'package:flutter/foundation.dart';
import '../../../core/models/user.dart';
import 'auth_session_client.dart';
import 'auth_token_store.dart';

class SessionBootstrapResult {
  final User? user;
  final bool sessionExpired;
  final bool migrated;
  final bool cleared;

  const SessionBootstrapResult({
    this.user,
    this.sessionExpired = false,
    this.migrated = false,
    this.cleared = false,
  });
}

class SessionBootstrap {
  final AuthTokenStore _store;
  final AuthSessionClient _client;

  SessionBootstrap({
    AuthTokenStore? store,
    AuthSessionClient? client,
  })  : _store = store ?? AuthTokenStore.instance,
        _client = client ?? AuthSessionClient();

  /// Silently upgrades a cached legacy Google session (no refresh token yet)
  /// into a backend `UserSession`, and clears legacy guest sessions cleanly.
  /// Never throws; network errors leave local state usable without falsely
  /// marking the session expired.
  Future<SessionBootstrapResult> bootstrapIfNeeded({
    required User cachedUser,
    required Future<String?> Function() fetchSilentGoogleIdToken,
  }) async {
    final isLegacyGuest =
        cachedUser.id.startsWith('guest_') || cachedUser.id.startsWith('user_');
    if (isLegacyGuest) {
      await _store.clearAuthSessionKeysOnly(legacyGuestUserId: cachedUser.id);
      return const SessionBootstrapResult(cleared: true);
    }

    final existingRefresh = await _store.getRefreshToken();
    if (existingRefresh != null && existingRefresh.isNotEmpty) {
      return SessionBootstrapResult(
        user: cachedUser,
        sessionExpired: await _store.readSessionExpired(),
      );
    }

    final deviceId = await _store.getOrCreateDeviceId();
    final deviceLabel = _store.getDeviceLabel();

    try {
      final idToken = await fetchSilentGoogleIdToken();
      if (idToken == null || idToken.isEmpty) {
        final existingAccess = await _store.getAccessToken();
        if (existingAccess == null || existingAccess.isEmpty) {
          await _store.clearSessionTokensOnly();
          return SessionBootstrapResult(user: cachedUser, sessionExpired: true);
        }
        return SessionBootstrapResult(user: cachedUser);
      }

      final res = await _client.exchangeGoogle(
        idToken: idToken,
        deviceId: deviceId,
        deviceLabel: deviceLabel,
      );
      final migratedUser = res.user ?? cachedUser;
      await _store.saveSession(
        user: migratedUser,
        accessToken: res.accessToken,
        refreshToken: res.refreshToken,
        sessionId: res.sessionId,
      );
      return SessionBootstrapResult(user: migratedUser, migrated: true);
    } on SessionUnrecoverableException {
      await _store.clearSessionTokensOnly();
      return SessionBootstrapResult(user: cachedUser, sessionExpired: true);
    } catch (e) {
      debugPrint('Google silent bootstrap skipped: $e');
      return SessionBootstrapResult(user: cachedUser);
    }
  }
}
