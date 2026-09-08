import 'user_item.dart';

/// Storage contract for authenticated users' annotation items (`user_items`).
///
/// Every method is scoped by [userId] (required — pre-auth device-local data is
/// never stored through this interface). Implementations must tolerate
/// individually corrupt rows and return whatever valid data they can.
abstract class UserItemDataAdapter {
  /// Opens/readies the backing store. Safe to call repeatedly.
  Future<void> initialize();

  /// All items for [userId], newest first.
  Future<List<UserItem>> loadAll(String userId);

  /// Items of [itemType] (`highlight` | `bookmark` | `note`) for [userId].
  Future<List<UserItem>> loadForType(String userId, String itemType);

  /// Non-deleted items anchored to [feature]:[targetId] for [userId].
  Future<List<UserItem>> loadByTarget(
      String userId, String feature, String targetId);

  /// Items mutated strictly after [since] (push window), oldest first.
  Future<List<UserItem>> loadSince(String userId, DateTime since);

  /// Insert or replace [items] (conflict on the primary key).
  Future<void> upsertAll(String userId, List<UserItem> items);

  /// Deletes every row of [itemType] for [userId] then inserts [items],
  /// preserving full-list (snapshot) semantics for highlights/bookmarks.
  Future<void> replaceForType(
      String userId, String itemType, List<UserItem> items);

  /// Hard-deletes the row [id] for [userId] (tombstone acknowledged).
  Future<void> remove(String userId, String id);

  /// Hard-deletes rows soft-deleted ([deleted]) for [userId] after a push ack.
  Future<void> purgeTombstones(String userId);

  /// Removes all items for [userId].
  Future<void> clearUser(String userId);
}