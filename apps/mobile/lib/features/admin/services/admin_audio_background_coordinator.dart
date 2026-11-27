import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, debugPrint, kIsWeb, TargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/services/notification_service.dart';
import '../models/audio_processor_models.dart';
import 'admin_audio_extractor_service.dart';
import 'admin_audio_job_store.dart';
import 'admin_audio_processor_api.dart';

const String kAdminAudioPeriodicTask = 'admin_audio_periodic_catchup';
const String kAdminAudioImmediateTask = 'admin_audio_immediate_run';

@pragma('vm:entry-point')
void adminAudioWorkmanagerDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await AppConfig.initialize();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      await AdminAudioBackgroundCoordinator.instance.runBackgroundCheck(
        forceProcess: inputData?['forceProcess'] == true,
      );
      return true;
    } catch (e) {
      debugPrint('AdminAudioWorkmanager error: $e');
      return true;
    }
  });
}

class AdminAudioBackgroundCoordinator {
  static final AdminAudioBackgroundCoordinator instance =
      AdminAudioBackgroundCoordinator._();
  AdminAudioBackgroundCoordinator._();

  static const _kAutoProcess = 'admin_audio_auto_process';
  static const _kWifiOnly = 'admin_audio_wifi_only';
  static const _kPauseLowBattery = 'admin_audio_pause_low_battery';
  static const _kConsecutiveFailures = 'admin_audio_consecutive_failures';
  static const _kNotifIdProgress = 9101;
  static const _kNotifIdPrompt = 9102;
  static const _kNotifIdAlert = 9103;

  bool _cancelRequested = false;
  bool _initialized = false;

  bool get isAndroidSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initializeForAdmin() async {
    if (!isAndroidSupported || _initialized) return;
    _initialized = true;
    try {
      await Workmanager().initialize(adminAudioWorkmanagerDispatcher);
      await schedulePeriodicCatchUp();
      await sweepOrphanedAudioTempFiles();
    } catch (e) {
      debugPrint('AdminAudioBackgroundCoordinator init warning: $e');
    }
  }

  Future<void> schedulePeriodicCatchUp() async {
    if (!isAndroidSupported) return;
    final settings = await loadSettings();
    await Workmanager().registerPeriodicTask(
      kAdminAudioPeriodicTask,
      kAdminAudioPeriodicTask,
      frequency: const Duration(hours: 3),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(
        networkType: settings.wifiOnly
            ? NetworkType.unmetered
            : NetworkType.connected,
        requiresBatteryNotLow: settings.pauseBelow20Battery,
      ),
    );
  }

