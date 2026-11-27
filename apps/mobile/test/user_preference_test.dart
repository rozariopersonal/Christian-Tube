import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/theme_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/core/models/user_preference.dart';
import 'package:mobile/core/services/user_preference_service.dart';
import 'package:mobile/shared/services/library_languages_controller.dart';
import 'package:mobile/features/bible/services/bible_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserPreference Model', () {
    test('defaults are set correctly', () {
      final pref = UserPreference.defaults();
      expect(pref.languages, equals(['en']));
      expect(pref.primaryBibleVersionId, equals('NASB'));
      expect(pref.themeMode, equals('system'));
      expect(pref.accentColor, equals('blue'));
      expect(pref.defaultPage, equals('feed'));
      expect(pref.lockScreenWordFeedEnabled, isFalse);
      expect(pref.lockScreenRefreshIntervalMinutes, equals(60));
      expect(pref.hasCompletedOnboarding, isFalse);
    });

    test('fromJson and toJson roundtrip preserves all trimmed fields', () {
      final json = {
        'languages': ['en', 'ta'],
        'primaryBibleVersionId': 'TAOBVSI',
        'themeMode': 'dark',
        'accentColor': 'emerald',
        'defaultPage': 'bible',
        'lockScreenWordFeedEnabled': true,
        'lockScreenRefreshIntervalMinutes': 30,
        'hasCompletedOnboarding': true,
      };

      final pref = UserPreference.fromJson({
        ...json,
        // Legacy keys are ignored cleanly
        'videoChannelIds': const ['ch1'],
        'shortsChannelIds': const ['ch2'],
        'channelSelectionsConfigured': true,
        'bibleVersionIds': const ['TAOBVSI', 'NASB'],
        'dailyReminderEnabled': true,
        'dailyReminderTime': '06:30',
      });
      expect(pref.languages, equals(['en', 'ta']));
      expect(pref.primaryBibleVersionId, equals('TAOBVSI'));
      expect(pref.themeMode, equals('dark'));
      expect(pref.accentColor, equals('emerald'));
      expect(pref.defaultPage, equals('bible'));
      expect(pref.lockScreenWordFeedEnabled, isTrue);
      expect(pref.lockScreenRefreshIntervalMinutes, equals(30));
      expect(pref.hasCompletedOnboarding, isTrue);

      final exported = pref.toJson();
      expect(exported, equals(json));
    });

    test('copyWith updates specified fields cleanly', () {
      const original = UserPreference();
      final updated = original.copyWith(
        languages: ['hi', 'en'],
        primaryBibleVersionId: 'HINERV',
        defaultPage: 'shorts',
        hasCompletedOnboarding: true,
      );

      expect(updated.languages, equals(['hi', 'en']));
      expect(updated.primaryBibleVersionId, equals('HINERV'));
      expect(updated.defaultPage, equals('shorts'));
      expect(updated.hasCompletedOnboarding, isTrue);
      // Unchanged fields remain original
      expect(updated.themeMode, equals(original.themeMode));
      expect(updated.accentColor, equals(original.accentColor));
    });

    test('equality and hashCode work as expected', () {
      const p1 = UserPreference(
        languages: ['en'],
        primaryBibleVersionId: 'NASB',
        defaultPage: 'feed',
      );
      const p2 = UserPreference(
        languages: ['en'],
        primaryBibleVersionId: 'NASB',
        defaultPage: 'feed',
      );
      const p3 = UserPreference(
        languages: ['ta'],
        primaryBibleVersionId: 'TAOBVSI',
        defaultPage: 'bible',
      );

      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));
      expect(p1, isNot(equals(p3)));
    });
  });

  group('UserPreferenceService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('canonical accent survives a new theme service', () async {
      final theme = ThemeService();
      await theme.setColorTheme(AppColorTheme.teal);
      final restored = ThemeService();
      await Future<void>.delayed(Duration.zero);
      expect(restored.colorTheme, AppColorTheme.teal);
    });

    test('initializes and saves preferences locally', () async {
      final service = UserPreferenceService.forTesting();
      expect(service.hasCompletedOnboarding, isFalse);

      const newPref = UserPreference(
        languages: ['en', 'ta'],
        primaryBibleVersionId: 'TAOBVSI',
        hasCompletedOnboarding: true,
      );

      await service.savePreferences(newPref, syncWithBackend: false);
      expect(service.hasCompletedOnboarding, isTrue);
      expect(service.preferences.primaryBibleVersionId, equals('TAOBVSI'));

      // Verify persisted in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final savedStr = prefs.getString('ct_user_preferences_v1');
      expect(savedStr, isNotNull);
      final decoded = jsonDecode(savedStr!);
      expect(decoded['primaryBibleVersionId'], equals('TAOBVSI'));
      expect(decoded['hasCompletedOnboarding'], isTrue);
    });

    test('applyToRuntimeControllers propagates to library and Bible settings', () async {
      final service = UserPreferenceService.forTesting();
      const pref = UserPreference(
        languages: ['ta'],
        primaryBibleVersionId: 'TAOBVSI',
        hasCompletedOnboarding: true,
      );

      await service.applyToRuntimeControllers(pref);

      // Verify LibraryLanguagesController has Tamil selected
      expect(LibraryLanguagesController.instance.state.selectedLanguages, contains('ta'));

      // Verify BibleSettingsService has TAOBVSI recorded
      final bibleSettings = await BibleSettingsService().loadSettings();
      expect(bibleSettings.lastVersion, equals('TAOBVSI'));
    });
  });
}
