import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile/core/api/github_data_service.dart';
import 'feed_data_adapter.dart';
import 'dart:math';

class WebFeedDataAdapter implements FeedDataAdapter {
  List<Map<String, dynamic>>? _cachedFeed;
  @override
  final ValueNotifier<double> downloadProgress = ValueNotifier(0.0);

  @override
  Future<void> initialize() async {
    if (_cachedFeed != null) return;
    
    downloadProgress.value = 0.0;
    final dio = Dio();
    final urls = GitHubDataService.scripturesFeedUrls();
    Object? lastError;
    
    for (final url in urls) {
      try {
        final res = await dio.get<dynamic>(
          url,
          options: Options(
            responseType: ResponseType.json,
            receiveTimeout: const Duration(minutes: 5),
          ),
          onReceiveProgress: (received, total) {
            if (total != -1) {
              downloadProgress.value = received / total;
            }
          },
        );
        if (res.statusCode == 200 && res.data != null) {
          final List<dynamic> list = res.data is String ? jsonDecode(res.data as String) : (res.data as List<dynamic>);
          
          _cachedFeed = list.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final item = entry.value as Map<String, dynamic>;
            return {
              'id': idx,
              'engine': item['engine'] ?? 'scripture',
              'bookNumber': item['bookNumber'],
              'bookName': item['bookName'],
              'chapter': item['chapter'],
              'startVerse': item['startVerse'],
              'endVerse': item['endVerse'],
              'referenceLabel': item['referenceLabel'],
              'category': item['category'],
              'backgroundPreset': item['backgroundPreset'],
              'tags': item['tags'] ?? [], // Already decoded on web JSON
              'isFeatured': item['isFeatured'] == true,
            };
          }).toList();
          lastError = null;
          break;
        }
      } catch (e) {
        lastError = e;
      }
    }
    
    if (lastError != null && _cachedFeed == null) {
      throw StateError('Unable to fetch web feed payload: $lastError');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getRandomItems(
    int limit, {
    String? bookFilter,
    String? testamentFilter,
    List<String>? excludeIds,
  }) async {
    if (_cachedFeed == null) await initialize();
    if (_cachedFeed == null || _cachedFeed!.isEmpty) return [];

    var filtered = _cachedFeed!.where((item) {
      if (bookFilter != null && bookFilter.isNotEmpty && bookFilter != 'All Books') {
        if (item['bookName'] != bookFilter) return false;
      }
      if (testamentFilter != null && testamentFilter.isNotEmpty && testamentFilter != 'All') {
        final int bookNumber = item['bookNumber'] as int;
        if (testamentFilter == 'Old Testament' && bookNumber > 39) return false;
        if (testamentFilter == 'New Testament' && bookNumber < 40) return false;
      }
      if (excludeIds != null && excludeIds.isNotEmpty) {
        if (excludeIds.contains(item['id'].toString())) return false;
      }
      return true;
    }).toList();

    filtered.shuffle(Random());
    return filtered.take(limit).toList();
  }
}