  Future<void> enqueueImmediateRun({bool forceProcess = false}) async {
    if (!isAndroidSupported) return;
    final settings = await loadSettings();
    await Workmanager().registerOneOffTask(
      kAdminAudioImmediateTask,
      kAdminAudioImmediateTask,
      inputData: {'forceProcess': forceProcess},
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: (!forceProcess && settings.wifiOnly)
            ? NetworkType.unmetered
            : NetworkType.connected,
      ),
    );
  }

  void requestStop() {
    _cancelRequested = true;
  }

  Future<AudioProcessorSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return AudioProcessorSettings(
      autoProcess: prefs.getBool(_kAutoProcess) ?? false,
      wifiOnly: prefs.getBool(_kWifiOnly) ?? true,
      pauseBelow20Battery: prefs.getBool(_kPauseLowBattery) ?? true,
    );
  }

  Future<void> saveSettings(AudioProcessorSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoProcess, settings.autoProcess);
    await prefs.setBool(_kWifiOnly, settings.wifiOnly);
    await prefs.setBool(_kPauseLowBattery, settings.pauseBelow20Battery);
    await schedulePeriodicCatchUp();
  }

  Future<void> cleanupOnSignOut({String? fcmToken}) async {
    _cancelRequested = true;
    if (isAndroidSupported) {
      try {
        await Workmanager().cancelByUniqueName(kAdminAudioPeriodicTask);
        await Workmanager().cancelByUniqueName(kAdminAudioImmediateTask);
      } catch (_) {}
    }
    if (fcmToken != null && fcmToken.isNotEmpty) {
      try {
        await AdminAudioProcessorApi().unregisterDeviceToken(fcmToken);
      } catch (_) {}
    }
    await AdminAudioJobStore.instance.clearAll();
  }

  Future<String?> _checkGuardrails(AudioProcessorSettings settings) async {
    if (!isAndroidSupported) return 'Android only';
    if (settings.wifiOnly) {
      final results = await Connectivity().checkConnectivity();
      final onWifi = results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
      if (!onWifi) return 'Waiting for Wi-Fi';
    }
    if (settings.pauseBelow20Battery) {
      try {
        final level = await Battery().batteryLevel;
        if (level > 0 && level < 20) return 'Paused (battery < 20%)';
      } catch (_) {}
    }
    return null;
  }

  Future<int> runBackgroundCheck({
    bool forceProcess = false,
    void Function(String status, int done, int total)? onProgress,
  }) async {
    if (!isAndroidSupported) return 0;
    _cancelRequested = false;

    final settings = await loadSettings();
    if (!forceProcess) {
      final blocked = await _checkGuardrails(settings);
      if (blocked != null) {
        onProgress?.call(blocked, 0, 0);
        return 0;
      }
    }

    final api = AdminAudioProcessorApi();
    final pending = await api.fetchPending(hours: 72);
    if (pending.isEmpty) {
      onProgress?.call('Idle', 0, 0);
      return 0;
    }

    if (!forceProcess && !settings.autoProcess) {
      await _showPromptNotification(pending.length);
      return 0;
    }

    // Cap each background run to 2 videos (~6 min) to stay safely under
    // Android's 10-minute WorkManager limit.
    final batch = forceProcess ? pending : pending.take(2).toList();
    int completedCount = 0;
    final prefs = await SharedPreferences.getInstance();
    int consecutiveFailures = prefs.getInt(_kConsecutiveFailures) ?? 0;

    for (int i = 0; i < batch.length; i++) {
      if (_cancelRequested) break;
      final video = batch[i];
      onProgress?.call('Processing ${i + 1}/${batch.length}: ${video.title}', i, batch.length);
      await _showProgressNotification(i + 1, batch.length, video.title);

      final outcome = await extractAndUploadVideo(
        video: video,
        api: api,
        jobStore: AdminAudioJobStore.instance,
      );

      if (outcome.status == 'completed' || outcome.status == 'short') {
        completedCount++;
        consecutiveFailures = 0;
        await prefs.setInt(_kConsecutiveFailures, 0);
      } else if (outcome.status == 'failed' && outcome.isExtractorError) {
        consecutiveFailures++;
        await prefs.setInt(_kConsecutiveFailures, consecutiveFailures);
        if (consecutiveFailures >= 3) {
          await _showExtractorAlertNotification();
        }
      }
    }

    await _cancelProgressNotification();
    onProgress?.call('Idle', batch.length, batch.length);
    return completedCount;
  }

  Future<void> _showPromptNotification(int count) async {
    try {
      await NotificationService().plugin.show(
        _kNotifIdPrompt,
        '$count new video${count == 1 ? '' : 's'} ready for audio',
        'Tap to open Audio Processor and convert in the background.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'admin_audio_processor',
            'Admin Audio Processor',
            channelDescription: 'New YouTube videos ready for audio processing',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: '/admin/audio-processor',
      );
    } catch (_) {}
  }

  Future<void> _showProgressNotification(int current, int total, String title) async {
    try {
      await NotificationService().plugin.show(
        _kNotifIdProgress,
        'Processing audio $current/$total',
        title,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'admin_audio_processor',
            'Admin Audio Processor',
            channelDescription: 'Background audio extraction progress',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            showProgress: true,
            maxProgress: total,
            progress: current,
          ),
        ),
        payload: '/admin/audio-processor',
      );
    } catch (_) {}
  }

  Future<void> _cancelProgressNotification() async {
    try {
      await NotificationService().plugin.cancel(_kNotifIdProgress);
    } catch (_) {}
  }

  Future<void> _showExtractorAlertNotification() async {
    try {
      await NotificationService().plugin.show(
        _kNotifIdAlert,
        'Mobile YouTube extractor failing',
        '3 videos failed in a row. Turn on Desktop worker or update the app.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'admin_audio_processor',
            'Admin Audio Processor',
            channelDescription: 'Admin audio processor alerts',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: '/admin/audio-processor',
      );
    } catch (_) {}
  }
}
