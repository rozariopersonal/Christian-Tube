import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scripture_card.dart';

class SavedScriptureService {
  static final SavedScriptureService _instance = SavedScriptureService._internal();
  factory SavedScriptureService() => _instance;
  SavedScriptureService._internal();

  static const String _storageKey = 'saved_scripture_verses_v1';
  final Map<String, ScriptureCard> _savedMap = {};
  bool _isInitialized = false;

  final ValueNotifier<int> savedCountNotifier = ValueNotifier<int>(0);

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawJson = prefs.getString(_storageKey);
      if (rawJson != null && rawJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(rawJson);
        _savedMap.clear();
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final card = ScriptureCard.fromJson(item);
            card.isSaved = true;
            _savedMap[card.id] = card;
          }
        }
      }
      savedCountNotifier.value = _savedMap.length;
      _isInitialized = true;
    } catch (e) {
      debugPrint('SavedScriptureService init error: $e');
    }
  }

  bool isSaved(String cardId) {
    return _savedMap.containsKey(cardId);
  }

  List<ScriptureCard> getSavedCards() {
    return _savedMap.values.toList().reversed.toList();
  }

  Future<bool> toggleSave(ScriptureCard card, String activeVersionId) async {
    await initialize();

    final cardId = card.id;
    final currentlySaved = _savedMap.containsKey(cardId);

    if (currentlySaved) {
      _savedMap.remove(cardId);
      card.isSaved = false;
    } else {
      card.isSaved = true;
      card.resolvedVersion ??= activeVersionId;
      _savedMap[cardId] = card;
    }

    savedCountNotifier.value = _savedMap.length;
    await _persist();
    return !currentlySaved;
  }

  Future<void> removeCard(String cardId) async {
    await initialize();
    if (_savedMap.containsKey(cardId)) {
      final card = _savedMap.remove(cardId);
      if (card != null) {
        card.isSaved = false;
      }
      savedCountNotifier.value = _savedMap.length;
      await _persist();
    }
  }

  Future<void> clearAll() async {
    await initialize();
    for (final card in _savedMap.values) {
      card.isSaved = false;
    }
    _savedMap.clear();
    savedCountNotifier.value = 0;
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _savedMap.values.map((c) => c.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(list));
    } catch (e) {
      debugPrint('Failed to persist saved scriptures: $e');
    }
  }
}
