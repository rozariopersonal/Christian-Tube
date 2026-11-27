import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../config/app_config.dart';
import '../engines/active_engine.g.dart';
import '../models/user_preference.dart';
import '../../shared/services/library_languages_controller.dart';
import '../../features/bible/services/bible_settings_service.dart';
import '../../features/auth/auth_service.dart';
import 'lockscreen_word_feed_service.dart';
import 'user_sync_service.dart';

class UserPreferenceService extends ChangeNotifier {
  static const String _prefStorageKey = 'ct_user_preferences_v1';
  static const String _deviceOnboardingCompletedKey = 'ct_device_onboarding_completed_v1';
  static final UserPreferenceService _instance = UserPreferenceService._internal();
  factory UserPreferenceService() => _instance;
  static UserPreferenceService get instance => _instance;

  final ApiClient _apiClient;
  UserPreference _preferences = const UserPreference();
  bool _isLoading = false;
  bool _isInitialized = false;
  bool _deviceOnboardingCompleted = false;
  int _preferenceRevision = 0;
  String? _cachedUserId;

  UserPreference get preferences => _preferences;
  bool get hasCompletedOnboarding =>
      _deviceOnboardingCompleted || _preferences.hasCompletedOnboarding;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;

  /// Resolves the user's configured [UserPreference.defaultPage] to a valid
  /// GoRouter path for the current app configuration.
  String get defaultRoutePath => resolveRoutePath(_preferences.defaultPage);

  static String resolveRoutePath(String? page) {
    final normalized = (page ?? 'feed').trim().toLowerCase();
    switch (normalized) {
      case 'shorts':
        return '/shorts';
      case 'bible':
        return AppConfig.instanceId != 'centum_academy' ? '/bible' : '/feed';
      case 'library':
      case 'books':
        return AppConfig.instanceId != 'centum_academy' ? '/library' : '/feed';
      case 'words':
        return kMicroFeedEnabled ? '/words' : '/feed';
      case 'audio':
        return AppConfig.instanceId != 'centum_academy' ? '/audio' : '/feed';
      case 'feed':
      default:
        return '/feed';
    }
  }

