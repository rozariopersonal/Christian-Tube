import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/video.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/watch/video_player_screen.dart';

void setSurfaceSize(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

ThemeData testTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      extensions: const [AppTokens.light],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleVideo = Video(
    id: 'test_video_1',
    title: 'Sunday Morning Sermon - Faith and Hope',
    description: 'A powerful sermon about enduring in faith and hope during trials.',
    thumbnailUrl: 'https://example.com/thumb.jpg',
    channelTitle: 'Grace Community',
    channelId: 'channel_1',
    viewCount: 12500,
    publishedAt: DateTime.now().subtract(const Duration(days: 2)),
    duration: '25:30',
  );

  Widget createSubject() {
    return MaterialApp(
      theme: testTheme(),
      home: VideoPlayerScreen(
        videoId: 'test_video_1',
        initialVideo: sampleVideo,
      ),
    );
  }

  group('VideoPlayerScreen Responsive Layout (AGENTS.md)', () {
    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      testWidgets('renders without overflow at $width logical px',
          (tester) async {
        setSurfaceSize(tester, width, width > 800 ? 900 : 700);
        await tester.pumpWidget(createSubject());
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull,
            reason: 'overflow/exception at $width');

        // Top navigation bar with back button is always present
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

        // Video title is rendered
        expect(
          find.text('Sunday Morning Sermon - Faith and Hope'),
          findsOneWidget,
        );

        // Channel title is rendered
        expect(find.text('Grace Community'), findsOneWidget);

        // Action buttons are rendered
        expect(find.text('Like'), findsOneWidget);
        expect(find.text('Clip'), findsOneWidget);
        expect(find.text('Share'), findsOneWidget);
        expect(find.text('Save'), findsOneWidget);
      });
    }

    testWidgets('mobile phone portrait renders compact layout with back button',
        (tester) async {
      setSurfaceSize(tester, 390, 844); // iPhone 12/13/14 portrait
      await tester.pumpWidget(createSubject());
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.text('Grace Community'), findsOneWidget);
    });

    testWidgets('mobile phone landscape enters fullscreen automatically',
        (tester) async {
      setSurfaceSize(tester, 844, 390); // iPhone 12/13/14 landscape (shortestSide=390 < 600)
      await tester.pumpWidget(createSubject());
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // In fullscreen on phone landscape, top AppBar is hidden so video fills screen
      expect(find.byType(AppBar), findsNothing);
    });

    testWidgets('tablet portrait (768x1024) renders two-column layout without overflow',
        (tester) async {
      setSurfaceSize(tester, 768, 1024); // iPad portrait
      await tester.pumpWidget(createSubject());
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Up Next'), findsOneWidget);
    });

    testWidgets('shows two-column layout on expanded desktop (1400px)',
        (tester) async {
      setSurfaceSize(tester, 1400, 900);
      await tester.pumpWidget(createSubject());
      await tester.pump(const Duration(milliseconds: 300));

      // Up Next is rendered in the right sidebar
      expect(find.text('Up Next'), findsOneWidget);
    });

    testWidgets('description card expands and collapses', (tester) async {
      setSurfaceSize(tester, 1000, 800);
      await tester.pumpWidget(createSubject());
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('...more'), findsOneWidget);
      await tester.tap(find.text('...more'));
      await tester.pump();
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('landscape fullscreen transition triggers video resume safely',
        (tester) async {
      setSurfaceSize(tester, 390, 844); // Portrait phone
      await tester.pumpWidget(createSubject());
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AppBar), findsOneWidget);

      // Rotate to phone landscape (enters fullscreen)
      setSurfaceSize(tester, 844, 390);
      await tester.pumpWidget(createSubject());
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AppBar), findsNothing);

      // Advance timers for resume retries
      await tester.pump(const Duration(milliseconds: 1000));
      expect(tester.takeException(), isNull);

      // Rotate back to portrait
      setSurfaceSize(tester, 390, 844);
      await tester.pumpWidget(createSubject());
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AppBar), findsOneWidget);

      // Advance timers for portrait transition resume retries
      await tester.pump(const Duration(milliseconds: 1000));
      expect(tester.takeException(), isNull);
    });
  });
}
