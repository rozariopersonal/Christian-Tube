import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/channel.dart';
import 'package:mobile/features/shorts/widgets/shorts_channel_filter_sheet.dart';

void main() {
  testWidgets('selects multiple channels and returns them on apply',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final channels = [
      const Channel(id: 'grace', title: 'Grace Today', avatarUrl: ''),
      const Channel(id: 'bible', title: 'Bible Minutes', avatarUrl: ''),
      const Channel(id: 'hope', title: 'Hope in Christ', avatarUrl: ''),
    ];
    Set<String>? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await ShortsChannelFilterSheet.show(
                    context,
                    channels: channels,
                    selectedChannelIds: const {'grace'},
                  );
                },
                child: const Text('Open filter'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bible Minutes'));
    await tester.pumpAndSettle();

    expect(find.text('Show Shorts (2)'), findsOneWidget);
    await tester.tap(find.text('Show Shorts (2)'));
    await tester.pumpAndSettle();

    expect(result, {'grace', 'bible'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('search narrows the available channel list', (tester) async {
    final channels = [
      const Channel(id: 'grace', title: 'Grace Today', avatarUrl: ''),
      const Channel(id: 'bible', title: 'Bible Minutes', avatarUrl: ''),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => ShortsChannelFilterSheet.show(
                  context,
                  channels: channels,
                  selectedChannelIds: const {},
                ),
                child: const Text('Open filter'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open filter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bible');
    await tester.pumpAndSettle();

    expect(find.text('Bible Minutes'), findsOneWidget);
    expect(find.text('Grace Today'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
