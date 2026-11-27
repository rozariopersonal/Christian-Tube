import 'package:flutter/foundation.dart';

@immutable
class UserPreference {
  final List<String> languages;
  final String primaryBibleVersionId;
  final String themeMode;
  final String accentColor;
  final String defaultPage;
  final bool lockScreenWordFeedEnabled;
  final int lockScreenRefreshIntervalMinutes;
  final bool hasCompletedOnboarding;

  const UserPreference({
    this.languages = const ['en'],
    this.primaryBibleVersionId = 'NASB',
    this.themeMode = 'system',
    this.accentColor = 'blue',
    this.defaultPage = 'feed',
    this.lockScreenWordFeedEnabled = false,
    this.lockScreenRefreshIntervalMinutes = 60,
    this.hasCompletedOnboarding = false,
  });

  factory UserPreference.defaults() => const UserPreference();

  factory UserPreference.fromJson(Map<String, dynamic> json) {
    List<String> parseStringList(dynamic value, [List<String> fallback = const []]) {
      if (value is List) {
        return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
      return fallback;
    }

    return UserPreference(
      languages: parseStringList(json['languages'], const ['en']),
      primaryBibleVersionId:
          (json['primaryBibleVersionId'] as String?)?.trim().isNotEmpty == true
              ? (json['primaryBibleVersionId'] as String).trim()
              : 'NASB',
      themeMode: (json['themeMode'] as String?) ?? 'system',
      accentColor: (json['accentColor'] as String?) ?? 'blue',
      defaultPage:
          (json['defaultPage'] as String?)?.trim().isNotEmpty == true
              ? (json['defaultPage'] as String).trim()
              : 'feed',
      lockScreenWordFeedEnabled: json['lockScreenWordFeedEnabled'] == true,
      lockScreenRefreshIntervalMinutes:
          (json['lockScreenRefreshIntervalMinutes'] as num?)?.toInt() ?? 60,
      hasCompletedOnboarding: json['hasCompletedOnboarding'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'languages': languages,
      'primaryBibleVersionId': primaryBibleVersionId,
      'themeMode': themeMode,
      'accentColor': accentColor,
      'defaultPage': defaultPage,
      'lockScreenWordFeedEnabled': lockScreenWordFeedEnabled,
      'lockScreenRefreshIntervalMinutes': lockScreenRefreshIntervalMinutes,
      'hasCompletedOnboarding': hasCompletedOnboarding,
    };
  }

  UserPreference copyWith({
    List<String>? languages,
    String? primaryBibleVersionId,
    String? themeMode,
    String? accentColor,
    String? defaultPage,
    bool? lockScreenWordFeedEnabled,
    int? lockScreenRefreshIntervalMinutes,
    bool? hasCompletedOnboarding,
  }) {
    return UserPreference(
      languages: languages ?? this.languages,
      primaryBibleVersionId:
          primaryBibleVersionId ?? this.primaryBibleVersionId,
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
      defaultPage: defaultPage ?? this.defaultPage,
      lockScreenWordFeedEnabled:
          lockScreenWordFeedEnabled ?? this.lockScreenWordFeedEnabled,
      lockScreenRefreshIntervalMinutes:
          lockScreenRefreshIntervalMinutes ?? this.lockScreenRefreshIntervalMinutes,
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserPreference &&
          runtimeType == other.runtimeType &&
          listEquals(languages, other.languages) &&
          primaryBibleVersionId == other.primaryBibleVersionId &&
          themeMode == other.themeMode &&
          accentColor == other.accentColor &&
          defaultPage == other.defaultPage &&
          lockScreenWordFeedEnabled == other.lockScreenWordFeedEnabled &&
          lockScreenRefreshIntervalMinutes ==
              other.lockScreenRefreshIntervalMinutes &&
          hasCompletedOnboarding == other.hasCompletedOnboarding;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(languages),
        primaryBibleVersionId,
        themeMode,
        accentColor,
        defaultPage,
        lockScreenWordFeedEnabled,
        lockScreenRefreshIntervalMinutes,
        hasCompletedOnboarding,
      );
}
