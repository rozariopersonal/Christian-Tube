import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/models/user.dart';
import 'auth_session_client.dart';
import 'auth_token_store.dart';

class SessionBootstrapResult {
  final User? user;
  final bool sessionExpired;
  final bool migrated;

  const SessionBootstrapResult({
    this.user,
    this.sessionExpired = false,
    this.migrated = false,
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

  /// Silently upgrades a cached legacy session (no refresh token yet) into a
  /// backend `UserSession`. Never throws; network errors leave local state
  /// usable without falsely marking the session expired.
  Future<SessionBootstrapResult> bootstrapIfNeeded({
    required User cachedUser,
    required Future<String?> Function() fetchSilentGoogleIdToken,
  }) async {
    final existingRefresh = await _store.getRefreshToken();
    if (existingRefresh != null && existingRefresh.isNotEmpty) {
      return SessionBootstrapResult(
        user: cachedUser,
        sessionExpired: await _store.readSessionExpired(),
      );
    }

    final isLegacyGuest = cachedUser.isGuest ||
        cachedUser.id.startsWith('guest_') ||
        cachedUser.id.startsWith('user_');

    final deviceId = await _store.getOrCreateDeviceId();
    final deviceLabel = _store.getDeviceLabel();

    if (isLegacyGuest) {
      try {
        final res = await _client.createGuest(
          deviceId: deviceId,
          deviceLabel: deviceLabel,
          displayName: cachedUser.displayName,
        );
        final migratedUser = res.user ??
            User(
              id: cachedUser.id,
              email: '',
              displayName: cachedUser.displayName,
              isGuest: true,
            );
        await _rekeyGuestPendingOps(cachedUser.id, migratedUser.id);
        await _store.saveSession(
          user: migratedUser,
          accessToken: res.accessToken,
          refreshToken: res.refreshToken,
          sessionId: res.sessionId,
        );
        return SessionBootstrapResult(user: migratedUser, migrated: true);
      } catch (e) {
        debugPrint('Guest session bootstrap skipped: $e');
        return SessionBootstrapResult(user: cachedUser);
      }
    }

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

  Future<void> _rekeyGuestPendingOps(String oldId, String newId) async {
    if (oldId.isEmpty || newId.isEmpty || oldId == newId) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final oldKey = 'mobile_sync_pending_v2_$oldId';
      final newKey = 'mobile_sync_pending_v2_$newId';
      final raw = prefs.getString(oldKey);
      if (raw != null && raw.isNotEmpty && !prefs.containsKey(newKey)) {
        await prefs.setString(newKey, raw.replaceAll(oldId, newId));
        await prefs.remove(oldKey);
      }
      await prefs.setString('mobile_last_guest_id_v1', newId);
    } catch (_) {}
  }
}
