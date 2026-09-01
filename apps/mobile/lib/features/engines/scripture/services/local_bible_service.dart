import 'package:flutter/foundation.dart';
import 'package:mobile/features/bible/models/bible_background_note.dart';
import 'package:mobile/features/bible/models/cross_reference.dart';
import 'package:mobile/features/engines/scripture/adapters/bible_data_adapter.dart';
import 'package:mobile/features/engines/scripture/adapters/sqlite_bible_data_adapter.dart';
import 'package:mobile/features/engines/scripture/adapters/web_bible_data_adapter.dart';

class LocalBibleService {
  static final LocalBibleService _instance = LocalBibleService._internal();
  factory LocalBibleService() => _instance;
  LocalBibleService._internal();

  late BibleDataAdapter _adapter;

  @visibleForTesting
  static String? overrideDbPath;

  @visibleForTesting
  static Future<void> resetForTest() async {
    await _instance._adapter.close();
    if (kIsWeb) {
      _instance._adapter = WebBibleDataAdapter();
    } else {
      _instance._adapter = SqliteBibleDataAdapter(overrideDbPath: overrideDbPath);
    }
  }

  Future<void> initialize() async {
    if (kIsWeb) {
      _adapter = WebBibleDataAdapter();
    } else {
      _adapter = SqliteBibleDataAdapter(overrideDbPath: overrideDbPath);
    }
    await _adapter.initialize();
  }

  Future<bool> hasVerses(String versionId) {
    return _adapter.hasVerses(versionId);
  }

  Future<String?> resolvePassage({
    required String versionId,
    required int bookNumber,
    required int chapter,
    required int startVerse,
    int? endVerse,
  }) {
    return _adapter.resolvePassage(
      versionId: versionId,
      bookNumber: bookNumber,
      chapter: chapter,
      startVerse: startVerse,
      endVerse: endVerse,
    );
  }

  String? resolvePassageSync({
    required String versionId,
    required int bookNumber,
    required int chapter,
    required int startVerse,
    int? endVerse,
  }) {
    return _adapter.resolvePassageSync(
      versionId: versionId,
      bookNumber: bookNumber,
      chapter: chapter,
      startVerse: startVerse,
      endVerse: endVerse,
    );
  }

  Future<Map<String, String>> resolvePassages({
    required String versionId,
    required List<(int bookNumber, int chapter, int verse, int? endVerse)> passages,
  }) {
    return _adapter.resolvePassages(versionId: versionId, passages: passages);
  }

  Future<List<String>> getInstalledVersionIds() {
    return _adapter.getInstalledVersionIds();
  }

  Future<void> registerInstalledVersion({
    required String id,
    required String name,
    required String language,
    required String languageCode,
    required String sizeDisplay,
  }) {
    return _adapter.registerInstalledVersion(
      id: id,
      name: name,
      language: language,
      languageCode: languageCode,
      sizeDisplay: sizeDisplay,
    );
  }

  Future<void> insertVerses(String versionId, List<Map<String, dynamic>> verses) {
    return _adapter.insertVerses(versionId, verses);
  }

  Future<void> deleteVersion(String versionId) {
    return _adapter.deleteVersion(versionId);
  }

  Future<bool> hasCrossReferences() {
    return _adapter.hasCrossReferences();
  }

  Future<void> insertCrossReferences(List<Map<String, dynamic>> items) {
    return _adapter.insertCrossReferences(items);
  }

  Future<void> deleteCrossReferences() {
    return _adapter.deleteCrossReferences();
  }

  Future<Map<int, List<CrossReference>>> getCrossReferencesForChapter(int bookNumber, int chapter) {
    return _adapter.getCrossReferencesForChapter(bookNumber, chapter);
  }

  Future<bool> hasBibleBackgrounds() {
    return _adapter.hasBackgrounds();
  }

  Future<void> insertBibleBackgrounds(List<Map<String, dynamic>> items) {
    return _adapter.insertBackgrounds(items);
  }

  Future<void> deleteBibleBackgrounds() {
    return _adapter.deleteBackgrounds();
  }

  Future<Map<int, List<BibleBackgroundNote>>> getBackgroundsForChapter(int bookNumber, int chapter) {
    return _adapter.getBackgroundsForChapter(bookNumber, chapter);
  }

  Future<List<BibleBackgroundNote>> getBackgroundsForVerse(int bookNumber, int chapter, int verse) async {
    final chapterMap = await getBackgroundsForChapter(bookNumber, chapter);
    return chapterMap[verse] ?? [];
  }

  Future<List<Map<String, dynamic>>> search(String versionId, String query, {int limit = 100}) {
    return _adapter.search(versionId, query, limit: limit);
  }

  Future<List<Map<String, dynamic>>> getChapter(String versionId, String bookName, int chapter) {
    return _adapter.getChapter(versionId, bookName, chapter);
  }
}
