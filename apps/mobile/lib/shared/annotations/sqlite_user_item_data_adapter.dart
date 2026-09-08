import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'user_item.dart';
import 'user_item_data_adapter.dart';

/// SQLite-backed [UserItemDataAdapter] for mobile/desktop.
///
/// Uses a dedicated `christian_tube_user_items.db` so authenticated users'
/// annotations survive re-downloads of the books/bibles databases and are kept
/// separate from pre-auth device-local stores. Rows are keyed by
/// `(user_id, id)` so one database serves every account on the device.
class SqliteUserItemDataAdapter implements UserItemDataAdapter {
  SqliteUserItemDataAdapter({String? databasePath}) : _databasePath = databasePath;

  /// Overridable for tests; defaults to `christian_tube_user_items.db` under
  /// the platform databases path.
  final String? _databasePath;

  Database? _db;
  bool _isInitializing = false;

  Future<Database?> get database async {
    if (_db != null && _db!.isOpen) return _db;
    await initialize();
    return _db;
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    _isInitializing = false;
    if (db != null && db.isOpen) {
      try {
        await db.close();
      } catch (_) {}
    }
  }

  @override
  Future<void> initialize() async {
    if (_db != null && _db!.isOpen) return;
    if (_isInitializing) {
      while (_isInitializing) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return;
    }
    _isInitializing = true;
    try {
      final dbPath = _databasePath ?? p.join(await getDatabasesPath(), 'christian_tube_user_items.db');
      _db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: (db, version) async {
          await _createTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _createTables(db);
        },
      );
      await _createTables(_db!);
    } catch (e) {
      debugPrint('SqliteUserItemDataAdapter initialize error: $e');
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_items (
        user_id     TEXT NOT NULL,
        id          TEXT NOT NULL,
        item_type   TEXT NOT NULL,
        feature     TEXT NOT NULL DEFAULT 'bible',
        version_id  TEXT NOT NULL DEFAULT '',
        book        TEXT NOT NULL DEFAULT '',
        chapter     INTEGER NOT NULL DEFAULT 0,
        verse_start INTEGER NOT NULL DEFAULT 0,
        verse_end   INTEGER NOT NULL DEFAULT 0,
        target_id   TEXT NOT NULL DEFAULT '',
        color_index INTEGER,
        text        TEXT NOT NULL DEFAULT '',
        context_text TEXT,
        created_at  TEXT NOT NULL,
        updated_at  TEXT NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (user_id, id)
      );
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_user_items_anchor
      ON user_items (user_id, item_type, feature, target_id);
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_user_items_updated
      ON user_items (user_id, updated_at);
    ''');
  }

  Future<List<UserItem>> _query(String userId, Database db,
      {String? where, List<Object?>? whereArgs, String? orderBy}) async {
    try {
      final rows = await db.query(
        'user_items',
        where: 'user_id = ?${where != null ? ' AND $where' : ''}',
        whereArgs: [userId, ...?whereArgs],
        orderBy: orderBy,
      );
      return rows.map(UserItem.fromMap).toList();
    } catch (e) {
      debugPrint('SqliteUserItemDataAdapter query error: $e');
      return [];
    }
  }

  @override
  Future<List<UserItem>> loadAll(String userId) async {
    final db = await database;
    if (db == null) return [];
    return _query(userId, db, orderBy: 'updated_at DESC');
  }

  @override
  Future<List<UserItem>> loadForType(String userId, String itemType) async {
    final db = await database;
    if (db == null) return [];
    return _query(
      userId,
      db,
      where: 'item_type = ?',
      whereArgs: [itemType],
      orderBy: 'updated_at DESC',
    );
  }

  @override
  Future<List<UserItem>> loadByTarget(
      String userId, String feature, String targetId) async {
    final db = await database;
    if (db == null) return [];
    return _query(
      userId,
      db,
      where: 'item_type = ? AND feature = ? AND target_id = ?',
      whereArgs: [UserItem.typeNote, feature, targetId],
      orderBy: 'updated_at DESC',
    );
  }

  @override
  Future<List<UserItem>> loadSince(String userId, DateTime since) async {
    final db = await database;
    if (db == null) return [];
    return _query(
      userId,
      db,
      where: 'updated_at > ?',
      whereArgs: [since.toIso8601String()],
      orderBy: 'updated_at ASC',
    );
  }

  @override
  Future<void> upsertAll(String userId, List<UserItem> items) async {
    final db = await database;
    if (db == null || items.isEmpty) return;
    try {
      final batch = db.batch();
      for (final item in items) {
        batch.insert(
          'user_items',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('SqliteUserItemDataAdapter upsertAll error: $e');
    }
  }

  @override
  Future<void> replaceForType(
      String userId, String itemType, List<UserItem> items) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        await txn.delete(
          'user_items',
          where: 'user_id = ? AND item_type = ?',
          whereArgs: [userId, itemType],
        );
        for (final item in items) {
          await txn.insert('user_items', item.toMap());
        }
      });
    } catch (e) {
      debugPrint('SqliteUserItemDataAdapter replaceForType error: $e');
    }
  }

  @override
  Future<void> remove(String userId, String id) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.delete(
        'user_items',
        where: 'user_id = ? AND id = ?',
        whereArgs: [userId, id],
      );
    } catch (e) {
      debugPrint('SqliteUserItemDataAdapter remove error: $e');
    }
  }

  @override
  Future<void> purgeTombstones(String userId) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.delete(
        'user_items',
        where: 'user_id = ? AND deleted = 1',
        whereArgs: [userId],
      );
    } catch (e) {
      debugPrint('SqliteUserItemDataAdapter purgeTombstones error: $e');
    }
  }

  @override
  Future<void> clearUser(String userId) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.delete('user_items', where: 'user_id = ?', whereArgs: [userId]);
    } catch (e) {
      debugPrint('SqliteUserItemDataAdapter clearUser error: $e');
    }
  }
}