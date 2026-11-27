import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import '../../../../core/config/app_config.dart';
import 'admin_audio_background_coordinator.dart';
import 'admin_audio_processor_api.dart';

@pragma('vm:entry-point')
Future<void> adminFcmBackgroundHandler(RemoteMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await AppConfig.initialize();
    if (message.data['type'] == 'new_video_audio') {
      await AdminAudioBackgroundCoordinator.instance.enqueueImmediateRun();
    }
  } catch (e) {
    debugPrint('Admin FCM background handler warning: $e');
  }
}

class AdminFcmService {
  static final AdminFcmService instance = AdminFcmService._();
  AdminFcmService._();

  String? _registeredToken;
  bool _initialized = false;

  String? get registeredToken => _registeredToken;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initializeForAdmin() async {
    if (!_isAndroid || _initialized) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      FirebaseMessaging.onBackgroundMessage(adminFcmBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        _registeredToken = token;
        await AdminAudioProcessorApi().registerDeviceToken(token);
      }

      messaging.onTokenRefresh.listen((newToken) async {
        _registeredToken = newToken;
        try {
          await AdminAudioProcessorApi().registerDeviceToken(newToken);
        } catch (_) {}
      });

      FirebaseMessaging.onMessage.listen((message) {
        if (message.data['type'] == 'new_video_audio') {
          AdminAudioBackgroundCoordinator.instance.enqueueImmediateRun();
        }
      });

      _initialized = true;
    } catch (e) {
      // Non-fatal: e.g. CentumAcademy or builds without google-services.json
      debugPrint('AdminFcmService init skipped: $e');
    }
  }
}
