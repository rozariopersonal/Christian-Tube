import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/audio_processor_models.dart';

class AdminAudioJobStore {
  static final AdminAudioJobStore instance = AdminAudioJobStore._();
  AdminAudioJobStore._();

  Database? _db;

  Future<Database?> _open() async {
    if (kIsWeb) return null;
    if (_db != null && _db!.isOpen) return _db;
    final dir = await getDatabasesPath();
    final dbPath = p.join(dir, 'admin_audio_jobs.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onConfigure: (db) async {
        // WAL mode prevents "database is locked" when the Report Page reads
        // while a background isolate writes.
        await db.rawQuery('PRAGMA journal_mode=WAL');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS admin_audio_jobs (
            videoId TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            channelName TEXT NOT NULL,
            status TEXT NOT NULL,
            uploadSessionId TEXT,
            putSucceeded INTEGER NOT NULL DEFAULT 0,
            bytesUploaded INTEGER,
            durationSeconds INTEGER,
            error TEXT,
            updatedAt TEXT NOT NULL
          )
        ''');
      },
    );
    return _db;
  }

  Future<void> upsert(LocalAudioJobRecord record) async {
    final db = await _open();
    if (db == null) return;
    await db.insert(
      'admin_audio_jobs',
      record.toDbRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<LocalAudioJobRecord?> getByVideoId(String videoId) async {
    final db = await _open();
    if (db == null) return null;
    final rows = await db.query(
      'admin_audio_jobs',
      where: 'videoId = ?',
      whereArgs: [videoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LocalAudioJobRecord.fromDbRow(rows.first);
  }

  Future<List<LocalAudioJobRecord>> listRecent({int limit = 50}) async {
    final db = await _open();
    if (db == null) return const [];
    final rows = await db.query(
      'admin_audio_jobs',
      orderBy: 'updatedAt DESC',
      limit: limit,
    );
    return rows.map(LocalAudioJobRecord.fromDbRow).toList(growable: false);
  }

  Future<void> clearAll() async {
    final db = await _open();
    if (db == null) return;
    await db.delete('admin_audio_jobs');
  }
}
