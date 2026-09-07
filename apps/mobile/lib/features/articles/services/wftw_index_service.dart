import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/api/github_data_service.dart';
import '../models/wftw_index_entry.dart';

/// Loads the Word-for-the-Week article index. Injectable so widget tests can
/// supply a fake without network access.
typedef WftwIndexLoader = Future<List<WftwIndexEntry>> Function();

/// Fetch + memory cache for the Word-for-the-Week article index
/// (`articles/wftw_index.json`).
///
/// Web-safe: unlike the feed SQLite sync, this uses plain HTTP (no `dart:io`,
/// no `sqflite`), so the teaching browser works on both mobile and web.
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

  List<WftwIndexEntry>? _cache;

  Future<List<WftwIndexEntry>> getIndex() async {
    final cached = _cache;
    if (cached != null) return cached;

    final urls = GitHubDataService.wftwIndexUrls();
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
          _cache = entries;
          return entries;
        }
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(
      'Failed to load Word for the Week index'
      '${lastError != null ? ': $lastError' : ''}. '
      'Please check your internet connection.',
    );
  }
}