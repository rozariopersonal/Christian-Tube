import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bible_bookmark.dart';

class BibleBookmarkService {
  static const String _key = 'bible_bookmarks_v1';

  Future<List<BibleBookmark>> loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => BibleBookmark.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<BibleBookmark> bookmarks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(bookmarks.map((b) => b.toJson()).toList()),
    );
  }

  Future<bool> isBookmarked(String versionId, String book, int chapter, int verse) async {
    final bookmarks = await loadBookmarks();
    return bookmarks.any((b) =>
        b.versionId == versionId &&
        b.book == book &&
        b.chapter == chapter &&
        b.verse == verse);
  }

  /// Adds or removes a bookmark for [verse] in [book] [chapter]. Returns true
  /// if the verse is now bookmarked (added), false if it was removed.
  Future<bool> toggle({
    required String versionId,
    required String book,
    required int chapter,
    required int verse,
    required String text,
  }) async {
    final bookmarks = await loadBookmarks();
    final existingIndex = bookmarks.indexWhere((b) =>
        b.versionId == versionId &&
        b.book == book &&
        b.chapter == chapter &&
        b.verse == verse);
    if (existingIndex != -1) {
      bookmarks.removeAt(existingIndex);
      await _saveAll(bookmarks);
      return false;
    }
    bookmarks.insert(
      0,
      BibleBookmark(
        versionId: versionId,
        book: book,
        chapter: chapter,
        verse: verse,
        text: text,
        savedAt: DateTime.now(),
      ),
    );
    await _saveAll(bookmarks);
    return true;
  }

  Future<void> remove(BibleBookmark bookmark) async {
    final bookmarks = await loadBookmarks();
    bookmarks.removeWhere((b) =>
        b.versionId == bookmark.versionId &&
        b.book == bookmark.book &&
        b.chapter == bookmark.chapter &&
        b.verse == bookmark.verse);
    await _saveAll(bookmarks);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
