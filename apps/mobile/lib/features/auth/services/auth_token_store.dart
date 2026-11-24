import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/user.dart';

class AuthTokenStore {
  AuthTokenStore._();
  static final AuthTokenStore instance = AuthTokenStore._();

  static const String keyUser = 'current_user';
  static const String keyAccessToken = 'auth_access_token';
  static const String keyRefreshToken = 'auth_refresh_token';
  static const String keySessionId = 'auth_session_id';
  static const String keyDeviceId = 'auth_device_id';
  static const String keySessionExpired = 'auth_session_expired';
  static const String legacyKeyToken = 'auth_token';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // In-memory fallback for test environments where SecureStorage platform channel isn't mocked.
  String? _ephemeralRefreshFallback;

  @visibleForTesting
  void resetForTesting() {
    _ephemeralRefreshFallback = null;
  }

  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(keyDeviceId);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing;
    }
    final generated = const Uuid().v4();
    await prefs.setString(keyDeviceId, generated);
    return generated;
  }

  String getDeviceLabel() {
    if (kIsWeb) return 'Flutter Web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android App';
      case TargetPlatform.iOS:
        return 'iOS App';
      case TargetPlatform.windows:
        return 'Windows App';
      case TargetPlatform.macOS:
        return 'macOS App';
      case TargetPlatform.linux:
        return 'Linux App';
      case TargetPlatform.fuchsia:
        return 'Fuchsia App';
    }
  }

  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString(keyAccessToken);
    if (current != null && current.trim().isNotEmpty) {
      return current;
    }
    final legacy = prefs.getString(legacyKeyToken);
    if (legacy != null && legacy.trim().isNotEmpty) {
      await prefs.setString(keyAccessToken, legacy);
      await prefs.remove(legacyKeyToken);
      return legacy;
    }
    return null;
  }

  Future<String?> getRefreshToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getString(keyRefreshToken);
      return (val != null && val.trim().isNotEmpty) ? val : null;
    }
    try {
      final val = await _secureStorage.read(key: keyRefreshToken);
      if (val != null && val.trim().isNotEmpty) return val;
    } on MissingPluginException {
      return _ephemeralRefreshFallback;
    } catch (_) {
      return _ephemeralRefreshFallback;
    }
    return null;
  }

  Future<String?> getSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(keySessionId);
    return (val != null && val.trim().isNotEmpty) ? val : null;
  }

  Future<User?> readUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      return User.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<bool> readSessionExpired() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keySessionExpired) ?? false;
  }

  Future<void> saveSession({
    User? user,
    required String accessToken,
    String? refreshToken,
    String? sessionId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (user != null) {
      await prefs.setString(keyUser, jsonEncode(user.toJson()));
    }
    await prefs.setString(keyAccessToken, accessToken);
    await prefs.remove(legacyKeyToken);
    if (sessionId != null && sessionId.isNotEmpty) {
      await prefs.setString(keySessionId, sessionId);
    }
    await prefs.setBool(keySessionExpired, false);

    if (refreshToken != null && refreshToken.isNotEmpty) {
      if (kIsWeb) {
        await prefs.setString(keyRefreshToken, refreshToken);
      } else {
        _ephemeralRefreshFallback = refreshToken;
        try {
          await _secureStorage.write(key: keyRefreshToken, value: refreshToken);
        } on MissingPluginException {
          // Safe fallback in unit tests
        } catch (_) {}
      }
    }
  }

  Future<void> clearSessionTokensOnly() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyAccessToken);
    await prefs.remove(legacyKeyToken);
    await prefs.remove(keySessionId);
    await prefs.setBool(keySessionExpired, true);
    if (kIsWeb) {
      await prefs.remove(keyRefreshToken);
    } else {
      _ephemeralRefreshFallback = null;
      try {
        await _secureStorage.delete(key: keyRefreshToken);
      } on MissingPluginException {
        // ignore
      } catch (_) {}
    }
  }

  Future<void> clearAllExceptDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString(keyDeviceId);
    await prefs.clear();
    if (deviceId != null && deviceId.trim().isNotEmpty) {
      await prefs.setString(keyDeviceId, deviceId);
    }
    _ephemeralRefreshFallback = null;
    if (!kIsWeb) {
      try {
        await _secureStorage.delete(key: keyRefreshToken);
      } on MissingPluginException {
        // ignore
      } catch (_) {}
    }
  }
}
