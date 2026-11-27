import 'package:flutter/foundation.dart';
import '../models/audio_processor_models.dart';
import '../services/admin_audio_background_coordinator.dart';
import '../services/admin_audio_job_store.dart';
import '../services/admin_audio_processor_api.dart';

enum ActivityFilter { all, completed, failed, skipped }

class AudioProcessorReportState {
  final bool loading;
  final bool running;
  final String liveStatus;
  final int progressDone;
  final int progressTotal;
  final String? errorMessage;
  final AudioProcessorReport report;
  final AudioProcessorSettings settings;
  final ActivityFilter filter;
  final List<LocalAudioJobRecord> localJobs;

  const AudioProcessorReportState({
    this.loading = true,
    this.running = false,
    this.liveStatus = 'Idle',
    this.progressDone = 0,
    this.progressTotal = 0,
    this.errorMessage,
    this.report = const AudioProcessorReport(),
    this.settings = const AudioProcessorSettings(),
    this.filter = ActivityFilter.all,
    this.localJobs = const [],
  });

  List<AudioProcessorActivityItem> get filteredActivity {
    final items = report.recentActivity;
    switch (filter) {
      case ActivityFilter.all:
        return items;
      case ActivityFilter.completed:
        return items.where((e) => e.status == 'completed').toList(growable: false);
      case ActivityFilter.failed:
        return items.where((e) => e.isFailed).toList(growable: false);
      case ActivityFilter.skipped:
        return items.where((e) => e.isSkipped).toList(growable: false);
    }
  }

  AudioProcessorReportState copyWith({
    bool? loading,
    bool? running,
    String? liveStatus,
    int? progressDone,
    int? progressTotal,
    String? errorMessage,
    bool clearError = false,
    AudioProcessorReport? report,
    AudioProcessorSettings? settings,
    ActivityFilter? filter,
    List<LocalAudioJobRecord>? localJobs,
  }) {
    return AudioProcessorReportState(
      loading: loading ?? this.loading,
      running: running ?? this.running,
      liveStatus: liveStatus ?? this.liveStatus,
      progressDone: progressDone ?? this.progressDone,
      progressTotal: progressTotal ?? this.progressTotal,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      report: report ?? this.report,
      settings: settings ?? this.settings,
      filter: filter ?? this.filter,
      localJobs: localJobs ?? this.localJobs,
    );
  }
}

class AudioProcessorReportController extends ChangeNotifier {
  final AdminAudioProcessorApi _api;
  final AdminAudioBackgroundCoordinator _coordinator;
  final AdminAudioJobStore _jobStore;

  AudioProcessorReportState _state = const AudioProcessorReportState();
  AudioProcessorReportState get state => _state;

  AudioProcessorReportController({
    AdminAudioProcessorApi? api,
    AdminAudioBackgroundCoordinator? coordinator,
    AdminAudioJobStore? jobStore,
  })  : _api = api ?? AdminAudioProcessorApi(),
        _coordinator = coordinator ?? AdminAudioBackgroundCoordinator.instance,
        _jobStore = jobStore ?? AdminAudioJobStore.instance;

  void _emit(AudioProcessorReportState next) {
    _state = next;
    notifyListeners();
  }

  Future<void> load() async {
    _emit(_state.copyWith(loading: true, clearError: true));
    try {
      final results = await Future.wait([
        _api.fetchReport(),
        _coordinator.loadSettings(),
        _jobStore.listRecent(limit: 30),
      ]);
      _emit(
        _state.copyWith(
          loading: false,
          report: results[0] as AudioProcessorReport,
          settings: results[1] as AudioProcessorSettings,
          localJobs: results[2] as List<LocalAudioJobRecord>,
        ),
      );
    } catch (e) {
      _emit(_state.copyWith(loading: false, errorMessage: e.toString()));
    }
  }

  void setFilter(ActivityFilter filter) {
    _emit(_state.copyWith(filter: filter));
  }

  Future<void> updateSettings(AudioProcessorSettings next) async {
    _emit(_state.copyWith(settings: next));
    await _coordinator.saveSettings(next);
  }

  Future<void> runNow() async {
    if (_state.running) return;
    _emit(
      _state.copyWith(
        running: true,
        liveStatus: 'Checking pending videos...',
        progressDone: 0,
        progressTotal: 0,
        clearError: true,
      ),
    );
    try {
      await _coordinator.runBackgroundCheck(
        forceProcess: true,
        onProgress: (status, done, total) {
          _emit(
            _state.copyWith(
              liveStatus: status,
              progressDone: done,
              progressTotal: total,
            ),
          );
        },
      );
    } catch (e) {
      _emit(_state.copyWith(errorMessage: e.toString()));
    } finally {
      _emit(_state.copyWith(running: false, liveStatus: 'Idle'));
      await load();
    }
  }

  void stopRun() {
    _coordinator.requestStop();
    _emit(_state.copyWith(liveStatus: 'Stopping...'));
  }

  Future<void> markIgnored(String videoId) async {
    try {
      await _api.markIgnored(videoId, reason: 'Ignored by admin from Report Page');
      await load();
    } catch (e) {
      _emit(_state.copyWith(errorMessage: e.toString()));
    }
  }
}
