import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../config/app_config.dart';
import 'lockscreen_word_feed_service.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  if (response.actionId == LockScreenWordFeedService.actionNextWord) {
    LockScreenWordFeedService.instance.rotateNextWord();
  } else if (response.actionId == LockScreenWordFeedService.actionBookmark) {
    LockScreenWordFeedService.instance.toggleBookmarkCurrentWord();
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  FlutterLocalNotificationsPlugin get plugin => _notificationsPlugin;

  static void Function(String payload)? onNotificationPayload;

  Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        if (response.actionId == LockScreenWordFeedService.actionNextWord) {
          await LockScreenWordFeedService.instance.rotateNextWord();
          return;
        }
        if (response.actionId == LockScreenWordFeedService.actionBookmark) {
          await LockScreenWordFeedService.instance.toggleBookmarkCurrentWord();
          return;
        }
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          onNotificationPayload?.call(payload);
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // Request notification permission for Android 13+ (API 33+) to allow lockscreen media controls
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      '${AppConfig.instanceId}_main_channel',
      '${AppConfig.appName} Updates',
      channelDescription: 'Notifications for new ${AppConfig.appName} videos and updates',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    final NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
    await _notificationsPlugin.show(id, title, body, platformDetails, payload: payload);
  }
}
