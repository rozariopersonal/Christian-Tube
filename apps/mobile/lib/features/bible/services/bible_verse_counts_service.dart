import '../../engines/scripture/services/local_bible_service.dart';
import '../models/bible_verse_counts.dart';

/// Loads the per-chapter verse-row counts for a version.
///
/// On device the counts are derived from the installed SQLite copy (via the
/// adapter) so offline reading keeps a correct whole-Bible index. On web they
/// are streamed from the releases repo. Failures degrade to empty counts, which
/// the reader treats as a single-chapter fallback.
class BibleVerseCountsService {
  BibleVerseCountsService();

  final LocalBibleService _service = LocalBibleService();

  Future<BibleVerseCounts> loadForVersion(String versionId) async {
    try {
      final rows = await _service.getChapterVerseCounts(versionId);
      return BibleVerseCounts.fromJson(rows);
    } catch (_) {
      return const BibleVerseCounts([]);
    }
  }
}