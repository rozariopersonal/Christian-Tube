import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/channel.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/channels/channel_service.dart';
import 'package:mobile/features/channels/screens/admin_channels_screen.dart';

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

  group('AdminChannelsScreen Tests', () {
    testWidgets('renders tabs and quick stats', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(AdminChannelsScreen(channelService: FakeChannelService())));
      await tester.pump();

      expect(find.text('Channel Administration'), findsOneWidget);
      expect(find.text('Channels'), findsOneWidget);
      expect(find.text('Requests'), findsOneWidget);

      expect(find.text('Total Channels'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
