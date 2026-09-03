abstract class BibleDataAdapter {
  Future<void> initialize();
  Future<void> close();

  Future<List<String>> getInstalledVersionIds();
  Future<bool> hasVerses(String versionId);
  Future<List<Map<String, dynamic>>> getChapter(
      String versionId, String bookName, int chapter);
  Future<List<Map<String, dynamic>>> search(String versionId, String query,
      {int limit = 100});
  Future<String?> resolvePassage({
    required String versionId,
    required int bookNumber,
    required int chapter,
    required int startVerse,
    int? endVerse,
  });
  String? resolvePassageSync({
    required String versionId,
    required int bookNumber,
    required int chapter,
    required int startVerse,
    int? endVerse,
  });
  Future<Map<String, String>> resolvePassages({
    required String versionId,
    required List<(int bookNumber, int chapter, int verse, int? endVerse)>
        passages,
  });
  Future<void> insertVerses(
      String versionId, List<Map<String, dynamic>> verses);
  Future<void> registerInstalledVersion({
    required String id,
    required String name,
    required String language,
    required String languageCode,
    required String sizeDisplay,
  });
  Future<void> deleteVersion(String versionId);
}
