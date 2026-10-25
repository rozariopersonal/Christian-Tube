import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/shared/ui/channel_follow_tile.dart';

Widget host(Widget child, {Brightness brightness = Brightness.light, double width = 360}) {
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
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  group('ChannelFollowTile content and interaction', () {
    testWidgets('renders channel title, default subtitle, and follow button', (tester) async {
      await tester.pumpWidget(
        host(
          ChannelFollowTile(
            channelId: 'ch1',
            title: 'Centum CFC Chennai',
            subscriberCount: 15400,
            videoCount: 240,
            isFollowed: false,
            onToggleFollow: () {},
          ),
        ),
      );

      expect(find.text('Centum CFC Chennai'), findsOneWidget);
      expect(find.text('15.4K subscribers • 240 videos'), findsOneWidget);
      expect(find.text('Follow'), findsOneWidget);
      expect(find.text('Following'), findsNothing);
    });

    testWidgets('renders Following label when isFollowed is true', (tester) async {
      await tester.pumpWidget(
        host(
          ChannelFollowTile(
            channelId: 'ch1',
            title: 'Centum CFC Chennai',
            subscriberCount: 15400,
            videoCount: 240,
            isFollowed: true,
            onToggleFollow: () {},
          ),
        ),
      );

      expect(find.text('Following'), findsOneWidget);
      expect(find.text('Follow'), findsNothing);
    });

    testWidgets('triggers onToggleFollow when follow button is tapped', (tester) async {
      var toggled = false;
      await tester.pumpWidget(
        host(
          ChannelFollowTile(
            channelId: 'ch1',
            title: 'Test Channel',
            isFollowed: false,
            onToggleFollow: () => toggled = true,
          ),
        ),
      );

      await tester.tap(find.text('Follow'));
      expect(toggled, isTrue);
    });

    testWidgets('triggers onTap when card body is tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        host(
          ChannelFollowTile(
            channelId: 'ch1',
            title: 'Test Channel',
            isFollowed: false,
            onToggleFollow: () {},
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.text('Test Channel'));
      expect(tapped, isTrue);
    });

    testWidgets('renders badge and custom actionButton when provided', (tester) async {
      await tester.pumpWidget(
        host(
          const ChannelFollowTile(
            channelId: 'ch1',
            title: 'Test Channel',
            isFollowed: false,
            badge: Text('PRO', style: TextStyle(fontSize: 10)),
            actionButton: ElevatedButton(
              onPressed: null,
              child: Text('Add'),
            ),
          ),
        ),
      );

      expect(find.text('PRO'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
      expect(find.text('Follow'), findsNothing);
    });
  });

  group('ChannelFollowTile responsiveness', () {
    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      testWidgets('renders cleanly without overflow at width $width', (tester) async {
        await tester.pumpWidget(
          host(
            ChannelFollowTile(
              channelId: 'ch_long',
              title: 'A Very Long Ministry Channel Name That Should Ellipsize Gracefully',
              subtitle: '999K subscribers • 1200 videos • Special Tag',
              isFollowed: true,
              onToggleFollow: () {},
              badge: const Text('PRO'),
            ),
            width: width,
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(ChannelFollowTile), findsOneWidget);
      });
    }
  });
}
