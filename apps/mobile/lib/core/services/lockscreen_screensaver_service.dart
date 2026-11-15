import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the fullscreen Android lock-screen Scripture screensaver
/// ([LockScreenScreensaverService] + [ScreensaverActivity]), which displays
/// Scripture cards when the screen wakes while locked, regardless of charging
/// state.
class LockScreenScreensaverService extends ChangeNotifier {
  static final LockScreenScreensaverService instance =
      LockScreenScreensaverService._internal();
  LockScreenScreensaverService._internal();

  static const MethodChannel _channel =
      MethodChannel('org.rozario.christiantube.mobile/screensaver');
  static const String _prefKeyEnabled = 'lockscreen_screensaver_enabled_v1';

  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<void> initialize() async {
    if (!isSupported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_prefKeyEnabled) ?? false;
      if (_isEnabled && await canDrawOverlays()) {
        await _channel.invokeMethod<void>('startLockScreenService');
      } else if (_isEnabled) {
        _isEnabled = false;
        await prefs.setBool(_prefKeyEnabled, false);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('LockScreenScreensaverService init error: $e');
    }
  }

  Future<bool> canDrawOverlays() async {
    if (!isSupported) return false;
    try {
      final granted = await _channel.invokeMethod<bool>('canDrawOverlays');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestOverlayPermission() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('requestOverlayPermission');
    } catch (_) {}
  }

  Future<bool> setEnabled(bool enabled) async {
    if (!isSupported) return false;
    if (enabled && !(await canDrawOverlays())) {
      return false;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyEnabled, enabled);
      if (enabled) {
        await _channel.invokeMethod<void>('startLockScreenService');
      } else {
        await _channel.invokeMethod<void>('stopLockScreenService');
      }
      _isEnabled = enabled;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('LockScreenScreensaverService setEnabled error: $e');
      return false;
    }
  }
}
