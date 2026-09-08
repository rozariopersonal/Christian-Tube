import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/shared/models/note.dart';
import 'note_data_adapter.dart';

/// SharedPreferences-backed [NoteDataAdapter] for web targets where sqflite is
/// unavailable. Mirrors the JSON-blob persistence used by the books feature's
/// web adapter so notes remain available across sessions.
class WebNoteDataAdapter implements NoteDataAdapter {
  static const String _key = 'user_notes_v1';

  Future<List<Note>> _decode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Note.fromJson(e as Map<String, dynamic>))
          .where((n) => n.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _encode(List<Note> notes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(notes.map((n) => n.toJson()).toList()),
    );
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<List<Note>> loadAllNotes() async {
    final all = await _decode();
    all.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return all;
  }

  @override
  Future<Note?> getNoteForTarget(String feature, String targetId) async {
    final all = await _decode();
    for (final n in all) {
      if (n.feature == feature && n.targetId == targetId) return n;
    }
    return null;
  }

  @override
  Future<List<Note>> getNotesForFeature(String feature) async {
    final all = await _decode();
    return all.where((n) => n.feature == feature).toList();
  }

  @override
  Future<void> upsertNote(Note note) async {
    final all = await _decode();
    final remaining = all
        .where((n) => !(n.feature == note.feature && n.targetId == note.targetId))
        .toList();
    remaining.add(note);
    remaining.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _encode(remaining);
  }

  @override
  Future<void> deleteNote(String feature, String targetId) async {
    final all = await _decode();
    final remaining =
        all.where((n) => !(n.feature == feature && n.targetId == targetId)).toList();
    await _encode(remaining);
  }

  @override
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}