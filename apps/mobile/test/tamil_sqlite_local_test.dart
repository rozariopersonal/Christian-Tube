import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:mobile/features/dictionary/adapters/sqlite_dictionary_data_adapter.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Local Tamil SQLite direct queries and stemmer match real Bible words', () async {
    final dbPath = p.normalize(p.absolute('../../data/dictionaries_published/dict_ta.sqlite'));
    print('Testing SQLite at: $dbPath');
    expect(File(dbPath).existsSync(), isTrue);

    final db = await databaseFactory.openDatabase(dbPath);
    expect(db.isOpen, isTrue);

    final testWords = [
      'தேவன்',
      'கிறிஸ்து',
      'ஜெபம்',
      'ஞானஸ்நானம்',
      'சுவிசேஷம்',
      'வானம்',
      'பூமி',
      'வெளிச்சம்',
      'விசுவாசம்',
      'கிருபை',
      'இரட்சிப்பு',
      'ஆதி',
    ];

    print('\n--- DIRECT SQL QUERY TESTS ---');
    for (final w in testWords) {
      final rows = await db.query(
        'dictionary_entries',
        where: 'headword = ? COLLATE NOCASE',
        whereArgs: [w],
      );
      print('Direct SQL "$w" => found ${rows.length} rows');
      if (rows.isNotEmpty) {
        final def = (rows.first['definition'] as String).replaceAll('\n', ' ');
        print('   Def: ${def.substring(0, def.length > 70 ? 70 : def.length)}');
      }
      expect(rows.isNotEmpty, isTrue, reason: 'Word $w should have entries in database');
    }

    print('\n--- STEMMER & INFLECTED BIBLE WORDS TESTS ---');
    final inflectedBibleWords = [
      'ஆதியிலே',
      'வானத்தையும்',
      'பூமியையும்',
      'சிருஷ்டித்தார்',
      'வெளிச்சத்துக்கு',
      'குமாரனை',
      'விசுவாசிக்கிறவன்',
      'கெட்டுப்போகாமல்',
      'அவரை',
      'அவராலே',
      'தம்முடைய',
      'நித்தியஜீவனை',
    ];

    for (final inflected in inflectedBibleWords) {
      // 1. Direct query
      var rows = await db.query(
        'dictionary_entries',
        where: 'headword = ? COLLATE NOCASE',
        whereArgs: [inflected],
      );

      // 2. If empty, test stemTamil
      if (rows.isEmpty) {
        final stems = SqliteDictionaryDataAdapter.stemTamil(inflected);
        print('Inflected "$inflected" => generated stems: $stems');
        for (final s in stems) {
          rows = await db.query(
            'dictionary_entries',
            where: 'headword = ? COLLATE NOCASE',
            whereArgs: [s],
          );
          if (rows.isNotEmpty) {
            print('   -> Matched stem "$s" (${rows.length} rows)');
            break;
          }
        }
      } else {
        print('Inflected "$inflected" => direct match (${rows.length} rows)');
      }
    }

    print('\n--- COMPLETE BIBLE VERSES TESTS ---');
    // Genesis 1:1: ஆதியிலே தேவன் வானத்தையும் பூமியையும் சிருஷ்டித்தார்.
    // John 1:1: ஆதியிலே வார்த்தை இருந்தது, அந்த வார்த்தை தேவனிடத்திலிருந்தது, அந்த வார்த்தை தேவனாயிருந்தது.
    // John 3:16: தேவன், தம்முடைய ஒரேபேறான குமாரனை விசுவாசிக்கிறவன் எவனோ அவன் கெட்டுப்போகாமல் நித்தியஜீவனை அடையும்படிக்கு, அவரைத் தந்தருளி, இவ்வளவாய் உலகத்தில் அன்புகூர்ந்தார்.
    final verses = [
      'ஆதியிலே தேவன் வானத்தையும் பூமியையும் சிருஷ்டித்தார்',
      'ஆதியிலே வார்த்தை இருந்தது அந்த வார்த்தை தேவனிடத்திலிருந்தது அந்த வார்த்தை தேவனாயிருந்தது',
      'தேவன் தம்முடைய ஒரேபேறான குமாரனை விசுவாசிக்கிறவன் எவனோ அவன் கெட்டுப்போகாமல் நித்தியஜீவனை அடையும்படிக்கு அவரைத் தந்தருளி இவ்வளவாய் உலகத்தில் அன்புகூர்ந்தார்'
    ];

    int totalVerseWords = 0;
    int matchedVerseWords = 0;
    final unmatchedWords = <String>[];

    for (final verse in verses) {
      final tokens = verse.split(' ').map((t) => t.trim()).where((t) => t.isNotEmpty);
      for (final tok in tokens) {
        totalVerseWords++;
        var rows = await db.query(
          'dictionary_entries',
          where: 'headword = ? COLLATE NOCASE',
          whereArgs: [tok],
        );
        if (rows.isNotEmpty) {
          matchedVerseWords++;
          continue;
        }
        final stems = SqliteDictionaryDataAdapter.stemTamil(tok);
        bool found = false;
        for (final s in stems) {
          rows = await db.query(
            'dictionary_entries',
            where: 'headword = ? COLLATE NOCASE',
            whereArgs: [s],
          );
          if (rows.isNotEmpty) {
            matchedVerseWords++;
            found = true;
            break;
          }
        }
        if (!found) {
          unmatchedWords.add(tok);
        }
      }
    }

    print('Complete Verses Word Test: $matchedVerseWords / $totalVerseWords words matched (${(matchedVerseWords*100/totalVerseWords).toStringAsFixed(1)}%)');
    print('Unmatched words from verses: $unmatchedWords');
    expect(matchedVerseWords / totalVerseWords, greaterThanOrEqualTo(0.70));

    await db.close();
  });

  test('SqliteDictionaryDataAdapter.lookupWord end-to-end lookup returns valid entries', () async {
    final sourceDbPath = p.normalize(p.absolute('../../data/dictionaries_published/dict_ta.sqlite'));
    final dbDir = await getDatabasesPath();
    final targetDbPath = p.join(dbDir, 'dict_ta.sqlite');
    
    // Copy published database to app test databases directory
    await File(sourceDbPath).copy(targetDbPath);
    expect(File(targetDbPath).existsSync(), isTrue);

    final adapter = SqliteDictionaryDataAdapter();

    final testLookups = [
      'தேவன்',
      'கிறிஸ்து',
      'வானத்தையும்',
      'பூமியையும்',
      'ஆதியிலே',
      'விசுவாசிக்கிறவன்',
      'குமாரனை',
      'நித்தியஜீவனை',
      'god',
      'grace',
      'prayer',
      'faith',
    ];

    print('\n--- ADAPTER.LOOKUPWORD END-TO-END TESTS (TAMIL & ENGLISH) ---');
    for (final word in testLookups) {
      final results = await adapter.lookupWord(word);
      print('lookupWord("$word") returned ${results.length} entries:');
      for (final r in results) {
        print('   -> [${r.headword} (${r.partOfSpeech})]: ${r.definition.replaceAll('\n', ' ').substring(0, r.definition.length > 60 ? 60 : r.definition.length)}');
      }
      expect(results.isNotEmpty, isTrue, reason: 'lookupWord must return definitions for $word');
    }

    await adapter.closeAll();
  });
}
