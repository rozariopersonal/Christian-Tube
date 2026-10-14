import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../bible/models/bible_book.dart';
import '../../../bible/models/book_abbreviation.dart';
import 'book_name_service.dart';

enum OnlineProvider { apiBible, youVersion }

typedef OnlineChapterListener = void Function(
  String versionId,
  int bookNumber,
  int chapter,
  List<Map<String, dynamic>> verses,
);

class OnlineBibleConfig {
  final String versionId;
  final String name;
  final String language;
  final String languageCode;
  final OnlineProvider provider;
  final String apiBibleId;
  final int youVersionId;
  final OnlineProvider? fallbackProvider;

  const OnlineBibleConfig({
    required this.versionId,
    required this.name,
    required this.language,
    required this.languageCode,
    required this.provider,
    this.apiBibleId = '',
    this.youVersionId = 0,
    this.fallbackProvider,
  });
}

class OnlineBibleService {
  static const String apiBibleKey = '7-rV1sxCwAuLPp4A2jAmQ';
  static const String youVersionAppKey = 'uXc7kDxs9Ay9ClVThpIsSIGHiw2clfTWgSOPgAl1B0V6Z6jM';

  static final Map<String, OnlineBibleConfig> _configs = {
    // English Modern
    'NASB': const OnlineBibleConfig(
      versionId: 'NASB',
      name: 'New American Standard Bible (1995)',
      language: 'English',
      languageCode: 'en',
      provider: OnlineProvider.apiBible,
      apiBibleId: 'b8ee27bcd1cae43a-01',
      youVersionId: 100,
      fallbackProvider: OnlineProvider.youVersion,
    ),
    'NLT': const OnlineBibleConfig(
      versionId: 'NLT',
      name: 'New Living Translation',
      language: 'English',
      languageCode: 'en',
      provider: OnlineProvider.apiBible,
      apiBibleId: 'd6e14a625393b4da-01',
    ),
    'MSG': const OnlineBibleConfig(
      versionId: 'MSG',
      name: 'The Message',
      language: 'English',
      languageCode: 'en',
      provider: OnlineProvider.apiBible,
      apiBibleId: '6f11a7de016f942e-01',
    ),
    'NIV': const OnlineBibleConfig(
      versionId: 'NIV',
      name: 'New International Version (2011)',
      language: 'English',
      languageCode: 'en',
      provider: OnlineProvider.youVersion,
      youVersionId: 111,
    ),
    'AMP': const OnlineBibleConfig(
      versionId: 'AMP',
      name: 'Amplified Bible',
      language: 'English',
      languageCode: 'en',
      provider: OnlineProvider.youVersion,
      youVersionId: 1588,
    ),

    // Indian Languages (Contemporary Versions)
    'HIN_HCV': const OnlineBibleConfig(
      versionId: 'HIN_HCV',
      name: 'Hindi Contemporary Version',
      language: 'Hindi',
      languageCode: 'hi',
      provider: OnlineProvider.apiBible,
      apiBibleId: '2133003bb8b5e62b-01',
    ),
    'TAM_TCV': const OnlineBibleConfig(
      versionId: 'TAM_TCV',
      name: 'Tamil Contemporary Version',
      language: 'Tamil',
      languageCode: 'ta',
      provider: OnlineProvider.apiBible,
      apiBibleId: '032ec262506b719f-01',
    ),
    'TEL_TCV': const OnlineBibleConfig(
      versionId: 'TEL_TCV',
      name: 'Telugu Contemporary Version',
      language: 'Telugu',
      languageCode: 'te',
      provider: OnlineProvider.apiBible,
      apiBibleId: '81d6933d39d343f8-03',
    ),
    'MAL_MCV': const OnlineBibleConfig(
      versionId: 'MAL_MCV',
      name: 'Malayalam Contemporary Version',
      language: 'Malayalam',
      languageCode: 'ml',
      provider: OnlineProvider.apiBible,
      apiBibleId: 'de295e9ba65f6d0f-01',
    ),
    'KAN_KCV': const OnlineBibleConfig(
      versionId: 'KAN_KCV',
      name: 'Kannada Contemporary Version',
      language: 'Kannada',
      languageCode: 'kn',
      provider: OnlineProvider.apiBible,
      apiBibleId: '08389f036844c2de-01',
    ),
    'BEN_BCV': const OnlineBibleConfig(
      versionId: 'BEN_BCV',
      name: 'Bengali Contemporary Version',
      language: 'Bengali',
      languageCode: 'bn',
      provider: OnlineProvider.apiBible,
      apiBibleId: 'efd8a351a07d4264-01',
    ),
    'MAR_MCV': const OnlineBibleConfig(
      versionId: 'MAR_MCV',
      name: 'Marathi Contemporary Version',
      language: 'Marathi',
      languageCode: 'mr',
      provider: OnlineProvider.apiBible,
      apiBibleId: '1c825c8591183bb0-01',
    ),
    'PAN_PCV': const OnlineBibleConfig(
      versionId: 'PAN_PCV',
      name: 'Punjabi Contemporary Version',
      language: 'Punjabi',
      languageCode: 'pa',
      provider: OnlineProvider.apiBible,
      apiBibleId: '38de522697cd8943-01',
    ),
    'URD_UCV': const OnlineBibleConfig(
      versionId: 'URD_UCV',
      name: 'Urdu Contemporary Version',
      language: 'Urdu',
      languageCode: 'ur',
      provider: OnlineProvider.apiBible,
      apiBibleId: 'eecbca904435fce9-01',
    ),
    'GUJ_IRV': const OnlineBibleConfig(
      versionId: 'GUJ_IRV',
      name: 'Gujarati IRV',
      language: 'Gujarati',
      languageCode: 'gu',
      provider: OnlineProvider.apiBible,
      apiBibleId: 'a3644a98420c2703-01',
    ),
    'ASM_IRV': const OnlineBibleConfig(
      versionId: 'ASM_IRV',
      name: 'Assamese IRV',
      language: 'Assamese',
      languageCode: 'as',
      provider: OnlineProvider.apiBible,
      apiBibleId: 'd199679f805f5b29-01',
    ),
  };

