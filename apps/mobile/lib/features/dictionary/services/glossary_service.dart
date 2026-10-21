import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../../../core/api/github_data_service.dart';
import '../models/glossary_entry.dart';

/// Service querying the classical biblical lexicon SQLite database with live streaming fallback.
class GlossaryService {
  static final GlossaryService _instance = GlossaryService._internal();
  factory GlossaryService() => _instance;
  GlossaryService._internal();

  Database? _db;
  bool _isOpening = false;
  final Map<String, List<GlossaryEntry>> _chapterWordsCache = {};

  /// Cleans punctuation and invalid characters from [raw] word.
  String cleanWord(String raw) {
    return raw
        .replaceAll('_', '')
        .replaceAll(
          RegExp(
            r'''[^\w\s\-\u0900-\u097F\u0B80-\u0BFF\u0C00-\u0C7F\u0C80-\u0CFF\u0D00-\u0D7F\u0600-\u06FF\u0400-\u04FF]''',
          ),
          '',
        )
        .replaceAll('_', '')
        .trim();
  }

  /// Checks if the glossary database is installed on the local device.
  Future<bool> isInstalled() async {
    if (kIsWeb) return false;
    try {
      final dbDir = await getDatabasesPath();
      final candidates = [
        p.join(dbDir, 'dict_ta_glossary.sqlite'),
        p.join(dbDir, 'taobvsi_glossary.sqlite'),
      ];
      for (final path in candidates) {
        final file = File(path);
        if (await file.exists() && await file.length() > 100000) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  /// Gets or opens the SQLite database.
  Future<Database?> _getDatabase() async {
    if (kIsWeb) return null;
    if (_db != null && _db!.isOpen) return _db;
    if (_isOpening) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (_db != null && _db!.isOpen) return _db;
    }

    _isOpening = true;
    try {
      final dbDir = await getDatabasesPath();
      final candidates = [
        p.join(dbDir, 'dict_ta_glossary.sqlite'),
        p.join(dbDir, 'taobvsi_glossary.sqlite'),
      ];

      String? validPath;
      for (final path in candidates) {
        final file = File(path);
        if (await file.exists() && await file.length() > 100000) {
          validPath = path;
          break;
        }
      }

      if (validPath == null) return null;
      _db = await openDatabase(validPath, readOnly: true);
      return _db;
    } catch (e) {
      debugPrint('GlossaryService: Failed to open database: $e');
      return null;
    } finally {
      _isOpening = false;
    }
  }

  /// Loads and caches word entries for a specific chapter from local release assets or remote CDN.
  Future<List<GlossaryEntry>> loadChapterWords({
    required int book,
    required int chapter,
    String versionId = 'taobvsi',
  }) async {
    final key = '${versionId.toLowerCase()}_${book}_$chapter';
    if (_chapterWordsCache.containsKey(key)) {
      return _chapterWordsCache[key]!;
    }

    // 1. If running locally or on desktop with release submodule present
    try {
      final localCandidates = [
        File('releases/study/${versionId.toLowerCase()}/words/$book/$chapter.json'),
        File('../releases/study/${versionId.toLowerCase()}/words/$book/$chapter.json'),
        File('../../releases/study/${versionId.toLowerCase()}/words/$book/$chapter.json'),
      ];
      for (final localFile in localCandidates) {
        if (await localFile.exists()) {
          final content = await localFile.readAsString();
          final data = jsonDecode(content);
          if (data is Map && data['words'] is List) {
            final entries = (data['words'] as List)
                .whereType<Map>()
                .map((w) => GlossaryEntry.fromContextualWord(
                      Map<String, dynamic>.from(w),
                      book: book,
                      chapter: chapter,
                    ))
                .toList();
            _chapterWordsCache[key] = entries;
            return entries;
          }
        }
      }
    } catch (_) {}

    // 2. Fetch live via GitHubDataService
    final urls = GitHubDataService.wordsChapterUrls(versionId, book, chapter);
    for (final url in urls) {
      try {
        final uri = Uri.parse(url);
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
        final request = await client.getUrl(uri);
        final response = await request.close();
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final data = jsonDecode(body);
          if (data is Map && data['words'] is List) {
            final entries = (data['words'] as List)
                .whereType<Map>()
                .map((w) => GlossaryEntry.fromContextualWord(
                      Map<String, dynamic>.from(w),
                      book: book,
                      chapter: chapter,
                    ))
                .toList();
            _chapterWordsCache[key] = entries;
            return entries;
          }
        }
      } catch (e) {
        debugPrint('GlossaryService: Failed to fetch chapter words from $url: $e');
      }
    }

    return const [];
  }

  /// Returns all interlinear words for a specific verse in sequential order.
  Future<List<GlossaryEntry>> getVerseWords({
    required int book,
    required int chapter,
    required int verse,
    String versionId = 'taobvsi',
  }) async {
    final chapterEntries = await loadChapterWords(
      book: book,
      chapter: chapter,
      versionId: versionId,
    );
    if (chapterEntries.isNotEmpty) {
      final targetRef = '$book:$chapter:$verse';
      return chapterEntries.where((e) => e.refs.contains(targetRef)).toList();
    }
    return const [];
  }

  /// Looks up a glossary entry by exact surface form, headword, id, or contextual verse location.
  Future<GlossaryEntry?> lookup(
    String rawWord, {
    int? book,
    int? chapter,
    int? verse,
    String versionId = 'taobvsi',
  }) async {
    final word = cleanWord(rawWord);
    if (word.isEmpty) return null;

    // 1. If book and chapter are provided, check chapter contextual words first
    if (book != null && chapter != null) {
      final chapterEntries = await loadChapterWords(
        book: book,
        chapter: chapter,
        versionId: versionId,
      );
      if (chapterEntries.isNotEmpty) {
        if (verse != null) {
          final targetRef = '$book:$chapter:$verse';
          for (final entry in chapterEntries) {
            if (entry.refs.contains(targetRef) &&
                (entry.forms.contains(word) ||
                 cleanWord(entry.headword) == word ||
                 cleanWord(entry.id) == word)) {
              return entry;
            }
          }
        }
        for (final entry in chapterEntries) {
          if (entry.forms.contains(word) ||
              cleanWord(entry.headword) == word ||
              cleanWord(entry.id) == word) {
            return entry;
          }
        }
      }
    }

    // 2. Query local SQLite database if available
    final db = await _getDatabase();
    if (db == null) return null;

    try {
      // 2a. Query verse_words if book, chapter, and verse are known
      if (book != null && chapter != null) {
        try {
          final List<Map<String, Object?>> vwRows;
          if (verse != null) {
            vwRows = await db.query(
              'verse_words',
              where: 'book = ? AND chapter = ? AND verse = ? AND surface_form = ?',
              whereArgs: [book, chapter, verse, word],
              limit: 1,
            );
          } else {
            vwRows = await db.query(
              'verse_words',
              where: 'book = ? AND chapter = ? AND surface_form = ?',
              whereArgs: [book, chapter, word],
              limit: 1,
            );
          }
          if (vwRows.isNotEmpty) {
            final r = vwRows.first;
            return GlossaryEntry(
              id: r['entry_id'] as String? ?? (r['canonical'] as String? ?? word),
              headword: r['canonical'] as String? ?? word,
              transliteration: r['original_translit'] as String? ?? '',
              pos: 'noun',
              posTa: 'சொல்',
              category: 'theological',
              glossEn: r['english_word'] as String? ?? '',
              englishWord: r['english_word'] as String?,
              definitionTa: r['definition_ta'] as String? ?? '',
              definitionEn: r['definition_en'] as String? ?? '',
              originalLang: book <= 39 ? 'Hebrew' : 'Greek',
              originalLemma: r['original_text'] as String?,
              originalTranslit: r['original_translit'] as String?,
              strongs: r['strongs'] as String?,
              rootDefinitionTa: r['root_definition_ta'] as String?,
              rootDefinitionEn: r['root_definition_en'] as String?,
              originalContext: r['original_context'] as String?,
              notes: r['notes'] as String? ?? '',
              forms: [word],
              refs: ['$book:$chapter:${r['verse']}'],
              occurrenceCount: 1,
            );
          }
        } catch (_) {}
      }

      // 2b. Direct surface form mapping (resolves inflected Tamil words in 0.1ms)
      final surfaceRows = await db.query(
        'surface_forms',
        columns: ['entry_id'],
        where: 'surface_form = ?',
        whereArgs: [word],
        limit: 1,
      );

      if (surfaceRows.isNotEmpty) {
        final entryId = surfaceRows.first['entry_id'] as String;
        final entryRows = await db.query(
          'glossary_entries',
          where: 'id = ?',
          whereArgs: [entryId],
          limit: 1,
        );
        if (entryRows.isNotEmpty) {
          return GlossaryEntry.fromMap(entryRows.first);
        }
      }

      // 2c. Headword match
      var rows = await db.query(
        'glossary_entries',
        where: 'headword = ? COLLATE NOCASE',
        whereArgs: [word],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return GlossaryEntry.fromMap(rows.first);
      }

      // 2d. ID match
      rows = await db.query(
        'glossary_entries',
        where: 'id = ?',
        whereArgs: [word],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return GlossaryEntry.fromMap(rows.first);
      }

      // 2e. Transliteration match
      rows = await db.query(
        'glossary_entries',
        where: 'transliteration = ? COLLATE NOCASE',
        whereArgs: [word],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return GlossaryEntry.fromMap(rows.first);
      }

      // 2f. English gloss match
      rows = await db.query(
        'glossary_entries',
        where: 'gloss_en LIKE ? OR english_word LIKE ?',
        whereArgs: ['%$word%', '%$word%'],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return GlossaryEntry.fromMap(rows.first);
      }

      // 2g. FTS5 Search fallback
      try {
        final ftsRows = await db.rawQuery(
          'SELECT id FROM glossary_fts WHERE glossary_fts MATCH ? LIMIT 1',
          ['"$word*"'],
        );
        if (ftsRows.isNotEmpty) {
          final ftsId = ftsRows.first['id'] as String;
          final entryRows = await db.query(
            'glossary_entries',
            where: 'id = ?',
            whereArgs: [ftsId],
            limit: 1,
          );
          if (entryRows.isNotEmpty) {
            return GlossaryEntry.fromMap(entryRows.first);
          }
        }
      } catch (_) {}

      return null;
    } catch (e) {
      debugPrint('GlossaryService.lookup error: $e');
      return null;
    }
  }

  /// Closes database handle.
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
