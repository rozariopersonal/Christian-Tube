import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
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
      expect(pref.videoChannelIds, isEmpty);
      expect(pref.shortsChannelIds, isEmpty);
      expect(pref.primaryBibleVersionId, equals('NASB'));
      expect(pref.bibleVersionIds, equals(['NASB']));
      expect(pref.themeMode, equals('system'));
      expect(pref.accentColor, equals('blue'));
      expect(pref.dailyReminderEnabled, isFalse);
      expect(pref.dailyReminderTime, equals('07:00'));
      expect(pref.hasCompletedOnboarding, isFalse);
    });

    test('fromJson and toJson roundtrip preserves all fields', () {
      final json = {
        'languages': ['en', 'ta'],
        'videoChannelIds': ['ch1', 'ch2'],
        'shortsChannelIds': ['ch2', 'ch3'],
        'primaryBibleVersionId': 'TAOBVSI',
        'bibleVersionIds': ['TAOBVSI', 'NASB'],
        'themeMode': 'dark',
        'accentColor': 'emerald',
        'dailyReminderEnabled': true,
        'dailyReminderTime': '06:30',
        'hasCompletedOnboarding': true,
      };

      final pref = UserPreference.fromJson(json);
      expect(pref.languages, equals(['en', 'ta']));
      expect(pref.videoChannelIds, equals(['ch1', 'ch2']));
      expect(pref.shortsChannelIds, equals(['ch2', 'ch3']));
      expect(pref.primaryBibleVersionId, equals('TAOBVSI'));
      expect(pref.bibleVersionIds, equals(['TAOBVSI', 'NASB']));
      expect(pref.themeMode, equals('dark'));
      expect(pref.accentColor, equals('emerald'));
      expect(pref.dailyReminderEnabled, isTrue);
      expect(pref.dailyReminderTime, equals('06:30'));
      expect(pref.hasCompletedOnboarding, isTrue);

      final exported = pref.toJson();
      expect(exported, equals(json));
    });

    test('copyWith updates specified fields cleanly', () {
      const original = UserPreference();
      final updated = original.copyWith(
        languages: ['hi', 'en'],
        primaryBibleVersionId: 'HINERV',
        hasCompletedOnboarding: true,
      );

      expect(updated.languages, equals(['hi', 'en']));
      expect(updated.primaryBibleVersionId, equals('HINERV'));
      expect(updated.hasCompletedOnboarding, isTrue);
      // Unchanged fields remain original
      expect(updated.themeMode, equals(original.themeMode));
      expect(updated.accentColor, equals(original.accentColor));
    });

    test('equality and hashCode work as expected', () {
      const p1 = UserPreference(
        languages: ['en'],
        videoChannelIds: ['c1'],
        primaryBibleVersionId: 'NASB',
      );
      const p2 = UserPreference(
        languages: ['en'],
        videoChannelIds: ['c1'],
        primaryBibleVersionId: 'NASB',
      );
      const p3 = UserPreference(
        languages: ['ta'],
        videoChannelIds: ['c1'],
        primaryBibleVersionId: 'TAOBVSI',
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
