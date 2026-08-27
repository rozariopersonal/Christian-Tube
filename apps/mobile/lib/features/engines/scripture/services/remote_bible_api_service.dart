import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class RemoteBibleApiService {
  static final RemoteBibleApiService _instance =
      RemoteBibleApiService._internal();
  factory RemoteBibleApiService() => _instance;
  RemoteBibleApiService._internal();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  // In-memory LRU cache for fetched remote verses
  final Map<String, String> _verseCache = {};

  Future<String?> fetchPassage({
    required String versionId,
    required String referenceLabel, // e.g. "John 14:27"
    required int bookNumber,
    required int chapter,
    required int startVerse,
    int? endVerse,
  }) async {
    final cacheKey =
        '${versionId}_${bookNumber}_${chapter}_${startVerse}_${endVerse ?? startVerse}';
    if (_verseCache.containsKey(cacheKey)) {
      return _verseCache[cacheKey];
    }

    try {
      // Free public Bible API endpoint (bible-api.com) with translation fallback
      final queryRef = endVerse != null && endVerse > startVerse
          ? '$referenceLabel'
          : '$referenceLabel';

      final response = await _dio.get(
        'https://bible-api.com/${Uri.encodeComponent(queryRef)}',
        queryParameters: {
          'translation': _mapToApiTranslation(versionId),
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final text = (response.data['text'] as String?)?.trim();
        if (text != null && text.isNotEmpty) {
          // Clean up newline characters
          final cleaned = text.replaceAll(RegExp(r'\s+'), ' ');
          _verseCache[cacheKey] = cleaned;
          return cleaned;
        }
      }
    } catch (e) {
      debugPrint('RemoteBibleApiService error for $referenceLabel: $e');
    }

    return null;
  }

  String _mapToApiTranslation(String versionId) {
    switch (versionId.toUpperCase()) {
      case 'KJV':
        return 'kjv';
      case 'BBE':
        return 'bbe';
      case 'ASV':
        return 'asv';
      case 'WEB':
      default:
        return 'web';
    }
  }
}
