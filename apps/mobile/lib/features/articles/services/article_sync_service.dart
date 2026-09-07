import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile/core/api/github_data_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/article_data.dart';

class ArticleSyncService {
  static final ArticleSyncService _instance = ArticleSyncService._internal();
  factory ArticleSyncService() => _instance;
  ArticleSyncService._internal();

  final Map<String, ArticleData> _memoryCache = {};
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  Future<String> _getCacheDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'articles_cache'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  Future<ArticleData?> getArticle(String articleId) async {
    // 1. Check memory cache (instant)
    if (_memoryCache.containsKey(articleId)) {
      return _memoryCache[articleId];
    }

    final cacheDir = await _getCacheDirectory();
    final localFile = File(p.join(cacheDir, '$articleId.json'));

    // 2. Check disk cache
    if (await localFile.exists()) {
      try {
        final content = await localFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final article = ArticleData.fromJson(json);
        _memoryCache[articleId] = article;
        return article;
      } catch (e) {
        debugPrint('Failed to read cached article $articleId: $e');
      }
    }

    // 3. Fetch from remote CDN
    final urls = GitHubDataService.wftwArticleUrls(articleId);
    for (final url in urls) {
      try {
        final response = await _dio.get<String>(
          url,
          options: Options(responseType: ResponseType.plain),
        );

        if (response.statusCode == 200 && response.data != null) {
          final json = jsonDecode(response.data!) as Map<String, dynamic>;
          final article = ArticleData.fromJson(json);

          // Save to memory cache
          _memoryCache[articleId] = article;

          // Save to disk cache asynchronously
          localFile.writeAsString(response.data!).catchError((_) => localFile);

          return article;
        }
      } catch (e) {
        debugPrint('Error fetching article from $url: $e');
      }
    }

    // If fetch failed and disk cache exists, use disk cache
    if (await localFile.exists()) {
      final content = await localFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final article = ArticleData.fromJson(json);
      _memoryCache[articleId] = article;
      return article;
    }

    throw Exception('Failed to load article. Please check your internet connection.');
  }
}
