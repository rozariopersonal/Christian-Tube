import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bottom_bar_visibility_service.dart';

/// Coordinates immersive reading mode across reader routes and the app shell.
///
/// Automatic entry is opt-in and starts after a period without pointer input.
/// The setting is shared by the Bible, book, and article readers.
class ReaderFullscreenService extends ChangeNotifier {
  ReaderFullscreenService._() {
    unawaited(_loadPreference());
  }

  static final ReaderFullscreenService instance = ReaderFullscreenService._();

  static const String _preferenceKey = 'reader_auto_fullscreen_seconds';
  static const List<int> supportedDelays = [0, 30, 60, 120];

  int _autoFullscreenSeconds = 0;
  bool _preferenceChanged = false;
  String? _activeReader;
  Timer? _idleTimer;
  bool _fullscreen = false;

  int get autoFullscreenSeconds => _autoFullscreenSeconds;
  bool get isFullscreen => _fullscreen;
  bool isFullscreenFor(String readerId) => _fullscreen && _activeReader == readerId;

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_preferenceKey) ?? 0;
      if (_preferenceChanged) return;
      _autoFullscreenSeconds = supportedDelays.contains(saved) ? saved : 0;
      if (_activeReader != null) _scheduleIdleEntry();
      notifyListeners();
    } catch (_) {
      // Keep automatic entry disabled if local preferences are unavailable.
    }
  }

  Future<void> setAutoFullscreenSeconds(int seconds) async {
    if (!supportedDelays.contains(seconds) || seconds == _autoFullscreenSeconds) {
      return;
    }
    _preferenceChanged = true;
    _autoFullscreenSeconds = seconds;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_preferenceKey, seconds);
    } catch (_) {
      // The preference remains active for this session if persistence fails.
    }
    _scheduleIdleEntry();
  }

  void attach(String readerId) {
    _idleTimer?.cancel();
    if (_activeReader != null && _activeReader != readerId) {
      _setFullscreen(false);
    }
    _activeReader = readerId;
    _fullscreen = false;
    BottomBarVisibilityService.instance.setReaderFullscreen(false);
    _scheduleIdleEntry();
  }

  void detach(String readerId) {
    if (_activeReader != readerId) return;
    _idleTimer?.cancel();
    _setFullscreen(false);
    _activeReader = null;
  }

  void toggle(String readerId) {
    if (_activeReader != readerId) return;
    if (_fullscreen) {
      exit(readerId);
    } else {
      enter(readerId);
    }
  }

  void enter(String readerId) {
    if (_activeReader != readerId || _fullscreen) return;
    _idleTimer?.cancel();
    _setFullscreen(true);
  }

  void exit(String readerId) {
    if (_activeReader != readerId || !_fullscreen) return;
    _setFullscreen(false);
    _scheduleIdleEntry();
  }

  /// Resets the inactivity timer after user input in the reader.
  void noteActivity(String readerId) {
    if (_activeReader != readerId || _fullscreen) return;
    _scheduleIdleEntry();
  }

  void _scheduleIdleEntry() {
    _idleTimer?.cancel();
    if (_activeReader == null || _fullscreen || _autoFullscreenSeconds <= 0) {
      return;
    }
    final owner = _activeReader!;
    _idleTimer = Timer(Duration(seconds: _autoFullscreenSeconds), () {
      enter(owner);
    });
  }

  void _setFullscreen(bool value) {
    _fullscreen = value;
    BottomBarVisibilityService.instance.setReaderFullscreen(value);
    if (!kIsWeb) {
      unawaited(SystemChrome.setEnabledSystemUIMode(
        value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ));
    }
    notifyListeners();
  }
}
