import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/models/user_preference.dart';
import '../../../core/services/user_preference_service.dart';
import '../../../shared/ui/language_meta.dart';
import '../../auth/auth_service.dart';
import '../../channels/channel_service.dart';
import '../../engines/scripture/models/bible_version_meta.dart';
import '../../engines/scripture/services/bible_download_manager.dart';

/// Immutable UI and behavioral state for single-screen Quick Start onboarding.
@immutable
class OnboardingState {
  static const Object _unset = Object();

  final Set<String> selectedLanguages;
  final String primaryBibleVersionId;
  final bool isLoadingChannels;
  final bool channelsLoaded;
  final int popularChannelsCount;
  final bool isSigningIn;
  final bool isCheckingReturningUser;
  final bool isSaving;
  final bool isReturningUser;
  final String? errorMessage;
  final String? pendingNavigationRoute;

  const OnboardingState({
    this.selectedLanguages = const {'en'},
    this.primaryBibleVersionId = 'NASB',
    this.isLoadingChannels = false,
    this.channelsLoaded = false,
    this.popularChannelsCount = 0,
    this.isSigningIn = false,
    this.isCheckingReturningUser = false,
    this.isSaving = false,
    this.isReturningUser = false,
    this.errorMessage,
    this.pendingNavigationRoute,
  });

  bool get isBusy => isSigningIn || isCheckingReturningUser || isSaving;

  OnboardingState copyWith({
    Set<String>? selectedLanguages,
    String? primaryBibleVersionId,
    bool? isLoadingChannels,
    bool? channelsLoaded,
    int? popularChannelsCount,
    bool? isSigningIn,
    bool? isCheckingReturningUser,
    bool? isSaving,
    bool? isReturningUser,
    Object? errorMessage = _unset,
    Object? pendingNavigationRoute = _unset,
  }) {
    return OnboardingState(
      selectedLanguages: selectedLanguages != null
          ? Set<String>.unmodifiable(selectedLanguages)
          : this.selectedLanguages,
      primaryBibleVersionId:
          primaryBibleVersionId ?? this.primaryBibleVersionId,
      isLoadingChannels: isLoadingChannels ?? this.isLoadingChannels,
      channelsLoaded: channelsLoaded ?? this.channelsLoaded,
      popularChannelsCount: popularChannelsCount ?? this.popularChannelsCount,
      isSigningIn: isSigningIn ?? this.isSigningIn,
      isCheckingReturningUser:
          isCheckingReturningUser ?? this.isCheckingReturningUser,
      isSaving: isSaving ?? this.isSaving,
      isReturningUser: isReturningUser ?? this.isReturningUser,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      pendingNavigationRoute: identical(pendingNavigationRoute, _unset)
          ? this.pendingNavigationRoute
          : pendingNavigationRoute as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is OnboardingState &&
            runtimeType == other.runtimeType &&
            setEquals(selectedLanguages, other.selectedLanguages) &&
            primaryBibleVersionId == other.primaryBibleVersionId &&
            isLoadingChannels == other.isLoadingChannels &&
            channelsLoaded == other.channelsLoaded &&
            popularChannelsCount == other.popularChannelsCount &&
            isSigningIn == other.isSigningIn &&
            isCheckingReturningUser == other.isCheckingReturningUser &&
            isSaving == other.isSaving &&
            isReturningUser == other.isReturningUser &&
            errorMessage == other.errorMessage &&
            pendingNavigationRoute == other.pendingNavigationRoute;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(selectedLanguages),
        primaryBibleVersionId,
        isLoadingChannels,
        channelsLoaded,
        popularChannelsCount,
        isSigningIn,
        isCheckingReturningUser,
        isSaving,
        isReturningUser,
        errorMessage,
        pendingNavigationRoute,
      );
}

/// Coordinates Quick Start onboarding state, language -> Bible derivation,
/// optional Google Sign-In returning-user restore, channel auto-follow seeding,
/// and preference persistence.
class OnboardingController extends ChangeNotifier {
  static const int _maxAutoFollowChannels = 4;
  static const String _fallbackBibleVersionId = 'NASB';

  final AuthService _authService;
  final ChannelService _channelService;
  final UserPreferenceService _preferenceService;
  final bool _wasSignedOutOnEntry;

  OnboardingState _state = const OnboardingState();
  bool _disposed = false;
  bool _userEditedLanguages = false;
  bool _isHandlingSignIn = false;
  String? _checkedUserId;
  Future<void>? _inFlightReturningCheck;
  Future<void>? _inFlightChannelsLoad;

  OnboardingController({
    required AuthService authService,
    ChannelService? channelService,
    UserPreferenceService? preferenceService,
  })  : _authService = authService,
        _channelService = channelService ?? ChannelService(),
        _preferenceService = preferenceService ?? UserPreferenceService(),
        _wasSignedOutOnEntry = !authService.isAuthenticated {
    _authService.addListener(_onAuthChanged);
  }

