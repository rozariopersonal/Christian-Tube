import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/core/models/user_preference.dart';
import 'package:mobile/core/services/user_preference_service.dart';
import 'package:mobile/core/theme/theme_service.dart';
import 'package:mobile/features/auth/auth_service.dart';
import 'package:mobile/features/onboarding/screens/onboarding_screen.dart';
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

  group('OnboardingScreen Widget Tests', () {
    testWidgets('renders step 0 without overflow across breakpoints (320, 600, 840, 1400)',
        (tester) async {
      final authService = AuthService();
      final themeService = ThemeService();

      for (final width in [320.0, 600.0, 840.0, 1400.0]) {
        tester.view.physicalSize = Size(width * 2, 800 * 2);
        tester.view.devicePixelRatio = 2.0;

        await tester.pumpWidget(
          buildTestApp(
            OnboardingScreen(
              authService: authService,
              themeService: themeService,
            ),
            themeService: themeService,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Welcome to'), findsOneWidget);
        expect(find.text('Sign in with Google'), findsOneWidget);
        expect(find.text('Continue as Guest (Setup Offline)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    });

    testWidgets('advances to language selection on tapping Continue as Guest',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;

      final authService = AuthService();
      final themeService = ThemeService();

      await tester.pumpWidget(
        buildTestApp(
          OnboardingScreen(
            authService: authService,
            themeService: themeService,
          ),
          themeService: themeService,
        ),
      );
      await tester.pumpAndSettle();

      // Tap Continue as Guest
      final guestButton = find.text('Continue as Guest (Setup Offline)');
      expect(guestButton, findsOneWidget);
      await tester.ensureVisible(guestButton);
      await tester.pumpAndSettle();
      await tester.tap(guestButton);
      await tester.pumpAndSettle();

      // Should now be on Step 2 of 6: Select Content Languages
      expect(find.text('Select Content Languages'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Tamil'), findsOneWidget);
      expect(tester.takeException(), isNull);

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    });
  });

  group('ContentPreferencesScreen Widget Tests', () {
    testWidgets('renders all 4 tabs across breakpoints without overflow',
        (tester) async {
      final authService = AuthService();
      final themeService = ThemeService();

      for (final width in [320.0, 600.0, 840.0, 1400.0]) {
        tester.view.physicalSize = Size(width * 2, 800 * 2);
        tester.view.devicePixelRatio = 2.0;

        await tester.pumpWidget(
          buildTestApp(
            ContentPreferencesScreen(
              authService: authService,
              themeService: themeService,
            ),
            themeService: themeService,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Content & Feed Preferences'), findsOneWidget);
        expect(find.text('Languages'), findsOneWidget);
        expect(find.text('Video Channels'), findsOneWidget);
        expect(find.text('Shorts Channels'), findsOneWidget);
        expect(find.text('Bible Versions'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    });

    testWidgets('switches tabs smoothly to Bible Versions', (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;

      final authService = AuthService();
      final themeService = ThemeService();

      await tester.pumpWidget(
        buildTestApp(
          ContentPreferencesScreen(
            authService: authService,
            themeService: themeService,
          ),
          themeService: themeService,
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Bible Versions tab
      final bibleTab = find.text('Bible Versions');
      expect(bibleTab, findsOneWidget);
      await tester.ensureVisible(bibleTab);
      await tester.pumpAndSettle();
      await tester.tap(bibleTab);
      await tester.pumpAndSettle();

      expect(find.text('Preferred Bible Translations'), findsOneWidget);
      expect(find.text('NASB'), findsWidgets);
      expect(tester.takeException(), isNull);

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    });

    testWidgets('Shorts Channels tab shows empty state when no channels have shorts', (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;

      final authService = AuthService();
      final themeService = ThemeService();

      await tester.pumpWidget(
        buildTestApp(
          ContentPreferencesScreen(
            authService: authService,
            themeService: themeService,
          ),
          themeService: themeService,
        ),
      );
      await tester.pumpAndSettle();

      final shortsTab = find.text('Shorts Channels');
      expect(shortsTab, findsOneWidget);
      await tester.ensureVisible(shortsTab);
      await tester.pumpAndSettle();
      await tester.tap(shortsTab);
      await tester.pumpAndSettle();

      expect(find.text('Followed Shorts Channels'), findsOneWidget);
      expect(find.text('No channels with shorts found'), findsOneWidget);
      expect(tester.takeException(), isNull);

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    });
  });

  group('Onboarding Bug Fixes & Edge Cases Tests', () {
    test('guest sign in generates unique guest identity without admin privilege', () async {
      final auth = AuthService();
      final user = await auth.signInAsGuest();

      expect(user.email, startsWith('guest_user_'));
      expect(user.email, endsWith('@guest.local'));
      expect(auth.isAdmin, isFalse);
      expect(user.email, isNot(equals('admin@centumacademy.org')));
    });

    test('device onboarding completion flag persists across sign out', () async {
      final prefService = UserPreferenceService.forTesting(
        initial: const UserPreference(hasCompletedOnboarding: true),
      );
      expect(prefService.hasCompletedOnboarding, isTrue);

      await prefService.clearForSignOut();
      // Even though user preferences were reset, device completion flag stays true
      expect(prefService.hasCompletedOnboarding, isTrue);
    });

    testWidgets('renders all onboarding steps across 320px viewport without overflow', (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;

      final authService = AuthService();
      final themeService = ThemeService();

      await tester.pumpWidget(
        buildTestApp(
          OnboardingScreen(
            authService: authService,
            themeService: themeService,
          ),
          themeService: themeService,
        ),
      );
      await tester.pumpAndSettle();

      // Step 0: Welcome
      expect(find.textContaining('Welcome to'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Advance to Step 1: Languages
      final guestButton = find.widgetWithText(ElevatedButton, 'Continue as Guest');
      expect(guestButton, findsOneWidget);
      await tester.tap(guestButton);
      await tester.pumpAndSettle();
      expect(find.text('Select Content Languages'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Advance to Step 2: Video Channels
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Follow Video Channels'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Advance to Step 3: Shorts Channels
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Follow Shorts Channels'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Advance to Step 4: Bible Versions
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Preferred Bible Translations'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Advance to Step 5: Personalization
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Personalize Your App'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Get Started'), findsOneWidget);
      expect(tester.takeException(), isNull);

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    });
  });
}
