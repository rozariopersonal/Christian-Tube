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

    test('compact landscape hides navigation', () {
      expect(resolve(width: 599, landscape: true), AppNavMode.hidden);
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
  });

  group('VideoFeedScreen size matrix', () {
    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
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