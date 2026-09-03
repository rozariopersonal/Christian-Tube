import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:mobile/core/api/github_data_service.dart';
import '../../models/verse_concept.dart';
import 'bible_study_repository.dart';

/// Fetches Bible study concepts (word/term definitions) per chapter from
/// the releases CDN. Results are cached in memory for the session.
///
/// Study data is organized by Bible version:
///   `study/{versionId}/chapters/b{bb}_c{ccc}.json`
class BibleStudyWebService implements BibleStudyRepository {
  /// The Bible version whose study data this service fetches.
  final String versionId;

  BibleStudyWebService({this.versionId = 'taobvsi'});

  final Map<String, dynamic> _chapterCache = {};
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
  ));

  @override
  Future<void> initialize() async {}

  @override
  Future<List<VerseConcept>> getConceptsForVerse(
      int book, int chapter, int verse) async {
    final cacheKey = 'b${book}_c$chapter';

    if (!_chapterCache.containsKey(cacheKey)) {
      try {
        final urls = GitHubDataService.studyChapterUrls(versionId, book, chapter);
        dynamic data;
        for (final url in urls) {
          try {
            final res = await _dio.get<dynamic>(url,
                options: Options(responseType: ResponseType.json));
            if (res.statusCode == 200 && res.data != null) {
              data = res.data is String ? jsonDecode(res.data as String) : res.data;
              break;
            }
          } catch (_) {
            continue;
          }
        }
        _chapterCache[cacheKey] = data; // null marks failure → no refetch
      } catch (_) {
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
