import 'package:flutter/material.dart';

import '../../core/layout/adaptivity.dart';
import '../../core/layout/content_width.dart';
import '../../core/theme/app_tokens.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'dart:convert';

/// What the user did in the [NoteEditorSheet].
///
/// - [NoteEditorSave]: the user tapped Save with [text] to persist.
/// - [NoteEditorDelete]: the user tapped Delete (remove the note).
/// - [NoteEditorDismiss]: the user cancelled / dismissed without saving.
sealed class NoteEditorResult {
  const NoteEditorResult();
}

class NoteEditorSave extends NoteEditorResult {
  final String text;
  const NoteEditorSave(this.text);
}

class NoteEditorDelete extends NoteEditorResult {
  const NoteEditorDelete();
}

class NoteEditorDismiss extends NoteEditorResult {
  const NoteEditorDismiss();
}

/// A friendly, reusable popup for composing/editing a note attached to an
/// anchored piece of content (a Bible verse, a book line, an article excerpt).
///
/// The sheet is presentational: it shows the anchored [contextText] as
/// read-only context, a large text field for the note, and Save / Cancel /
/// Delete actions. It does **not** touch persistence — the caller (typically a
/// feature controller) persists the returned text via the shared [NoteService].
///
/// Responsive (AGENTS.md "Modals, sheets, dialogs"):
/// - `compact`: bottom sheet.
/// - `medium`/`expanded`: centered [Dialog] capped at [kSheetMaxWidth] width,
///   scrolling internally so the keyboard/scale cannot overflow the window.
///
/// Returns a [NoteEditorResult]; see that type for the possible outcomes.
class NoteEditorSheet extends StatefulWidget {
  /// Initial note text to populate the editor (empty for a new note).
  final String initialText;

  /// The anchored content to show for context (verse text, excerpt). May be
  /// null when there is no readable snippet to display.
  final String? contextText;

  /// Label shown in the header (e.g. `Genesis 1:3`).
  final String? title;

  /// Whether a note already exists (enables the Delete action).
  final bool hasExistingNote;

  const NoteEditorSheet({
    super.key,
    this.initialText = '',
    this.contextText,
    this.title,
    this.hasExistingNote = false,
  });

  /// Shows the editor from [context], routing to a bottom sheet on `compact`
  /// or a centered dialog on `medium`+.
  static Future<NoteEditorResult?> show(
    BuildContext context, {
    String initialText = '',
    String? contextText,
    String? title,
    bool hasExistingNote = false,
  }) {
    if (ScreenClass.of(context).isCompact) {
      return showModalBottomSheet<NoteEditorResult>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: true,
        enableDrag: true,
        builder: (_) => NoteEditorSheet(
          initialText: initialText,
          contextText: contextText,
          title: title,
          hasExistingNote: hasExistingNote,
        ),
      );
    }
    return showDialog<NoteEditorResult>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: kSheetMaxWidth,
            maxHeight: 560,
          ),
          child: NoteEditorSheet(
            initialText: initialText,
            contextText: contextText,
            title: title,
            hasExistingNote: hasExistingNote,
          ),
        ),
      ),
    );
  }

  @override
  State<NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<NoteEditorSheet> {
  late final QuillController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = _initController(widget.initialText);
    _controller.addListener(_onChanged);
    _focusNode = FocusNode()..requestFocus();
  }

  QuillController _initController(String text) {
    if (text.isEmpty) return QuillController.basic();
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return QuillController(
          document: Document.fromJson(decoded),
          selection: const TextSelection.collapsed(offset: 0),
        );
      }
    } catch (_) {}
    
    final safeText = text.endsWith('\n') ? text : '$text\n';
    final doc = Document()..insert(0, safeText);
    return QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  void _onChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _pop(NoteEditorResult result) => Navigator.of(context).pop(result);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textCol = tokens.onSurface;
    final mutedCol = tokens.onSurfaceMuted;
    final borderCol = tokens.surfaceBorder;

    final canSave = !_controller.document.isEmpty();

    return Material(
      color: tokens.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  MediaQuery.sizeOf(context).height * 0.4,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: borderCol,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.edit_note_rounded,
                        color: tokens.accent, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.title == null || widget.title!.isEmpty
                            ? 'Note'
                            : 'Note — ${widget.title}',
                        style: TextStyle(
                          color: textCol,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: Icon(Icons.close, color: mutedCol, size: 20),
                      onPressed: () => _pop(const NoteEditorDismiss()),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (widget.contextText != null &&
                    widget.contextText!.trim().isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tokens.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderCol, width: 0.5),
                    ),
                    child: Text(
                      widget.contextText!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        color: mutedCol,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                QuillSimpleToolbar(
                  controller: _controller,
                  config: const QuillSimpleToolbarConfig(
                    showFontFamily: false,
                    showFontSize: false,
                    showSearchButton: false,
                    showInlineCode: false,
                    showCodeBlock: false,
                    showIndent: false,
                    showColorButton: true,
                    showBackgroundColorButton: true,
                    showClearFormat: true,
                    showAlignmentButtons: false,
                    showDirection: false,
                    showHeaderStyle: true,
                    showListCheck: false,
                    showQuote: false,
                    showLink: false,
                    showSubscript: false,
                    showSuperscript: false,
                    showStrikeThrough: true,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 240,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tokens.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderCol),
                  ),
                  child: QuillEditor.basic(
                    controller: _controller,
                    focusNode: _focusNode,
                    config: const QuillEditorConfig(),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (widget.hasExistingNote) ...[
                      IconButton(
                        tooltip: 'Delete note',
                        onPressed: () => _pop(const NoteEditorDelete()),
                        icon: Icon(Icons.delete_outline, color: mutedCol),
                      ),
                      const Spacer(),
                    ],
                    TextButton(
                      onPressed: () => _pop(const NoteEditorDismiss()),
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: mutedCol),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: canSave
                          ? () {
                              final text = jsonEncode(
                                  _controller.document.toDelta().toJson());
                              _pop(NoteEditorSave(text));
                            }
                          : null,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
