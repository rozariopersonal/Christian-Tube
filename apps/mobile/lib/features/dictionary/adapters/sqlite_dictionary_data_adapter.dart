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
      final t = s.trim();
      if (t.length >= 2 && !candidates.contains(t)) {
        candidates.add(t);
      }
    }

    var w = word.trim();
    // 1. Strip doubling sandhi consonants at the end (க், ச், த், ப்)
    const sandhiDoubles = ['க்', 'ச்', 'த்', 'ப்'];
    for (final sd in sandhiDoubles) {
      if (w.endsWith(sd) && w.length > sd.length) {
        w = w.substring(0, w.length - sd.length);
        add(w);
        break;
      }
    }

    // 2. Direct verbal & grammatical transformations:
    // -க்கடவது, -கடவது (உண்டாகக்கடவது -> உண்டாக்கு, உண்டு, உண்டாக்கம்)
    if (w.endsWith('க்கடவது') && w.length > 7) {
      final base = w.substring(0, w.length - 7);
      add(base);
      if (base == 'உண்டாக') { add('உண்டு'); add('உண்டாக்கு'); }
    } else if (w.endsWith('கடவது') && w.length > 5) {
      final base = w.substring(0, w.length - 5);
      add(base);
    }

    // Participles: -க்கிறவன், -கிறவன்
    const participleSuffixes = [
      'க்கிறவர்கள்', 'கிறவர்கள்', 'க்கிறவன்', 'கிறவன்',
      'க்கிறவள்', 'கிறவள்', 'க்கிறவர்', 'கிறவர்', 'க்கிற', 'கிற'
    ];
    for (final suff in participleSuffixes) {
      if (w.endsWith(suff) && w.length > suff.length) {
        final base = w.substring(0, w.length - suff.length);
        add(base);
        if (base.contains('விசுவாசி')) {
          add('விசுவாசி');
          add('விசுவாசம்');
        }
        break;
      }
    }

    // Negative verbs: -போகாமல், -ஆமல்
    const negSuffixes = ['போகாமல்', 'க்காமல்', 'காமல்', 'ஆமல்', 'யாமல்', 'வாமல்', 'ாமல்'];
    for (final suff in negSuffixes) {
      if (w.endsWith(suff) && w.length > suff.length) {
        final base = w.substring(0, w.length - suff.length);
        add(base);
        if (w.contains('கெட்டு')) { add('கெடு'); add('கெடுதல்'); }
        break;
      }
    }

    // 3. Direct Case, Number, and Pronoun transformations:
    // Accusative: குமாரனை -> குமாரன், அவரை -> அவர், கால்களை -> கால்கள்
    if (w.endsWith('னை') && w.length > 2) {
      add('${w.substring(0, w.length - 2)}ன்');
      add(w.substring(0, w.length - 2));
    }
    if (w.endsWith('ரை') && w.length > 2) {
      add('${w.substring(0, w.length - 2)}ர்');
      add(w.substring(0, w.length - 2));
    }
    if (w.endsWith('லை') && w.length > 2) {
      add('${w.substring(0, w.length - 2)}ல்');
      add(w.substring(0, w.length - 2));
    }
    if (w.endsWith('ளை') && w.length > 2) {
      add('${w.substring(0, w.length - 2)}ள்');
      add(w.substring(0, w.length - 2));
    }
    if (w.endsWith('மை') && w.length > 2) {
      add('${w.substring(0, w.length - 2)}ம்');
      add(w.substring(0, w.length - 2));
    }

    // Possessive / Genitive: தம்முடைய -> தம் / தாம், அவருடைய -> அவர், அவனுடைய -> அவன்
    if (w.endsWith('முடைய') && w.length > 5) {
      add('${w.substring(0, w.length - 5)}ம்');
      add('தம்');
      add('தாம்');
    }
    if (w.endsWith('ருடைய') && w.length > 5) {
      add('${w.substring(0, w.length - 5)}ர்');
    }
    if (w.endsWith('னுடைய') && w.length > 5) {
      add('${w.substring(0, w.length - 5)}ன்');
    }

    // Instrumental / Ablative: அவராலே -> அவர், அவனால் -> அவன்
    if (w.endsWith('ராலே') && w.length > 4) {
      add('${w.substring(0, w.length - 4)}ர்');
    }
    if (w.endsWith('னாலே') && w.length > 4) {
      add('${w.substring(0, w.length - 4)}ன்');
    }
    if (w.endsWith('ரால்') && w.length > 3) {
      add('${w.substring(0, w.length - 3)}ர்');
    }
    if (w.endsWith('னால்') && w.length > 3) {
      add('${w.substring(0, w.length - 3)}ன்');
    }

    // Coordinating -உம் / -மும்: சாயங்காலமும் -> சாயங்காலம்
    if (w.endsWith('மும்') && w.length > 3) {
      add('${w.substring(0, w.length - 3)}ம்');
    }

    // 4. Comprehensive Agglutinative Suffix List
    final suffixes = [
      // Compound / Postpositional suffixes
      'விடியற்காலமுமாகி', 'அசைவாடிக்கொண்டிருந்தார்', 'அசைவாடிக்கொண்டிருந்தது',
      'பிரிவுண்டாக்கினார்', 'உண்டுபண்ணினார்', 'உண்டுபண்ணி',
      'முழுவதும்', 'யாவற்றையும்', 'அனைத்தையும்', 'எல்லாவற்றையும்',
      'களுக்குள்', 'களுக்குரிய', 'களுக்கு', 'களிலிருந்து',
      'இன்மேல்', 'யின்மேல்', 'வின்மேல்', 'தன்மேல்', 'என்மேல்', 'மேல்',
      'இடத்தில்', 'யிடத்தில்', 'விடத்தில்', 'இடத்திற்கு',
      'த்தையுமாய்', 'வையுமாய்', 'யையுமாய்', 'மையுமாய்', 'மாய்',
      'த்தையுமே', 'வையுமே', 'யையுமே', 'தையுமே',
      'த்தையும்', 'பூமியையும்', 'யையும்', 'வையும்', 'ையையும்',
      'களிலே', 'யிலே', 'விலே', 'இலே', 'திலே', 'ிலே',
      'களின்', 'களில்', 'களால்', 'களோடு', 'களுடன்',
      'யானவர்', 'ஆனவர்', 'வானவர்', 'இன்வர்',
      'னுடைய', 'ருடைய', 'முடைய', 'உடைய', 'க்குரிய', 'வுக்குரிய',
      'வானது', 'யானது', 'ஆனது',
      'த்தினால்', 'வினால்', 'யினால்',
      'த்திற்குப்', 'த்துக்குப்', 'த்திற்கு', 'த்துக்கு', 'வுக்குக்', 'வுக்கு',
      'க்குக்', 'க்கு', 'க்காய்', 'க்காய', 'க்காக',
      'த்தோடு', 'யோடு', 'வோடு', 'ஓடு',
      'த்துடன்', 'யுடன்', 'வுடன்', 'உடன்',
      'த்தாலே', 'யாலே', 'வாலே', 'ஆலே',
      'த்திலே', 'யிலே', 'விலே',
      'த்தில்', 'யில்', 'வில்', 'இல்',
      'த்தால்', 'யால்', 'வால்', 'ஆல்',
      'த்தை', 'யை', 'வை', 'தை', 'னை', 'ரை', 'லை', 'ளை', 'ஐ',
      'யும்', 'வும்', 'உம்',
      'யே', 'வே', 'ஏ', 'தானே', 'தான்',
      'யாக', 'வாக', 'ஆக', 'யாய்', 'வாய்', 'ஆய்',
      'யான', 'வான', 'ஆன',
      'களுடைய', 'கள்', 'களை', 'லின்', 'ரின்', 'வின்', 'யின்', 'இன்',
      'ினார்', 'ித்தார்', 'ந்தார்', 'த்தார்', 'ட்டார்', 'யினார்', 'யார்', 'வார்', 'பார்',
      'ியது', 'ந்தது', 'த்தது', 'ாயிற்று', 'ிற்று', 'பட்டது',
      'ுகிறான்', 'ுகிறார்', 'ுகின்ற', 'ுகிற', 'க்கிற',
      'ுகிறேன்', 'ுகிறோம்', 'ுகிறார்', 'ுகின்றார்',
      'ும்', 'னும்', 'லும்', 'ரும்', 'வும்'
    ];
    suffixes.sort((a, b) => b.length.compareTo(a.length));

    for (final s in suffixes) {
      if (w.endsWith(s) && w.length > s.length) {
        final base = w.substring(0, w.length - s.length);
        add(base);

        // Sandhi / Euphonic transformations:
        // 1. வான + த்தையும் -> வானம், வெளிச்ச + த்தை -> வெளிச்சம்
        if (s.startsWith('த்த') || base.endsWith('த்த') || base.endsWith('த்து')) {
          final cleanB = base.replaceAll(RegExp(r'த்த[ு]?$'), '');
          if (cleanB.isNotEmpty) {
            add('$cleanBம்');
            add(cleanB);
          }
        }
        // 2. தேவனு + க்கு -> தேவன் (னு -> ன்)
        if (base.endsWith('னு')) {
          add('${base.substring(0, base.length - 2)}ன்');
        }
        // 3. இருளு + க்கு -> இருள் (ளு -> ள்)
        if (base.endsWith('ளு')) {
          add('${base.substring(0, base.length - 2)}ள்');
        }
        // 4. காலு + க்கு -> கால் (லு -> ல்)
        if (base.endsWith('லு')) {
          add('${base.substring(0, base.length - 2)}ல்');
        }
        // 5. மண்ணு + க்கு -> மண் (ணு -> ண்)
        if (base.endsWith('ணு')) {
          add('${base.substring(0, base.length - 2)}ண்');
        }
        // 6. அவரு + க்கு -> அவர் (ரு -> ர்)
        if (base.endsWith('ரு')) {
          add('${base.substring(0, base.length - 2)}ர்');
        }
        // 7. மரத்து + க்கு -> மரம்
        if (base.endsWith('த்து')) {
          add('${base.substring(0, base.length - 3)}ம்');
        }
        if (base.endsWith('த்') || base.endsWith('ப்') || base.endsWith('க்') || base.endsWith('ச்')) {
          add(base.substring(0, base.length - 2));
        }
      }
    }

    // Special Biblical compounds and roots:
    if (w == 'தேவ' || w.startsWith('தேவனிட') || w.startsWith('தேவனா') || w.startsWith('தேவனு')) {
      add('தேவன்');
    }
    if (w.startsWith('அன்புகூர்')) {
      add('அன்பு');
      add('கூர்');
    }
    if (w.contains('தந்தருள')) {
      add('அருள்');
      add('தா');
    }
    if (w.contains('நித்திய') && w.contains('ஜீவ')) {
      add('நித்திய ஜீவன்');
      add('நித்திய');
      add('ஜீவன்');
    }
    if (w.contains('மனுஷ') && w.contains('குமார')) {
      add('மனுபுத்திரன்');
      add('மனுஷன்');
      add('குமாரன்');
    }
    if (w.contains('ஆகாய') && w.contains('விரி')) {
      add('ஆகாயம்');
      add('விரிவு');
    }
    if (w.contains('பரிசுத்த') && w.contains('ஆவி')) {
      add('பரிசுத்த ஆவி');
      add('ஆவி');
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

            if (rows.isEmpty) {
              final runes = cleaned.runes.toList();
              if (runes.length >= 3) {
                final prefix = String.fromCharCodes(runes.take(runes.length >= 5 ? 4 : 3));
                rows = await db.query(
                  'dictionary_entries',
                  where: 'headword LIKE ?',
                  whereArgs: ['$prefix%'],
                  limit: 3,
                );
              }
            }

            if (rows.isEmpty && cleaned.length >= 3) {
              rows = await db.query(
                'dictionary_entries',
                where: 'definition LIKE ?',
                whereArgs: ['%$cleaned%'],
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
