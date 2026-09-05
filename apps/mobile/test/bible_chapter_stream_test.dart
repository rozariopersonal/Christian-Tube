import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/features/bible/services/bible_chapter_stream.dart';
import 'package:mobile/features/bible/services/bible_verse_counts_service.dart';
import 'package:mobile/features/bible/services/bible_verse_index.dart';
import 'package:mobile/features/engines/scripture/services/book_name_service.dart';
import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await BookNameService().ensureLoaded();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bible_chapter_stream_test_');
    LocalBibleService.overrideDbPath = p.join(tempDir.path, 'bible.db');
    await LocalBibleService.resetForTest();

    final service = LocalBibleService();
    await service.initialize();
    await service.registerInstalledVersion(
      id: 'WEB',
      name: 'World English Bible',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1 MB',
    );
  });

  tearDown(() async {
    LocalBibleService.overrideDbPath = null;
    await LocalBibleService.resetForTest();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Future<void> insertJohn(String versionId, List<Map<String, dynamic>> verses) async {
    final service = LocalBibleService();
    await service.insertVerses(versionId, verses);
  }

  test('chapterVersesFromRows maps raw rows to ordered BibleVerse rows',
      () async {
    final rows = [
      {'verse': 3, 'text': 'third'},
      {'verse': 1, 'text': 'first'},
      {'verse': 2, 'text': 'second'},
    ];

    final verses = chapterVersesFromRows(rows, 'WEB');
    expect(verses.map((v) => v.number), [1, 2, 3]);
    expect(verses.first.text, 'first');
    expect(verses.first.versionLabel, 'WEB');
    expect(verses.last.text, 'third');
  });

  test('BibleChapterStream loads, caches, and deduplicates chapters',
      () async {
    await insertJohn('WEB', [
      for (var v = 1; v <= 5; v++)
        {
          'bookNumber': 43,
          'bookName': 'John',
          'chapter': 3,
          'verse': v,
          'text': 'John 3:$v text',
        },
    ]);

    final stream = BibleChapterStream('WEB');
    expect(stream.contains(43, 3), isFalse);

    final first = await stream.ensureChapter(43, 3);
    expect(stream.contains(43, 3), isTrue);
    expect(first, hasLength(5));
    expect(first.first.number, 1);
    expect(first.last.number, 5);

    final second = await stream.ensureChapter(43, 3);
    expect(identical(first, second), isTrue,
        reason: 'cached chapters resolve the same instance');
  });

  test('BibleChapterStream preloadAround warms neighbors and honors canon bounds',
      () async {
    await insertJohn('WEB', [
      for (var v = 1; v <= 5; v++)
        {
          'bookNumber': 43,
          'bookName': 'John',
          'chapter': 3,
          'verse': v,
          'text': 'John 3:$v text',
        },
      for (var v = 1; v <= 2; v++)
        {
          'bookNumber': 43,
          'bookName': 'John',
          'chapter': 4,
          'verse': v,
          'text': 'John 4:$v text',
        },
      for (var v = 1; v <= 3; v++)
        {
          'bookNumber': 43,
          'bookName': 'John',
          'chapter': 2,
          'verse': v,
          'text': 'John 2:$v text',
        },
    ]);

    final stream = BibleChapterStream('WEB');
    await stream.ensureChapter(43, 3);
    stream.preloadAround(43, 3, radius: 1);

    final ch2 = await stream.ensureChapter(43, 2);
    expect(ch2, hasLength(3));
    final ch4 = await stream.ensureChapter(43, 4);
    expect(ch4, hasLength(2));

    expect(stream.contains(43, 3), isTrue);
    expect(stream.contains(43, 2), isTrue);
    expect(stream.contains(43, 4), isTrue);
  });

  test('preloadAround at Genesis 1 only warms forward chapters', () async {
    final stream = BibleChapterStream('WEB');
    stream.preloadAround(1, 1, radius: 2);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(stream.contains(1, 2), isTrue);
    expect(stream.contains(1, 3), isTrue);
  });

  test('BibleVerseCountsService derives padded 66-book counts from sqlite',
      () async {
    await insertJohn('WEB', [
      for (var v = 1; v <= 2; v++)
        {
          'bookNumber': 43,
          'bookName': 'John',
          'chapter': 1,
          'verse': v,
          'text': 'John 1:$v text',
        },
      for (var v = 1; v <= 10; v++)
        {
          'bookNumber': 43,
          'bookName': 'John',
          'chapter': 3,
          'verse': v,
          'text': 'John 3:$v text',
        },
    ]);

    final service = BibleVerseCountsService();
    final counts = await service.loadForVersion('WEB');

    expect(counts.bookCount, 66,
        reason: 'books with no installed verses are still padded to the canon');
    expect(counts.verseRowsInChapter(bookNumber: 43, chapter: 1), 2);
    expect(counts.verseRowsInChapter(bookNumber: 43, chapter: 2), 0,
        reason: 'missing chapters read as zero rows');
    expect(counts.verseRowsInChapter(bookNumber: 43, chapter: 3), 10);
    expect(counts.verseRowsInChapter(bookNumber: 1, chapter: 1), 0);

    final index = BibleVerseIndex(counts);
    expect(index.totalVerses, 12);
    expect(index.chapterStartRow(bookNumber: 43, chapter: 3), 2);
    expect(index.globalRowFor(bookNumber: 43, chapter: 3, verse: 1), 2);
  });

  test('BibleVerseCountsService degrades to empty counts on missing version',
      () async {
    final service = BibleVerseCountsService();
    final counts = await service.loadForVersion('NOT_INSTALLED');
    expect(counts.isLoaded, isFalse);
  });
}