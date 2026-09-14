import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/channel.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/channels/channel_service.dart';
import 'package:mobile/features/channels/screens/user_subscriptions_screen.dart';

class FakeChannelService extends ChannelService {
  FakeChannelService() : super.test();

  @override
  Future<void> fetchChannels() async {}

  @override
  Future<void> fetchRequests() async {}

  @override
  List<Channel> get channels => [];

  @override
  List<Map<String, dynamic>> get channelRequests => [];
  
  @override
  bool get isLoading => false;

  @override
  bool get isLoadingRequests => false;
}

void main() {
  Widget buildTestApp(Widget child, {Size size = const Size(400, 800)}) {
    return MaterialApp(
      theme: ThemeData(
        extensions: const [AppTokens.light],
      ),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: child,
      ),
    );
  }

  group('UserSubscriptionsScreen Tests', () {
    testWidgets('renders basic layout correctly', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(UserSubscriptionsScreen(channelService: FakeChannelService())));
      await tester.pump();

      expect(find.text('Subscriptions'), findsOneWidget);
      // Wait for empty state or loading indicator
      expect(find.text('No subscriptions yet'), findsOneWidget);
      
      // Floating Action Button for requesting channel
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Request Channel'), findsOneWidget);
    });
  });
}
