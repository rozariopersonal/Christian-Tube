import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/dictionary_entry.dart';
import 'dictionary_download_manager.dart';

/// Service querying local offline dictionary SQLite databases.
class DictionaryService {
  static final DictionaryService _instance = DictionaryService._internal();
  factory DictionaryService() => _instance;
  DictionaryService._internal();

  final Map<String, Database> _openedDbs = {};

  Future<Database?> _getDb(String dictId) async {
    if (_openedDbs.containsKey(dictId) && _openedDbs[dictId]!.isOpen) {
      return _openedDbs[dictId];
    }
    if (kIsWeb) return null;

    final dbDir = await getDatabasesPath();
    final dbPath = p.join(dbDir, 'dict_$dictId.sqlite');
    final file = File(dbPath);
    if (!await file.exists()) return null;

    try {
      final db = await openDatabase(dbPath, readOnly: true);
      _openedDbs[dictId] = db;
      return db;
    } catch (e) {
      debugPrint('DictionaryService: Could not open $dbPath: $e');
      return null;
    }
  }

  /// Cleans and normalizes query word while preserving Indian and international scripts.
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

  /// Automatically detects language code from the characters in [text].
  static String? detectLanguageCode(String text) {
    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(text)) return 'ta'; // Tamil
    if (RegExp(r'[\u0D00-\u0D7F]').hasMatch(text)) return 'ml'; // Malayalam
    if (RegExp(r'[\u0C00-\u0C7F]').hasMatch(text)) return 'te'; // Telugu
    if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(text)) return 'kn'; // Kannada
    if (RegExp(r'[\u0900-\u097F]').hasMatch(text)) return 'hi'; // Hindi / Devanagari
    return null;
  }

  /// Looks up definitions for a word across active/installed dictionaries.
  Future<List<DictionaryEntry>> lookupWord(String word, {String? preferredLangCode}) async {
    final cleaned = cleanWord(word);
    if (cleaned.isEmpty) return [];

    final targetLang = preferredLangCode ?? detectLanguageCode(cleaned);

    final manager = DictionaryDownloadManager();
    await manager.initialize();

    final results = <DictionaryEntry>[];
    final installed = manager.installedIds.toList();

    // Priority order:
    // If target language is non-English (e.g. Tamil, Malayalam, Telugu, Kannada, Hindi),
    // prioritize that language's dictionary first!
    final orderedIds = <String>[];
    if (targetLang != null && installed.contains(targetLang)) {
      orderedIds.add(targetLang);
    }
    if (installed.contains('eastons') && !orderedIds.contains('eastons')) {
      orderedIds.add('eastons');
    }
    if (installed.contains('strongs') && !orderedIds.contains('strongs')) {
      orderedIds.add('strongs');
    }
    if (installed.contains('en') && !orderedIds.contains('en')) {
      orderedIds.add('en');
    }
    for (final id in installed) {
      if (!orderedIds.contains(id)) orderedIds.add(id);
    }

    for (final dictId in orderedIds) {
      final db = await _getDb(dictId);
      if (db == null) continue;

      final meta = DictionaryDownloadManager.catalog.where((c) => c.id == dictId).firstOrNull;
      final sourceName = meta?.name ?? 'Dictionary';

      // 1. Exact match
      var rows = await db.query(
        'dictionary_entries',
        where: 'headword = ? COLLATE NOCASE',
        whereArgs: [cleaned],
        limit: 5,
      );

      // 2. Lemmatization fallback (plural / past tense)
      if (rows.isEmpty && cleaned.length > 4) {
        if (cleaned.endsWith('s')) {
          rows = await db.query(
            'dictionary_entries',
            where: 'headword = ? COLLATE NOCASE',
            whereArgs: [cleaned.substring(0, cleaned.length - 1)],
            limit: 3,
          );
        } else if (cleaned.endsWith('ed')) {
          rows = await db.query(
            'dictionary_entries',
            where: 'headword = ? COLLATE NOCASE',
            whereArgs: [cleaned.substring(0, cleaned.length - 2)],
            limit: 3,
          );
        } else if (cleaned.endsWith('ing')) {
          rows = await db.query(
            'dictionary_entries',
            where: 'headword = ? COLLATE NOCASE',
            whereArgs: [cleaned.substring(0, cleaned.length - 3)],
            limit: 3,
          );
        }
      }

      for (final row in rows) {
        results.add(DictionaryEntry.fromMap(row, source: sourceName));
      }

      if (results.length >= 6) break;
    }

    // If no local offline matches (e.g. on web or uninstalled dictionaries), query online APIs
    if (results.isEmpty) {
      final onlineResults = await _lookupOnlineApi(cleaned, langCode: targetLang);
      results.addAll(onlineResults);
    }

    return results;
  }

  /// Queries free online dictionary APIs (FreeDictionaryAPI for English, Wiktionary for global/Indian languages).
  Future<List<DictionaryEntry>> _lookupOnlineApi(String word, {String? langCode}) async {
    final dio = Dio();

    // 1. English lookup via FreeDictionaryAPI
    if (langCode == null || langCode == 'en') {
      try {
        final res = await dio.get<dynamic>(
          'https://api.dictionaryapi.dev/api/v2/entries/en/${Uri.encodeComponent(word)}',
          options: Options(
            responseType: ResponseType.json,
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
        if (res.statusCode == 200 && res.data is List && (res.data as List).isNotEmpty) {
          final List<dynamic> entries = res.data as List<dynamic>;
          final list = <DictionaryEntry>[];
          for (final item in entries) {
            final hw = item['word'] as String? ?? word;
            final phonetic = item['phonetic'] as String? ?? '';
            final meanings = item['meanings'] as List<dynamic>? ?? [];
            for (final m in meanings) {
              final pos = m['partOfSpeech'] as String? ?? '';
              final defs = m['definitions'] as List<dynamic>? ?? [];
              for (final d in defs) {
                final def = d['definition'] as String? ?? '';
                final ex = d['example'] as String? ?? '';
                if (def.isNotEmpty) {
                  list.add(DictionaryEntry(
                    headword: hw,
                    partOfSpeech: pos,
                    phonetic: phonetic,
                    definition: def,
                    examples: ex,
                    source: 'English Dictionary (Live)',
                  ));
                }
                if (list.length >= 5) break;
              }
              if (list.length >= 5) break;
            }
          }
          if (list.isNotEmpty) return list;
        }
      } catch (_) {}
    }

    // 2. Wiktionary API for Indian and global languages
    final targetLang = langCode ?? 'en';
    try {
      final res = await dio.get<dynamic>(
        'https://$targetLang.wiktionary.org/api/rest_v1/page/definition/${Uri.encodeComponent(word)}',
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      if (res.statusCode == 200 && res.data is Map) {
        final Map<String, dynamic> data = res.data as Map<String, dynamic>;
        final list = <DictionaryEntry>[];
        for (final key in data.keys) {
          final langItems = data[key] as List<dynamic>? ?? [];
          for (final item in langItems) {
            final pos = item['partOfSpeech'] as String? ?? '';
            final defs = item['definitions'] as List<dynamic>? ?? [];
            for (final d in defs) {
              final defText = (d['definition'] as String? ?? '')
                  .replaceAll(RegExp(r'<[^>]*>'), '');
              if (defText.isNotEmpty) {
                list.add(DictionaryEntry(
                  headword: word,
                  partOfSpeech: pos,
                  phonetic: '',
                  definition: defText,
                  examples: '',
                  source: 'Wiktionary (Live)',
                ));
              }
              if (list.length >= 4) break;
            }
          }
        }
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    return [];
  }
}
