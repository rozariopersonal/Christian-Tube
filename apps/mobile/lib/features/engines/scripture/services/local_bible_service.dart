import 'package:flutter/foundation.dart';
import 'package:mobile/features/engines/scripture/adapters/bible_data_adapter.dart';
import 'package:mobile/features/engines/scripture/adapters/sqlite_bible_data_adapter.dart';
import 'package:mobile/features/engines/scripture/adapters/web_bible_data_adapter.dart';

class LocalBibleService {
  static final LocalBibleService _instance = LocalBibleService._internal();
  factory LocalBibleService() => _instance;
  LocalBibleService._internal();

  BibleDataAdapter? _adapterInstance;

  @visibleForTesting
  static String? overrideDbPath;

  BibleDataAdapter get _adapter {
    if (_adapterInstance == null) {
      if (kIsWeb) {
        _adapterInstance = WebBibleDataAdapter();
      } else {
        _adapterInstance = SqliteBibleDataAdapter(overrideDbPath: overrideDbPath);
      }
      _adapterInstance!.initialize();
    }
    return _adapterInstance!;
  }

  Future<BibleDataAdapter> _getAdapter() async {
    if (_adapterInstance == null) {
      await initialize();
    }
    return _adapterInstance!;
  }

  @visibleForTesting
  static Future<void> resetForTest() async {
    if (_instance._adapterInstance != null) {
      await _instance._adapterInstance!.close();
    }
    if (kIsWeb) {
      _instance._adapterInstance = WebBibleDataAdapter();
    } else {
      _instance._adapterInstance = SqliteBibleDataAdapter(overrideDbPath: overrideDbPath);
    }
    await _instance._adapterInstance!.initialize();
  }

  Future<void> initialize() async {
    if (_adapterInstance != null) {
      await _adapterInstance!.initialize();
      return;
    }
    if (kIsWeb) {
      _adapterInstance = WebBibleDataAdapter();
    } else {
      _adapterInstance = SqliteBibleDataAdapter(overrideDbPath: overrideDbPath);
    }
    await _adapterInstance!.initialize();
  }

  Future<bool> hasVerses(String versionId) async {
    final adapter = await _getAdapter();
    return adapter.hasVerses(versionId);
  }

  Future<String?> resolvePassage({
    required String versionId,
    required int bookNumber,
    required int chapter,
    required int startVerse,
    int? endVerse,
  }) async {
    final adapter = await _getAdapter();
    return adapter.resolvePassage(
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
  }) async {
    final adapter = await _getAdapter();
    return adapter.resolvePassages(versionId: versionId, passages: passages);
  }

  Future<List<String>> getInstalledVersionIds() async {
    final adapter = await _getAdapter();
    return adapter.getInstalledVersionIds();
  }

  Future<List<Map<String, dynamic>>> getInstalledVersions() async {
    final adapter = await _getAdapter();
    return adapter.getInstalledVersions();
  }

  Future<void> registerInstalledVersion({
    required String id,
    required String name,
    required String language,
    required String languageCode,
    required String sizeDisplay,
  }) async {
    final adapter = await _getAdapter();
    return adapter.registerInstalledVersion(
      id: id,
      name: name,
      language: language,
      languageCode: languageCode,
      sizeDisplay: sizeDisplay,
    );
  }

  Future<void> insertVerses(String versionId, List<Map<String, dynamic>> verses) async {
    final adapter = await _getAdapter();
    return adapter.insertVerses(versionId, verses);
  }

  Future<void> deleteVersion(String versionId) async {
    final adapter = await _getAdapter();
    return adapter.deleteVersion(versionId);
  }

  Future<List<Map<String, dynamic>>> search(String versionId, String query, {int limit = 100}) async {
    final adapter = await _getAdapter();
    return adapter.search(versionId, query, limit: limit);
  }

  Future<List<Map<String, dynamic>>> getChapter(String versionId, String bookName, int chapter) async {
    final adapter = await _getAdapter();
    return adapter.getChapter(versionId, bookName, chapter);
  }

  Future<List<List<int>>> getChapterVerseCounts(String versionId) async {
    final adapter = await _getAdapter();
    return adapter.getChapterVerseCounts(versionId);
  }
}
