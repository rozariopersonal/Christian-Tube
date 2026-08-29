import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';
import 'package:mobile/features/engines/scripture/services/remote_bible_api_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    LocalBibleService.resetForTest();
    tempDir = await Directory.systemTemp.createTemp('bible_test_');
    LocalBibleService.overrideDbPath = p.join(tempDir.path, 'bible.db');
  });

  tearDown(() async {
    LocalBibleService.resetForTest();
    LocalBibleService.overrideDbPath = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
      'downloaded verses resolve via getChapter by English book name (blank page fix)',
      () async {
    final service = LocalBibleService();
    await service.initialize();

    await service.insertVerses('TAOBVSI', [
      for (var v = 1; v <= 3; v++)
        {
          'bookNumber': 1,
          'bookName': 'Genesis',
          'chapter': 1,
          'verse': v,
          'text': 'Tamil verse $v',
        },
    ]);

    final rows = await service.getChapter('TAOBVSI', 'Genesis', 1);
    expect(rows.length, 3);
    expect(rows[0]['verse'], 1);
    expect(rows[0]['book_name'], 'Genesis');
    expect(rows[0]['text'], 'Tamil verse 1');
  });

  test(
      'downloading a version purges stale wrong-language rows (no English/Tamil mix)',
      () async {
    final service = LocalBibleService();
    await service.initialize();

    // Older builds cached an English fallback under the Tamil version id.
    await service.insertVerses('TAOBVSI', [
      {
        'bookNumber': 43,
        'bookName': 'John',
        'chapter': 3,
        'verse': 16,
        'text':
            'For God so loved the world, that he gave his one and only Son, that whoever believes in him should not perish, but have eternal life.',
      },
    ]);

    // The real Tamil download replaces the whole version.
    await service.insertVerses('TAOBVSI', [
      {
        'bookNumber': 43,
        'bookName': 'John',
        'chapter': 3,
        'verse': 16,
        'text':
            'தேவன், தம்முடைய ஒரேபேறான குமாரனை விசுவாசிக்கிற எவனும் கெட்டுப்போகாமல் நித்தியஜீவனை அடையும்படிக்கு, அவரைத் தந்தருளி, இவ்வளவாய் உலகத்தில் அன்புகூர்ந்தார்.',
      },
    ]);

    final rows = await service.getChapter('TAOBVSI', 'John', 3);
    final verse16 = rows.where((r) => r['verse'] == 16).toList();
    expect(verse16.length, 1,
        reason: 'polluted rows must not coexist after a fresh download');
    expect(verse16.single['text'], contains('தேவன்'));
  });

  test('remote API never serves English text for non-English versions', () {
    final remote = RemoteBibleApiService();
    expect(remote.supportsVersion('WEB'), isTrue);
    expect(remote.supportsVersion('KJV'), isTrue);
    expect(remote.supportsVersion('ASV'), isTrue);
    expect(remote.supportsVersion('BBE'), isTrue);
    expect(remote.supportsVersion('TAOBVSI'), isFalse);
    expect(remote.supportsVersion('taobvsi'), isFalse);
    expect(remote.supportsVersion('MAL_IRV'), isFalse);
    expect(remote.supportsVersion('TEL_IRV'), isFalse);
  });
}