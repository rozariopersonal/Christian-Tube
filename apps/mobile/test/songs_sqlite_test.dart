import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mobile/features/songs/adapters/offline_songs_catalog_adapter.dart';
import 'package:mobile/features/songs/adapters/sqlite_songs_catalog_adapter.dart';
import 'package:mobile/features/songs/services/songs_download_manager.dart';

const _schema = '''
CREATE TABLE songs (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  title_roman TEXT,
  author TEXT,
  album TEXT,
  collection TEXT,
  language TEXT NOT NULL,
  category TEXT,
  audio_url TEXT
);
CREATE TABLE song_verses (
  song_id TEXT NOT NULL,
  idx INTEGER NOT NULL,
  text TEXT,
  text_roman TEXT,
  PRIMARY KEY (song_id, idx)
);
CREATE INDEX idx_song_verses_song ON song_verses(song_id);
CREATE VIRTUAL TABLE songs_fts USING fts5(
  song_id UNINDEXED, title, title_roman, author, album, collection, category
);
CREATE VIRTUAL TABLE lyrics_fts USING fts5(
  song_id UNINDEXED, verse_idx UNINDEXED, text, text_roman
);
''';

Future<void> _createCatalogDb(String path) async {
  final db = await databaseFactory.openDatabase(path);
  await db.execute(_schema);

  await db.execute(
    'INSERT INTO songs (id, title, title_roman, author, album, collection, language, category, audio_url) '
    "VALUES ('s1', 'Amazing Grace', NULL, 'John Newton', NULL, 'SDA Hymnal', 'en', NULL, NULL)",
  );
  await db.execute(
    "INSERT INTO songs_fts (song_id, title, title_roman, author, album, collection, category) "
    "VALUES ('s1', 'Amazing Grace', '', 'John Newton', '', 'SDA Hymnal', '')",
  );
  await db.execute(
    'INSERT INTO song_verses (song_id, idx, text, text_roman) VALUES '
    "('s1', 0, 'Amazing grace how sweet the sound', NULL), "
    "('s1', 1, 'That saved a wretch like me', NULL)",
  );
  await db.execute(
    "INSERT INTO lyrics_fts (song_id, verse_idx, text, text_roman) VALUES "
    "('s1', 0, 'Amazing grace how sweet the sound', ''), "
    "('s1', 1, 'That saved a wretch like me', '')",
  );

  await db.execute(
    'INSERT INTO songs (id, title, title_roman, author, album, collection, language, category, audio_url) '
    "VALUES ('s2', 'எனக்காய் ஜீவன் விட்டவரே', 'Enakkaai Jeevan Vittavarae', NULL, NULL, 'செயல்வீரர் கீதங்கள்', 'ta', NULL, NULL)",
  );
  await db.execute(
    "INSERT INTO songs_fts (song_id, title, title_roman, author, album, collection, category) "
    "VALUES ('s2', 'எனக்காய் ஜீவன் விட்டவரே', 'Enakkaai Jeevan Vittavarae', '', '', 'செயல்வீரர் கீதங்கள்', '')",
  );
  await db.execute(
    'INSERT INTO song_verses (song_id, idx, text, text_roman) VALUES '
    "('s2', 0, 'தமிழ் வரி ஒன்று', 'Tamil line one'), "
    "('s2', 1, 'என்னோடிருக்க எழுந்தவரே', 'Ennodirukka ezhunthavarae')",
  );
  await db.execute(
    "INSERT INTO lyrics_fts (song_id, verse_idx, text, text_roman) VALUES "
    "('s2', 0, 'தமிழ் வரி ஒன்று', 'Tamil line one'), "
    "('s2', 1, 'என்னோடிருக்க எழுந்தவரே', 'Ennodirukka ezhunthavarae')",
  );

  await db.execute(
    'INSERT INTO songs (id, title, title_roman, author, album, collection, language, category, audio_url) '
    "VALUES ('s3', 'Rejoice', NULL, 'John', NULL, 'Hymnal', 'en', NULL, NULL)",
  );
  await db.execute(
    "INSERT INTO songs_fts (song_id, title, title_roman, author, album, collection, category) "
    "VALUES ('s3', 'Rejoice', '', 'John', '', 'Hymnal', '')",
  );
  await db.execute(
    'INSERT INTO song_verses (song_id, idx, text, text_roman) VALUES '
    "('s3', 0, 'Sing and be glad', NULL)",
  );
  await db.execute(
    "INSERT INTO lyrics_fts (song_id, verse_idx, text, text_roman) VALUES "
    "('s3', 0, 'Sing and be glad', '')",
  );

  await db.close();
}

