import '../models/verse_concept.dart';

abstract class BibleStudyRepository {
  /// Initializes the service.
  Future<void> initialize();

  /// Fetches the theological concepts and original language data for a specific verse.
  Future<List<VerseConcept>> getConceptsForVerse(int book, int chapter, int verse);
}
