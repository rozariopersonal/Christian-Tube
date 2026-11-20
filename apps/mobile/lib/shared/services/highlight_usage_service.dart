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

  static const String _legacyPrefsKey = 'highlight_color_usage_v1';
  static const String _prefsKey = 'highlight_color_usage_v2';

  /// Swatches shown until there is usage data (Warm Amber Light, Emerald Green
  /// Light, Sapphire Blue Light).
  static const List<int> defaultOrder = HighlightPalette.defaultTopIndices;

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
        _decodeInto(raw, migrate: false);
      } else {
        final legacyRaw = prefs.getString(_legacyPrefsKey);
        if (legacyRaw != null) {
          _decodeInto(legacyRaw, migrate: true);
          await _persist(prefs);
        }
      }
    } catch (_) {
      // Corrupt or unavailable storage falls back to defaults.
    }
    _loaded = true;
  }

  void _decodeInto(String raw, {required bool migrate}) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    for (final entry in decoded.entries) {
      final rawIdx = int.tryParse(entry.key);
      final value = entry.value;
      if (rawIdx == null || value is! List || value.length != 2) continue;
      final idx = migrate
          ? HighlightPalette.migrateLegacyIndex(rawIdx)
          : rawIdx;
      if (idx < 0 || idx >= HighlightPalette.count) continue;
      final count = (value[0] as num).toInt();
      final last = (value[1] as num).toInt();
      _counts[idx] = (_counts[idx] ?? 0) + count;
      if (last > (_lastUsed[idx] ?? 0)) {
        _lastUsed[idx] = last;
      }
      if (last > _tick) _tick = last;
    }
  }

  Future<void> _persist(SharedPreferences prefs) async {
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        for (final e in _counts.entries)
          '${e.key}': [e.value, _lastUsed[e.key] ?? 0],
      }),
    );
  }

  /// Records one use of [colorIndex].
  Future<void> record(int colorIndex) async {
    if (colorIndex < 0 || colorIndex >= HighlightPalette.count) return;
    _counts[colorIndex] = (_counts[colorIndex] ?? 0) + 1;
    _lastUsed[colorIndex] = ++_tick;
    try {
      final prefs = await SharedPreferences.getInstance();
      await _persist(prefs);
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
