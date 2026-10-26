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
    final urls = GitHubDataService.scripturesPoolUrls();
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
              'verseMappings': item['verseMappings'],
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
    int offset = 0,
    String? bookFilter,
    String? testamentFilter,
    List<String>? categoryFilter,
    List<String>? tagFilter,
    String order = 'random',
    List<String>? excludeIds,
  }) async {
    if (_cachedFeed == null) await initialize();
    if (_cachedFeed == null || _cachedFeed!.isEmpty) return [];

    final hasCategories = categoryFilter != null && categoryFilter.isNotEmpty;
    final hasTags = tagFilter != null && tagFilter.isNotEmpty;

    var filtered = _cachedFeed!.where((item) {
      if (bookFilter != null && bookFilter.isNotEmpty && bookFilter != 'All Books') {
        if (item['bookName'] != bookFilter) return false;
      }
      if (testamentFilter != null && testamentFilter.isNotEmpty && testamentFilter != 'All') {
        final int bookNumber = item['bookNumber'] as int;
        if (testamentFilter == 'Old Testament' && bookNumber > 39) return false;
        if (testamentFilter == 'New Testament' && bookNumber < 40) return false;
      }
      if (hasCategories && hasTags) {
        final catMatch = categoryFilter.contains(item['category']);
        final List<dynamic> itemTags = item['tags'] as List<dynamic>? ?? [];
        final tagMatch = itemTags.any((t) => tagFilter.contains(t.toString()));
        if (!catMatch && !tagMatch) return false;
      } else if (hasCategories) {
        if (!categoryFilter.contains(item['category'])) return false;
      } else if (hasTags) {
        final List<dynamic> itemTags = item['tags'] as List<dynamic>? ?? [];
        if (!itemTags.any((t) => tagFilter.contains(t.toString()))) return false;
      }

      if (excludeIds != null && excludeIds.isNotEmpty && order == 'random') {
        if (excludeIds.contains(item['id'].toString())) return false;
      }
      return true;
    }).toList();

    if (order == 'canonical') {
      filtered.sort((a, b) {
        final b1 = (a['bookNumber'] as int?) ?? 0;
        final b2 = (b['bookNumber'] as int?) ?? 0;
        if (b1 != b2) return b1.compareTo(b2);
        final c1 = (a['chapter'] as int?) ?? 0;
        final c2 = (b['chapter'] as int?) ?? 0;
        if (c1 != c2) return c1.compareTo(c2);
        final s1 = (a['startVerse'] as int?) ?? 0;
        final s2 = (b['startVerse'] as int?) ?? 0;
        return s1.compareTo(s2);
      });
      return filtered.skip(offset).take(limit).toList();
    } else {
      filtered.shuffle(Random());
      return filtered.take(limit).toList();
    }
  }
}
