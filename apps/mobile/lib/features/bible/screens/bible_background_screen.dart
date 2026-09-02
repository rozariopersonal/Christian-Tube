import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/layout/adaptivity.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/bible_background_note.dart';

/// Dedicated "Historical & Cultural Context" screen for viewing background notes.
///
/// Responsive layout per the app-wide AGENTS.md standard:
/// - `compact`: main verse is placed at the top and the cultural notes scroll below.
/// - `medium`/`expanded`: split view — the main verse on the left pane, the background
///   notes list on the right pane inside a [MaxWidthBox].
class BibleBackgroundScreen extends StatelessWidget {
  final String verseText;
  final String verseLabel;
  final String? versionLabel;
  final List<BibleBackgroundNote> notes;
  final double baseFontSize;

  const BibleBackgroundScreen({
    super.key,
    required this.verseText,
    required this.verseLabel,
    this.versionLabel,
    required this.notes,
    required this.baseFontSize,
  });

  Widget _buildVerseCard(BuildContext context) {
    final tokens = context.tokens;
    final screen = ScreenClass.of(context);
    final fontSize = screen.isCompact ? baseFontSize : baseFontSize + 1.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: tokens.accent, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  verseLabel,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              if (versionLabel != null && versionLabel!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    versionLabel!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.onSurfaceMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            verseText,
            style: TextStyle(
              color: tokens.onSurface,
              fontSize: fontSize,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteItem(BuildContext context, BibleBackgroundNote note) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final textTheme = theme.textTheme;
    final commentaryFontSize = (baseFontSize * 0.92).clamp(14.0, 22.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Topic header & pill
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    note.topic,
                    style: (textTheme.titleMedium ?? const TextStyle()).copyWith(
                      color: tokens.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 15.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_edu_rounded, size: 12, color: tokens.accent),
                      const SizedBox(width: 4),
                      Text(
                        note.isChapterOverview ? 'Overview' : 'Context',
                        style: TextStyle(
                          color: tokens.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Quote container if present
            if (note.quote != null && note.quote!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: tokens.accent.withValues(alpha: 0.22)),
                ),
                child: Text(
                  '“${note.quote}”',
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: (commentaryFontSize * 0.88).clamp(12.0, 16.0),
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],

            // Note body
            const SizedBox(height: 12),
            Text(
              note.text,
              style: (textTheme.bodyMedium ?? const TextStyle()).copyWith(
                color: tokens.onSurface,
                fontSize: commentaryFontSize,
                height: 1.6,
                letterSpacing: 0.15,
              ),
            ),

            // Footer: Verified source attribution & Copy button
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.verified_outlined, size: 13, color: tokens.onSurfaceMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    note.source,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.onSurfaceMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(
                      ClipboardData(
                        text: '${note.topic}:\n${note.text}\n(${note.source})',
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Note copied to clipboard'),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.content_copy_outlined, size: 12, color: tokens.onSurfaceMuted),
                        const SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final screen = ScreenClass.of(context);

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        elevation: 0,
        title: Text(
          'Historical & Cultural Context',
          style: TextStyle(
            color: tokens.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: tokens.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: screen.isCompact ? _buildCompact(context) : _buildSplit(context),
    );
  }

  Widget _buildCompact(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _buildVerseCard(context),
        const SizedBox(height: 12),
        if (notes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'No specific historical background notes for this verse.',
                style: TextStyle(color: context.tokens.onSurfaceMuted),
              ),
            ),
          )
        else
          for (final note in notes) _buildNoteItem(context, note),
      ],
    );
  }

  Widget _buildSplit(BuildContext context) {
    return MaxWidthBox(
      child: SizedBox(
        height: double.infinity,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 360,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 24),
                child: _buildVerseCard(context),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Text(
                    '${notes.length} historical background ${notes.length == 1 ? 'note' : 'notes'}',
                    style: TextStyle(
                      color: context.tokens.onSurfaceMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final note in notes) _buildNoteItem(context, note),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
