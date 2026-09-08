import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global preference controlling whether Tamil songs show their Latin
/// transliteration alongside (or instead of) the primary script in the reader.
///
/// The value is persisted so a user opts in/out once and it applies across
/// every Tamil song. Default is off (Tamil script only, per the lyrics-first
/// design), but when a song has no transliteration the toggle is hidden.
class SongTransliterationController extends ChangeNotifier {
  static const String prefKey = 'song_show_transliteration';

  bool _showTransliteration = false;

  bool get showTransliteration => _showTransliteration;

  set showTransliteration(bool value) {
    if (_showTransliteration == value) return;
    _showTransliteration = value;
    notifyListeners();
    unawaited(_save(value));
  }

  /// Restores the persisted preference. Call once before first build.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _showTransliteration = prefs.getBool(prefKey) ?? false;
      notifyListeners();
    } catch (_) {
      // Non-fatal: default stays off.
    }
  }

  Future<void> _save(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefKey, value);
    } catch (_) {}
  }
}
