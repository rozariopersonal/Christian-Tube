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
      final db = await openDatabase(dbPath);
      _openedDbs[dictId] = db;
      return db;
    } catch (e) {
      debugPrint('SqliteDictionaryDataAdapter: Could not open $dbPath: $e');
      return null;
    }
  }

  /// Closes the database handle for [dictId].
  Future<void> closeDatabase(String dictId) async {
    if (_openedDbs.containsKey(dictId)) {
      try {
        final db = _openedDbs[dictId];
        if (db != null && db.isOpen) {
          await db.close();
        }
      } catch (_) {}
      _openedDbs.remove(dictId);
    }
  }

  /// Closes all active database handles.
  Future<void> closeAll() async {
    for (final db in _openedDbs.values) {
      try {
        if (db.isOpen) await db.close();
      } catch (_) {}
    }
    _openedDbs.clear();
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

  static List<String> stemTamil(String word) {
    final candidates = <String>[];
    void add(String s) {
      if (s.length >= 2 && !candidates.contains(s)) {
        candidates.add(s);
      }
    }

    final suffixes = [
      'த்தையும்', 'யையும்', 'வையும்', 'ையும்', 'உடைய', 'னுடைய', 'க்குரிய', 'வுக்கு',
      'களுக்கு', 'களின்', 'களில்', 'ஆனது', 'யானது', 'வானது', 'யிலே', 'விலே', 'இலே', 'ிலே',
      'யில்', 'வில்', 'இல்', 'ஆல்', 'யால்', 'வால்', 'ஓடு', 'யோடு', 'வோடு',
      'உடன்', 'யுடன்', 'வுடன்', 'த்தை', 'யை', 'வை', 'யும்', 'வும்', 'உம்',
      'ுக்கு', 'க்கு', 'லின்', 'ரின்', 'வின்', 'யின்', 'ல்', 'ன்', 'ஐ', 'ஏ', 'தானே', 'தான்', 'கள்', 'களை'
    ];
    suffixes.sort((a, b) => b.length.compareTo(a.length));

    for (final s in suffixes) {
      if (word.endsWith(s) && word.length > s.length) {
        final base = word.substring(0, word.length - s.length);
        add(base);

        // Sandhi / Euphonic transformations:
        // வான + த்தையும் -> வானம், வெளிச்ச + த்தை -> வெளிச்சம்
        if (s == 'த்தையும்' || s == 'த்தை') {
          add(base + 'ம்');
        }
        if (base.endsWith('த்த')) {
          add('${base.substring(0, base.length - 2)}ம்');
        }
        // தேவனு + க்கு -> தேவன் (னு -> ன்)
        if (base.endsWith('னு')) {
          add('${base.substring(0, base.length - 2)}ன்');
        }
        // இருளு + க்கு -> இருள் (ளு -> ள்)
        if (base.endsWith('ளு')) {
          add('${base.substring(0, base.length - 2)}ள்');
        }
        // காலு + க்கு -> கால் (லு -> ல்)
        if (base.endsWith('லு')) {
          add('${base.substring(0, base.length - 2)}ல்');
        }
        // மண்ணு + க்கு -> மண் (ணு -> ண்)
        if (base.endsWith('ணு')) {
          add('${base.substring(0, base.length - 2)}ண்');
        }
        // மரத்து + க்கு -> மரம்
        if (base.endsWith('த்து')) {
          add('${base.substring(0, base.length - 3)}ம்');
        }
        if (base.endsWith('த்') || base.endsWith('ப்') || base.endsWith('க்') || base.endsWith('ச்')) {
          add(base.substring(0, base.length - 1));
        }
      }
    }
    return candidates;
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

    final isTamil = targetLang == 'ta' || RegExp(r'[\u0B80-\u0BFF]').hasMatch(cleaned);

    for (final dictId in orderedIds) {
      final db = await _getDb(dictId);
      if (db == null) continue;

      final meta = DictionaryDownloadManager.catalog.where((c) => c.id == dictId).firstOrNull;
      final sourceName = meta?.name ?? 'Dictionary';

      try {
        var rows = await db.query(
          'dictionary_entries',
          where: 'headword = ? COLLATE NOCASE',
          whereArgs: [cleaned],
          limit: 5,
        );

        if (rows.isEmpty) {
          if (dictId == 'ta' || isTamil) {
            final stems = stemTamil(cleaned);
            for (final stem in stems) {
              rows = await db.query(
                'dictionary_entries',
                where: 'headword = ? COLLATE NOCASE',
                whereArgs: [stem],
                limit: 3,
              );
              if (rows.isNotEmpty) break;
            }

            if (rows.isEmpty && cleaned.length >= 3) {
              final prefix = cleaned.substring(0, cleaned.length >= 4 ? 4 : 3);
              rows = await db.query(
                'dictionary_entries',
                where: 'headword LIKE ?',
                whereArgs: ['$prefix%'],
                limit: 3,
              );
            }
          } else if (cleaned.length > 4) {
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
        }

        for (final row in rows) {
          results.add(DictionaryEntry.fromMap(row, source: sourceName));
        }
      } catch (e) {
        debugPrint('Error querying dictionary $dictId: $e');
        continue;
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
