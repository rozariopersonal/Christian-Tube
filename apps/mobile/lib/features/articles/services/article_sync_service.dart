import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile/core/api/github_data_service.dart';
import 'package:mobile/core/api/release_assets.dart';
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

  Future<ArticleData?> getArticle(String articleId, {String? lang}) async {
    final code = (lang == null || lang.trim().isEmpty)
        ? 'en'
        : lang.trim().toLowerCase();

    // Key the cache (memory + disk) by the dataset revision so a data push
    // with a bumped `manifest.json` revision refetches article bodies instead
    // of serving stale text for the rest of the session/installs.
    final revision = ReleaseAssets.revision.trim();
    final revisionTag = revision.isEmpty
        ? ''
        : '_${revision.replaceAll(RegExp(r'[^\w]'), '_')}';
    final cacheKey = '$code/$articleId$revisionTag';
    final fileName = '${code}_$articleId$revisionTag.json';

    // 1. Check memory cache (instant)
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey];
    }

    final cacheDir = await _getCacheDirectory();
    final localFile = File(p.join(cacheDir, fileName));

    // 2. Check disk cache
    if (await localFile.exists()) {
      try {
        final content = await localFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final article = ArticleData.fromJson(json);
        _memoryCache[cacheKey] = article;
        return article;
      } catch (e) {
        debugPrint('Failed to read cached article $cacheKey: $e');
      }
    }

    // 3. Fetch from remote CDN
    final urls = GitHubDataService.languageArticleUrls(code, articleId);
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
          _memoryCache[cacheKey] = article;

          // Save to disk cache asynchronously
          localFile
              .writeAsString(response.data!)
              .catchError((_) => localFile);

          // Drop cache files for the same article from older revisions.
          _pruneStaleFiles(cacheDir, code, articleId, fileName);

          return article;
        }
      } catch (e) {
        debugPrint('Error fetching article from $url: $e');
      }
    }

    throw Exception('Failed to load article. Please check your internet connection.');
  }

  /// Deletes disk-cache files for [articleId] under [code] that belong to a
  /// different dataset revision, keeping only [keepFileName]. Best effort.
  Future<void> _pruneStaleFiles(
    String cacheDir,
    String code,
    String articleId,
    String keepFileName,
  ) async {
    try {
      final directory = Directory(cacheDir);
      if (!await directory.exists()) return;
      final prefix = '${code}_$articleId';
      final keepPath = p.join(cacheDir, keepFileName);
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        try {
          final name = p.basename(entity.path);
          if (name.startsWith(prefix) &&
              name.endsWith('.json') &&
              entity.path != keepPath) {
            await entity.delete();
          }
        } catch (e) {
          debugPrint('Failed to delete stale article cache file: $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to prune stale article cache files: $e');
    }
  }
}
