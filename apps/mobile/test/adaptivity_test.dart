import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/layout/adaptivity.dart';
import 'package:mobile/core/layout/content_width.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/feed/video_feed_screen.dart';

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
  group('ScreenClass.ofWidth', () {
    test('compact below 600', () {
      expect(ScreenClass.ofWidth(320), ScreenClass.compact);
      expect(ScreenClass.ofWidth(599), ScreenClass.compact);
    });

    test('medium 600-839', () {
      expect(ScreenClass.ofWidth(600), ScreenClass.medium);
      expect(ScreenClass.ofWidth(839), ScreenClass.medium);
    });

    test('expanded >= 840', () {
      expect(ScreenClass.ofWidth(840), ScreenClass.expanded);
      expect(ScreenClass.ofWidth(1400), ScreenClass.expanded);
    });
  });

  group('resolveNavMode', () {
    AppNavMode resolve({
      required double width,
      bool landscape = false,
      bool shortPlaying = false,
      bool hidden = false,
      bool watch = false,
      bool web = false,
    }) =>
        resolveNavMode(
          width: width,
          isLandscape: landscape,
          isShortPlaying: shortPlaying,
          isExplicitlyHidden: hidden,
          isWatchRoute: watch,
          isWeb: web,
        );

    test('compact portrait keeps the bottom bar', () {
      expect(resolve(width: 320), AppNavMode.bottomBar);
      expect(resolve(width: 599), AppNavMode.bottomBar);
    });

    test('compact landscape shows the rail so navigation stays reachable', () {
      expect(resolve(width: 599, landscape: true), AppNavMode.rail);
    });

    test('medium and expanded always use the rail', () {
      expect(resolve(width: 600), AppNavMode.rail);
      expect(resolve(width: 839), AppNavMode.rail);
      expect(resolve(width: 840), AppNavMode.rail);
      expect(resolve(width: 1400), AppNavMode.rail);
    });

    test('landscape watch fullscreens off-web but keeps rail on web', () {
      expect(resolve(width: 840, landscape: true, watch: true, web: false),
          AppNavMode.hidden);
      expect(resolve(width: 840, landscape: true, watch: true, web: true),
          AppNavMode.rail);
    });

    test('explicit hides and shorts playback always suppress navigation', () {
      expect(resolve(width: 320, hidden: true), AppNavMode.hidden);
      expect(resolve(width: 1400, shortPlaying: true), AppNavMode.hidden);
    });
  });

  group('adaptiveContentMaxWidth', () {
    test('fills the viewport up to the content ceiling', () {
      expect(adaptiveContentMaxWidth(320), 320);
      expect(adaptiveContentMaxWidth(600), 600);
      expect(adaptiveContentMaxWidth(840), 840);
      expect(adaptiveContentMaxWidth(kContentMaxWidth), kContentMaxWidth);
    });

    test('grows proportionally on wide displays', () {
      expect(adaptiveContentMaxWidth(1080), closeTo(1080, 1));
      expect(adaptiveContentMaxWidth(1920), closeTo(1500, 1));
      expect(adaptiveContentMaxWidth(2000), closeTo(1540, 1));
    });

    test('caps on ultra-wide displays', () {
      expect(adaptiveContentMaxWidth(3440), kUltraContentMaxWidth);
      expect(adaptiveContentMaxWidth(3840), kUltraContentMaxWidth);
      expect(adaptiveContentMaxWidth(5120), kUltraContentMaxWidth);
    });

    test('never exceeds the absolute ceiling', () {
      for (final w in [1920.0, 2560.0, 3440.0, 3840.0, 5120.0]) {
        expect(adaptiveContentMaxWidth(w), lessThanOrEqualTo(kUltraContentMaxWidth));
      }
    });
  });

  group('MaxWidthBox', () {
    const childKey = Key('max-width-box-child');

    Widget subject() => const Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: double.infinity,
            height: 600,
            child: MaxWidthBox(
              child: SizedBox(key: childKey, width: 2000, height: 100),
            ),
          ),
        );

    testWidgets('caps content at the readable measure on wide windows',
        (tester) async {
      setSurfaceSize(tester, 1400, 800);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: subject())));

      final size = tester.getSize(find.byKey(childKey));
      expect(size.width, lessThanOrEqualTo(kContentMaxWidth));
    });

    testWidgets('lets compact content fill the viewport', (tester) async {
      setSurfaceSize(tester, 320, 640);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: subject())));

      final size = tester.getSize(find.byKey(childKey));
      expect(size.width, 320);
    });

    testWidgets('caps an ultra-wide viewport at the readable measure',
        (tester) async {
      setSurfaceSize(tester, 3440, 1440);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: subject())));

      final size = tester.getSize(find.byKey(childKey));
      // MaxWidthBox (without an explicit override) caps content at the
      // readable 1080px measure regardless of how wide the window is.
      expect(size.width, lessThanOrEqualTo(kContentMaxWidth));
      expect(size.width, 1080);
    });
  });

  group('VideoFeedScreen size matrix', () {
    for (final width in [320.0, 600.0, 840.0, 1400.0, 2560.0]) {
      testWidgets('renders without overflow at $width logical px',
          (tester) async {
        setSurfaceSize(tester, width, width > 1000 ? 900 : 700);
        await tester.pumpWidget(
          MaterialApp(theme: testTheme(), home: const VideoFeedScreen()),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull,
            reason: 'overflow/exception at $width');
      });
    }
  });
}