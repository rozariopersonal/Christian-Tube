import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/api/github_data_service.dart';
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

/// Fetch + memory cache for the Word-for-the-Week combined multi-language
/// article index (`articles/articles_index.json`) and the language catalog.
///
/// Web-safe: uses plain HTTP (no `dart:io`, no `sqflite`), so the teaching
/// browser works on both mobile and web.
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

  /// Combined multi-language articles index (`articles/articles_index.json`).
  Future<List<WftwIndexEntry>> getArticlesIndex() async {
    final cached = _combinedCache;
    if (cached != null) return cached;

    final urls = GitHubDataService.articlesIndexUrls();
    Object? lastError;
    for (final url in urls) {
      try {
        final response = await _dio.get<String>(
          url,
          options: Options(responseType: ResponseType.plain),
        );
        if (response.statusCode == 200 && response.data != null) {
          final decoded = jsonDecode(response.data!) as List<dynamic>;
          final entries = decoded
              .map((e) => WftwIndexEntry.fromJson(e as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
          _combinedCache = entries;
          return entries;
        }
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(
      'Failed to load articles index'
      '${lastError != null ? ': $lastError' : ''}. '
      'Please check your internet connection.',
    );
  }

  /// Language catalog (`articles/languages.json`): non-zero-count entries.
  Future<List<ArticleLanguage>> getLanguages() async {
    final urls = GitHubDataService.articlesLanguagesUrls();
    Object? lastError;
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
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(
      'Failed to load languages catalog'
      '${lastError != null ? ': $lastError' : ''}. '
      'Please check your internet connection.',
    );
  }
}