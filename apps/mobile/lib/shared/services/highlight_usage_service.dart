import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/highlight_palette.dart';

/// Tracks how often each highlight colour is applied so selection bars can
/// surface the user's most-used swatches first.
///
/// Shared by the Bible, Book and Article readers.
class HighlightUsageService {
  HighlightUsageService._();

  static final HighlightUsageService instance = HighlightUsageService._();

  static const String _prefsKey = 'highlight_color_usage_v1';

  /// Swatches shown until there is usage data (Mustard, Sage, Sky Blue).
  static const List<int> defaultOrder = [0, 2, 4];

  final Map<int, int> _counts = {};
  final Map<int, int> _lastUsed = {};
  int _tick = 0;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          final idx = int.tryParse(entry.key);
          final value = entry.value;
          if (idx == null || value is! List || value.length != 2) continue;
          _counts[idx] = (value[0] as num).toInt();
          _lastUsed[idx] = (value[1] as num).toInt();
          if (_lastUsed[idx]! > _tick) _tick = _lastUsed[idx]!;
        }
      }
    } catch (_) {
      // Corrupt or unavailable storage falls back to defaults.
    }
    _loaded = true;
  }

  /// Records one use of [colorIndex].
  Future<void> record(int colorIndex) async {
    if (colorIndex < 0 || colorIndex >= HighlightPalette.count) return;
    _counts[colorIndex] = (_counts[colorIndex] ?? 0) + 1;
    _lastUsed[colorIndex] = ++_tick;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          for (final e in _counts.entries)
            '${e.key}': [e.value, _lastUsed[e.key] ?? 0],
        }),
      );
    } catch (_) {}
  }

  /// The [n] most-used colours (ties → most recent), padded with
  /// [defaultOrder] when there is not enough usage data.
  List<int> topColors([int n = 3]) {
    final used = _counts.keys.toList()
      ..sort((a, b) {
        final byCount = _counts[b]!.compareTo(_counts[a]!);
        if (byCount != 0) return byCount;
        return (_lastUsed[b] ?? 0).compareTo(_lastUsed[a] ?? 0);
      });
    final result = <int>[...used.take(n)];
    for (final d in defaultOrder) {
      if (result.length >= n) break;
      if (!result.contains(d)) result.add(d);
    }
    for (var i = 0; result.length < n && i < HighlightPalette.count; i++) {
      if (!result.contains(i)) result.add(i);
    }
    return result;
  }

  /// Test helper: clears in-memory state so the next [load] re-reads storage.
  void resetForTest() {
    _counts.clear();
    _lastUsed.clear();
    _tick = 0;
    _loaded = false;
  }
}
