import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/watch/widgets/flutter_video_controls_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FlutterVideoControlsOverlay renders center controls, time and speed',
      (WidgetTester tester) async {
    bool playTriggered = false;
    bool pauseTriggered = false;
    Duration? seekTarget;
    double? _selectedSpeed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: FlutterVideoControlsOverlay(
              isPlaying: true,
              isBuffering: false,
              position: const Duration(minutes: 2, seconds: 15),
              duration: const Duration(minutes: 10, seconds: 30),
              playbackRate: 1.0,
              onPlay: () => playTriggered = true,
              onPause: () => pauseTriggered = true,
              onSeek: (pos) => seekTarget = pos,
              onSetSpeed: (speed) => _selectedSpeed = speed,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify time display formatted properly
    expect(find.text('02:15 / 10:30'), findsOneWidget);

    // Verify speed button displays '1.0x'
    expect(find.text('1.0x'), findsOneWidget);

    // Verify center buttons (-10s, pause, +10s)
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byIcon(Icons.replay_10_rounded), findsWidgets);
    expect(find.byIcon(Icons.forward_10_rounded), findsWidgets);

    // Tap pause button
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    expect(pauseTriggered, isTrue);

    // Tap +10s button (the clickable circle button)
    final forwardButton = find.widgetWithIcon(InkWell, Icons.forward_10_rounded);
    await tester.tap(forwardButton);
    await tester.pump();
    expect(seekTarget, isNotNull);
    expect(seekTarget!.inSeconds, equals(145)); // 2:15 (135s) + 10s = 145s
  });

  testWidgets('FlutterVideoControlsOverlay renders buffering indicator',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: FlutterVideoControlsOverlay(
              isPlaying: true,
              isBuffering: true,
              position: Duration(seconds: 30),
              duration: Duration(minutes: 5),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    // Verify CircularProgressIndicator is present when buffering
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
