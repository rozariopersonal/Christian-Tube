import 'package:mobile/features/bible/models/bible_background_note.dart';
import 'package:mobile/features/bible/models/cross_reference.dart';

abstract class BibleDataAdapter {
  Future<void> initialize();
  Future<void> close();
  
  Future<List<String>> getInstalledVersionIds();
  Future<bool> hasVerses(String versionId);
  Future<List<Map<String, dynamic>>> getChapter(String versionId, String bookName, int chapter);
  Future<List<Map<String, dynamic>>> search(String versionId, String query, {int limit = 100});
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
    required List<(int bookNumber, int chapter, int verse, int? endVerse)> passages,
  });
  Future<void> insertVerses(String versionId, List<Map<String, dynamic>> verses);
  Future<void> registerInstalledVersion({
    required String id,
    required String name,
    required String language,
    required String languageCode,
    required String sizeDisplay,
  });
  Future<void> deleteVersion(String versionId);

  // Cross References
  Future<bool> hasCrossReferences();
  Future<Map<int, List<CrossReference>>> getCrossReferencesForChapter(int bookNumber, int chapter);
  Future<void> insertCrossReferences(List<Map<String, dynamic>> items);
  Future<void> deleteCrossReferences();

  // Backgrounds
  Future<bool> hasBackgrounds();
  Future<Map<int, List<BibleBackgroundNote>>> getBackgroundsForChapter(int bookNumber, int chapter);
  Future<void> insertBackgrounds(List<Map<String, dynamic>> items);
  Future<void> deleteBackgrounds();
}
