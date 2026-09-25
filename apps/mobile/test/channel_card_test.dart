import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/channels/channels_screen.dart';
import 'package:mobile/shared/ui/channel_card.dart';

void setSurfaceSize(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

ThemeData testTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      extensions: const [AppTokens.light],
    );

/// The channels grid pins cards to [kChannelCardGridExtent], and [ChannelCard]
/// relies on an [Expanded] body, so the card must always be given a bounded
/// height by its parent.
Widget host(
  Widget child, {
  double height = kChannelCardGridExtent,
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    theme: testTheme().copyWith(brightness: brightness),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 340, height: height, child: child),
      ),
    ),
  );
}

ChannelCard subject({
  String title = 'Centum CFC Chennai',
  String? description = 'Daily devotional messages from Chennai Central Fellowship Church.',
  String avatarUrl = '',
  String? bannerUrl,
  int subscriberCount = 12500,
  int videoCount = 320,
  String? language = 'ta',
  VoidCallback? onTap,
  Widget? actionButton,
  Widget? trailingMenu,
  bool isCompact = true,
}) {
  return ChannelCard(
    title: title,
    description: description,
    avatarUrl: avatarUrl,
    bannerUrl: bannerUrl,
    subscriberCount: subscriberCount,
    videoCount: videoCount,
    language: language,
    onTap: onTap,
    actionButton: actionButton ?? const ElevatedButton(onPressed: null, child: Text('Subscribe')),
    trailingMenu: trailingMenu,
    isCompact: isCompact,
  );
}

void main() {
  group('ChannelCard content', () {
    testWidgets('renders title, subscriber count and video count', (tester) async {
      await tester.pumpWidget(host(subject()));

      expect(find.text('Centum CFC Chennai'), findsOneWidget);
      expect(find.text('12.5K subs'), findsOneWidget);
      expect(find.text('320 videos'), findsOneWidget);
    });

    testWidgets('formats subscriber counts in millions', (tester) async {
      await tester.pumpWidget(host(subject(subscriberCount: 2400000)));

      expect(find.text('2.4M subs'), findsOneWidget);
    });

    testWidgets('renders the description when provided', (tester) async {
      await tester.pumpWidget(host(subject()));

      expect(
        find.text('Daily devotional messages from Chennai Central Fellowship Church.'),
        findsOneWidget,
      );
    });

    testWidgets('omits the description when null or empty', (tester) async {
      await tester.pumpWidget(host(subject(description: null)));
      expect(find.textContaining('Daily devotional'), findsNothing);

      await tester.pumpWidget(host(subject(description: '')));
      expect(find.textContaining('Daily devotional'), findsNothing);
    });

    testWidgets('uppercases and badges the language when provided', (tester) async {
      await tester.pumpWidget(host(subject(language: 'ta')));

      expect(find.text('TA'), findsOneWidget);
    });

    testWidgets('omits the language badge when null or empty', (tester) async {
      await tester.pumpWidget(host(subject(language: null)));
      expect(find.text('TA'), findsNothing);

      await tester.pumpWidget(host(subject(language: '')));
      expect(find.text('TA'), findsNothing);
    });

    testWidgets('renders the avatar initial when no avatar url is given', (tester) async {
      await tester.pumpWidget(host(subject(avatarUrl: '')));

      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('renders the required action button', (tester) async {
      await tester.pumpWidget(host(subject()));

      expect(find.widgetWithText(ElevatedButton, 'Subscribe'), findsOneWidget);
    });

    testWidgets('renders the trailing menu only when supplied', (tester) async {
      await tester.pumpWidget(host(subject()));
      expect(find.byIcon(Icons.more_vert), findsNothing);

      await tester.pumpWidget(host(
        subject(trailingMenu: const Icon(Icons.more_vert, size: 20)),
      ));
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('invokes onTap when the card body is tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(subject(onTap: () => taps++)));

      await tester.tap(find.text('Centum CFC Chennai'));
      await tester.pump();

      expect(taps, 1);
    });
  });

  group('ChannelCard adaptivity', () {
    // Definition of done per the Responsive & Adaptive UI Standard: the card
    // must render at 320, 600, 840 and 1400 logical px without overflow.
    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      testWidgets('renders without overflow at ${width.toInt()} logical px', (tester) async {
        setSurfaceSize(tester, width, 900);
        final isCompact = width < 600;

        await tester.pumpWidget(MaterialApp(
          theme: testTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width - 32,
                height: kChannelCardGridExtent,
                child: subject(
                  isCompact: isCompact,
                  title: 'A very long channel title that should be truncated gracefully',
                  description:
                      'A long description that spans several lines so the card body has to wrap, clamp and ellipsize without overflowing its fixed extent.',
                  language: 'ta',
                  trailingMenu: const Icon(Icons.more_vert, size: 20),
                ),
              ),
            ),
          ),
        ));

        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(ChannelCard), findsOneWidget);
      });
    }

    testWidgets('shows the full description at the grid extent', (tester) async {
      // Guards the grid's mainAxisExtent: the body clamps overflow rather than
      // throwing, so a too-short extent would silently clip the description.
      await tester.pumpWidget(host(subject(), height: kChannelCardGridExtent));

      final description = tester.getRect(
        find.text('Daily devotional messages from Chennai Central Fellowship Church.'),
      );
      final action = tester.getRect(
        find.widgetWithText(ElevatedButton, 'Subscribe'),
      );

      expect(description.bottom, lessThanOrEqualTo(action.top));
    });

    testWidgets('does not overflow at 320 logical px with a 2x text scale', (tester) async {
      setSurfaceSize(tester, 320, 900);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 288,
              height: kChannelCardGridExtent,
              child: subject(
                title: 'Centum CFC Chennai',
                description: 'Daily devotional messages.',
                language: 'ta',
              ),
            ),
          ),
        ),
      ));

      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('compact stretches the action button to full width', (tester) async {
      await tester.pumpWidget(host(
        subject(
          isCompact: true,
          actionButton: const ElevatedButton(onPressed: null, child: Text('Subscribe')),
        ),
      ));

      final button = tester.getSize(
        find.widgetWithText(ElevatedButton, 'Subscribe'),
      );
      // Card is 340 wide minus 16dp padding on each side.
      expect(button.width, closeTo(308, 1));
    });

    testWidgets('non-compact right-aligns the action button', (tester) async {
      await tester.pumpWidget(host(
        subject(
          isCompact: false,
          actionButton: const ElevatedButton(onPressed: null, child: Text('Subscribe')),
        ),
      ));

      final cardRect = tester.getRect(find.byType(ChannelCard));
      final buttonRect = tester.getRect(
        find.widgetWithText(ElevatedButton, 'Subscribe'),
      );

      expect(buttonRect.right, closeTo(cardRect.right - 16, 1));
      expect(buttonRect.width, lessThan(cardRect.width));
    });
  });

  group('ChannelCard theming', () {
    testWidgets('resolves colors from tokens rather than raw literals', (tester) async {
      await tester.pumpWidget(host(subject()));

      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color, AppTokens.light.surface);
    });

    testWidgets('renders in dark theme without overflow', (tester) async {
      await tester.pumpWidget(host(subject(), brightness: Brightness.dark));

      expect(tester.takeException(), isNull);
      expect(find.text('Centum CFC Chennai'), findsOneWidget);
    });
  });
}
