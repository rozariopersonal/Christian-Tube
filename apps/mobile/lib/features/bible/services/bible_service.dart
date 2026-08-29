import 'package:dio/dio.dart';
import '../models/bible_version.dart';

class BibleService {
  static const String baseUrl = 'https://api.biblesupersearch.com/api';
  final Dio _dio;

  BibleService({Dio? dio}) : _dio = dio ?? Dio();

  Future<List<BibleVersion>> getVersions() async {
    try {
      final response = await _dio.get('$baseUrl/bibles');
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = response.data;
        final results = data['results'] as Map<String, dynamic>;
        
        return results.entries
            .map((e) => BibleVersion.fromJson(e.key, e.value))
            .toList();
      }
    } catch (e) {
      print('Error fetching bible versions: $e');
    }
    return [];
  }

  Future<List<BibleVerse>> getChapter(String versionShortname, String book, int chapter) async {
    try {
      final response = await _dio.get(
        '$baseUrl/',
        queryParameters: {
          'bible': versionShortname.toLowerCase(),
          'reference': '$book $chapter',
        },
      );
      
      if (response.statusCode == 200) {
        final data = response.data;
        if (data['results'] != null && data['results'].isNotEmpty) {
          final result = data['results'][0];
          final versesMap = result['verses'][versionShortname.toLowerCase()]['$chapter'] as Map<String, dynamic>?;
          
          if (versesMap != null) {
            return versesMap.entries.map((e) {
              // Strip HTML tags from text since API sometimes includes them
              String rawText = e.value.toString();
              String cleanText = rawText.replaceAll(RegExp(r'<[^>]*>'), '');
              return BibleVerse(
                number: int.tryParse(e.key) ?? 0,
                text: cleanText,
              );
            }).toList();
          }
        }
      }
    } catch (e) {
      print('Error fetching chapter: $e');
    }
    return [];
  }
}