  UserPreferenceService._internal({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient() {
    initialize();
  }

  @visibleForTesting
  UserPreferenceService.forTesting({
    ApiClient? apiClient,
    UserPreference? initial,
    bool? deviceOnboardingCompleted,
  })  : _apiClient = apiClient ?? ApiClient(),
        _preferences = initial ?? const UserPreference(),
        _deviceOnboardingCompleted = deviceOnboardingCompleted ??
            (initial?.hasCompletedOnboarding ?? false),
        _isInitialized = true;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _deviceOnboardingCompleted =
          prefs.getBool(_deviceOnboardingCompletedKey) ?? false;
      final raw = prefs.getString(_prefStorageKey);
      if (raw != null && raw.isNotEmpty) {
        final savedData = jsonDecode(raw) as Map<String, dynamic>;
        _preferences = UserPreference.fromJson(savedData);
        if (_preferences.hasCompletedOnboarding &&
            (_preferences.videoChannelIds.isNotEmpty ||
                _preferences.shortsChannelIds.isNotEmpty)) {
          _preferences = _preferences.copyWith(channelSelectionsConfigured: true);
        }
        _cachedUserId = savedData['userId'] as String?;
        final savedUser = prefs.getString('current_user');
        if (_cachedUserId == null && savedUser != null) {
          final user = jsonDecode(savedUser) as Map<String, dynamic>;
          _cachedUserId = user['id'] as String?;
        }
      }
      if (_preferences.hasCompletedOnboarding && !_deviceOnboardingCompleted) {
        _deviceOnboardingCompleted = true;
        await prefs.setBool(_deviceOnboardingCompletedKey, true);
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
    final preferenceRevision = _preferenceRevision;
    final sync = UserSyncService.instance;
    final acknowledgementVersion = sync.acknowledgementVersion;
    final userId = auth?.currentUser?.id;
    _isLoading = true;
    notifyListeners();

    try {
      final canSync = auth?.canSync ?? (AuthService.shared?.canSync ?? false);
      if (canSync) {
        dynamic response;
        try {
          response = await _apiClient.dio.get('/api/user/preferences');
        } catch (_) {
          response = await _apiClient.dio.get('/user/preferences');
        }

        if (response.statusCode == 200 &&
            response.data is Map &&
            userId == auth?.currentUser?.id &&
            preferenceRevision == _preferenceRevision &&
            acknowledgementVersion == sync.acknowledgementVersion) {
          final data = Map<String, dynamic>.from(response.data as Map);
          final pending = sync.activeUserId == userId
              ? sync.pendingOps.values.where((op) => op.kind == 'preference')
              : const <SyncOp>[];
          final sameUser = _cachedUserId == userId;
          if (sameUser && data['hasCompletedOnboarding'] != true &&
              _preferences.hasCompletedOnboarding) {
            data.addAll(_preferences.toJson());
          } else if (sameUser && _preferences.channelSelectionsConfigured &&
              !UserPreference.fromJson(data).channelSelectionsConfigured) {
            data.addAll({
              'channelSelectionsConfigured': true,
              'videoChannelIds': _preferences.videoChannelIds,
              'shortsChannelIds': _preferences.shortsChannelIds,
            });
          }
          for (final op in pending) {
            data[op.itemId] = op.prefValue;
          }
          final cloudPref = UserPreference.fromJson(data);
          await _saveToLocal(cloudPref, userId);
          if (preferenceRevision == _preferenceRevision &&
              userId == auth?.currentUser?.id) {
            _preferences = cloudPref;
            _cachedUserId = userId;
            await applyToRuntimeControllers(cloudPref);
          }
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
    bool applyRuntime = true,
    bool syncAll = false,
  }) async {
    final previous = _preferences;
    final previousUserId = _cachedUserId;
    final userId = auth?.currentUser?.id ?? previousUserId;
    final prevJson = previous.toJson();
    final nextJson = newPreferences.toJson()
      ..remove('channelSelectionsConfigured');
    final revision = ++_preferenceRevision;
    _preferences = newPreferences;
    _cachedUserId = userId;
    notifyListeners();

    try {
      await _saveToLocal(newPreferences, userId);
    } catch (_) {
      if (revision == _preferenceRevision) {
        _preferences = previous;
        _cachedUserId = previousUserId;
        notifyListeners();
      }
      rethrow;
    }

    final sync = UserSyncService.instance;
    if (syncWithBackend &&
        (auth == null || auth.currentUser?.id == sync.activeUserId) &&
        sync.activeUserId != null) {
      final sendChannelSelections = newPreferences.channelSelectionsConfigured;
      final channelListsChanged = sendChannelSelections &&
          (!previous.channelSelectionsConfigured ||
              !listEquals(previous.videoChannelIds, newPreferences.videoChannelIds) ||
              !listEquals(previous.shortsChannelIds, newPreferences.shortsChannelIds));
      final changes = <String, dynamic>{};
      for (final entry in nextJson.entries) {
        final isChannelList = entry.key == 'videoChannelIds' ||
            entry.key == 'shortsChannelIds';
        if (isChannelList && !sendChannelSelections) continue;
        if (syncAll || (isChannelList && channelListsChanged) ||
            jsonEncode(prevJson[entry.key]) != jsonEncode(entry.value)) {
          changes[entry.key] = entry.value;
        }
      }
      await sync.enqueuePreferences(changes);
    }

    if (newPreferences.hasCompletedOnboarding && !_deviceOnboardingCompleted) {
      _deviceOnboardingCompleted = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_deviceOnboardingCompletedKey, true);
      } catch (_) {}
    }

    if (applyRuntime && revision == _preferenceRevision) {
      await applyToRuntimeControllers(newPreferences);
    }
  }

  Future<void> setDefaultPage(
    String page, {
    AuthService? auth,
    bool syncWithBackend = true,
  }) async {
    final normalized = page.trim().toLowerCase();
    final safePage = normalized.isEmpty ? 'feed' : normalized;
    if (_preferences.defaultPage == safePage) return;
    final updated = _preferences.copyWith(defaultPage: safePage);
    await savePreferences(updated, auth: auth, syncWithBackend: syncWithBackend);
  }

  Future<void> markOnboardingComplete({
    AuthService? auth,
    bool syncWithBackend = true,
  }) async {
    final updated = _preferences.copyWith(hasCompletedOnboarding: true);
    await savePreferences(updated, auth: auth, syncWithBackend: syncWithBackend);
  }

  /// Synchronizes a follow/unfollow action into the local UserPreference.
  Future<void> syncChannelFollowState(
    String channelId,
    bool isFollowed, {
    AuthService? auth,
    bool hasShorts = true,
    bool? targetVideo,
    bool? targetShorts,
  }) async {
    final videoList = List<String>.from(_preferences.videoChannelIds);
    final shortsList = List<String>.from(_preferences.shortsChannelIds);

    final affectVideo = targetVideo ?? true;
    final affectShorts = targetShorts ?? hasShorts;

    if (isFollowed) {
      if (affectVideo && !videoList.contains(channelId)) videoList.add(channelId);
      if (affectShorts && !shortsList.contains(channelId)) shortsList.add(channelId);
    } else {
      if (affectVideo) videoList.remove(channelId);
      if (affectShorts) shortsList.remove(channelId);
    }

    if (!listEquals(videoList, _preferences.videoChannelIds) ||
        !listEquals(shortsList, _preferences.shortsChannelIds)) {
      final updated = _preferences.copyWith(
        videoChannelIds: videoList,
        shortsChannelIds: shortsList,
        channelSelectionsConfigured: true,
      );
      await savePreferences(updated, auth: auth, applyRuntime: false);
    }
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
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pref_bible_version', pref.primaryBibleVersionId);
      } catch (e) {
        debugPrint('Failed to set preferred Bible version: $e');
      }
    }

    // 4. Lock screen word feed
    try {
      if (pref.lockScreenWordFeedEnabled) {
        final enabled = await LockScreenWordFeedService.instance.enable(
          intervalMinutes: pref.lockScreenRefreshIntervalMinutes,
        );
        if (!enabled && _preferences.lockScreenWordFeedEnabled) {
          _preferences = _preferences.copyWith(lockScreenWordFeedEnabled: false);
          await _saveToLocal(_preferences, _cachedUserId);
          notifyListeners();
        }
      } else {
        await LockScreenWordFeedService.instance.disable();
      }
    } catch (e) {
      debugPrint('Failed to sync LockScreenWordFeedService: $e');
    }

    // 5. Theme and Accent Color synchronization
    try {
      final prefs = await SharedPreferences.getInstance();
      if (pref.themeMode.isNotEmpty) {
        await prefs.setString('theme_mode_preference', pref.themeMode);
      }
      if (pref.accentColor.isNotEmpty) {
        await prefs.setString('theme_color_preference', pref.accentColor);
      }
    } catch (_) {}
  }

  Future<void> _saveToLocal(UserPreference pref, String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    final data = pref.toJson();
    if (userId != null) data['userId'] = userId;
    if (!await prefs.setString(_prefStorageKey, jsonEncode(data))) {
      throw StateError('Could not save preferences on this device');
    }
  }

  Future<void> clearForSignOut() async {
    _preferenceRevision++;
    _cachedUserId = null;
    _preferences = const UserPreference();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefStorageKey);
    } catch (_) {}
    notifyListeners();
  }
}
