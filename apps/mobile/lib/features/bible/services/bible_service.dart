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
}
