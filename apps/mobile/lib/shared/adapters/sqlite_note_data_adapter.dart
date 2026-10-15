import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:mobile/core/database/database_init.dart';
import 'package:mobile/shared/models/note.dart';
import 'note_data_adapter.dart';

/// SQLite-backed [NoteDataAdapter] for mobile/desktop.
///
/// Uses a dedicated `christian_tube_notes.db` so user notes survive
/// re-downloads of the books/bibles databases and are shared across all
/// reading surfaces. The `user_notes` table enforces one note per anchor via
/// a unique index on `(feature, target_id)`.
class SqliteNoteDataAdapter implements NoteDataAdapter {
  final String? databasePath;
  SqliteNoteDataAdapter({this.databasePath});

  static String? overrideDbPath;

  Database? _db;
  Future<Database?>? _openFuture;

  /// Unique, unduplicated rows per anchored target.
  Future<Database?> get database async {
    if (_db != null && _db!.isOpen) return _db;
    return _openDatabase();
  }

  Future<Database?> _openDatabase() {
    if (_openFuture != null) return _openFuture!;
    final future = Future(() async {
      try {
        initPlatformDatabases();
        final dbPath = databasePath ??
            overrideDbPath ??
            p.join(await getDatabasesPath(), 'christian_tube_notes.db');
        final db = await openDatabase(
          dbPath,
          version: 1,
          onCreate: (db, version) async {
            await _createTables(db);
          },
        );
        _db = db;
        return db;
      } catch (e) {
        debugPrint('SqliteNoteDataAdapter initialize error: $e');
        return null;
      } finally {
        _openFuture = null;
      }
    });
    _openFuture = future;
    return future;
  }

  @override
  Future<void> initialize() async {
    await database;
  }

  Future<void> close() async {
    _openFuture = null;
    final db = _db;
    _db = null;
    if (db != null && db.isOpen) {
      try {
        await db.close();
      } catch (_) {}
    }
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_notes (
        id TEXT PRIMARY KEY,
        feature TEXT NOT NULL,
        target_id TEXT NOT NULL,
        text TEXT NOT NULL DEFAULT '',
        context_text TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_notes_feature_target
      ON user_notes (feature, target_id);
    ''');
  }

  @override
  Future<List<Note>> loadAllNotes() async {
    final db = await database;
    if (db == null) return [];
    try {
      final rows = await db.query(
        'user_notes',
        orderBy: 'updated_at DESC',
      );
      return rows.map(Note.fromMap).toList();
    } catch (e) {
      debugPrint('SqliteNoteDataAdapter loadAllNotes error: $e');
      return [];
    }
  }

  @override
  Future<Note?> getNoteForTarget(String feature, String targetId) async {
    final db = await database;
    if (db == null) return null;
    try {
      final rows = await db.query(
        'user_notes',
        where: 'feature = ? AND target_id = ?',
        whereArgs: [feature, targetId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return Note.fromMap(rows.first);
    } catch (e) {
      debugPrint('SqliteNoteDataAdapter getNoteForTarget error: $e');
      return null;
    }
  }

  @override
  Future<List<Note>> getNotesForFeature(String feature) async {
    final db = await database;
    if (db == null) return [];
    try {
      final rows = await db.query(
        'user_notes',
        where: 'feature = ?',
        whereArgs: [feature],
        orderBy: 'updated_at DESC',
      );
      return rows.map(Note.fromMap).toList();
    } catch (e) {
      debugPrint('SqliteNoteDataAdapter getNotesForFeature error: $e');
      return [];
    }
  }

  @override
  Future<void> upsertNote(Note note) async {
    final db = await database;
    if (db == null) {
      throw StateError('Notes database is not initialized');
    }
    await db.insert(
      'user_notes',
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteNote(String feature, String targetId) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.delete(
        'user_notes',
        where: 'feature = ? AND target_id = ?',
        whereArgs: [feature, targetId],
      );
    } catch (e) {
      debugPrint('SqliteNoteDataAdapter deleteNote error: $e');
    }
  }

  @override
  Future<void> clearAll() async {
    final db = await database;
    if (db == null) return;
    try {
      await db.delete('user_notes');
    } catch (e) {
      debugPrint('SqliteNoteDataAdapter clearAll error: $e');
    }
  }
}