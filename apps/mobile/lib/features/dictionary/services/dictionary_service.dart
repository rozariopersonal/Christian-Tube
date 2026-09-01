import 'dart:async';
import 'dart:io';
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

  /// Cleans and normalizes query word (e.g. "sanctification," -> "sanctification").
  String cleanWord(String raw) {
    return raw
        .replaceAll(RegExp(r'''[^\w\s\-\u0900-\u097F\u0B80-\u0BFF\u0600-\u06FF\u0400-\u04FF]'''), '')
        .trim();
  }

  /// Looks up definitions for a word across active/installed dictionaries.
  Future<List<DictionaryEntry>> lookupWord(String word, {String? preferredLangCode}) async {
    final cleaned = cleanWord(word);
    if (cleaned.isEmpty) return [];

    final manager = DictionaryDownloadManager();
    await manager.initialize();

    final results = <DictionaryEntry>[];
    final installed = manager.installedIds.toList();

    // Priority order: Easton's / Strong's first for theological precision, then general dictionaries
    final orderedIds = <String>[];
    if (installed.contains('eastons')) orderedIds.add('eastons');
    if (installed.contains('strongs')) orderedIds.add('strongs');
    if (preferredLangCode != null && installed.contains(preferredLangCode)) {
      orderedIds.add(preferredLangCode);
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

    return results;
  }
}
