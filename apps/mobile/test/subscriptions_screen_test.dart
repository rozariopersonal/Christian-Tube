import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/channel.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/channels/channel_service.dart';
import 'package:mobile/features/profile/subscriptions_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget host(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: brightness,
      ),
      extensions: [
        brightness == Brightness.dark ? AppTokens.dark : AppTokens.light,
      ],
    ),
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SubscriptionsScreen Widget Tests', () {
    testWidgets('renders empty state when no channels followed', (tester) async {
      final channelService = ChannelService.forTesting(dio: Dio());

      await tester.pumpWidget(
        host(SubscriptionsScreen(channelService: channelService)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Followed Channels'), findsOneWidget);
      expect(find.text('No Followed Channels'), findsOneWidget);
      expect(
        find.text('Browse the Channels tab to discover and follow channels.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders ChannelFollowTile when channels are followed', (tester) async {
      final channelService = ChannelService.forTesting(dio: Dio());
      channelService.seedSubscribedIds({'c1'});

      // Inject channel into channelService
      const channel = Channel(
        id: 'c1',
        title: 'CFC India',
        avatarUrl: 'https://example.com/avatar.jpg',
        subscriberCount: 25000,
        videoCount: 500,
        isSubscribed: true,
      );
      channelService.setChannelsForTesting([channel]);

      await tester.pumpWidget(
        host(SubscriptionsScreen(channelService: channelService)),
      );
      await tester.pumpAndSettle();

      expect(find.text('CFC India'), findsOneWidget);
      expect(find.text('Following'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without overflow across breakpoints (320, 600, 840, 1400)', (tester) async {
      final channelService = ChannelService.forTesting(dio: Dio());
      channelService.seedSubscribedIds({'c1'});
      const channel = Channel(
        id: 'c1',
        title: 'Christian Fellowship Centre Bangalore',
        avatarUrl: 'https://example.com/avatar.jpg',
        subscriberCount: 50000,
        videoCount: 1200,
        isSubscribed: true,
      );
      channelService.setChannelsForTesting([channel]);

      for (final width in [320.0, 600.0, 840.0, 1400.0]) {
        tester.view.physicalSize = Size(width * 2, 800 * 2);
        tester.view.devicePixelRatio = 2.0;

        await tester.pumpWidget(
          host(SubscriptionsScreen(channelService: channelService)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Christian Fellowship Centre Bangalore'), findsOneWidget);
        expect(find.text('Following'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    });
  });
}
