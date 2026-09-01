import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:mobile/features/dictionary/models/dictionary_entry.dart';
import 'package:mobile/features/dictionary/services/dictionary_download_manager.dart';
import 'dictionary_data_adapter.dart';
import 'online_dictionary_api.dart';

class SqliteDictionaryDataAdapter implements DictionaryDataAdapter {
  final Map<String, Database> _openedDbs = {};

  Future<Database?> _getDb(String dictId) async {
    if (_openedDbs.containsKey(dictId) && _openedDbs[dictId]!.isOpen) {
      return _openedDbs[dictId];
    }

    final dbDir = await getDatabasesPath();
    final dbPath = p.join(dbDir, 'dict_$dictId.sqlite');
    final file = File(dbPath);
    if (!await file.exists()) return null;

    try {
      final db = await openDatabase(dbPath, readOnly: true);
      _openedDbs[dictId] = db;
      return db;
    } catch (e) {
      debugPrint('SqliteDictionaryDataAdapter: Could not open $dbPath: $e');
      return null;
    }
  }

  String _cleanWord(String raw) {
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

  static String? detectLanguageCode(String text) {
    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(text)) return 'ta'; // Tamil
    if (RegExp(r'[\u0D00-\u0D7F]').hasMatch(text)) return 'ml'; // Malayalam
    if (RegExp(r'[\u0C00-\u0C7F]').hasMatch(text)) return 'te'; // Telugu
    if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(text)) return 'kn'; // Kannada
    if (RegExp(r'[\u0900-\u097F]').hasMatch(text)) return 'hi'; // Hindi / Devanagari
    return null;
  }

  @override
  Future<List<DictionaryEntry>> lookupWord(String word, {String? preferredLangCode}) async {
    final cleaned = _cleanWord(word);
    if (cleaned.isEmpty) return [];

    final targetLang = preferredLangCode ?? detectLanguageCode(cleaned);

    final manager = DictionaryDownloadManager();
    await manager.initialize();

    final results = <DictionaryEntry>[];
    final installed = manager.installedIds.toList();

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

      var rows = await db.query(
        'dictionary_entries',
        where: 'headword = ? COLLATE NOCASE',
        whereArgs: [cleaned],
        limit: 5,
      );

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

    if (results.isEmpty) {
      final onlineResults = await OnlineDictionaryApi.lookupOnlineApi(cleaned, langCode: targetLang);
      results.addAll(onlineResults);
    }

    return results;
  }
}
