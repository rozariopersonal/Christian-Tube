import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/channels/widgets/request_channel_sheet.dart';

void main() {
  Widget wrap(Widget child, {required Size size}) {
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        theme: ThemeData.light().copyWith(extensions: const [AppTokens.light]),
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  for (final width in [320.0, 600.0, 840.0, 1400.0]) {
    testWidgets(
      'RequestChannelBottomSheet renders without overflow at ${width.toInt()}dp',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          wrap(
            RequestChannelBottomSheet(
              onSearch: (_) async => [
                {
                  'id': 'UC_existing',
                  'name': 'Already Added Ministry Channel With A Long Title',
                  'handle': '@existing',
                  'isExisting': true,
                },
                {
                  'id': 'UC_new',
                  'name': 'Grace Fellowship International',
                  'handle': '@gracefellowship',
                  'subscriberCount': 25400,
                  'isExisting': false,
                },
              ],
              onSubmitRequest: (_, __) async => (ok: true, error: null),
            ),
            size: Size(width, 800),
          ),
        );

        await tester.enterText(find.byType(TextField), 'Grace');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(find.text('Added'), findsOneWidget);
        expect(find.text('Request'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('keeps sheet open and displays error when submission fails',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        RequestChannelBottomSheet(
          onSearch: (_) async => [],
          onSubmitRequest: (_, __) async => (
            ok: false,
            error: 'A pending request for this channel already exists.',
          ),
        ),
        size: const Size(400, 800),
      ),
    );

    await tester.enterText(find.byType(TextField), '@grace');
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(
      find.text('A pending request for this channel already exists.'),
      findsOneWidget,
    );
    expect(find.byType(RequestChannelBottomSheet), findsOneWidget);
  });
}
