import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/models/local_short_item.dart';

class LocalShortsStorage {
  static const String _storageKey = 'local_shorts_items_v1';

  static Future<List<LocalShortItem>> loadShorts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return [];

      final List<dynamic> list = jsonDecode(raw);
      return list
          .whereType<Map<String, dynamic>>()
          .map((j) => LocalShortItem.fromJson(j))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint('Error loading local shorts from storage: $e');
      return [];
    }
  }

  static Future<void> saveShorts(List<LocalShortItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = items.map((item) => item.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving local shorts to storage: $e');
    }
  }

  static Future<void> upsertShort(LocalShortItem item) async {
    final list = await loadShorts();
    final index = list.indexWhere((i) => i.id == item.id);
    if (index >= 0) {
      list[index] = item;
    } else {
      list.insert(0, item);
    }
    await saveShorts(list);
  }

  static Future<void> deleteShort(String id) async {
    final list = await loadShorts();
    list.removeWhere((i) => i.id == id);
    await saveShorts(list);
  }
}
