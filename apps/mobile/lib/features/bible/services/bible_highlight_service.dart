import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bible_highlight.dart';

/// Persists per-verse color highlights for the Bible reader.
///
/// Highlights are stored as a single JSON blob keyed by version+book+chapter,
/// allowing multiple verses to share one highlight color. This mirrors the
/// [BibleBookmarkService] persistence pattern (SharedPreferences JSON blob).
class BibleHighlightService {
  static const String _key = 'bible_highlights_v1';

  Future<List<BibleHighlight>> loadHighlights() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => BibleHighlight.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<BibleHighlight> highlights) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(highlights.map((h) => h.toJson()).toList()),
    );
  }

  /// Returns all highlights for the given [book] [chapter], regardless of
  /// version (verse numbers are canonical across translations).
  Future<List<BibleHighlight>> getForChapter(String book, int chapter) async {
    final all = await loadHighlights();
    return all
        .where((h) => h.book == book && h.chapter == chapter)
        .toList();
  }

  /// Sets the highlight color for [verses] in [book] [chapter] to [colorIndex].
  ///
  /// Verses already present in another highlight for the same version/book/
  /// chapter are removed (replace model — one color per verse). Returns the
  /// color index that was applied.
  Future<int> apply({
    required String versionId,
    required String book,
    required int chapter,
    required List<int> verses,
    required int colorIndex,
    required String text,
  }) async {
    final all = await loadHighlights();
    final verseSet = verses.toSet();

    // Remove any existing highlights (any color/version) that cover these verses.
    final remaining = <BibleHighlight>[];
    for (final h in all) {
      if (h.book == book &&
          h.chapter == chapter &&
          h.verses.any((v) => verseSet.contains(v))) {
        continue; // drop covered verses
      }
      remaining.add(h);
    }

    remaining.add(BibleHighlight(
      versionId: versionId,
      book: book,
      chapter: chapter,
      verses: verses,
      colorIndex: colorIndex,
      text: text,
      savedAt: DateTime.now(),
    ));
    await _saveAll(remaining);
    return colorIndex;
  }

  /// Removes highlights for [verses] in [book] [chapter] (any color). Returns
  /// the number of highlights removed, or 0 if none were present.
  Future<int> remove({
    required String book,
    required int chapter,
    required List<int> verses,
  }) async {
    final all = await loadHighlights();
    final verseSet = verses.toSet();
    int removed = 0;

    final remaining = <BibleHighlight>[];
    for (final h in all) {
      if (h.book == book && h.chapter == chapter) {
        final kept = <int>[];
        for (final v in h.verses) {
          if (verseSet.contains(v)) {
            removed++;
          } else {
            kept.add(v);
          }
        }
        if (kept.isEmpty) continue;
        remaining.add(BibleHighlight(
          versionId: h.versionId,
          book: h.book,
          chapter: h.chapter,
          verses: kept,
          colorIndex: h.colorIndex,
          text: h.text,
          savedAt: h.savedAt,
        ));
      } else {
        remaining.add(h);
      }
    }
    await _saveAll(remaining);
    return removed;
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
