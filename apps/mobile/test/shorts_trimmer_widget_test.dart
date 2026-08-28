import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/watch/widgets/shorts_trimmer_sheet.dart';
import 'package:mobile/features/watch/widgets/clip_preview_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ShortsTrimmerSheet renders on-preview 9:16 viewfinder and controls',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    double? lastSeekTimestamp;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShortsTrimmerSheet(
            sourceVideoId: 'video_test_123',
            sourceVideoTitle: 'Overcoming Storms by Faith',
            sourceVideoThumbnail:
                'https://img.youtube.com/vi/video_test_123/hqdefault.jpg',
            currentPlayheadSeconds: 240.0, // 4 mins in
            totalDurationSeconds: 1800.0, // 30 mins
            onLiveSeek: (timestamp) {
              lastSeekTimestamp = timestamp;
            },
          ),
        ),
      ),
    );

    await tester.pump();

    // Verify Title and Header
    expect(find.text('Create Short (Up to 3 mins)'), findsOneWidget);

    // Verify Live Preview Player is embedded with on-preview 9:16 badge
    expect(find.byType(ClipPreviewPlayer), findsOneWidget);
    expect(find.text('LIVE PREVIEW'), findsOneWidget);
    expect(find.text('Center'), findsOneWidget); // Default center pan badge on viewfinder

    // Verify Clean 2-Way Framing Options are present
    expect(find.text('9:16 Short'), findsWidgets);
    expect(find.text('16:9 Landscape'), findsWidgets);

    // Verify On-Preview Drag hint is present
    expect(find.text('Drag on the preview to move the 9:16 crop window across the stage'), findsOneWidget);

    // Verify Sections exist
    expect(find.text('CLIP DURATION'), findsOneWidget);
    expect(find.text('POSITION IN FULL VIDEO'), findsOneWidget);
    expect(find.text('SHORT DETAILS'), findsOneWidget);

    // Verify Duration default is 01:00
    expect(find.text('01:00'), findsWidgets);

    // Verify Presets are present
    expect(find.text('15s'), findsOneWidget);
    expect(find.text('30s'), findsOneWidget);
    expect(find.text('60s (Standard)'), findsOneWidget);
    expect(find.text('180s (Max)'), findsOneWidget);

    // Verify Nudge buttons are present
    expect(find.text('-1s'), findsNWidgets(2));
    expect(find.text('+1s'), findsNWidgets(2));

    // Verify prefilled title
    expect(find.text('Overcoming Storms by Faith #Shorts'), findsOneWidget);

    // Verify Publish button exists
    expect(find.text('Publish Short (720p)'), findsOneWidget);

    // Test dragging on the preview canvas to pan the 9:16 viewfinder
    await tester.drag(find.byType(ClipPreviewPlayer), const Offset(-100, 0));
    await tester.pump();

    // Test Framing selector tap -> 16:9 Landscape
    await tester.tap(find.text('16:9 Landscape'));
    await tester.pump();
    expect(find.text('16:9 Landscape'), findsWidgets);

    // Test Duration preset tap (30s)
    await tester.tap(find.text('30s'));
    await tester.pump();
    expect(find.text('00:30'), findsWidgets);

    // Test Start Nudge button
    await tester.tap(find.text('+1s').first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(lastSeekTimestamp, isNotNull);
  });
}
