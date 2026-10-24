import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../models/user_preference.dart';
import '../../shared/services/library_languages_controller.dart';
import '../../features/bible/services/bible_settings_service.dart';
import '../../features/channels/channel_service.dart';
import '../../features/auth/auth_service.dart';
import 'lockscreen_word_feed_service.dart';

class UserPreferenceService extends ChangeNotifier {
  static const String _prefStorageKey = 'ct_user_preferences_v1';
  static final UserPreferenceService _instance = UserPreferenceService._internal();
  factory UserPreferenceService() => _instance;
  static UserPreferenceService get instance => _instance;

  final ApiClient _apiClient;
  UserPreference _preferences = const UserPreference();
  bool _isLoading = false;
  bool _isInitialized = false;

  UserPreference get preferences => _preferences;
  bool get hasCompletedOnboarding => _preferences.hasCompletedOnboarding;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;

  UserPreferenceService._internal({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient() {
    initialize();
  }

  @visibleForTesting
  UserPreferenceService.forTesting({ApiClient? apiClient, UserPreference? initial})
      : _apiClient = apiClient ?? ApiClient(),
        _preferences = initial ?? const UserPreference(),
        _isInitialized = true;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefStorageKey);
      if (raw != null && raw.isNotEmpty) {
        _preferences = UserPreference.fromJson(jsonDecode(raw));
      }
    } catch (e) {
      debugPrint('UserPreferenceService init error: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Fetches preferences from the backend if authenticated, falling back to local cache.
  Future<UserPreference> fetchPreferences({AuthService? auth}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final isAuthenticated = auth?.isAuthenticated ?? false;
      if (isAuthenticated) {
        dynamic response;
        try {
          response = await _apiClient.dio.get('/api/user/preferences');
        } catch (_) {
          response = await _apiClient.dio.get('/user/preferences');
        }

        if (response.statusCode == 200 && response.data != null) {
          final cloudPref = UserPreference.fromJson(
            response.data is Map<String, dynamic>
                ? response.data
                : Map<String, dynamic>.from(response.data as Map),
          );
          _preferences = cloudPref;
          await _saveToLocal(cloudPref);
          await applyToRuntimeControllers(cloudPref);
        }
      }
    } catch (e) {
      debugPrint('UserPreferenceService fetchPreferences error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return _preferences;
  }

  /// Saves preferences locally and synchronizes them to the backend.
  Future<void> savePreferences(
    UserPreference newPreferences, {
    AuthService? auth,
    bool syncWithBackend = true,
  }) async {
    _preferences = newPreferences;
    notifyListeners();

    // 1. Persist locally
    await _saveToLocal(newPreferences);

    // 2. Apply to runtime controllers (library languages, bible, channels, lockscreen)
    await applyToRuntimeControllers(newPreferences);

    // 3. Sync to backend if authenticated
    final isAuthenticated = auth?.isAuthenticated ?? false;
    if (syncWithBackend && isAuthenticated) {
      try {
        dynamic response;
        try {
          response = await _apiClient.dio.put(
            '/api/user/preferences',
            data: newPreferences.toJson(),
          );
        } catch (_) {
          response = await _apiClient.dio.put(
            '/user/preferences',
            data: newPreferences.toJson(),
          );
        }

        if (response.statusCode == 200 && response.data != null) {
          debugPrint('User preferences successfully synced to database.');
        }
      } catch (e) {
        debugPrint('UserPreferenceService backend sync error: $e');
      }
    }
  }

  Future<void> markOnboardingComplete({
    AuthService? auth,
    bool syncWithBackend = true,
  }) async {
    final updated = _preferences.copyWith(hasCompletedOnboarding: true);
    await savePreferences(updated, auth: auth, syncWithBackend: syncWithBackend);
  }

  /// Propagates saved preferences to the app's specialized controllers.
  Future<void> applyToRuntimeControllers(UserPreference pref) async {
    // 1. Library and audio content languages
    if (pref.languages.isNotEmpty) {
      await LibraryLanguagesController.instance.selectLanguages(
        pref.languages.toSet(),
      );
    }

    // 2. Preferred Bible version
    if (pref.primaryBibleVersionId.isNotEmpty) {
      try {
        final bibleService = BibleSettingsService();
        final currentSettings = await bibleService.loadSettings();
        await bibleService.saveSettings(
          currentSettings.copyWith(
            lastVersion: pref.primaryBibleVersionId,
          ),
        );
      } catch (e) {
        debugPrint('Failed to set preferred Bible version: $e');
      }
    }

    // 3. Refresh channel subscriptions in ChannelService
    try {
      final channelService = ChannelService();
      await channelService.loadSubscriptions();
    } catch (_) {}

    // 4. Lock screen word feed
    try {
      if (pref.lockScreenWordFeedEnabled) {
        await LockScreenWordFeedService.instance.enable(
          intervalMinutes: pref.lockScreenRefreshIntervalMinutes,
        );
      } else {
        await LockScreenWordFeedService.instance.disable();
      }
    } catch (e) {
      debugPrint('Failed to sync LockScreenWordFeedService: $e');
    }
  }

  Future<void> _saveToLocal(UserPreference pref) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefStorageKey, jsonEncode(pref.toJson()));
    } catch (e) {
      debugPrint('Failed to persist user preferences locally: $e');
    }
  }

  Future<void> clearForSignOut() async {
    _preferences = const UserPreference();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefStorageKey);
    } catch (_) {}
    notifyListeners();
  }
}
