import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/song.dart';
import 'song_catalog_adapter.dart';

/// SQLite-backed songs catalog reading the optional offline package
/// (`songs.sqlite`, installed by `SongsDownloadManager`).
///
/// The package is prebuilt by `tool/build_songs_catalog.js` and carries a
/// normalized `songs` + `song_verses` schema plus two FTS5 virtual tables
/// (`songs_fts`, `lyrics_fts`) for rich, relevance-ranked full-text search.
class SqliteSongsCatalogAdapter implements SongCatalogAdapter {
  static const String defaultFileName = 'songs.sqlite';

  /// Test seam: override the database file location instead of using the
  /// platform databases directory.
  final String? _dbPathOverride;
  Database? _db;

  SqliteSongsCatalogAdapter({String? dbPathOverride})
      : _dbPathOverride = dbPathOverride;

  /// Whether the offline songs database file exists on disk.
  Future<bool> get isInstalled async {
    if (kIsWeb) return false;
    try {
      return await File(await _dbPath()).exists();
    } catch (_) {
      return false;
    }
  }

  /// Resolves the database file path (defaults to the app databases dir).
  Future<String> _dbPath() async {
    if (_dbPathOverride != null) return _dbPathOverride;
    final dir = await getDatabasesPath();
    return p.join(dir, defaultFileName);
  }

  Future<Database?> _getDb() async {
    if (_db != null && _db!.isOpen) return _db;
    if (!await isInstalled) return null;
    try {
      _db = await openDatabase(await _dbPath());
      return _db;
    } catch (e) {
      debugPrint('SqliteSongsCatalogAdapter: could not open songs db: $e');
      return null;
    }
  }

  /// Closes the open handle (required before swapping the file during install).
  Future<void> close() async {
    if (_db != null) {
      try {
        if (_db!.isOpen) await _db!.close();
      } catch (_) {}
      _db = null;
    }
  }

  /// Number of songs in the database (0 when not installed). Used as a sanity
  /// check after install.
  Future<int> count() async {
    final db = await _getDb();
    if (db == null) return 0;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM songs');
    return (rows.first['c'] as int?) ?? 0;
  }

  @override
  Future<List<Song>> fetchSongs({bool forceRefresh = false}) async {
    final db = await _getDb();
    if (db == null) return const [];
    final rows = await db.query('songs', orderBy: 'rowid');
    final songs = <Song>[];
    for (final row in rows) {
      songs.add(await _songFromRow(db, row));
    }
    return songs;
  }

  @override
  Future<Song?> fetchSong(String songId, {bool forceRefresh = false}) async {
    final db = await _getDb();
    if (db == null) return null;
    final rows = await db.query(
      'songs',
      where: 'id = ?',
      whereArgs: [songId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _songFromRow(db, rows.first);
  }

  /// Rich search over the local FTS5 index (title/authors/labels first, then
  /// lyrics), with a LIKE substring fallback for non-tokenized matches. Results
  /// are deduplicated and relevance-ordered.
  @override
  Future<List<Song>> search(String query, {int limit = 50}) async {
    final term = query.trim();
    if (term.isEmpty) return const [];

    final db = await _getDb();
    if (db == null) return const [];

    final ids = <String>{};
    final ordered = <String>[];
    void addIds(List<Map<String, dynamic>> rows) {
      for (final row in rows) {
        final id = row['song_id'] as String? ?? row['id'] as String?;
        if (id == null) continue;
        if (ids.add(id)) ordered.add(id);
      }
    }

    // 1. Ranked FTS5 matches over song metadata and lyrics.
    final ftsTerm = _quotePhrase(term);
    if (ftsTerm.isNotEmpty) {
      try {
        final metaRows = await db.rawQuery(
          'SELECT song_id FROM songs_fts WHERE songs_fts MATCH ? ORDER BY rank',
          [ftsTerm],
        );
        addIds(metaRows);
        final lyricRows = await db.rawQuery(
          'SELECT song_id FROM lyrics_fts WHERE lyrics_fts MATCH ? ORDER BY rank',
          [ftsTerm],
        );
        addIds(lyricRows);
      } catch (e) {
        debugPrint('SqliteSongsCatalogAdapter: FTS5 search failed ($e); '
            'falling back to LIKE');
      }
    }

    // 2. LIKE substring fallback across metadata and lyrics.
    final like = '%${_escapeLike(term)}%';
    if (ordered.length < limit) {
      final metaRows = await db.query(
        'songs',
        columns: ['id'],
        where: "title LIKE ? ESCAPE '\\' OR title_roman LIKE ? ESCAPE '\\' "
            "OR author LIKE ? ESCAPE '\\' OR album LIKE ? ESCAPE '\\' "
            "OR collection LIKE ? ESCAPE '\\'",
        whereArgs: [like, like, like, like, like],
        limit: limit - ordered.length,
      );
      addIds(metaRows);
    }
    if (ordered.length < limit) {
      final verseRows = await db.query(
        'song_verses',
        columns: ['song_id'],
        where: "text LIKE ? ESCAPE '\\' OR text_roman LIKE ? ESCAPE '\\'",
        whereArgs: [like, like],
        limit: limit - ordered.length,
      );
      addIds(verseRows);
    }

    final results = <Song>[];
    for (final id in ordered.take(limit)) {
      final song = await _songFromId(db, id);
      if (song != null) results.add(song);
    }
    return results;
  }

  /// Wraps user input as an FTS5 quoted phrase so it is never interpreted as
  /// query syntax. Embedded double quotes are escaped per FTS5 rules.
  String _quotePhrase(String term) => '"${term.replaceAll('"', '""')}"';

  /// Escapes LIKE wildcards so user input is matched literally.
  String _escapeLike(String term) => term
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  Future<Song?> _songFromId(Database db, String id) async {
    final rows = await db.query(
      'songs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _songFromRow(db, rows.first);
  }

  Future<Song> _songFromRow(Database db, Map<String, dynamic> row) async {
    final verses = <String>[];
    final versesRoman = <String>[];
    final verseRows = await db.query(
      'song_verses',
      columns: ['idx', 'text', 'text_roman'],
      where: 'song_id = ?',
      whereArgs: [row['id']],
      orderBy: 'idx',
    );
    for (final v in verseRows) {
      verses.add(v['text'] as String? ?? '');
      versesRoman.add(v['text_roman'] as String? ?? '');
    }
    return Song(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      titleRoman: row['title_roman'] as String?,
      author: row['author'] as String?,
      album: row['album'] as String?,
      collection: row['collection'] as String?,
      language: row['language'] as String? ?? 'en',
      category: row['category'] as String?,
      verses: verses,
      versesRoman: versesRoman,
      audioUrl: row['audio_url'] as String?,
    );
  }
}