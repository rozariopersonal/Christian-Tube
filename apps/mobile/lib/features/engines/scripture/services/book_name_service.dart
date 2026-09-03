import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mobile/core/api/github_data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads localized Bible book names (per version, keyed by canonical book
/// number 1..66) from the releases repo's `book_names.json` on demand, with
/// an English fallback so the UI always renders. Names are cached on disk so
/// they survive app restarts and work offline once fetched.
class BookNameService {
  static final BookNameService _instance = BookNameService._internal();
  factory BookNameService() => _instance;
  BookNameService._internal();

  static const List<String> _bookNamesKey = [
    'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy', 'Joshua',
    'Judges', 'Ruth', '1 Samuel', '2 Samuel', '1 Kings', '2 Kings',
    '1 Chronicles', '2 Chronicles', 'Ezra', 'Nehemiah', 'Esther', 'Job',
    'Psalms', 'Proverbs', 'Ecclesiastes', 'Song of Solomon', 'Isaiah',
    'Jeremiah', 'Lamentations', 'Ezekiel', 'Daniel', 'Hosea', 'Joel', 'Amos',
    'Obadiah', 'Jonah', 'Micah', 'Nahum', 'Habakkuk', 'Zephaniah', 'Haggai',
    'Zechariah', 'Malachi', 'Matthew', 'Mark', 'Luke', 'John', 'Acts',
    'Romans', '1 Corinthians', '2 Corinthians', 'Galatians', 'Ephesians',
    'Philippians', 'Colossians', '1 Thessalonians', '2 Thessalonians',
    '1 Timothy', '2 Timothy', 'Titus', 'Philemon', 'Hebrews', 'James',
    '1 Peter', '2 Peter', '1 John', '2 John', '3 John', 'Jude', 'Revelation',
  ];

  Map<String, Map<String, String>> _namesByVersion = {};
  Completer<void>? _loadingCompleter;

  bool get isLoaded => _namesByVersion.isNotEmpty;

  static List<String> get englishBookNames => _bookNamesKey;

  static String englishNameFor(int bookNumber) {
    if (bookNumber < 1 || bookNumber > _bookNamesKey.length) {
      return 'Genesis';
    }
    return _bookNamesKey[bookNumber - 1];
  }

  /// Ensures localized names are available. Idempotent and non-fatal: any
  /// failure leaves English fallbacks in place.
  Future<void> ensureLoaded() async {
    if (_namesByVersion.isNotEmpty) return;
    if (_loadingCompleter != null && !_loadingCompleter!.isCompleted) {
      return _loadingCompleter!.future;
    }
    final completer = Completer<void>();
    _loadingCompleter = completer;
    try {
      final fetched = await _fetch();
      if (fetched.isNotEmpty) {
        _namesByVersion = fetched;
        await _writeCache();
        return;
      }
      final cached = await _readCached();
      if (cached.isNotEmpty) {
        _namesByVersion = cached;
      }
    } catch (e) {
      debugPrint('BookNameService failed to load: $e');
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
      _loadingCompleter = null;
    }
  }

  /// Localized name for [versionId]'s [bookNumber] book, English when
  /// unknown or not loaded yet.
  String nameFor(String versionId, int bookNumber) {
    final localized = _namesByVersion[versionId.toLowerCase()]?['$bookNumber'] ??
        _namesByVersion[versionId.toUpperCase()]?['$bookNumber'];
    if (localized != null && localized.trim().isNotEmpty) {
      return localized;
    }
    return englishNameFor(bookNumber);
  }

  Future<Map<String, Map<String, String>>> _fetch() async {
    // 1. Try local file (for unit/widget tests and local development where file is directly on disk)
    if (!kIsWeb) {
      for (final candidate in [
        'assets/book_names.json',
        'apps/mobile/assets/book_names.json',
      ]) {
        try {
          final file = File(candidate);
          if (file.existsSync()) {
            final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
            final parsed = _parseMap(raw);
            if (parsed.isNotEmpty) return parsed;
          }
        } catch (_) {}
      }
    }

    // 2. Try bundled asset (works in app bundles on Android, iOS, Web)
    try {
      final assetStr = await rootBundle.loadString('assets/book_names.json');
      final raw = jsonDecode(assetStr) as Map<String, dynamic>;
      final parsed = _parseMap(raw);
      if (parsed.isNotEmpty) return parsed;
    } catch (_) {}

    // 2. Fall back to releases CDN / Raw GitHub
    final dio = Dio();
    for (final url in GitHubDataService.bookNamesUrls()) {
      try {
        final response = await dio.get(
          url,
          options: Options(receiveTimeout: const Duration(seconds: 30)),
        );
        if (response.statusCode != 200) continue;
        final raw = response.data is String
            ? jsonDecode(response.data as String) as Map<String, dynamic>
            : response.data as Map<String, dynamic>;
        final parsed = _parseMap(raw);
        if (parsed.isNotEmpty) return parsed;
      } catch (e) {
        debugPrint('BookNameService fetch failed for $url: $e');
      }
    }
    return <String, Map<String, String>>{};
  }

  Map<String, Map<String, String>> _parseMap(Map<String, dynamic> raw) {
    final result = <String, Map<String, String>>{};
    raw.forEach((versionId, value) {
      final map = <String, String>{};
      if (value is Map) {
        value.forEach((k, v) {
          if (k != null && v != null) {
            map['$k'] = '$v';
          }
        });
      }
      result[versionId.toLowerCase()] = map;
      result[versionId.toUpperCase()] = map;
    });
    return result;
  }

  Future<void> _writeCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('book_names_cache', jsonEncode(_namesByVersion));
    } catch (e) {
      debugPrint('BookNameService cache write failed: $e');
    }
  }

  Future<Map<String, Map<String, String>>> _readCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('book_names_cache');
      if (str == null) return <String, Map<String, String>>{};
      
      final raw = jsonDecode(str) as Map<String, dynamic>;
      return _parseMap(raw);
    } catch (e) {
      debugPrint('BookNameService cache read failed: $e');
      return <String, Map<String, String>>{};
    }
  }
}