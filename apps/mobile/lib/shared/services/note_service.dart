import 'package:flutter/foundation.dart';

import 'package:mobile/features/user_items/services/user_item_sync_service.dart';
import 'package:mobile/shared/adapters/note_data_adapter.dart';
import 'package:mobile/shared/adapters/sqlite_note_data_adapter.dart';
import 'package:mobile/shared/adapters/web_note_data_adapter.dart';
import 'package:mobile/shared/annotations/user_item.dart';
import 'package:mobile/shared/annotations/user_item_repository.dart';
import 'package:mobile/shared/models/note.dart';

/// Shared persistence facade for user-authored notes.
///
/// The notes system is reused across reading surfaces (Bible, books,
/// articles). Feature controllers delegate to this service (AGENTS.md
/// "explicit layer boundaries") rather than touching the storage layer
/// directly.
///
/// **Two-tier storage**: pre-auth, notes live in the device store (SQLite on
/// mobile/desktop, a SharedPreferences JSON blob on web) and are never
/// uploaded. Signed-in users route through the per-user `user_items` store via
/// [UserItemSyncService]; deletes become soft-delete tombstones (`deleted`)
/// so they propagate to other devices before being purged after ack.
class NoteService {
  NoteService._(NoteDataAdapter adapter) : _adapter = adapter;

  late final NoteDataAdapter _adapter;

  /// Global shared instance backed by the platform-appropriate adapter.
  static final NoteService instance = NoteService._(_platformAdapter());

  /// A fresh instance with an injected [adapter] for widget-free unit tests.
  @visibleForTesting
  factory NoteService.forTesting({NoteDataAdapter? adapter}) =>
      NoteService._(adapter ?? _platformAdapter());

  static NoteDataAdapter _platformAdapter() {
    if (kIsWeb) return WebNoteDataAdapter();
    return SqliteNoteDataAdapter();
  }

  bool get _userTier => UserItemSyncService.instance.isUserTierActive;
  String get _userId => UserItemSyncService.instance.currentUserId!;

  Future<void> initialize() => _adapter.initialize();

  /// All notes, newest first.
  Future<List<Note>> loadAllNotes() =>
      _userTier ? _loadUserNotes() : _adapter.loadAllNotes();

  /// Device-tier-only load (used by sign-in re-home, never routed).
  Future<List<Note>> loadAllDeviceNotes() => _adapter.loadAllNotes();

  Future<List<Note>> _loadUserNotes() async {
    final items = await UserItemRepository.instance
        .loadForType(_userId, UserItem.typeNote);
    return items.map((i) => i.toNote()).toList();
  }

  /// The note anchored to [feature]:[targetId], or null when none exists.
  Future<Note?> getNoteForTarget(String feature, String targetId) async {
    if (!_userTier) return _adapter.getNoteForTarget(feature, targetId);
    final items = await UserItemRepository.instance
        .loadByTarget(_userId, feature, targetId);
    if (items.isEmpty) return null;
    return items.first.toNote();
  }

  /// All notes belonging to [feature] (e.g. `bible`).
  Future<List<Note>> getNotesForFeature(String feature) async {
    final all = await loadAllNotes();
    return all.where((n) => n.feature == feature).toList();
  }

  /// Persists (inserts or updates) [note].
  Future<void> saveNote(Note note) async {
    if (!_userTier) {
      await _adapter.upsertNote(note);
      return;
    }
    final repo = UserItemRepository.instance;
    final userId = _userId;
    // Enforce one note per anchor in the user tier too: drop any older row
    // that shares (feature, targetId) but carries a different id.
    final stale = await repo.loadByTarget(userId, note.feature, note.targetId);
    for (final existing in stale) {
      if (existing.id != note.id) {
        await repo.remove(userId, existing.id);
      }
    }
    await repo.insertOrReplace(userId, [UserItem.fromNote(note, userId)]);
    UserItemSyncService.instance.schedulePush();
  }

  /// Removes the note anchored to [feature]:[targetId]. No-op when absent.
  Future<void> deleteNote(String feature, String targetId) async {
    if (!_userTier) {
      await _adapter.deleteNote(feature, targetId);
      return;
    }
    final repo = UserItemRepository.instance;
    final userId = _userId;
    final existing = await repo.loadByTarget(userId, feature, targetId);
    if (existing.isEmpty) return;
    final now = DateTime.now().toUtc();
    await repo.insertOrReplace(
      userId,
      existing.map((i) => i.copyWith(deleted: true, updatedAt: now)).toList(),
    );
    UserItemSyncService.instance.schedulePush();
  }

  Future<void> clearAll() async {
    if (!_userTier) {
      await _adapter.clearAll();
      return;
    }
    final userId = _userId;
    final repo = UserItemRepository.instance;
    final all = await repo.loadForType(userId, UserItem.typeNote);
    for (final item in all) {
      await repo.remove(userId, item.id);
    }
    UserItemSyncService.instance.schedulePush();
  }

  /// Device-tier-only clear (used by sign-in re-home, never routed).
  Future<void> clearDeviceNotes() => _adapter.clearAll();

  /// Builds a persisted `updatedAt`-fresh [Note], retaining the existing id
  /// when one is present for the anchor. Convenience for callers that resolve
  /// the existing note first.
  static Note makeNote({
    required String id,
    required String feature,
    required String targetId,
    required String text,
    String? contextText,
  }) {
    final now = DateTime.now();
    return Note(
      id: id,
      feature: feature,
      targetId: targetId,
      text: text,
      contextText: contextText,
      createdAt: now,
      updatedAt: now,
    );
  }
}