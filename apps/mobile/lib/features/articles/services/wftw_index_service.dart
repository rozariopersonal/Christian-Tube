import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/api/github_data_service.dart';
import '../../../core/api/release_assets.dart';
import '../models/wftw_index_entry.dart';

/// Loads the Word-for-the-Week article index. Injectable so widget tests can
/// supply a fake without network access.
typedef WftwIndexLoader = Future<List<WftwIndexEntry>> Function();

/// Combined multi-language catalog loader (Library articles shelf preview).
typedef ArticlesCatalogLoader = Future<List<WftwIndexEntry>> Function();

/// Languages catalog loader.
typedef ArticlesLanguagesLoader = Future<List<ArticleLanguage>> Function();

class ArticleLanguage {
  final String code;
  final String name;
  final int count;

  const ArticleLanguage({
    required this.code,
    required this.name,
    required this.count,
  });

  factory ArticleLanguage.fromJson(Map<String, dynamic> json) =>
      ArticleLanguage(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        count: json['count'] as int? ?? 0,
      );
}

List<WftwIndexEntry> _parseArticlesJson(String jsonString) {
  final decoded = jsonDecode(jsonString) as List<dynamic>;
  return decoded
      .map((e) => WftwIndexEntry.fromJson(e as Map<String, dynamic>))
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
}

/// Fetch + memory & disk cache for the Word-for-the-Week articles index
/// (`articles/articles_index.json`), recent preview (`articles/recent.json`),
/// and the language catalog.
class WftwIndexService {
  static final WftwIndexService _instance = WftwIndexService._internal();
  factory WftwIndexService() => _instance;
  WftwIndexService._internal();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  List<WftwIndexEntry>? _combinedCache;
  List<WftwIndexEntry>? _recentCache;

  Future<File?> _getCacheFile(String baseName) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory(p.join(dir.path, 'articles_cache'));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      final rev =
          ReleaseAssets.revision.trim().replaceAll(RegExp(r'[^\w]'), '_');
      final fileName =
          rev.isEmpty ? '$baseName.json' : '${baseName}_$rev.json';
      return File(p.join(cacheDir.path, fileName));
    } catch (_) {
      return null;
    }
  }

  /// Recent articles preview for instant Library shelf rendering (~5-6 KB).
  Future<List<WftwIndexEntry>> getRecentArticles({bool forceRefresh = false}) async {
    if (!forceRefresh && _recentCache != null && _recentCache!.isNotEmpty) {
      return _recentCache!;
    }

    final cacheFile = await _getCacheFile('recent');
    if (!forceRefresh && cacheFile != null && await cacheFile.exists()) {
      try {
        final content = await cacheFile.readAsString();
        final entries = _parseArticlesJson(content);
        _recentCache = entries;
        return entries;
      } catch (e) {
        debugPrint('Failed to read recent articles disk cache: $e');
      }
    }

    final urls = [
      ...GitHubDataService.articlesRecentUrls(),
      ...GitHubDataService.articlesIndexUrls(),
    ];

    for (final url in urls) {
      try {
        final response = await _dio.get<String>(
          url,
          options: Options(responseType: ResponseType.plain),
        );
        if (response.statusCode == 200 && response.data != null) {
          final entries = _parseArticlesJson(response.data!);
          final recent = entries.length > 30 ? entries.sublist(0, 30) : entries;
          _recentCache = recent;
          if (cacheFile != null) {
            try {
              await cacheFile.writeAsString(response.data!);
            } catch (_) {}
          }
          return recent;
        }
      } catch (_) {}
    }

    return _recentCache ?? const [];
  }

  /// Combined multi-language articles index (`articles/articles_index.json`).
  Future<List<WftwIndexEntry>> getArticlesIndex({bool forceRefresh = false}) async {
    final cached = _combinedCache;
    if (!forceRefresh && cached != null) return cached;

    final cacheFile = await _getCacheFile('index');
    if (!forceRefresh && cacheFile != null && await cacheFile.exists()) {
      try {
        final content = await cacheFile.readAsString();
        final entries = await compute(_parseArticlesJson, content);
        _combinedCache = entries;
        return entries;
      } catch (e) {
        debugPrint('Failed to read articles index disk cache: $e');
      }
    }

    final urls = GitHubDataService.articlesIndexUrls();
    Object? lastError;
    for (final url in urls) {
      try {
        final response = await _dio.get<String>(
          url,
          options: Options(responseType: ResponseType.plain),
        );
        if (response.statusCode == 200 && response.data != null) {
          final entries = await compute(_parseArticlesJson, response.data!);
          _combinedCache = entries;
          if (cacheFile != null) {
            try {
              await cacheFile.writeAsString(response.data!);
            } catch (_) {}
          }
          return entries;
        }
      } catch (e) {
        lastError = e;
      }
    }

    if (_combinedCache != null) return _combinedCache!;
    if (_recentCache != null) return _recentCache!;

    throw Exception(
      'Failed to load articles index'
      '${lastError != null ? ': $lastError' : ''}. '
      'Please check your internet connection.',
    );
  }

  /// Language catalog (`articles/languages.json`): non-zero-count entries.
  Future<List<ArticleLanguage>> getLanguages() async {
    final urls = GitHubDataService.articlesLanguagesUrls();
    for (final url in urls) {
      try {
        final response = await _dio.get<String>(
          url,
          options: Options(responseType: ResponseType.plain),
        );
        if (response.statusCode == 200 && response.data != null) {
          final decoded = jsonDecode(response.data!) as List<dynamic>;
          return decoded
              .map((e) => ArticleLanguage.fromJson(e as Map<String, dynamic>))
              .where((l) => l.count > 0 && l.code.isNotEmpty)
              .toList();
        }
      } catch (_) {
        // Try fallback url
      }
    }
    return const [];
  }
}