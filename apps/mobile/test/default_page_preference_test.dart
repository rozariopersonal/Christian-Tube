import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/core/engines/active_engine.g.dart';
import 'package:mobile/core/models/user_preference.dart';
import 'package:mobile/core/services/user_preference_service.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/core/theme/theme_service.dart';
import 'package:mobile/features/profile/settings_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UserPreference defaultPage', () {
    test('defaults to feed and round-trips via JSON and copyWith', () {
      const pref = UserPreference();
      expect(pref.defaultPage, 'feed');

      final updated = pref.copyWith(defaultPage: 'bible');
      expect(updated.defaultPage, 'bible');
      expect(updated == pref, isFalse);

      final decoded = UserPreference.fromJson(updated.toJson());
      expect(decoded.defaultPage, 'bible');
      expect(decoded, updated);

      final blankFallback = UserPreference.fromJson(const {'defaultPage': '  '});
      expect(blankFallback.defaultPage, 'feed');
    });

    test('resolveRoutePath maps canonical page ids to GoRouter paths', () {
      expect(UserPreferenceService.resolveRoutePath(null), '/feed');
      expect(UserPreferenceService.resolveRoutePath('feed'), '/feed');
      expect(UserPreferenceService.resolveRoutePath('shorts'), '/shorts');
      expect(UserPreferenceService.resolveRoutePath('bible'), '/bible');
      expect(UserPreferenceService.resolveRoutePath('library'), '/library');
      expect(UserPreferenceService.resolveRoutePath('books'), '/library');
      expect(UserPreferenceService.resolveRoutePath('audio'), '/audio');
      expect(
        UserPreferenceService.resolveRoutePath('words'),
        kMicroFeedEnabled ? '/words' : '/feed',
      );
      expect(UserPreferenceService.resolveRoutePath('unknown'), '/feed');
    });

    test('setDefaultPage updates service state and persists locally', () async {
      final service = UserPreferenceService.forTesting();
      expect(service.defaultRoutePath, '/feed');

      await service.setDefaultPage('shorts', syncWithBackend: false);
      expect(service.preferences.defaultPage, 'shorts');
      expect(service.defaultRoutePath, '/shorts');

      await service.setDefaultPage('bible', syncWithBackend: false);
      expect(service.preferences.defaultPage, 'bible');
      expect(service.defaultRoutePath, '/bible');
    });
  });

  group('SettingsScreen Default Page on Open', () {
    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      testWidgets('renders without overflow at ${width.toInt()}dp', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final themeService = ThemeService();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: [AppTokens.light],
            ),
            home: SettingsScreen(themeService: themeService),
          ),
        );
        await tester.pump();

        final promptFinder = find.text(
          'Choose which page opens first when you launch the app:',
        );
        await tester.scrollUntilVisible(
          promptFinder,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();

        expect(promptFinder, findsOneWidget);
        expect(find.text('Videos'), findsOneWidget);
        expect(find.text('Shorts'), findsOneWidget);
        expect(find.text('Bible'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
