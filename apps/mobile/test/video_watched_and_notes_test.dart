import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/core/models/video.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/profile/user_service.dart';
import 'package:mobile/shared/adapters/note_data_adapter.dart';
import 'package:mobile/shared/annotations/user_item.dart';
import 'package:mobile/shared/models/note.dart';
import 'package:mobile/shared/services/note_service.dart';
import 'package:mobile/shared/ui/video_card.dart';
import 'package:mobile/shared/ui/video_thumbnail_overlays.dart';

class _InMemoryNoteAdapter implements NoteDataAdapter {
  final Map<String, Note> _store = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<List<Note>> loadAllNotes() async => _store.values.toList();

  @override
  Future<Note?> getNoteForTarget(String feature, String targetId) async =>
      _store['$feature:$targetId'];

  @override
  Future<List<Note>> getNotesForFeature(String feature) async =>
      _store.values.where((n) => n.feature == feature).toList();

  @override
  Future<void> upsertNote(Note note) async {
    _store['${note.feature}:${note.targetId}'] = note;
  }

  @override
  Future<void> deleteNote(String feature, String targetId) async {
    _store.remove('$feature:$targetId');
  }

  @override
  Future<void> clearAll() async {
    _store.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UserService watched threshold & re-watch reset', () {
    test('parseDurationSeconds parses MM:SS and HH:MM:SS', () {
      expect(UserService.parseDurationSeconds('0:45'), 45);
      expect(UserService.parseDurationSeconds('12:34'), 754);
      expect(UserService.parseDurationSeconds('1:02:03'), 3723);
      expect(UserService.parseDurationSeconds(''), 0);
      expect(UserService.parseDurationSeconds(null), 0);
    });

    test('marks watched in last 10s and resets on re-watch', () async {
      final svc = UserService();
      const id = 'vid_test_1';

      await svc.saveVideoPosition(id, 50, durationSeconds: 100);
      expect(svc.isWatched(id, durationSeconds: 100), isFalse);
      expect(svc.progressFraction(id, durationSeconds: 100), closeTo(0.5, 0.01));

      // Enter last 10 seconds -> Watched
      await svc.saveVideoPosition(id, 90, durationSeconds: 100);
      expect(svc.isWatched(id, durationSeconds: 100), isTrue);

      // Re-watch from start -> resets back to progress (not watched)
      await svc.saveVideoPosition(id, 0, durationSeconds: 100);
      expect(svc.isWatched(id, durationSeconds: 100), isFalse);
      expect(svc.progressFraction(id, durationSeconds: 100), 0.0);

      await svc.saveVideoPosition(id, 25, durationSeconds: 100);
      expect(svc.isWatched(id, durationSeconds: 100), isFalse);
      expect(svc.progressFraction(id, durationSeconds: 100), closeTo(0.25, 0.01));
    });
  });

  group('NoteService for video and short targets', () {
    test('saves, queries, and deletes private video and short notes', () async {
      final svc = NoteService.forTesting(adapter: _InMemoryNoteAdapter());
      await svc.initialize();

      final now = DateTime.utc(2026, 11, 23);
      await svc.saveNote(Note(
        id: 'n1',
        feature: UserItem.featureVideo,
        targetId: 'vid-1',
        text: 'Great point on grace',
        contextText: 'Channel A',
        createdAt: now,
        updatedAt: now,
      ));
      await svc.saveNote(Note(
        id: 'n2',
        feature: UserItem.featureShort,
        targetId: 'short-1',
        text: 'Share with small group',
        createdAt: now,
        updatedAt: now,
      ));

      final vNote = await svc.getNoteForTarget(UserItem.featureVideo, 'vid-1');
      final sNote = await svc.getNoteForTarget(UserItem.featureShort, 'short-1');
      expect(vNote?.text, 'Great point on grace');
      expect(sNote?.text, 'Share with small group');

      await svc.deleteNote(UserItem.featureShort, 'short-1');
      expect(
        await svc.getNoteForTarget(UserItem.featureShort, 'short-1'),
        isNull,
      );
      expect(
        await svc.getNoteForTarget(UserItem.featureVideo, 'vid-1'),
        isNotNull,
      );
    });
  });

  group('VideoCard & VideoWatchedOverlays responsive rendering', () {
    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      testWidgets('renders without overflow at ${width.toInt()}px',
          (tester) async {
        await UserService().saveVideoPosition('v_card_1', 95, durationSeconds: 100);

        final video = Video(
          id: 'v_card_1',
          title: 'Walking in Faith - Sunday Sermon',
          thumbnailUrl: '',
          channelId: 'ch1',
          channelTitle: 'Grace Fellowship',
          publishedAt: DateTime(2026, 11, 20),
          duration: '1:40',
        );

        await tester.binding.setSurfaceSize(Size(width, 900));
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              extensions: const [AppTokens.light],
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    VideoCard(video: video, onTap: () {}),
                    const SizedBox(
                      width: 150,
                      height: 220,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoWatchedOverlays(
                            videoId: 'v_card_1',
                            duration: '1:40',
                            compact: true,
                            badgeTopOffset: 34,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Watched'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
