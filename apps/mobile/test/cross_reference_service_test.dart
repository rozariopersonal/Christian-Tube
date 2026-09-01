import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mobile/features/bible/models/cross_reference.dart';
import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    LocalBibleService.resetForTest();
    tempDir = await Directory.systemTemp.createTemp('crossref_test_');
    LocalBibleService.overrideDbPath = p.join(tempDir.path, 'bible.db');
  });

  tearDown(() async {
    LocalBibleService.resetForTest();
    LocalBibleService.overrideDbPath = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('install + query cross-references grouped by source verse', () async {
    final service = LocalBibleService();
    await service.initialize();

    await service.insertCrossReferences([
      // Genesis 1:1 -> John 1:1-3, Hebrews 11:3
      {
        'bookNumber': 1,
        'chapter': 1,
        'verse': 1,
        'refBookNumber': 43,
        'refChapter': 1,
        'refVerse': 1,
        'refEndVerse': 3,
        'score': 349,
      },
      {
        'bookNumber': 1,
        'chapter': 1,
        'verse': 1,
        'refBookNumber': 58,
        'refChapter': 11,
        'refVerse': 3,
        'refEndVerse': null,
        'score': 254,
      },
      // Genesis 1:2 -> another reference.
      {
        'bookNumber': 1,
        'chapter': 1,
        'verse': 2,
        'refBookNumber': 24,
        'refChapter': 4,
        'refVerse': 23,
        'refEndVerse': null,
        'score': 92,
      },
    ]);

    expect(await service.hasCrossReferences(), isTrue);

    final chapter = await service.getCrossReferencesForChapter(1, 1);
    expect(chapter.keys, containsAll([1, 2]));
    expect(chapter[1]!.length, 2, reason: 'verse 1 has two references');

    // Sorted by score descending (highest first).
    final v1 = chapter[1]!;
    expect(v1[0].score, 349);
    expect(v1[1].score, 254);
    expect(v1[0].bookNumber, 43);
    expect(v1[0].chapter, 1);
    expect(v1[0].verse, 1);
    expect(v1[0].endVerse, 3);

    expect(chapter[2]!.single.verse, 23);
  });

  test('deleteCrossReferences removes all data', () async {
    final service = LocalBibleService();
    await service.initialize();

    await service.insertCrossReferences([
      {
        'bookNumber': 1,
        'chapter': 1,
        'verse': 1,
        'refBookNumber': 43,
        'refChapter': 1,
        'refVerse': 1,
        'refEndVerse': null,
        'score': 10,
      },
    ]);

    await service.deleteCrossReferences();
    expect(await service.hasCrossReferences(), isFalse);
    expect(await service.getCrossReferencesForChapter(1, 1), isEmpty);
  });

  test('resolvePassages maps text for references', () async {
    final service = LocalBibleService();
    await service.initialize();

    await service.insertVerses('WEB', [
      {
        'bookNumber': 43,
        'bookName': 'John',
        'chapter': 1,
        'verse': 1,
        'text': 'In the beginning was the Word.',
      },
      {
        'bookNumber': 43,
        'bookName': 'John',
        'chapter': 1,
        'verse': 2,
        'text': 'The same was in the beginning with God.',
      },
    ]);

    final resolved = await service.resolvePassages(
      versionId: 'WEB',
      passages: [(43, 1, 1, null), (43, 1, 2, 3)],
    );

    expect(resolved['43_1_1'], 'In the beginning was the Word.');
    expect(resolved['43_1_2'], isNotNull);
  });
}
