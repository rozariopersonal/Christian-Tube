import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/core/theme/highlight_palette.dart';
import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';
import 'package:mobile/features/user_items/services/user_item_sync_service.dart';
import 'package:mobile/shared/annotations/user_item.dart';
import 'package:mobile/shared/annotations/user_item_repository.dart';
import '../models/bible_highlight.dart';

/// Persists per-verse color highlights for the Bible reader.
///
/// **Two-tier storage**: pre-auth, highlights live in the local Bible SQLite
/// database (native) or SharedPreferences (web) via [LocalBibleService] and are
/// never uploaded. Once a user signs in, [UserItemSyncService] re-homes those
/// device highlights into the per-user `user_items` store and all reads/writes
/// route there; the user tier is then synchronized with the backend database.
/// Highlights keep the replace model (one color per verse) in both tiers.
class BibleHighlightService {
  bool get _userTier => UserItemSyncService.instance.isUserTierActive;
  String get _userId => UserItemSyncService.instance.currentUserId!;

  String get _migrationFlagKey =>
      'bible_highlights_palette_v2_migrated_${_userTier ? _userId : "device"}';

  Future<List<BibleHighlight>> loadHighlights() async {
    final list = _userTier
        ? await _loadUserHighlights()
        : await LocalBibleService().loadHighlights();
    return _migrateLegacyIfNeeded(list);
  }

  Future<List<BibleHighlight>> _migrateLegacyIfNeeded(
      List<BibleHighlight> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_migrationFlagKey) == true) return list;
      if (list.isEmpty) {
        await prefs.setBool(_migrationFlagKey, true);
        return list;
      }
      var changed = false;
      final migrated = <BibleHighlight>[];
      for (final h in list) {
        final nextColor = HighlightPalette.migrateLegacyIndex(h.colorIndex);
        if (nextColor != h.colorIndex) changed = true;
        migrated.add(BibleHighlight(
          versionId: h.versionId,
          book: h.book,
          chapter: h.chapter,
          verses: h.verses,
          colorIndex: nextColor,
          text: h.text,
          savedAt: h.savedAt,
        ));
      }
      if (changed) await _saveAll(migrated);
      await prefs.setBool(_migrationFlagKey, true);
      return migrated;
    } catch (_) {
      return list;
    }
  }

  /// Device-tier-only load (used by sign-in re-home, never routed).
  Future<List<BibleHighlight>> loadDeviceHighlights() =>
      LocalBibleService().loadHighlights();

  Future<List<BibleHighlight>> _loadUserHighlights() async {
    final items = await UserItemRepository.instance
        .loadForType(_userId, UserItem.typeHighlight);
    return items.map((i) => i.toBibleHighlight()).toList();
  }

  Future<void> _saveAll(List<BibleHighlight> highlights) async {
    if (_userTier) {
      final items = <UserItem>[
        for (final h in highlights) ...UserItem.fromBibleHighlight(h, _userId),
      ];
      await UserItemRepository.instance
          .replaceForType(_userId, UserItem.typeHighlight, items);
      UserItemSyncService.instance.schedulePush();
      return;
    }
    await LocalBibleService().saveHighlights(highlights);
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

    // Remove any existing highlights (any color/version) that cover these verses,
    // keeping the non-covered verses as a leftover run so unselected verses
    // don't silently lose their highlight.
    final remaining = <BibleHighlight>[];
    for (final h in all) {
      if (h.book == book &&
          h.chapter == chapter &&
          h.verses.any((v) => verseSet.contains(v))) {
        final kept = h.verses.where((v) => !verseSet.contains(v)).toList();
        if (kept.isEmpty) continue;
        remaining.add(BibleHighlight(
          versionId: h.versionId,
          book: h.book,
          chapter: h.chapter,
          verses: kept,
          colorIndex: h.colorIndex,
          text: h.text,
          savedAt: DateTime.now(),
        ));
        continue;
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
          savedAt: DateTime.now(),
        ));
      } else {
        remaining.add(h);
      }
    }
    await _saveAll(remaining);
    return removed;
  }

  Future<void> clearAll() async {
    if (_userTier) {
      await UserItemRepository.instance
          .replaceForType(_userId, UserItem.typeHighlight, const []);
      UserItemSyncService.instance.schedulePush();
      return;
    }
    await LocalBibleService().clearHighlights();
  }

  /// Device-tier-only clear (used by sign-in re-home, never routed).
  Future<void> clearDeviceHighlights() =>
      LocalBibleService().clearHighlights();
}