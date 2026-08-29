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

  /// English translations the free API can serve in their own language.
  /// Non-English versions (Tamil, Malayalam, Telugu, ...) must never be
  /// silently replaced with English, or the user sees the wrong language.
  static const Set<String> _supportedTranslations = {'WEB', 'KJV', 'ASV', 'BBE'};

  /// Whether the remote API can return [versionId] in its own language.
  bool supportsVersion(String versionId) =>
      _supportedTranslations.contains(versionId.toUpperCase());

  Future<String?> fetchPassage({
    required String versionId,
    required String referenceLabel, // e.g. "John 14:27"
    required int bookNumber,
    required int chapter,
    required int startVerse,
    int? endVerse,
  }) async {
    if (!supportsVersion(versionId)) {
      return null;
    }

    final cacheKey =
        '${versionId}_${bookNumber}_${chapter}_${startVerse}_${endVerse ?? startVerse}';
    if (_verseCache.containsKey(cacheKey)) {
      return _verseCache[cacheKey];
    }

    try {
      // Free public Bible API endpoint (bible-api.com) with translation fallback.
      // For a multi-verse range, request the explicit "Book Ch:Start-End" form so
      // the whole passage is returned rather than only the labelled verse.
      final isRange = endVerse != null && endVerse > startVerse;
      final book = _extractBook(referenceLabel);
      final queryRef = book != null && isRange
          ? '$book $chapter:$startVerse-$endVerse'
          : referenceLabel;

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

  /// Extracts the leading book name from a reference label like "John 14:27"
  /// or "1 Peter 5:7", returning null if no book prefix can be determined.
  String? _extractBook(String referenceLabel) {
    final trimmed = referenceLabel.trim();
    final match = RegExp(r'^(.+?)\s+\d+:\d+').firstMatch(trimmed);
    return match?.group(1);
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