  OnboardingState get state => _state;

  /// All user-selectable content languages (excluding `'all'`).
  List<LanguageMeta> get availableLanguages =>
      LanguageMeta.supportedLanguages.values
          .where((l) => l.code.toLowerCase() != 'all')
          .toList(growable: false);

  /// Initializes channel preloading (non-blocking), pre-fills any existing
  /// local preferences, and checks returning-user cloud state only when the
  /// user entered signed out.
  Future<void> initialize() async {
    _prefillFromPreferences(_preferenceService.preferences);
    final channelsFuture = _loadChannels();
    _inFlightChannelsLoad = channelsFuture;
    unawaited(channelsFuture);
    if (_authService.isAuthenticated && _wasSignedOutOnEntry) {
      await checkReturningUser();
    }
  }

  void _prefillFromPreferences(UserPreference pref) {
    if (_userEditedLanguages || pref.languages.isEmpty) return;
    final restoredLanguages = pref.languages
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty && e != 'all')
        .toSet();
    if (restoredLanguages.isEmpty) return;
    final derivedBible = derivePrimaryBibleVersion(
      restoredLanguages,
      current: pref.primaryBibleVersionId,
    );
    _updateState(
      _state.copyWith(
        selectedLanguages: restoredLanguages,
        primaryBibleVersionId: derivedBible,
      ),
    );
  }

  void _onAuthChanged() {
    if (_disposed || _isHandlingSignIn || !_wasSignedOutOnEntry) return;
    final userId = _authService.currentUser?.id;
    if (_authService.isAuthenticated &&
        userId != null &&
        userId != _checkedUserId &&
        _inFlightReturningCheck == null) {
      unawaited(checkReturningUser());
    }
  }

  Future<void> _loadChannels() async {
    if (_channelService.channels.isNotEmpty) {
      _updateState(
        _state.copyWith(
          isLoadingChannels: false,
          channelsLoaded: true,
          popularChannelsCount:
              math.min(_maxAutoFollowChannels, _channelService.channels.length),
        ),
      );
      return;
    }

    _updateState(_state.copyWith(isLoadingChannels: true));
    try {
      await _channelService.fetchChannels();
    } catch (e) {
      debugPrint('Onboarding channel preload failed (continuing offline): $e');
    }

    _updateState(
      _state.copyWith(
        isLoadingChannels: false,
        channelsLoaded: _channelService.channels.isNotEmpty,
        popularChannelsCount:
            math.min(_maxAutoFollowChannels, _channelService.channels.length),
      ),
    );
  }

  /// Toggles a content language chip, always preserving at least one selection,
  /// and automatically derives the matching primary Bible translation.
  ///
  /// Returns `false` if the tap was ignored because it was the last selected
  /// language.
  bool toggleLanguage(String languageCode) {
    final normalized = languageCode.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'all') return false;

    final current = Set<String>.from(_state.selectedLanguages);
    if (current.contains(normalized)) {
      if (current.length <= 1) {
        return false;
      }
      current.remove(normalized);
    } else {
      current.add(normalized);
    }

