import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../config/app_config.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
      },
    );
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
