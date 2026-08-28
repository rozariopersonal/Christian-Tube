import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/watch/widgets/shorts_trimmer_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ShortsTrimmerSheet renders duration slider and timeline track',
      (WidgetTester tester) async {
    double? lastSeekTimestamp;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShortsTrimmerSheet(
            sourceVideoId: 'video_test_123',
            sourceVideoTitle: 'Overcoming Storms by Faith',
            sourceVideoThumbnail: 'https://img.youtube.com/vi/video_test_123/hqdefault.jpg',
            currentPlayheadSeconds: 240.0, // 4 mins in
            totalDurationSeconds: 1800.0,  // 30 mins
            onLiveSeek: (timestamp) {
              lastSeekTimestamp = timestamp;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title and Subtitle exist
    expect(find.text('Create Short (Up to 3 mins)'), findsOneWidget);
    expect(find.text('1. CLIP DURATION'), findsOneWidget);
    expect(find.text('2. POSITION IN FULL VIDEO'), findsOneWidget);
    expect(find.text('3. SHORT DETAILS'), findsOneWidget);

    // Verify Duration default is 01:00
    expect(find.text('01:00'), findsWidgets);

    // Verify prefilled title
    expect(find.text('Overcoming Storms by Faith #Shorts'), findsOneWidget);

    // Verify Publish button exists
    expect(find.text('Publish Short (720p)'), findsOneWidget);
  });
}
