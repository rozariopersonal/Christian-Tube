import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mobile/features/bible/models/bible_bookmark.dart';
import 'package:mobile/features/bible/models/bible_highlight.dart';
import 'package:mobile/features/bible/services/bible_bookmark_service.dart';
import 'package:mobile/features/bible/services/bible_highlight_service.dart';
import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';
import 'package:mobile/features/user_items/services/user_item_sync_service.dart';
import 'package:mobile/shared/annotations/sqlite_user_item_data_adapter.dart';
import 'package:mobile/shared/annotations/user_item.dart';
import 'package:mobile/shared/annotations/user_item_repository.dart';
import 'package:mobile/shared/annotations/web_user_item_data_adapter.dart';
import 'package:mobile/shared/models/note.dart';
import 'package:mobile/shared/services/note_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() {
    // Always fall back to the pre-auth device tier between tests.
    UserItemSyncService.instance.setUserIdForTest(null);
  });

  group('UserItem model conversions', () {
    UserItem makeBibleNote() => UserItem(
          userId: 'u1',
          id: 'n1',
          itemType: UserItem.typeNote,
          feature: UserItem.featureBible,
          book: 'Genesis',
          chapter: 1,
          verseStart: 3,
          verseEnd: 3,
          targetId: 'Genesis:1:3',
          text: 'In the beginning',
          contextText: 'And God said, Let there be light',
          createdAt: DateTime.utc(2026, 9, 8, 1),
          updatedAt: DateTime.utc(2026, 9, 8, 2),
        );

    test('fromBibleHighlight → toBibleHighlight round-trips verses as a range',
        () {
      final h = BibleHighlight(
        versionId: 'TAOBVSI',
        book: 'John',
        chapter: 3,
        verses: [16, 17, 18],
        colorIndex: 7,
        text: 'a\nb\nc',
        savedAt: DateTime.utc(2026, 9, 8, 1),
      );
      final items = UserItem.fromBibleHighlight(h, 'u1');
      expect(items, hasLength(1));
      final item = items.single;
      expect(item.userId, 'u1');
      expect(item.itemType, UserItem.typeHighlight);
      expect(item.verseStart, 16);
      expect(item.verseEnd, 18);
      expect(item.updatedAt, h.savedAt);

      final back = item.toBibleHighlight();
      expect(back.verses, [16, 17, 18]);
      expect(back.colorIndex, 7);
      expect(back.text, h.text);
      expect(back.savedAt, h.savedAt);
    });

    test('non-contiguous highlights split into one run per contiguous range',
        () {
      // Removing the middle verse leaves a hole; the hole must not be
      // re-expanded when read back through the range-based user_items store.
      final h = BibleHighlight(
        versionId: 'TAOBVSI',
        book: 'John',
        chapter: 3,
        verses: [16, 18, 19],
        colorIndex: 7,
        text: 'x',
        savedAt: DateTime.utc(2026, 9, 8, 1),
      );
      final items = UserItem.fromBibleHighlight(h, 'u1');
      expect(items, hasLength(2));
      expect(items[0].verseStart, 16);
      expect(items[0].verseEnd, 16);
      expect(items[1].verseStart, 18);
      expect(items[1].verseEnd, 19);
      expect(items[1].id, isNot(items[0].id));

      final restored = items.map((i) => i.toBibleHighlight()).toList();
      expect(restored.map((x) => x.verses).toList(), [
        [16],
        [18, 19],
      ]);
    });

    test('timestamps are normalized to UTC on the wire and in the DB', () {
      final local = DateTime(2026, 9, 8, 12); // local zone builds offset form
      final item = UserItem(
        userId: 'u1',
        id: 'n1',
        itemType: UserItem.typeNote,
        feature: UserItem.featureBible,
        targetId: 'Genesis:1:3',
        text: 'x',
        createdAt: local,
        updatedAt: local,
      );
      expect(item.toJson()['createdAt'], endsWith('Z'));
      expect(item.toJson()['updatedAt'], endsWith('Z'));
      expect(item.toMap()['created_at'], endsWith('Z'));
      expect(item.toMap()['updated_at'], endsWith('Z'));
      expect(
        UserItem.fromJson(item.toJson()).createdAt.isUtc,
        isTrue,
      );
    });

    test('fromBibleBookmark → toBibleBookmark round-trips a verse', () {
      final b = BibleBookmark(
        versionId: 'TAOBVSI',
        book: 'John',
        chapter: 3,
        verse: 16,
        text: 'For God so loved the world',
        savedAt: DateTime.utc(2026, 9, 8, 1),
      );
      final item = UserItem.fromBibleBookmark(b, 'u1');
      expect(item.itemType, UserItem.typeBookmark);
      expect(item.verseStart, 16);
      expect(item.verseEnd, 16);

      final back = item.toBibleBookmark();
      expect(back.book, 'John');
      expect(back.chapter, 3);
      expect(back.verse, 16);
    });

    test('fromNote keeps the canonical Bible anchor; toNote preserves it', () {
      final n = Note(
        id: 'n1',
        feature: 'bible',
        targetId: 'Genesis:1:3',
        text: 'shine',
        contextText: 'let there be light',
        createdAt: DateTime.utc(2026, 9, 8, 1),
        updatedAt: DateTime.utc(2026, 9, 8, 2),
      );
      final item = UserItem.fromNote(n, 'u1');
      expect(item.book, 'Genesis');
      expect(item.chapter, 1);
      expect(item.verseStart, 3);
      expect(item.targetId, 'Genesis:1:3');

      final back = item.toNote();
      expect(back.feature, 'bible');
      expect(back.targetId, 'Genesis:1:3');
      expect(back.text, 'shine');
      expect(back.id, 'n1');
    });

    test('non-bible notes keep a raw targetId and no verse anchor', () {
      final n = Note(
        id: 'n2',
        feature: 'book',
        targetId: 'raburu/page-12',
        text: 'note',
        createdAt: DateTime.utc(2026, 9, 8, 1),
        updatedAt: DateTime.utc(2026, 9, 8, 2),
      );
      final item = UserItem.fromNote(n, 'u1');
      expect(item.book, '');
      expect(item.chapter, 0);
      expect(item.targetId, 'raburu/page-12');
    });

    test('toJson/fromJson round-trip', () {
      final item = makeBibleNote();
      final restored = UserItem.fromJson(item.toJson());
      expect(restored.userId, 'u1');
      expect(restored.id, 'n1');
      expect(restored.itemType, UserItem.typeNote);
      expect(restored.feature, 'bible');
      expect(restored.book, 'Genesis');
      expect(restored.chapter, 1);
      expect(restored.verseStart, 3);
      expect(restored.targetId, 'Genesis:1:3');
      expect(restored.updatedAt, item.updatedAt);
    });

    test('reference renders bible ranges and verses', () {
      expect(makeBibleNote().reference, 'Genesis 1:3');
      final multi = makeBibleNote().copyWith(
        verseEnd: 5,
        itemType: UserItem.typeHighlight,
        colorIndex: () => 2,
      );
      expect(multi.reference, 'Genesis 1:3-5');
    });
  });

  group('SqliteUserItemDataAdapter (per-user rows)', () {
    late Directory tempDir;
    late SqliteUserItemDataAdapter adapter;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('user_items_test_');
      adapter = SqliteUserItemDataAdapter(
          databasePath: p.join(tempDir.path, 'user_items.db'));
      await adapter.initialize();
    });

    tearDown(() async {
      await adapter.close();
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    Future<UserItem> note(String id, String userId,
        {DateTime? updatedAt, String targetId = 'Genesis:1:3'}) =>
        Future.value(UserItem(
          userId: userId,
          id: id,
          itemType: UserItem.typeNote,
          feature: UserItem.featureBible,
          book: 'Genesis',
          chapter: 1,
          verseStart: 3,
          verseEnd: 3,
          targetId: targetId,
          text: 'text $id',
          createdAt: DateTime.utc(2026, 9, 8, 1),
          updatedAt: updatedAt ?? DateTime.utc(2026, 9, 8, 2),
        ));

    test('isolates users completely', () async {
      await adapter.upsertAll('u1', [await note('a1', 'u1')]);
      await adapter.upsertAll('u2', [await note('b1', 'u2')]);

      expect((await adapter.loadAll('u1')).map((i) => i.id), ['a1']);
      expect((await adapter.loadAll('u2')).map((i) => i.id), ['b1']);
      expect(await adapter.loadAll('u3'), isEmpty);
    });

    test('insert-or-replace upserts by primary key', () async {
      await adapter.upsertAll('u1', [await note('a1', 'u1')]);
      await adapter.upsertAll('u1', [
        await note('a1', 'u1', updatedAt: DateTime.utc(2026, 9, 9, 1)),
      ]);
      final all = await adapter.loadAll('u1');
      expect(all.length, 1);
      expect(all.first.updatedAt, DateTime.utc(2026, 9, 9, 1));
    });

    test('replaceForType snapshots a type without touching other types',
        () async {
      await adapter.upsertAll('u1', [
        await note('a1', 'u1'),
        await note('a2', 'u1', targetId: 'Genesis:1:4'),
      ]);
      await adapter.replaceForType('u1', UserItem.typeHighlight, const []);
      expect((await adapter.loadForType('u1', UserItem.typeHighlight)),
          isEmpty);
      expect((await adapter.loadAll('u1')).length, 2);
    });

    test('loadForType filters by type', () async {
      await adapter.upsertAll('u1', [await note('a1', 'u1')]);
      await adapter.replaceForType(
        'u1',
        UserItem.typeHighlight,
        [
          UserItem(
            userId: 'u1',
            id: 'h1',
            itemType: UserItem.typeHighlight,
            feature: UserItem.featureBible,
            versionId: 'TAOBVSI',
            book: 'John',
            chapter: 3,
            verseStart: 16,
            verseEnd: 18,
            targetId: 'John:3:16',
            colorIndex: 7,
            createdAt: DateTime.utc(2026, 9, 8),
            updatedAt: DateTime.utc(2026, 9, 8),
          ),
        ],
      );
      expect(await adapter.loadForType('u1', UserItem.typeNote), hasLength(1));
      expect(await adapter.loadForType('u1', UserItem.typeHighlight),
          hasLength(1));
    });

    test('loadSince windows strictly after the cursor', () async {
      final now = DateTime.utc(2026, 9, 8, 12);
      await adapter.upsertAll('u1', [
        await note('a1', 'u1', updatedAt: now),
        await note('a2', 'u1',
            targetId: 'Genesis:1:4', updatedAt: now.subtract(const Duration(hours: 1))),
      ]);
      final after = await adapter.loadSince('u1', now.subtract(const Duration(minutes: 1)));
      expect(after.map((i) => i.id), ['a1']);
    });

    test('tombstones are loaded via loadSince and purged via purgeTombstones',
        () async {
      final tomb = await note('a1', 'u1',
          updatedAt: DateTime.utc(2026, 9, 8, 12)).then((n) =>
          n.copyWith(deleted: true));
      await adapter.upsertAll('u1', [tomb]);
      final dirty = await adapter.loadSince(
          'u1', DateTime.utc(2026, 9, 8, 12).subtract(const Duration(days: 1)));
      expect(dirty, hasLength(1));
      expect(dirty.first.deleted, isTrue);

      await adapter.purgeTombstones('u1');
      expect(await adapter.loadAll('u1'), isEmpty);
    });
  });

  group('WebUserItemDataAdapter (per-user blobs)', () {
    test('isolates users and tolerates corrupt JSON', () async {
      SharedPreferences.setMockInitialValues({
        'user_items_v1_u1': 'not json at all',
      });
      final adapter = WebUserItemDataAdapter();
      expect(await adapter.loadAll('u1'), isEmpty);

      await adapter.upsertAll('u1', [
        UserItem(
          userId: 'u1',
          id: 'a1',
          itemType: UserItem.typeNote,
          feature: UserItem.featureBible,
          targetId: 'Genesis:1:3',
          book: 'Genesis',
          chapter: 1,
          verseStart: 3,
          verseEnd: 3,
          text: 'x',
          createdAt: DateTime.utc(2026, 9, 8),
          updatedAt: DateTime.utc(2026, 9, 8),
        ),
      ]);
      await adapter.upsertAll('u2', [
        UserItem(
          userId: 'u2',
          id: 'b1',
          itemType: UserItem.typeNote,
          feature: UserItem.featureBible,
          targetId: 'Exodus:1:1',
          book: 'Exodus',
          chapter: 1,
          verseStart: 1,
          verseEnd: 1,
          text: 'y',
          createdAt: DateTime.utc(2026, 9, 8),
          updatedAt: DateTime.utc(2026, 9, 8),
        ),
      ]);
      expect((await adapter.loadAll('u1')).map((i) => i.id), ['a1']);
      expect((await adapter.loadAll('u2')).map((i) => i.id), ['b1']);
      await adapter.clearUser('u1');
      expect(await adapter.loadAll('u1'), isEmpty);
      expect(await adapter.loadAll('u2'), hasLength(1));
    });
  });

  group('UserItemRepository rollback semantics (SQLite)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('user_repo_test_');
      UserItemRepository.overrideDbPath = p.join(tempDir.path, 'user_items.db');
      await UserItemRepository.resetForTest();
    });

    tearDown(() async {
      UserItemRepository.overrideDbPath = null;
      await UserItemRepository.resetForTest();
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('load* filters soft-deleted rows', () async {
      final repo = UserItemRepository.instance;
      final now = DateTime.utc(2026, 9, 8);
      await repo.insertOrReplace('u1', [
        UserItem(
          userId: 'u1',
          id: 'n1',
          itemType: UserItem.typeNote,
          feature: UserItem.featureBible,
          targetId: 'Genesis:1:3',
          text: 'x',
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      expect(await repo.loadAll('u1'), hasLength(1));

      await repo.insertOrReplace('u1', [
        UserItem(
          userId: 'u1',
          id: 'n1',
          itemType: UserItem.typeNote,
          feature: UserItem.featureBible,
          targetId: 'Genesis:1:3',
          text: 'x',
          createdAt: now,
          updatedAt: now.add(const Duration(minutes: 1)),
          deleted: true,
        ),
      ]);
      expect(await repo.loadAll('u1'), isEmpty);
      expect((await repo.loadDirtySince('u1', now.subtract(const Duration(days: 1))))
          .single.deleted, isTrue);
    });
  });

  group('Facade routing (device vs user tier)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('facade_routing_');
      LocalBibleService.overrideDbPath = p.join(tempDir.path, 'bible.db');
      await LocalBibleService.resetForTest();
      UserItemRepository.overrideDbPath =
          p.join(tempDir.path, 'user_items.db');
      await UserItemRepository.resetForTest();
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      LocalBibleService.overrideDbPath = null;
      await LocalBibleService.resetForTest();
      UserItemRepository.overrideDbPath = null;
      await UserItemRepository.resetForTest();
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('highlights stay device-local before sign-in and per-user after',
        () async {
      final service = BibleHighlightService();
      await service.apply(
        versionId: 'TAOBVSI',
        book: 'John',
        chapter: 3,
        verses: [16],
        colorIndex: 7,
        text: 'x',
      );
      expect(await service.loadHighlights(), hasLength(1));

      UserItemSyncService.instance.setUserIdForTest('u1');
      // Device data is not visible in the (empty) user tier.
      expect(await service.loadHighlights(), isEmpty);

      await service.apply(
        versionId: 'TAOBVSI',
        book: 'John',
        chapter: 3,
        verses: [17],
        colorIndex: 4,
        text: 'y',
      );
      final highlights = await service.loadHighlights();
      expect(highlights, hasLength(1));
      expect(highlights.first.verses, [17]);
    });

    test('removing a middle verse does not resurrect it (user tier)',
        () async {
      UserItemSyncService.instance.setUserIdForTest('u1');
      final service = BibleHighlightService();
      await service.apply(
        versionId: 'TAOBVSI',
        book: 'John',
        chapter: 3,
        verses: [16, 17, 18],
        colorIndex: 7,
        text: 'x',
      );
      await service.remove(book: 'John', chapter: 3, verses: [17]);

      final forChapter = await service.getForChapter('John', 3);
      final verses = forChapter.expand((h) => h.verses).toSet();
      expect(verses, {16, 18});
    });

    test('removing a verse in user tier marks the kept highlight dirty for sync',
        () async {
      UserItemSyncService.instance.setUserIdForTest('u1');
      final service = BibleHighlightService();
      await service.apply(
        versionId: 'TAOBVSI',
        book: 'John',
        chapter: 3,
        verses: [16, 17],
        colorIndex: 7,
        text: 'a\nb',
      );

      // Let a tick pass so the next timestamp is strictly later.
      await Future.delayed(const Duration(milliseconds: 20));
      final since = DateTime.now().toUtc();
      await Future.delayed(const Duration(milliseconds: 20));

      await service.remove(book: 'John', chapter: 3, verses: [17]);

      final dirty = await UserItemRepository.instance
          .loadDirtySince('u1', since);
      final highlights =
          dirty.where((i) => i.itemType == UserItem.typeHighlight).toList();
      expect(highlights, isNotEmpty);
      expect(highlights.any((i) => i.verseStart == 16), isTrue);
    });

    test('user tier highlights never leak across accounts', () async {
      UserItemSyncService.instance.setUserIdForTest('u1');
      await BibleHighlightService().apply(
        versionId: 'TAOBVSI',
        book: 'John',
        chapter: 3,
        verses: [16],
        colorIndex: 7,
        text: 'x',
      );
      UserItemSyncService.instance.setUserIdForTest('u2');
      expect(await BibleHighlightService().loadHighlights(), isEmpty);
    });

    test('bookmarks toggle in the user tier', () async {
      UserItemSyncService.instance.setUserIdForTest('u1');
      final service = BibleBookmarkService();
      expect(
        await service.toggle(
          versionId: 'TAOBVSI',
          book: 'John',
          chapter: 3,
          verse: 16,
          text: 't',
        ),
        isTrue,
      );
      expect(await service.isBookmarked('TAOBVSI', 'John', 3, 16), isTrue);
      expect(
        await service.toggle(
          versionId: 'TAOBVSI',
          book: 'John',
          chapter: 3,
          verse: 16,
          text: 't',
        ),
        isFalse,
      );
      expect(await service.isBookmarked('TAOBVSI', 'John', 3, 16), isFalse);
    });

    test('notes save, delete (tombstone), and stay one-per-anchor',
        () async {
      UserItemSyncService.instance.setUserIdForTest('u1');
      final now = DateTime.utc(2026, 9, 8, 12);
      await NoteService.instance.saveNote(Note(
        id: 'n1',
        feature: 'bible',
        targetId: 'Genesis:1:3',
        text: 'first',
        createdAt: now,
        updatedAt: now,
      ));
      // Editing the same anchor with a different id replaces the old note.
      await NoteService.instance.saveNote(Note(
        id: 'n2',
        feature: 'bible',
        targetId: 'Genesis:1:3',
        text: 'second',
        createdAt: now,
        updatedAt: now.add(const Duration(minutes: 1)),
      ));
      final notes = await NoteService.instance.getNotesForFeature('bible');
      expect(notes, hasLength(1));
      expect(notes.single.id, 'n2');

      await NoteService.instance.deleteNote('bible', 'Genesis:1:3');
      expect(await NoteService.instance.getNoteForTarget('bible', 'Genesis:1:3'),
          isNull);
      // Tombstone is still in the sync window.
      final repo = UserItemRepository.instance;
      final dirty = await repo.loadDirtySince(
          'u1', now.subtract(const Duration(days: 1)));
      expect(dirty, isNotEmpty);
      expect(dirty.every((i) =>
          i.deleted || i.id == 'n1' || i.id == 'n2'), isTrue);
    });

    test('noteService device methods are never routed to the user tier',
        () async {
      await NoteService.instance.saveNote(Note(
        id: 'd1',
        feature: 'bible',
        targetId: 'Genesis:1:9',
        text: 'device note',
        createdAt: DateTime.utc(2026, 9, 8),
        updatedAt: DateTime.utc(2026, 9, 8),
      ));
      UserItemSyncService.instance.setUserIdForTest('u1');
      // The regular API now reads the (empty) user tier…
      expect(await NoteService.instance.getNoteForTarget('bible', 'Genesis:1:9'),
          isNull);
      // …but the device-only surface still sees the pre-auth note (re-home).
      final deviceNotes = await NoteService.instance.loadAllDeviceNotes();
      expect(deviceNotes.map((n) => n.id), contains('d1'));
      await NoteService.instance.clearDeviceNotes();
      expect(await NoteService.instance.loadAllDeviceNotes(), isEmpty);
    });
  });
}