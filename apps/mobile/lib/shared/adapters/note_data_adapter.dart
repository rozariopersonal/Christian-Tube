import 'package:mobile/shared/models/note.dart';

/// Persistence contract for user-authored notes.
///
/// Implementations store notes in platform persistence (SQLite on
/// mobile/desktop, SharedPreferences JSON on web). The notes system is shared
/// across reading surfaces (Bible, books, articles), so all adapters speak the
/// same generic [Note] model keyed by ([Note.feature], [Note.targetId]).
abstract class NoteDataAdapter {
  /// Opens/prepares the underlying store. Safe to call repeatedly.
  Future<void> initialize();

  /// All notes, newest first.
  Future<List<Note>> loadAllNotes();

  /// The note anchored to [feature]:[targetId], or null when absent.
  Future<Note?> getNoteForTarget(String feature, String targetId);

  /// All notes for [feature].
  Future<List<Note>> getNotesForFeature(String feature);

  /// Inserts [note], replacing an existing note on the same anchor
  /// ([Note.feature] + [Note.targetId]).
  Future<void> upsertNote(Note note);

  /// Removes the note anchored to [feature]:[targetId]. No-op when absent.
  Future<void> deleteNote(String feature, String targetId);

  /// Removes every note.
  Future<void> clearAll();
}