    _userEditedLanguages = true;
    final derivedBible = derivePrimaryBibleVersion(
      current,
      current: _state.primaryBibleVersionId,
    );
    _updateState(
      _state.copyWith(
        selectedLanguages: current,
        primaryBibleVersionId: derivedBible,
        errorMessage: null,
      ),
    );
    return true;
  }

  /// Derives the primary Bible version ID from [languages] using
  /// [BibleDownloadManager.catalog], keeping [current] if it still matches any
  /// selected language, and falling back to `'NASB'` when no catalog version
  /// matches.
  static String derivePrimaryBibleVersion(
    Set<String> languages, {
    String? current,
  }) {
    final normalized = languages
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (normalized.isEmpty) return _fallbackBibleVersionId;

    if (current != null && current.trim().isNotEmpty) {
      final upperCurrent = current.trim().toUpperCase();
      for (final meta in BibleDownloadManager.catalog) {
        if (meta.id.toUpperCase() == upperCurrent &&
            normalized.any((lang) => _versionMatchesLanguage(meta, lang))) {
          return meta.id;
        }
      }
    }

    for (final lang in normalized) {
      for (final meta in BibleDownloadManager.catalog) {
        if (_versionMatchesLanguage(meta, lang)) {
          return meta.id;
        }
      }
    }

    return _fallbackBibleVersionId;
  }

  static bool _versionMatchesLanguage(
    BibleVersionMeta meta,
    String normalizedLangCode,
  ) {
    if (meta.languageCode.trim().toLowerCase() == normalizedLangCode) {
      return true;
    }
    return LanguageMeta.canonicalCode(meta.language) == normalizedLangCode;
  }

  /// Triggers Google Sign-In and immediately checks whether the signed-in user
  /// already completed onboarding in the cloud.
  Future<bool> signInWithGoogle() async {
    if (_state.isBusy) return false;
    _isHandlingSignIn = true;
    _updateState(_state.copyWith(isSigningIn: true, errorMessage: null));

    try {
      final user = await _authService.signInWithGoogle();
      if (user == null) {
        _updateState(
          _state.copyWith(
            isSigningIn: false,
            errorMessage: _authService.lastError,
          ),
        );
        return false;
      }

      _checkedUserId = user.id;
      await _performReturningUserCheck();
      _updateState(_state.copyWith(isSigningIn: false));
      return true;
    } catch (e) {
      debugPrint('Onboarding Google sign-in error: $e');
      _updateState(
        _state.copyWith(
          isSigningIn: false,
          errorMessage: 'Sign-in failed. You can still start exploring.',
        ),
      );
      return false;
    } finally {
      _isHandlingSignIn = false;
    }
  }

  /// Checks cloud preferences and subscriptions for an authenticated user and
  /// signals immediate navigation if `hasCompletedOnboarding == true`.
  Future<void> checkReturningUser() {
    if (!_authService.isAuthenticated) return Future.value();
    if (_inFlightReturningCheck != null) return _inFlightReturningCheck!;

    final future = _performReturningUserCheck();
    _inFlightReturningCheck = future;
    return future.whenComplete(() {
      if (identical(_inFlightReturningCheck, future)) {
        _inFlightReturningCheck = null;
      }
    });
  }

  Future<void> _performReturningUserCheck() async {
    _checkedUserId = _authService.currentUser?.id;
    _updateState(_state.copyWith(isCheckingReturningUser: true));

    try {
      final pref = await _preferenceService.fetchPreferences(auth: _authService);
      await _channelService.loadSubscriptions();

      if (_wasSignedOutOnEntry && pref.hasCompletedOnboarding) {
        await _preferenceService.markOnboardingComplete(
          auth: _authService,
          syncWithBackend: false,
        );
        _updateState(
          _state.copyWith(
            isCheckingReturningUser: false,
            isReturningUser: true,
            pendingNavigationRoute: _preferenceService.defaultRoutePath,
          ),
        );
        return;
      }

      _prefillFromPreferences(pref);
    } catch (e) {
      debugPrint('Error checking returning user onboarding state: $e');
    }

    _updateState(_state.copyWith(isCheckingReturningUser: false));
  }

  /// Completes Quick Start: ensures >= 1 language, derives primary Bible
  /// version, auto-follows popular channels (non-blocking if offline), persists
  /// [UserPreference], and signals navigation to [UserPreferenceService.defaultRoutePath].
  Future<bool> startExploring() async {
    if (_state.isSaving) return false;
    _updateState(_state.copyWith(isSaving: true, errorMessage: null));

    try {
      final languages = _state.selectedLanguages.isEmpty
          ? const {'en'}
          : _state.selectedLanguages;
      final primaryBible = derivePrimaryBibleVersion(
        languages,
        current: _state.primaryBibleVersionId,
      );

      if (_channelService.channels.isEmpty && _inFlightChannelsLoad != null) {
        try {
          await _inFlightChannelsLoad!.timeout(
            const Duration(seconds: 2),
            onTimeout: () {},
          );
        } catch (e) {
          debugPrint('Onboarding channel preload wait failed (continuing): $e');
        }
      }

      if (_channelService.subscribedChannelIds.isEmpty &&
          _channelService.channels.isNotEmpty) {
        final popularIds = _channelService.channels
            .take(_maxAutoFollowChannels)
            .map((c) => c.id)
            .toSet();
        if (popularIds.isNotEmpty) {
          await _channelService.saveChannelSelections(
            {..._channelService.subscribedChannelIds},
            {..._channelService.subscribedChannelIds, ...popularIds},
          );
        }
      }

      final UserPreference finalPref = _preferenceService.preferences.copyWith(
        languages: languages.toList(growable: false),
        primaryBibleVersionId: primaryBible,
        hasCompletedOnboarding: true,
      );

      await _preferenceService.savePreferences(
        finalPref,
        auth: _authService,
        syncAll: _authService.isAuthenticated,
      );

      _updateState(
        _state.copyWith(
          isSaving: false,
          primaryBibleVersionId: primaryBible,
          pendingNavigationRoute: _preferenceService.defaultRoutePath,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Error completing quick start onboarding: $e');
      _updateState(
        _state.copyWith(
          isSaving: false,
          errorMessage: 'Could not save setup. Please try again.',
        ),
      );
      return false;
    }
  }

  /// Marks any pending navigation route as handled by the view.
  void consumeNavigation() {
    if (_state.pendingNavigationRoute == null) return;
    _updateState(_state.copyWith(pendingNavigationRoute: null));
  }

  /// Clears any displayed error banner.
  void clearError() {
    if (_state.errorMessage == null) return;
    _updateState(_state.copyWith(errorMessage: null));
  }

  void _updateState(OnboardingState next) {
    if (_disposed || next == _state) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _authService.removeListener(_onAuthChanged);
    super.dispose();
  }
}
