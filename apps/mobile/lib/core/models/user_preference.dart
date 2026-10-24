import 'package:flutter/foundation.dart';

@immutable
class UserPreference {
  final List<String> languages;
  final List<String> videoChannelIds;
  final List<String> shortsChannelIds;
  final String primaryBibleVersionId;
  final List<String> bibleVersionIds;
  final String themeMode;
  final String accentColor;
  final bool dailyReminderEnabled;
  final String dailyReminderTime;
  final bool lockScreenWordFeedEnabled;
  final int lockScreenRefreshIntervalMinutes;
  final bool hasCompletedOnboarding;

  const UserPreference({
    this.languages = const ['en'],
    this.videoChannelIds = const [],
    this.shortsChannelIds = const [],
    this.primaryBibleVersionId = 'NASB',
    this.bibleVersionIds = const ['NASB'],
    this.themeMode = 'system',
    this.accentColor = 'blue',
    this.dailyReminderEnabled = false,
    this.dailyReminderTime = '07:00',
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
      videoChannelIds: parseStringList(json['videoChannelIds']),
      shortsChannelIds: parseStringList(json['shortsChannelIds']),
      primaryBibleVersionId:
          (json['primaryBibleVersionId'] as String?)?.trim().isNotEmpty == true
              ? (json['primaryBibleVersionId'] as String).trim()
              : 'NASB',
      bibleVersionIds: parseStringList(json['bibleVersionIds'], const ['NASB']),
      themeMode: (json['themeMode'] as String?) ?? 'system',
      accentColor: (json['accentColor'] as String?) ?? 'blue',
      dailyReminderEnabled: json['dailyReminderEnabled'] == true,
      dailyReminderTime: (json['dailyReminderTime'] as String?) ?? '07:00',
      lockScreenWordFeedEnabled: json['lockScreenWordFeedEnabled'] == true,
      lockScreenRefreshIntervalMinutes:
          (json['lockScreenRefreshIntervalMinutes'] as num?)?.toInt() ?? 60,
      hasCompletedOnboarding: json['hasCompletedOnboarding'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'languages': languages,
      'videoChannelIds': videoChannelIds,
      'shortsChannelIds': shortsChannelIds,
      'primaryBibleVersionId': primaryBibleVersionId,
      'bibleVersionIds': bibleVersionIds,
      'themeMode': themeMode,
      'accentColor': accentColor,
      'dailyReminderEnabled': dailyReminderEnabled,
      'dailyReminderTime': dailyReminderTime,
      'lockScreenWordFeedEnabled': lockScreenWordFeedEnabled,
      'lockScreenRefreshIntervalMinutes': lockScreenRefreshIntervalMinutes,
      'hasCompletedOnboarding': hasCompletedOnboarding,
    };
  }

  UserPreference copyWith({
    List<String>? languages,
    List<String>? videoChannelIds,
    List<String>? shortsChannelIds,
    String? primaryBibleVersionId,
    List<String>? bibleVersionIds,
    String? themeMode,
    String? accentColor,
    bool? dailyReminderEnabled,
    String? dailyReminderTime,
    bool? lockScreenWordFeedEnabled,
    int? lockScreenRefreshIntervalMinutes,
    bool? hasCompletedOnboarding,
  }) {
    return UserPreference(
      languages: languages ?? this.languages,
      videoChannelIds: videoChannelIds ?? this.videoChannelIds,
      shortsChannelIds: shortsChannelIds ?? this.shortsChannelIds,
      primaryBibleVersionId:
          primaryBibleVersionId ?? this.primaryBibleVersionId,
      bibleVersionIds: bibleVersionIds ?? this.bibleVersionIds,
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
      dailyReminderEnabled: dailyReminderEnabled ?? this.dailyReminderEnabled,
      dailyReminderTime: dailyReminderTime ?? this.dailyReminderTime,
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
          listEquals(videoChannelIds, other.videoChannelIds) &&
          listEquals(shortsChannelIds, other.shortsChannelIds) &&
          primaryBibleVersionId == other.primaryBibleVersionId &&
          listEquals(bibleVersionIds, other.bibleVersionIds) &&
          themeMode == other.themeMode &&
          accentColor == other.accentColor &&
          dailyReminderEnabled == other.dailyReminderEnabled &&
          dailyReminderTime == other.dailyReminderTime &&
          lockScreenWordFeedEnabled == other.lockScreenWordFeedEnabled &&
          lockScreenRefreshIntervalMinutes ==
              other.lockScreenRefreshIntervalMinutes &&
          hasCompletedOnboarding == other.hasCompletedOnboarding;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(languages),
        Object.hashAll(videoChannelIds),
        Object.hashAll(shortsChannelIds),
        primaryBibleVersionId,
        Object.hashAll(bibleVersionIds),
        themeMode,
        accentColor,
        dailyReminderEnabled,
        dailyReminderTime,
        lockScreenWordFeedEnabled,
        lockScreenRefreshIntervalMinutes,
        hasCompletedOnboarding,
      );
}