  static Set<String> get onlineVersionIds => _configs.keys.toSet();

  static bool isOnlineVersion(String versionId) =>
      _configs.containsKey(versionId.toUpperCase());

  static OnlineBibleConfig? getConfig(String versionId) =>
      _configs[versionId.toUpperCase()];

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
  ));

  static final Map<String, List<Map<String, dynamic>>> _memoryCache = {};
  static final Map<String, Future<List<Map<String, dynamic>>>> _inFlight = {};
  static final List<OnlineChapterListener> _chapterListeners = [];

  static final List<({String versionId, int bookNumber, int chapter})> _prefetchQueue = [];
  static final Set<String> _queuedKeys = {};
  static bool _isPrefetching = false;

  /// Registers a listener called whenever an online chapter finishes fetching.
  static void addChapterListener(OnlineChapterListener listener) {
    if (!_chapterListeners.contains(listener)) {
      _chapterListeners.add(listener);
    }
  }

  /// Removes a previously registered online chapter listener.
  static void removeChapterListener(OnlineChapterListener listener) {
    _chapterListeners.remove(listener);
  }

  static void _notifyChapterLoaded(
    String versionId,
    int bookNumber,
    int chapter,
    List<Map<String, dynamic>> verses,
  ) {
    for (final listener in List.of(_chapterListeners)) {
      try {
        listener(versionId, bookNumber, chapter, verses);
      } catch (e) {
        debugPrint('Error in OnlineChapterListener: $e');
      }
    }
  }

  /// Fetches a chapter from the live online provider (API.Bible or YouVersion).
  ///
  /// Deduplicates concurrent in-flight requests for the exact same chapter, caches
  /// results in memory, and notifies registered listeners on arrival.
  static Future<List<Map<String, dynamic>>> fetchLiveChapter(
    String versionId,
    int bookNumber,
    int chapter,
  ) async {
    final config = getConfig(versionId);
    if (config == null) return const [];

    final cacheKey = '${versionId.toUpperCase()}_${bookNumber}_$chapter';
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey]!;
    }

    final pending = _inFlight[cacheKey];
    if (pending != null) return pending;

    final future = _doFetchLiveChapter(config, bookNumber, chapter);
    _inFlight[cacheKey] = future;

    try {
      final results = await future;
      if (results.isNotEmpty) {
        _memoryCache[cacheKey] = results;
        _notifyChapterLoaded(versionId, bookNumber, chapter, results);
      }
      return results;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  static Future<List<Map<String, dynamic>>> _doFetchLiveChapter(
    OnlineBibleConfig config,
    int bookNumber,
    int chapter,
  ) async {
    final bookUsfm = BookAbbreviation.abbreviationFor(bookNumber) ?? 'GEN';
    final bookName = BookNameService.englishNameFor(bookNumber);

    try {
      if (config.provider == OnlineProvider.apiBible) {
        return await _fetchApiBible(config, bookUsfm, bookNumber, bookName, chapter);
      } else {
        return await _fetchYouVersion(config, bookUsfm, bookNumber, bookName, chapter);
      }
    } catch (e) {
      debugPrint('OnlineBibleService primary fetch failed for ${config.versionId}: $e');
      if (config.fallbackProvider == OnlineProvider.youVersion && config.youVersionId > 0) {
        try {
          return await _fetchYouVersion(config, bookUsfm, bookNumber, bookName, chapter);
        } catch (e2) {
          debugPrint('OnlineBibleService fallback fetch failed for ${config.versionId}: $e2');
        }
      } else if (config.fallbackProvider == OnlineProvider.apiBible && config.apiBibleId.isNotEmpty) {
        try {
          return await _fetchApiBible(config, bookUsfm, bookNumber, bookName, chapter);
        } catch (e2) {
          debugPrint('OnlineBibleService fallback fetch failed for ${config.versionId}: $e2');
        }
      }
      return const [];
    }
  }

  /// Asynchronously prefetches adjacent chapters before and after the anchor
  /// chapter in the background so that reading navigation is instantaneous.
  static void prefetchAdjacentChapters(
    String versionId,
    int bookNumber,
    int chapter, {
    int radius = 2,
    Future<bool> Function(int book, int ch)? isCachedLocally,
  }) {
    if (!isOnlineVersion(versionId)) return;

    // Next chapters (+1, +2, ...)
    var next = nextBibleChapter(bookNumber, chapter);
    for (int i = 0; i < radius && next != null; i++) {
      _enqueuePrefetch(versionId, next.$1, next.$2, isCachedLocally);
      next = nextBibleChapter(next.$1, next.$2);
    }

    // Previous chapters (-1, -2, ...)
    var prev = prevBibleChapter(bookNumber, chapter);
    for (int i = 0; i < radius && prev != null; i++) {
      _enqueuePrefetch(versionId, prev.$1, prev.$2, isCachedLocally);
      prev = prevBibleChapter(prev.$1, prev.$2);
    }
  }

  static void _enqueuePrefetch(
    String versionId,
    int bookNumber,
    int chapter,
    Future<bool> Function(int book, int ch)? isCachedLocally,
  ) {
    final key = '${versionId.toUpperCase()}_${bookNumber}_$chapter';
    if (_memoryCache.containsKey(key) ||
        _queuedKeys.contains(key) ||
        _inFlight.containsKey(key)) {
      return;
    }

    _queuedKeys.add(key);
    _prefetchQueue.add((versionId: versionId, bookNumber: bookNumber, chapter: chapter));
    _drainPrefetchQueue(isCachedLocally);
  }

  static Future<void> _drainPrefetchQueue(
    Future<bool> Function(int book, int ch)? isCachedLocally,
  ) async {
    if (_isPrefetching) return;
    _isPrefetching = true;

    try {
      while (_prefetchQueue.isNotEmpty) {
        final task = _prefetchQueue.removeAt(0);
        final key = '${task.versionId.toUpperCase()}_${task.bookNumber}_${task.chapter}';
        _queuedKeys.remove(key);

        if (_memoryCache.containsKey(key)) continue;

        if (isCachedLocally != null) {
          try {
            final alreadyCached = await isCachedLocally(task.bookNumber, task.chapter);
            if (alreadyCached) continue;
          } catch (_) {}
        }

        try {
          await fetchLiveChapter(task.versionId, task.bookNumber, task.chapter);
        } catch (_) {}

        // Courteous throttle between background prefetch requests so API limits are respected
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    } finally {
      _isPrefetching = false;
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchApiBible(
    OnlineBibleConfig config,
    String bookUsfm,
    int bookNumber,
    String bookName,
    int chapter,
  ) async {
    final url =
        'https://api.scripture.api.bible/v1/bibles/${config.apiBibleId}/chapters/$bookUsfm.$chapter?content-type=json&include-notes=false&include-titles=false&include-chapter-numbers=false&include-verse-numbers=true&include-verse-spans=true';

    final res = await _dio.get<dynamic>(
      url,
      options: Options(
        headers: {'api-key': apiBibleKey},
        responseType: ResponseType.json,
      ),
    );

    if (res.statusCode != 200 || res.data == null) return const [];

    final dynamic rawData = res.data;
    final Map<String, dynamic> data = rawData is String
        ? jsonDecode(rawData) as Map<String, dynamic>
        : (rawData as Map<String, dynamic>);

    final inner = data['data'];
    if (inner is! Map) return const [];
    final content = inner['content'];
    if (content is! List) return const [];

    final rawVerses = <String, String>{};
    String? currentKey;

    void walk(dynamic node) {
      if (node == null || node is! Map) return;
      final name = node['name'] as String?;
      final attrs = node['attrs'] as Map?;

      if (name == 'verse' && attrs != null) {
        final numAttr = attrs['number'] ?? attrs['sid'];
        if (numAttr != null) {
          currentKey = numAttr.toString().trim();
          if (!rawVerses.containsKey(currentKey)) {
            rawVerses[currentKey!] = '';
          }
          return;
        }
      }

      final type = node['type'] as String?;
      final text = node['text'] as String?;
      if (type == 'text' && text != null && currentKey != null) {
        rawVerses[currentKey!] = (rawVerses[currentKey!] ?? '') + text;
      }

      final items = node['items'];
      if (items is List) {
        for (final child in items) {
          walk(child);
        }
      }
    }

    for (final n in content) {
      walk(n);
    }

    final Map<int, String> finalVerses = {};
    for (final entry in rawVerses.entries) {
      final cleanText = entry.value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (cleanText.isEmpty) continue;

      final spanMatch = RegExp(r'(\d+)\s*[-–]\s*(\d+)').firstMatch(entry.key);
      if (spanMatch != null) {
        final start = int.tryParse(spanMatch.group(1)!) ?? 1;
        final end = int.tryParse(spanMatch.group(2)!) ?? start;
        for (int v = start; v <= end; v++) {
          finalVerses[v] = cleanText;
        }
      } else {
        final singleMatch = RegExp(r'(\d+)$').firstMatch(entry.key);
        if (singleMatch != null) {
          final v = int.tryParse(singleMatch.group(1)!) ?? 1;
          finalVerses[v] = cleanText;
        }
      }
    }

    final sortedNumbers = finalVerses.keys.toList()..sort();
    return sortedNumbers.map((v) => {
          'version_id': config.versionId,
          'book_name': bookName,
          'book_number': bookNumber,
          'chapter': chapter,
          'verse': v,
          'text': finalVerses[v]!,
        }).toList();
  }

  static Future<List<Map<String, dynamic>>> _fetchYouVersion(
    OnlineBibleConfig config,
    String bookUsfm,
    int bookNumber,
    String bookName,
    int chapter,
  ) async {
    final url =
        'https://api.youversion.com/v1/bibles/${config.youVersionId}/passages/$bookUsfm.$chapter?format=html';

    final res = await _dio.get<dynamic>(
      url,
      options: Options(
        headers: {'X-YVP-App-Key': youVersionAppKey},
        responseType: ResponseType.json,
      ),
    );

    if (res.statusCode != 200 || res.data == null) return const [];

    final dynamic rawData = res.data;
    final Map<String, dynamic> data = rawData is String
        ? jsonDecode(rawData) as Map<String, dynamic>
        : (rawData as Map<String, dynamic>);

    final html = data['content'] as String? ?? '';
    final verses = <Map<String, dynamic>>[];

    final regex = RegExp(
      r'<span class="yv-v" v="(\d+)"><\/span>(?:<span class="yv-vlbl">\d+<\/span>)?([\s\S]*?)(?=(?:<span class="yv-v" v="\d+"><\/span>|$))',
    );

    for (final m in regex.allMatches(html)) {
      final vNum = int.tryParse(m.group(1) ?? '1') ?? 1;
      final rawVerseText = m.group(2) ?? '';
      final text = rawVerseText
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.isNotEmpty) {
        verses.add({
          'version_id': config.versionId,
          'book_name': bookName,
          'book_number': bookNumber,
          'chapter': chapter,
          'verse': vNum,
          'text': text,
        });
      }
    }

    verses.sort((a, b) => (a['verse'] as int).compareTo(b['verse'] as int));
    return verses;
  }
}
