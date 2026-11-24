import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/note.dart';
import '../services/note_service.dart';
import 'note_editor_sheet.dart';

/// Opens [NoteEditorSheet] for a media target ([feature]: `video` or `short`)
/// and persists any save/delete through [NoteService].
///
/// Returns `true` if a note now exists for the target, `false` if deleted/absent,
/// or `null` if the user dismissed without changing anything.
Future<bool?> showMediaNoteEditor(
  BuildContext context, {
  required String feature,
  required String targetId,
  String? title,
  String? contextText,
}) async {
  final existing = await NoteService.instance.getNoteForTarget(feature, targetId);
  if (!context.mounted) return null;

  final result = await NoteEditorSheet.show(
    context,
    initialText: existing?.text ?? '',
    contextText: contextText,
    title: title,
    hasExistingNote: existing != null && !existing.isEmpty,
  );
  if (!context.mounted || result == null) return null;

  switch (result) {
    case NoteEditorSave(:final text):
      final now = DateTime.now();
      final note = Note(
        id: existing?.id ?? const Uuid().v4(),
        feature: feature,
        targetId: targetId,
        text: text,
        contextText: contextText,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
      await NoteService.instance.saveNote(note);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note saved'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return true;
    case NoteEditorDelete():
      await NoteService.instance.deleteNote(feature, targetId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note deleted'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    case NoteEditorDismiss():
      return null;
  }
}
