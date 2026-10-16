import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/glossary_entry.dart';

/// Service querying the classical biblical lexicon SQLite database.
class GlossaryService {
  static final GlossaryService _instance = GlossaryService._internal();
  factory GlossaryService() => _instance;
  GlossaryService._internal();

  Database? _db;
  bool _isOpening = false;

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

  /// Looks up a glossary entry by exact surface form, headword, or id.
  Future<GlossaryEntry?> lookup(String rawWord) async {
    final word = cleanWord(rawWord);
    if (word.isEmpty) return null;

    final db = await _getDatabase();
    if (db == null) return null;

    try {
      // 1. Direct surface form mapping (resolves inflected Tamil words in 0.1ms)
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

      // 2. Headword match
      var rows = await db.query(
        'glossary_entries',
        where: 'headword = ? COLLATE NOCASE',
        whereArgs: [word],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return GlossaryEntry.fromMap(rows.first);
      }

      // 3. ID match
      rows = await db.query(
        'glossary_entries',
        where: 'id = ?',
        whereArgs: [word],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return GlossaryEntry.fromMap(rows.first);
      }

      // 4. Transliteration match
      rows = await db.query(
        'glossary_entries',
        where: 'transliteration = ? COLLATE NOCASE',
        whereArgs: [word],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return GlossaryEntry.fromMap(rows.first);
      }

      // 5. English gloss match
      rows = await db.query(
        'glossary_entries',
        where: 'gloss_en LIKE ?',
        whereArgs: ['%$word%'],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return GlossaryEntry.fromMap(rows.first);
      }

      // 6. FTS5 Search fallback
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
