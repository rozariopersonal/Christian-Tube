import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/core/models/user.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/auth/auth_service.dart';
import 'package:mobile/features/auth/services/auth_token_store.dart';
import 'package:mobile/shared/ui/sync_avatar_button.dart';

Widget _wrap({
  required Widget child,
  required bool dark,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: (dark ? ThemeData.dark() : ThemeData.light()).copyWith(
      extensions: [dark ? AppTokens.dark : AppTokens.light],
    ),
    builder: (context, inner) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: inner!,
    ),
    home: Scaffold(
      appBar: AppBar(
        actions: [child],
      ),
      body: const SizedBox.expand(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthTokenStore.instance.resetForTesting();
  });

  group('SyncAvatarButton & AccountSyncPanel responsive widget tests', () {
    const viewports = [320.0, 600.0, 840.0, 1400.0];

    for (final width in viewports) {
      for (final dark in [false, true]) {
        testWidgets(
          'renders expired badge and adaptive panel without overflow at ${width}px (${dark ? 'dark' : 'light'})',
          (tester) async {
            tester.view.physicalSize = Size(width * 2, 800 * 2);
            tester.view.devicePixelRatio = 2.0;
            addTearDown(() {
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
            });

            final auth = AuthService(
              registerAsShared: false,
              skipInitialLoad: true,
              initialUserForTesting: const User(
                id: 'u_1',
                email: 'arul.rozario4@gmail.com',
                displayName: 'Arul Rozario',
                isGuest: false,
              ),
              initialSessionExpiredForTesting: true,
            );
            addTearDown(auth.dispose);

            await tester.pumpWidget(
              _wrap(
                dark: dark,
                textScale: 1.4,
                child: SyncAvatarButton(authService: auth),
              ),
            );
            await tester.pump();

            expect(find.byIcon(Icons.sync_problem), findsOneWidget);
            expect(
              find.bySemanticsLabel('Account. Sync paused, tap to resume.'),
              findsOneWidget,
            );

            await tester.tap(find.byKey(const ValueKey('btn_profile')));
            await tester.pumpAndSettle();

            expect(find.text('Resume sync'), findsOneWidget);
            expect(
              find.text('Sync paused · Local changes are saved on this device'),
              findsOneWidget,
            );

            if (width < 600) {
              expect(find.byType(BottomSheet), findsOneWidget);
            } else {
              expect(find.byType(AlertDialog), findsOneWidget);
            }

            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('hides sync_problem badge when session is healthy', (tester) async {
      final auth = AuthService(
        registerAsShared: false,
        skipInitialLoad: true,
        initialUserForTesting: const User(
          id: 'u_1',
          email: 'arul@example.com',
          displayName: 'Arul',
          isGuest: false,
        ),
        initialSessionExpiredForTesting: false,
      );
      addTearDown(auth.dispose);

      await tester.pumpWidget(
        _wrap(
          dark: false,
          child: SyncAvatarButton(authService: auth),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.sync_problem), findsNothing);
      expect(find.text('AR'), findsOneWidget);
    });
  });
}
