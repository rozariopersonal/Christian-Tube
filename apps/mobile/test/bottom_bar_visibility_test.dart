import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/bottom_bar_visibility_service.dart';

void main() {
  group('BottomBarVisibilityService Tests', () {
    late BottomBarVisibilityService service;

    setUp(() {
      service = BottomBarVisibilityService.instance;
      service.setShortPlaying(false);
      service.setExplicitlyHidden(false);
    });

    testWidgets('shows bottom bar in portrait mode for standard routes', (tester) async {
      late BuildContext capturedContext;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)), // Portrait
            child: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      // Home feed
      expect(
        service.shouldShow(
          context: capturedContext,
          currentPath: '/feed',
          selectedIndex: 0,
        ),
        isTrue,
      );

      // Watch video in portrait (subpage hides bottom bar)
      expect(
        service.shouldShow(
          context: capturedContext,
          currentPath: '/watch/abc1234',
          selectedIndex: 0,
        ),
        isFalse,
      );

      // Search screen (subpage hides bottom bar)
      expect(
        service.shouldShow(
          context: capturedContext,
          currentPath: '/search',
          selectedIndex: 0,
        ),
        isFalse,
      );

      // Watch plans screen (subpage hides bottom bar)
      expect(
        service.shouldShow(
          context: capturedContext,
          currentPath: '/watch-plans',
          selectedIndex: 4,
        ),
        isFalse,
      );

      // Channels screen (subpage hides bottom bar)
      expect(
        service.shouldShow(
          context: capturedContext,
          currentPath: '/channels',
          selectedIndex: 3,
        ),
        isFalse,
      );

      // Shorts feed exploration grid (root tab: keeps bottom bar)
      expect(
        service.shouldShow(
          context: capturedContext,
          currentPath: '/shorts',
          selectedIndex: 1,
        ),
        isTrue,
      );

      // Books catalog screen (subpage hides bottom bar)
      expect(
        service.shouldShow(
          context: capturedContext,
          currentPath: '/books',
          selectedIndex: 3,
        ),
        isFalse,
      );
    });

    testWidgets('hides bottom bar in landscape mode (fullscreen video)', (tester) async {
      late BuildContext capturedContext;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(844, 390)), // Landscape
            child: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      // Video watch in landscape
      expect(
        service.shouldShow(
          context: capturedContext,
          currentPath: '/watch/abc1234',
          selectedIndex: 0,
        ),
        isFalse,
      );

      // Feed in landscape
      expect(
        service.shouldShow(
          context: capturedContext,
          currentPath: '/feed',
          selectedIndex: 0,
        ),
        isFalse,
      );

      // Shorts in landscape
      expect(
        service.shouldShow(
          context: capturedContext,
          currentPath: '/shorts',
          selectedIndex: 1,
        ),
        isFalse,
      );
    });

    testWidgets('shows bottom bar on /shorts when browsing and hides only when a short is playing', (tester) async {
      late BuildContext capturedContext;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)), // Portrait
            child: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      // Browsing shorts grid (not playing) -> Bottom bar VISIBLE
      service.setShortPlaying(false);
      expect(
        service.shouldShow(
          context: capturedContext,
          currentPath: '/shorts',
          selectedIndex: 1,
        ),
        isTrue,
      );

      // Short video is actively playing in fullscreen player -> Bottom bar HIDDEN
      service.setShortPlaying(true);
      expect(
        service.shouldShow(
          context: capturedContext,
          currentPath: '/shorts',
          selectedIndex: 1,
        ),
        isFalse,
      );

      // Exiting playback back to grid -> Bottom bar VISIBLE again
      service.setShortPlaying(false);
      expect(
        service.shouldShow(
          context: capturedContext,
          currentPath: '/shorts',
          selectedIndex: 1,
        ),
        isTrue,
      );
    });

    testWidgets('hides bottom bar when short video is actively playing or explicitly hidden', (tester) async {
      late BuildContext capturedContext;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)), // Portrait
            child: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      service.setShortPlaying(true);
      expect(
        service.shouldShow(
          context: capturedContext,
          currentPath: '/feed',
          selectedIndex: 0,
        ),
        isFalse,
      );

      service.setShortPlaying(false);
      service.setExplicitlyHidden(true);
      expect(
        service.shouldShow(
          context: capturedContext,
          currentPath: '/feed',
          selectedIndex: 0,
        ),
        isFalse,
      );
    });
  });
}
