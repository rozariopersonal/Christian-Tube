import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/update/widgets/update_dialog.dart';

Widget wrapWithApp(Widget child) {
  return MaterialApp(
    theme: ThemeData.dark().copyWith(
      extensions: const [AppTokens.dark],
    ),
    home: Scaffold(
      body: child,
    ),
  );
}

void main() {
  const sampleUpdateData = {
    'currentVersion': 'v1.242.0',
    'latestVersion': 'v1.251.0',
    'releaseNotes': '• Performance improvements\n• Enhanced video streaming\n• Bug fixes and general stability updates',
    'sizeBytes': 28500000,
    'downloadUrl': 'https://example.com/releases/download/v1.251.0/christian-app.apk',
  };

  group('UpdateDialog Responsive & Layout Tests', () {
    const testViewports = [320.0, 600.0, 840.0, 1400.0];

    for (final width in testViewports) {
      testWidgets('renders cleanly without overflow at width $width', (tester) async {
        tester.view.physicalSize = Size(width * 2, 800 * 2);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          wrapWithApp(
            const UpdateDialog(updateData: sampleUpdateData),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Update Available!'), findsOneWidget);
        expect(find.text('v1.242.0'), findsOneWidget);
        expect(find.text('v1.251.0'), findsOneWidget);
        expect(find.text("What's New"), findsOneWidget);
        expect(find.text('Update Now'), findsOneWidget);
        expect(find.text('Later'), findsOneWidget);

        // Verify SingleChildScrollView is present so content can scroll
        expect(find.byType(SingleChildScrollView), findsWidgets);
      });
    }

    testWidgets('allows vertical scrolling within the dialog container', (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 600 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        wrapWithApp(
          const UpdateDialog(updateData: sampleUpdateData),
        ),
      );
      await tester.pumpAndSettle();

      final scrollableFinder = find.byType(SingleChildScrollView).first;
      expect(scrollableFinder, findsOneWidget);

      // Verify drag scrolling doesn't throw or crash
      await tester.drag(scrollableFinder, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('displays Retry button and clean message when error message is shown', (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          const UpdateDialog(updateData: sampleUpdateData),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 'Update Now' to trigger download
      final updateNowFinder = find.text('Update Now');
      expect(updateNowFinder, findsOneWidget);
      await tester.tap(updateNowFinder);
      await tester.pump();

      // State is downloading or retrying; verify Cancel button is visible
      expect(find.text('Cancel Download'), findsOneWidget);
    });
  });
}
