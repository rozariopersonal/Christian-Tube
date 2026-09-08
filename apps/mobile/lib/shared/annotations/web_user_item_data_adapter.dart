import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'user_item.dart';
import 'user_item_data_adapter.dart';

/// SharedPreferences-backed [UserItemDataAdapter] for web targets where
/// sqflite is unavailable. Stores one JSON blob per user
/// (`user_items_v1_<userId>`) so accounts do not leak into each other.
class WebUserItemDataAdapter implements UserItemDataAdapter {
  static String _keyFor(String userId) => 'user_items_v1_$userId';

  Future<List<UserItem>> _decode(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFor(userId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => UserItem.fromJson(e as Map<String, dynamic>))
          .where((i) => i.userId == userId && i.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _encode(String userId, List<UserItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final rows =
        items.map((i) => i.copyWith(userId: userId).toJson()).toList();
    await prefs.setString(_keyFor(userId), jsonEncode(rows));
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<List<UserItem>> loadAll(String userId) async {
    final all = await _decode(userId);
    all.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return all;
  }

  @override
  Future<List<UserItem>> loadForType(String userId, String itemType) async {
    final all = await _decode(userId);
    final filtered = all.where((i) => i.itemType == itemType).toList();
    filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return filtered;
  }

  @override
  Future<List<UserItem>> loadByTarget(
      String userId, String feature, String targetId) async {
    final all = await _decode(userId);
    return all
        .where((i) =>
            i.itemType == UserItem.typeNote &&
            i.feature == feature &&
            i.targetId == targetId)
        .toList();
  }

  @override
  Future<List<UserItem>> loadSince(String userId, DateTime since) async {
    final all = await _decode(userId);
    final filtered =
        all.where((i) => i.updatedAt.isAfter(since)).toList();
    filtered.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return filtered;
  }

  @override
  Future<void> upsertAll(String userId, List<UserItem> items) async {
    final all = await _decode(userId);
    final byId = <String, UserItem>{for (final i in all) i.id: i};
    for (final item in items) {
      byId[item.id] = item.copyWith(userId: userId);
    }
    await _encode(userId, byId.values.toList());
  }

  @override
  Future<void> replaceForType(
      String userId, String itemType, List<UserItem> items) async {
    final all = await _decode(userId);
    final kept = all.where((i) => i.itemType != itemType).toList()
      ..addAll(items);
    await _encode(userId, kept);
  }

  @override
  Future<void> remove(String userId, String id) async {
    final all = await _decode(userId);
    await _encode(userId, all.where((i) => i.id != id).toList());
  }

  @override
  Future<void> purgeTombstones(String userId) async {
    final all = await _decode(userId);
    await _encode(userId, all.where((i) => !i.deleted).toList());
  }

  @override
  Future<void> clearUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFor(userId));
  }
}