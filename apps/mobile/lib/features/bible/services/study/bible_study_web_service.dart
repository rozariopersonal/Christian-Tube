import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/config/app_config.dart';
import '../../models/verse_concept.dart';
import 'bible_study_repository.dart';

class BibleStudyWebService implements BibleStudyRepository {
  final Map<String, dynamic> _chapterCache = {};

  @override
  Future<void> initialize() async {
    // No initialization needed for Web HTTP fetcher
  }

  @override
  Future<List<VerseConcept>> getConceptsForVerse(int book, int chapter, int verse) async {
    final cacheKey = 'b${book}_c$chapter';
    
    if (!_chapterCache.containsKey(cacheKey)) {
      try {
        final bookStr = book.toString().padLeft(2, '0');
        final chapterStr = chapter.toString().padLeft(3, '0');
        // Fetching directly from the raw GitHub user content of the releases/data repo
        final url = Uri.parse(
          'https://raw.githubusercontent.com/${AppConfig.releasesRepo}/main/data/study_ta_ovbsi/chapters/b${bookStr}_c${chapterStr}.json'
        );
        
        final response = await http.get(url);
        if (response.statusCode == 200) {
          _chapterCache[cacheKey] = jsonDecode(response.body);
        } else {
          _chapterCache[cacheKey] = null; // Mark as failed to avoid refetching immediately
        }
      } catch (e) {
        _chapterCache[cacheKey] = null;
      }
    }

    final chapterData = _chapterCache[cacheKey];
    if (chapterData == null || chapterData['terms'] == null) {
      return [];
    }

    final List<dynamic> terms = chapterData['terms'];
    final List<VerseConcept> concepts = [];

    for (final term in terms) {
      // Filter for the specific verse
      if (term['reference'] != null && term['reference']['verse'] == verse) {
        concepts.add(VerseConcept.fromJson(term as Map<String, dynamic>));
      }
    }

    return concepts;
  }
}
