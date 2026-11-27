import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/core/models/channel.dart';
import 'package:mobile/core/models/user_preference.dart';
import 'package:mobile/core/services/user_preference_service.dart';
import 'package:mobile/core/theme/theme_service.dart';
import 'package:mobile/features/auth/auth_service.dart';
import 'package:mobile/features/channels/channel_service.dart';
import 'package:mobile/features/profile/screens/content_preferences_screen.dart';

Widget buildTestApp(Widget child, {ThemeService? themeService}) {
  final ts = themeService ?? ThemeService();
  return AnimatedBuilder(
    animation: ts,
    builder: (context, _) {
      return MaterialApp(
        theme: ts.lightTheme,
        darkTheme: ts.darkTheme,
        themeMode: ts.themeMode,
        home: child,
      );
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ContentPreferencesScreen Widget Tests', () {
    testWidgets('renders all 3 tabs across breakpoints without overflow',
        (tester) async {
      final authService = AuthService(registerAsShared: false, skipInitialLoad: true);
      final themeService = ThemeService();
      final prefService = UserPreferenceService.forTesting();
      final channelService = ChannelService.forTesting();
      addTearDown(() {
        authService.dispose();
        themeService.dispose();
        prefService.dispose();
        channelService.dispose();
      });

      for (final width in [320.0, 600.0, 840.0, 1400.0]) {
        tester.view.physicalSize = Size(width * 2, 800 * 2);
        tester.view.devicePixelRatio = 2.0;

        await tester.pumpWidget(
          buildTestApp(
            ContentPreferencesScreen(
              authService: authService,
              themeService: themeService,
              preferenceService: prefService,
              channelService: channelService,
            ),
            themeService: themeService,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Content & Feed Preferences'), findsOneWidget);
        expect(find.text('Languages'), findsOneWidget);
        expect(find.text('Channels'), findsOneWidget);
        expect(find.text('Bible Version'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    });

    testWidgets('Languages tab toggles selections and requires at least one language',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final authService = AuthService(registerAsShared: false, skipInitialLoad: true);
      final themeService = ThemeService();
      final prefService = UserPreferenceService.forTesting(
        initial: const UserPreference(languages: ['en']),
      );
      final channelService = ChannelService.forTesting();
      addTearDown(() {
        authService.dispose();
        themeService.dispose();
        prefService.dispose();
        channelService.dispose();
      });

      await tester.pumpWidget(
        buildTestApp(
          ContentPreferencesScreen(
            authService: authService,
            themeService: themeService,
            preferenceService: prefService,
            channelService: channelService,
          ),
          themeService: themeService,
        ),
      );
      await tester.pumpAndSettle();

      // Unchecking the sole language shows a guard snackbar and keeps 'en'.
      await tester.tap(find.widgetWithText(CheckboxListTile, 'English'));
      await tester.pumpAndSettle();
      expect(find.text('At least one language is required'), findsOneWidget);
      expect(prefService.preferences.languages, equals(['en']));

      // Selecting Tamil adds 'ta'.
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Tamil'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(prefService.preferences.languages, containsAll(['en', 'ta']));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Channels tab shows empty state and manages unified ChannelService follows',
        (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final authService = AuthService(registerAsShared: false, skipInitialLoad: true);
      final themeService = ThemeService();
      final prefService = UserPreferenceService.forTesting();
      final channelService = ChannelService.forTesting();
      addTearDown(() {
        authService.dispose();
        themeService.dispose();
        prefService.dispose();
        channelService.dispose();
      });

      await tester.pumpWidget(
        buildTestApp(
          ContentPreferencesScreen(
            authService: authService,
            themeService: themeService,
            preferenceService: prefService,
            channelService: channelService,
          ),
          themeService: themeService,
        ),
      );
      await tester.pumpAndSettle();

      final channelsTab = find.text('Channels');
      expect(channelsTab, findsOneWidget);
      await tester.ensureVisible(channelsTab);
      await tester.pumpAndSettle();
      await tester.tap(channelsTab);
      await tester.pumpAndSettle();

      expect(find.text('Followed Channels'), findsOneWidget);
      expect(find.text('No channels found'), findsOneWidget);

      // Seed channels into unified ChannelService and verify All / Clear / Toggle.
      channelService.setChannelsForTesting([
        const Channel(id: 'ch_1', title: 'Grace Fellowship', avatarUrl: ''),
        const Channel(id: 'ch_2', title: 'Daily Scripture', avatarUrl: '', hasShorts: true),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Grace Fellowship'), findsOneWidget);
      expect(find.text('Daily Scripture'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'All'));
      await tester.pumpAndSettle();
      expect(channelService.subscribedChannelIds, containsAll(['ch_1', 'ch_2']));

      await tester.tap(find.widgetWithText(TextButton, 'Clear'));
      await tester.pumpAndSettle();
      expect(channelService.subscribedChannelIds, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Bible Version tab selects a single primary translation without multi-checkboxes',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final authService = AuthService(registerAsShared: false, skipInitialLoad: true);
      final themeService = ThemeService();
      final prefService = UserPreferenceService.forTesting(
        initial: const UserPreference(
          languages: ['en'],
          primaryBibleVersionId: 'NASB',
        ),
      );
      final channelService = ChannelService.forTesting();
      addTearDown(() {
        authService.dispose();
        themeService.dispose();
        prefService.dispose();
        channelService.dispose();
      });

      await tester.pumpWidget(
        buildTestApp(
          ContentPreferencesScreen(
            authService: authService,
            themeService: themeService,
            preferenceService: prefService,
            channelService: channelService,
          ),
          themeService: themeService,
        ),
      );
      await tester.pumpAndSettle();

      final bibleTab = find.text('Bible Version');
      expect(bibleTab, findsOneWidget);
      await tester.ensureVisible(bibleTab);
      await tester.pumpAndSettle();
      await tester.tap(bibleTab);
      await tester.pumpAndSettle();

      expect(find.text('Primary Bible Version'), findsOneWidget);
      expect(find.text('PRIMARY'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('NASB'), findsOneWidget);

      // Selecting KJV updates primaryBibleVersionId to KJV.
      await tester.tap(find.text('KJV'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(prefService.preferences.primaryBibleVersionId, equals('KJV'));
      expect(find.text('PRIMARY'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('UserPreferenceService Onboarding Flag Tests', () {
    test('device onboarding completion flag persists across sign out', () async {
      final prefService = UserPreferenceService.forTesting(
        initial: const UserPreference(hasCompletedOnboarding: true),
      );
      expect(prefService.hasCompletedOnboarding, isTrue);

      await prefService.clearForSignOut();
      expect(prefService.hasCompletedOnboarding, isTrue);
    });
  });
}
