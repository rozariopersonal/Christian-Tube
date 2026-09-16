import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/audio_series.dart';
import '../models/audio_track.dart';
import 'audio_catalog_adapter.dart';

class SqliteAudioCatalogAdapter implements AudioCatalogAdapter {
  static const String defaultFileName = 'audio_sync.sqlite';
  static const String syncedPrefKey = 'audio_sqlite_synced';
  static const int schemaVersion = 1;

  final String? dbPathOverride;
  Database? _db;
  Completer<Database>? _dbOpenCompleter;

  SqliteAudioCatalogAdapter({this.dbPathOverride});

  Future<String> _resolveDbPath() async {
    if (dbPathOverride != null) return dbPathOverride!;
    final dir = await getDatabasesPath();
    return p.join(dir, defaultFileName);
  }

  Future<bool> get isInitialized async {
    if (kIsWeb) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(syncedPrefKey) != true) {
        return false;
      }
      final path = await _resolveDbPath();
      if (!await File(path).exists()) return false;
      
      // Check if we have synced any data
      final db = await _getDb();
      final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM series'));
      return (count ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }

  Future<Database> _getDb() async {
    if (_db != null && _db!.isOpen) return _db!;
    if (_dbOpenCompleter != null) {
      return _dbOpenCompleter!.future;
    }

    final completer = Completer<Database>();
    _dbOpenCompleter = completer;
    try {
      final path = await _resolveDbPath();
      final db = await openDatabase(
      path,
      version: schemaVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE series (
            id TEXT PRIMARY KEY,
            title TEXT,
            description TEXT,
            speaker TEXT,
            category TEXT,
            language TEXT,
            coverUrl TEXT,
            trackCount INTEGER DEFAULT 0,
            updatedAt INTEGER
          )
        ''');
        
        await db.execute('''
          CREATE TABLE tracks (
            id TEXT PRIMARY KEY,
            seriesId TEXT,
            seriesTitle TEXT,
            title TEXT,
            speaker TEXT,
            durationSeconds INTEGER,
            audioUrl TEXT,
            streamUrl TEXT,
            fallbackUrl TEXT,
            coverUrl TEXT,
            thumbnailUrl TEXT,
            scriptureBook TEXT,
            scriptureChapter INTEGER,
            scriptureVerse INTEGER,
            updatedAt INTEGER,
            FOREIGN KEY (seriesId) REFERENCES series (id) ON DELETE CASCADE
          )
        ''');

        // Create FTS5 table for fast searching
        await db.execute('''
          CREATE VIRTUAL TABLE series_fts USING fts5(
            id UNINDEXED,
            title,
            description,
            speaker,
            category,
            language,
            content='series',
            content_rowid='rowid'
          )
        ''');
        
        await db.execute('''
          CREATE TRIGGER series_ai AFTER INSERT ON series BEGIN
            INSERT INTO series_fts(rowid, id, title, description, speaker, category, language) 
            VALUES (new.rowid, new.id, new.title, new.description, new.speaker, new.category, new.language);
          END;
        ''');
        
        await db.execute('''
          CREATE TRIGGER series_au AFTER UPDATE ON series BEGIN
            INSERT INTO series_fts(series_fts, rowid, id, title, description, speaker, category, language) 
            VALUES('delete', old.rowid, old.id, old.title, old.description, old.speaker, old.category, old.language);
            INSERT INTO series_fts(rowid, id, title, description, speaker, category, language) 
            VALUES (new.rowid, new.id, new.title, new.description, new.speaker, new.category, new.language);
          END;
        ''');
      },
    );
    _db = db;
    completer.complete(db);
    return db;
    } catch (e, st) {
      completer.completeError(e, st);
      rethrow;
    } finally {
      _dbOpenCompleter = null;
    }
  }

  Future<void> upsertSeries(AudioSeries series, {int? updatedAtMs}) async {
    final db = await _getDb();
    
    await db.insert('series', {
      'id': series.id,
      'title': series.title,
      'description': series.description,
      'speaker': series.speaker,
      'category': series.category,
      'language': series.language,
      'coverUrl': series.coverUrl,
      'trackCount': series.trackCount,
      'updatedAt': updatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    if (series.tracks.isNotEmpty) {
      final batch = db.batch();
      for (final track in series.tracks) {
        batch.insert('tracks', {
          'id': track.id,
          'seriesId': track.seriesId,
          'seriesTitle': track.seriesTitle,
          'title': track.title,
          'speaker': track.speaker,
          'durationSeconds': track.durationSeconds,
          'audioUrl': track.audioUrl,
          'streamUrl': track.streamUrl,
          'fallbackUrl': track.fallbackUrl,
          'coverUrl': track.coverUrl,
          'thumbnailUrl': track.thumbnailUrl,
          'scriptureBook': track.scriptureBook,
          'scriptureChapter': track.scriptureChapter,
          'scriptureVerse': track.scriptureVerse,
          'updatedAt': updatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    }
  }

  Future<int> getLastSyncTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(syncedPrefKey) != true) return 0;
      final path = await _resolveDbPath();
      if (!await File(path).exists()) return 0;
      final db = await _getDb();
      final result = await db.rawQuery('SELECT MAX(updatedAt) as max_time FROM series');
      if (result.isNotEmpty && result.first['max_time'] != null) {
        return result.first['max_time'] as int;
      }
    } catch (_) {}
    return 0;
  }

  @override
  Future<List<AudioSeries>> fetchCatalog({bool forceRefresh = false}) async {
    final db = await _getDb();
    final results = await db.query('series', orderBy: 'title ASC');
    
    return results.map((row) => AudioSeries(
      id: row['id'] as String,
      title: row['title'] as String,
      description: row['description'] as String,
      speaker: row['speaker'] as String,
      trackCount: row['trackCount'] as int,
      category: row['category'] as String,
      language: row['language'] as String,
      coverUrl: row['coverUrl'] as String?,
      tracks: [],
    )).toList();
  }

  @override
  Future<AudioSeries?> fetchSeries(String seriesId, {bool forceRefresh = false}) async {
    final db = await _getDb();
    
    final seriesRes = await db.query('series', where: 'id = ?', whereArgs: [seriesId]);
    if (seriesRes.isEmpty) return null;
    
    final row = seriesRes.first;
    
    final tracksRes = await db.query('tracks', where: 'seriesId = ?', whereArgs: [seriesId]);
    final tracks = tracksRes.map((t) => AudioTrack(
      id: t['id'] as String,
      seriesId: t['seriesId'] as String,
      seriesTitle: t['seriesTitle'] as String? ?? row['title'] as String,
      title: t['title'] as String,
      speaker: t['speaker'] as String? ?? 'Zac Poonen',
      durationSeconds: t['durationSeconds'] as int,
      audioUrl: t['audioUrl'] as String,
      streamUrl: t['streamUrl'] as String?,
      fallbackUrl: t['fallbackUrl'] as String?,
      coverUrl: t['coverUrl'] as String?,
      thumbnailUrl: t['thumbnailUrl'] as String?,
      scriptureBook: t['scriptureBook'] as String?,
      scriptureChapter: t['scriptureChapter'] as int?,
      scriptureVerse: t['scriptureVerse'] as int?,
    )).toList();
    
    return AudioSeries(
      id: row['id'] as String,
      title: row['title'] as String,
      description: row['description'] as String,
      speaker: row['speaker'] as String,
      trackCount: row['trackCount'] as int,
      category: row['category'] as String,
      language: row['language'] as String,
      coverUrl: row['coverUrl'] as String?,
      tracks: tracks,
    );
  }
  
  @override
  Future<List<AudioSeries>> search(String query, {int limit = 50}) async {
    final db = await _getDb();
    
    // Fuzzy search using FTS5 virtual table
    final cleanQuery = query.replaceAll('"', '""').trim();
    final ftsQuery = '"$cleanQuery"*';
    
    final results = await db.rawQuery('''
      SELECT s.* 
      FROM series s
      JOIN series_fts fts ON s.id = fts.id
      WHERE series_fts MATCH ?
      ORDER BY rank
      LIMIT ?
    ''', [ftsQuery, limit]);

    return results.map((row) => AudioSeries(
      id: row['id'] as String,
      title: row['title'] as String,
      description: row['description'] as String,
      speaker: row['speaker'] as String,
      trackCount: row['trackCount'] as int,
      category: row['category'] as String,
      language: row['language'] as String,
      coverUrl: row['coverUrl'] as String?,
      tracks: [],
    )).toList();
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }
}
