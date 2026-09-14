import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/features/bible/controllers/bible_controller.dart';
import 'package:mobile/features/engines/scripture/services/book_name_service.dart';
import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';
import 'package:mobile/features/bible/services/bible_bookmark_service.dart';
import 'package:mobile/features/user_items/services/user_item_sync_service.dart';
import 'package:mobile/shared/annotations/user_item_repository.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    await BookNameService().ensureLoaded();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bible_notes_test_');
    LocalBibleService.overrideDbPath = p.join(tempDir.path, 'bible.db');
    UserItemRepository.overrideDbPath = p.join(tempDir.path, 'user_items.db');
    await LocalBibleService.resetForTest();
    await UserItemRepository.resetForTest();

    final service = LocalBibleService();
    await service.initialize();
    await service.registerInstalledVersion(
      id: 'WEB',
      name: 'World English Bible',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1 MB',
    );
    await service.insertVerses('WEB', [
      for (var v = 1; v <= 10; v++)
        {
          'bookNumber': 43,
          'bookName': 'John',
          'chapter': 3,
          'verse': v,
          'text': 'Verse $v',
        },
    ]);
  });

  tearDown(() async {
    LocalBibleService.overrideDbPath = null;
    UserItemRepository.overrideDbPath = null;
    await LocalBibleService.resetForTest();
    await UserItemRepository.resetForTest();
    UserItemSyncService.instance.setUserIdForTest(null);
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('Save and retrieve note in BibleController (pre-auth)', () async {
    final controller = BibleController(
      initialVersionId: 'WEB',
      initialBook: 'John',
      initialChapter: 3,
      initialVerse: null,
      saveProgress: false,
    );

    await controller.init();

    expect(controller.state.verseNotes, isEmpty);

    // Save note on John 3:1
    await controller.saveNoteForVerse(1, 'My test note for John 3:1');

    // Check state
    final expectedKey = BibleController.verseNoteKey('John', 3, 1);
    expect(controller.state.verseNotes.contains(expectedKey), isTrue);

    // Check getNoteForVerse
    final note = await controller.getNoteForVerse(1);
    expect(note, isNotNull);
    expect(note?.text, 'My test note for John 3:1');
  });

  test('Save and retrieve note in BibleController (signed-in user)', () async {
    UserItemSyncService.instance.setUserIdForTest('user123');

    final controller = BibleController(
      initialVersionId: 'WEB',
      initialBook: 'John',
      initialChapter: 3,
      initialVerse: null,
      saveProgress: false,
    );

    await controller.init();

    // Save note on John 3:2
    await controller.saveNoteForVerse(2, 'User note for John 3:2');

    final expectedKey = BibleController.verseNoteKey('John', 3, 2);
    expect(controller.state.verseNotes.contains(expectedKey), isTrue);

    final note = await controller.getNoteForVerse(2);
    expect(note, isNotNull);
    expect(note?.text, 'User note for John 3:2');
  });

  test('Bookmark on verse does not corrupt or overwrite note in user tier', () async {
    UserItemSyncService.instance.setUserIdForTest('user123');

    final controller = BibleController(
      initialVersionId: 'WEB',
      initialBook: 'John',
      initialChapter: 3,
      initialVerse: null,
      saveProgress: false,
    );

    await controller.init();

    // Select verse 3 and toggle bookmark
    controller.toggleVerseSelection(3);
    await controller.toggleBookmarkSelected();
    controller.clearSelection();

    // Now get note for verse 3 - should be null!
    final noteBefore = await controller.getNoteForVerse(3);
    expect(noteBefore, isNull);

    // Now save a note on verse 3
    await controller.saveNoteForVerse(3, 'Actual note on verse 3');

    // Verify bookmark is STILL there
    expect(await BibleBookmarkService().isBookmarked('WEB', 'John', 3, 3), isTrue);

    // Verify note is there
    final noteAfter = await controller.getNoteForVerse(3);
    expect(noteAfter?.text, 'Actual note on verse 3');
  });

  test('Save and retrieve notes across different chapters and delete note', () async {
    final controller = BibleController(
      initialVersionId: 'WEB',
      initialBook: 'John',
      initialChapter: 3,
      initialVerse: null,
      saveProgress: false,
    );

    await controller.init();

    // Save note on John 4:5 explicitly
    await controller.saveNoteForVerse(5, 'Living Water Note', book: 'John', chapter: 4);

    final key = BibleController.verseNoteKey('John', 4, 5);
    expect(controller.state.verseNotes.contains(key), isTrue);

    final note = await controller.getNoteForVerse(5, book: 'John', chapter: 4);
    expect(note?.text, 'Living Water Note');

    // Delete note
    await controller.deleteNoteForVerse(5, book: 'John', chapter: 4);
    expect(controller.state.verseNotes.contains(key), isFalse);

    final deleted = await controller.getNoteForVerse(5, book: 'John', chapter: 4);
    expect(deleted, isNull);
  });
}
