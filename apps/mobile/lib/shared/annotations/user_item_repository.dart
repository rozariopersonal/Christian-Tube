import 'package:flutter/foundation.dart';

import 'sqlite_user_item_data_adapter.dart';
import 'user_item.dart';
import 'user_item_data_adapter.dart';
import 'web_user_item_data_adapter.dart';

/// Local persistence front door for authenticated users' annotation items.
///
/// Routes to the platform-appropriate [UserItemDataAdapter] (SQLite on mobile/
/// desktop, a per-user SharedPreferences blob on web). All operations are
/// scoped by [userId]; pre-auth device-local data never flows through here.
///
/// Highlights and bookmarks are persisted as full-list snapshots via
/// [replaceForType] (matching the device `saveAll` semantics), while notes use
/// row-level upserts and soft-delete tombstones so deletions can sync.
class UserItemRepository {
  UserItemRepository._() : _adapter = _platformAdapter();

  UserItemDataAdapter _adapter;

  /// Redirects the SQLite database file in tests (mirrors
  /// `LocalBibleService.overrideDbPath`); must be set before [resetForTest].
  @visibleForTesting
  static String? overrideDbPath;

  static UserItemDataAdapter _platformAdapter() => kIsWeb
      ? WebUserItemDataAdapter()
      : SqliteUserItemDataAdapter(databasePath: overrideDbPath);

  static final UserItemRepository instance = UserItemRepository._();

  /// A fresh instance with an injected [adapter] for widget-free unit tests.
  @visibleForTesting
  factory UserItemRepository.forTesting({UserItemDataAdapter? adapter}) =>
      UserItemRepository._adapterWrapper(adapter ?? _platformAdapter());

  UserItemRepository._adapterWrapper(this._adapter);

  /// Closes the active native adapter and rebuilds it from the current
  /// platform/override state (see `SqliteUserItemDataAdapter.overrideDbPath`).
  @visibleForTesting
  static Future<void> resetForTest() async {
    final prev = instance._adapter;
    if (prev is SqliteUserItemDataAdapter) {
      await prev.close();
    }
    instance._adapter = _platformAdapter();
  }

  Future<List<UserItem>> loadAll(String userId) async {
    final items = await _adapter.loadAll(userId);
    return items.where((i) => !i.deleted).toList();
  }

  Future<List<UserItem>> loadForType(String userId, String itemType) async {
    final items = await _adapter.loadForType(userId, itemType);
    return items.where((i) => !i.deleted).toList();
  }

  Future<List<UserItem>> loadByTarget(
      String userId, String feature, String targetId) async {
    final items = await _adapter.loadByTarget(userId, feature, targetId);
    return items.where((i) => !i.deleted).toList();
  }

  /// Everything mutated after [since] including soft-deleted tombstone rows
  /// (the push window).
  Future<List<UserItem>> loadDirtySince(String userId, DateTime since) =>
      _adapter.loadSince(userId, since);

  Future<void> insertOrReplace(String userId, List<UserItem> items) {
    if (items.isEmpty) return Future.value();
    return _adapter.upsertAll(userId, items);
  }

  Future<void> replaceForType(
          String userId, String itemType, List<UserItem> items) =>
      _adapter.replaceForType(userId, itemType, items);

  Future<void> remove(String userId, String id) => _adapter.remove(userId, id);

  Future<void> purgeTombstones(String userId) =>
      _adapter.purgeTombstones(userId);

  Future<void> clearUser(String userId) => _adapter.clearUser(userId);
}