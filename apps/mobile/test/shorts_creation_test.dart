import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/local_short_item.dart';
import 'package:mobile/core/models/short.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Short Model Duration Tests (Up to 3 minutes)', () {
    test('Short duration parsing handles mm:ss and hh:mm:ss', () {
      expect(Short.parseDurationInSeconds('01:30'), 90);
      expect(Short.parseDurationInSeconds('03:00'), 180);
      expect(Short.parseDurationInSeconds('00:45'), 45);
      expect(Short.parseDurationInSeconds('01:00:00'), 3600);
    });

    test('isShort accurately classifies up to 180 seconds', () {
      expect(
        Short.isShort({
          'duration': '02:30',
          'title': 'Test Clip',
        }),
        isTrue,
      );

      expect(
        Short.isShort({
          'duration': '03:00',
          'title': '3 Min Short',
        }),
        isTrue,
      );

      expect(
        Short.isShort({
          'duration': '03:01',
          'title': 'Long Sermon',
        }),
        isFalse,
      );
    });

    test('Short.fromJson correctly parses creator metadata & sourceVideoId', () {
      final json = {
        'id': 'short_yt_123',
        'title': 'Finding Peace #Shorts',
        'duration': '01:15',
        'sourceVideoId': 'sermon_full_999',
        'clipStartTime': 120.0,
        'clipEndTime': 195.0,
        'creatorName': 'Brother Mark',
        'creatorEmail': 'mark@test.com',
      };

      final short = Short.fromJson(json);
      expect(short.id, 'short_yt_123');
      expect(short.durationSeconds, 75);
      expect(short.sourceVideoId, 'sermon_full_999');
      expect(short.clipStartTime, 120.0);
      expect(short.clipEndTime, 195.0);
      expect(short.creatorName, 'Brother Mark');
      expect(short.creatorEmail, 'mark@test.com');
    });
  });

  group('LocalShortItem Model Lifecycle Tests', () {
    test('LocalShortItem serialization and statusDisplay', () {
      final item = LocalShortItem(
        id: 'test_uuid_1',
        sourceVideoId: 'sermon_abc',
        sourceVideoTitle: 'Walking in the Spirit',
        title: 'Spirit Clip #Shorts',
        creatorName: 'Sister Sarah',
        creatorEmail: 'sarah@test.com',
        clipStartTime: 60.0,
        clipEndTime: 150.0,
        duration: 90.0,
        status: ShortCreationStatus.downloading,
        progress: 0.25,
        createdAt: DateTime(2026, 8, 28),
        cropOffsetX: -0.4,
        framingMode: ShortsFramingMode.portrait9x16,
      );

      expect(item.statusDisplay, contains('Extracting stream 25%'));
      expect(item.isPlayable, isFalse);
      expect(item.cropOffsetX, -0.4);
      expect(item.framingMode, ShortsFramingMode.portrait9x16);

      final renderedItem = item.copyWith(
        status: ShortCreationStatus.readyLocal,
        localVideoPath: '/path/to/rendered.mp4',
        progress: 1.0,
      );
      expect(renderedItem.isPlayable, isTrue);
      expect(renderedItem.statusDisplay, contains('Rendered'));

      final scheduledItem = renderedItem.copyWith(
        status: ShortCreationStatus.scheduledUpload,
        scheduledRetryAt: DateTime.now().add(const Duration(hours: 5)),
      );
      expect(scheduledItem.isPlayable, isTrue);
      expect(scheduledItem.statusDisplay, contains('Scheduled'));

      // Test JSON roundtrip
      final json = scheduledItem.toJson();
      final revived = LocalShortItem.fromJson(json);
      expect(revived.id, item.id);
      expect(revived.title, item.title);
      expect(revived.duration, 90.0);
      expect(revived.cropOffsetX, -0.4);
      expect(revived.framingMode, ShortsFramingMode.portrait9x16);
      expect(revived.status, ShortCreationStatus.scheduledUpload);
      expect(revived.isPlayable, isTrue);
    });
  });
}
