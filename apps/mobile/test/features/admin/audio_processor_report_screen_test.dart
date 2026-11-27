import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/admin/controllers/audio_processor_report_controller.dart';
import 'package:mobile/features/admin/models/audio_processor_models.dart';
import 'package:mobile/features/admin/screens/audio_processor_report_screen.dart';
import 'package:mobile/features/admin/services/admin_audio_background_coordinator.dart';
import 'package:mobile/features/admin/services/admin_audio_job_store.dart';
import 'package:mobile/features/admin/services/admin_audio_processor_api.dart';

class _FakeApi extends AdminAudioProcessorApi {
  final AudioProcessorReport fakeReport;
  _FakeApi(this.fakeReport) : super();

  @override
  Future<AudioProcessorReport> fetchReport() async => fakeReport;

  @override
  Future<void> markIgnored(String videoId, {String? reason}) async {}
}

class _FakeCoordinator implements AdminAudioBackgroundCoordinator {
  AudioProcessorSettings _settings = const AudioProcessorSettings();

  @override
  bool get isAndroidSupported => true;

  @override
  Future<AudioProcessorSettings> loadSettings() async => _settings;

  @override
  Future<void> saveSettings(AudioProcessorSettings settings) async {
    _settings = settings;
  }

  @override
  Future<void> initializeForAdmin() async {}

  @override
  Future<void> schedulePeriodicCatchUp() async {}

  @override
  Future<void> enqueueImmediateRun({bool forceProcess = false}) async {}

  @override
  void requestStop() {}

  @override
  Future<void> cleanupOnSignOut({String? fcmToken}) async {}

  @override
  Future<int> runBackgroundCheck({
    bool forceProcess = false,
    void Function(String status, int done, int total)? onProgress,
  }) async =>
      0;
}

class _FakeJobStore implements AdminAudioJobStore {
  @override
  Future<List<LocalAudioJobRecord>> listRecent({int limit = 50}) async =>
      const [];

  @override
  Future<void> upsert(LocalAudioJobRecord record) async {}

  @override
  Future<LocalAudioJobRecord?> getByVideoId(String videoId) async => null;

  @override
  Future<void> clearAll() async {}
}

void main() {
  final sampleReport = AudioProcessorReport(
    pendingCount: 3,
    last24h: const AudioProcessorWindowStats(
      completed: 4,
      failed: 1,
      skipped: 2,
      mobileCompleted: 3,
      desktopCompleted: 1,
    ),
    last7d: const AudioProcessorWindowStats(
      completed: 18,
      failed: 2,
      skipped: 5,
      mobileCompleted: 10,
      desktopCompleted: 8,
    ),
    lastDesktopSyncAt: DateTime.utc(2026, 11, 27, 6, 30),
    audioComAuthError: 'Audio.com returned 401 Unauthorized',
    fcmConfigured: true,
    fcmDeviceCount: 1,
    recentActivity: [
      AudioProcessorActivityItem(
        videoId: 'vid_1',
        title: 'Sunday Morning Message — Walking in Humility',
        channelName: 'CFC India',
        status: 'completed',
        source: 'mobile',
        at: DateTime.utc(2026, 11, 27, 5, 0),
      ),
      AudioProcessorActivityItem(
        videoId: 'vid_2',
        title: 'Livestream Recording',
        channelName: 'CHENNAI CFC',
        status: 'failed',
        source: 'mobile',
        error: 'M4A stream not ready yet',
        at: DateTime.utc(2026, 11, 27, 4, 0),
      ),
    ],
  );

  for (final width in [320.0, 600.0, 840.0, 1400.0]) {
    testWidgets('renders without overflow at ${width.toInt()}px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = AudioProcessorReportController(
        api: _FakeApi(sampleReport),
        coordinator: _FakeCoordinator(),
        jobStore: _FakeJobStore(),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light().copyWith(extensions: [AppTokens.light]),
          home: AudioProcessorReportScreen(
            controller: controller,
            isAndroidOverride: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Audio Processor'), findsOneWidget);
      expect(find.text('Audio.com Token Expired'), findsOneWidget);
      expect(find.text('Auto-Process without asking'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