Future<String> _tempDbPath(String name) async {
  final dir = await Directory.systemTemp.createTemp('songs_test');
  addTearDown(() async {
    final file = File(p.join(dir.path, name));
    if (await file.exists()) await file.delete();
    final wal = File(p.join(dir.path, '$name-wal'));
    if (await wal.exists()) await wal.delete();
    final shm = File(p.join(dir.path, '$name-shm'));
    if (await shm.exists()) await shm.delete();
    await dir.delete(recursive: true);
  });
  return p.join(dir.path, name);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SqliteSongsCatalogAdapter', () {
    late String dbPath;

    setUp(() async {
      dbPath = await _tempDbPath('songs.sqlite');
      await _createCatalogDb(dbPath);
    });

    test('fetches all songs with verses in order', () async {
      final adapter =
          SqliteSongsCatalogAdapter(dbPathOverride: dbPath);
      addTearDown(adapter.close);
      expect(await adapter.isInstalled, isTrue);

      final songs = await adapter.fetchSongs();
      expect(songs.map((s) => s.id), ['s1', 's2', 's3']);
      expect(songs.first.verses,
          ['Amazing grace how sweet the sound', 'That saved a wretch like me']);
      expect(songs.first.author, 'John Newton');
      expect(songs[1].titleRoman, 'Enakkaai Jeevan Vittavarae');
      expect(songs[1].versesRoman, ['Tamil line one', 'Ennodirukka ezhunthavarae']);
    });

    test('fetches one song by id', () async {
      final adapter = SqliteSongsCatalogAdapter(dbPathOverride: dbPath);
      addTearDown(adapter.close);
      final song = await adapter.fetchSong('s2');
      expect(song, isNotNull);
      expect(song!.title, 'எனக்காய் ஜீவன் விட்டவரே');
      expect(song.verses.length, 2);

      expect(await adapter.fetchSong('nope'), isNull);
    });

    test('reports not installed when the file is absent', () async {
      await File(dbPath).delete();
      final adapter = SqliteSongsCatalogAdapter(dbPathOverride: dbPath);
      addTearDown(adapter.close);
      expect(await adapter.isInstalled, isFalse);
      expect(await adapter.fetchSongs(), isEmpty);
      expect(await adapter.fetchSong('s1'), isNull);
    });

    test('search matches titles via FTS5', () async {
      final adapter = SqliteSongsCatalogAdapter(dbPathOverride: dbPath);
      addTearDown(adapter.close);
      final results = await adapter.search('grace');
      expect(results.map((s) => s.id), contains('s1'));
    });

    test('search matches transliterated title and lyrics', () async {
      final adapter = SqliteSongsCatalogAdapter(dbPathOverride: dbPath);
      addTearDown(adapter.close);
      final byTitle = await adapter.search('enakkaai');
      expect(byTitle.map((s) => s.id), contains('s2'));

      final byLyrics = await adapter.search('tamil line');
      expect(byLyrics.map((s) => s.id), contains('s2'));
    });

    test('search respects the result cap and returns empty for no matches',
        () async {
      final adapter = SqliteSongsCatalogAdapter(dbPathOverride: dbPath);
      addTearDown(adapter.close);
      final capped = await adapter.search('a', limit: 1);
      expect(capped.length, lessThanOrEqualTo(1));

      expect(await adapter.search('zzzz-nothing'), isEmpty);
      expect(await adapter.search('   '), isEmpty);
    });
  });

  group('OfflineSongsCatalogAdapter', () {
    late String dbPath;
    // Never hits the network: every remote request returns 400.
    final offlineClient =
        MockClient((_) async => http.Response('unavailable', 400));

    setUp(() async {
      dbPath = await _tempDbPath('songs.sqlite');
      await _createCatalogDb(dbPath);
    });

    test('prefers the local database when installed', () async {
      final adapter = OfflineSongsCatalogAdapter(
        client: offlineClient,
        dbPathOverride: dbPath,
      );
      addTearDown(adapter.close);
      final songs = await adapter.fetchSongs();
      expect(songs.map((s) => s.id), ['s1', 's2', 's3']);

      final results = await adapter.search('grace');
      expect(results.map((s) => s.id), contains('s1'));
    });

    test('drops to the remote JSON source once the db is removed', () async {
      await File(dbPath).delete();
      final adapter = OfflineSongsCatalogAdapter(
        client: offlineClient,
        dbPathOverride: dbPath,
      );
      addTearDown(adapter.close);
      // Remote always fails with 400 here, so the fallback yields no songs
      // rather than throwing or hanging.
      expect(await adapter.fetchSongs(), isEmpty);
      expect(await adapter.search('grace'), isEmpty);
    });
  });

  group('SongsDownloadManager', () {
    test('refreshInstalled detects a file and delete removes it', () async {
      final dbPath = p.join(await getDatabasesPath(), 'songs.sqlite');

      final manager = SongsDownloadManager();
      await manager.refreshInstalled();
      expect(manager.isInstalled, isFalse);

      await _createCatalogDb(dbPath);
      await manager.refreshInstalled();
      expect(manager.isInstalled, isTrue);

      await manager.delete();
      expect(manager.isInstalled, isFalse);
      expect(File(dbPath).existsSync(), isFalse);
    });

    test('delete is a no-op when nothing is installed', () async {
      final manager = SongsDownloadManager();
      await manager.refreshInstalled();
      await manager.delete();
      expect(manager.isInstalled, isFalse);
    });
  });
}