import 'package:flutter/material.dart';
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
    final tokens = context.tokens;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  note.topic,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  note.isChapterOverview ? 'Overview' : 'Context',
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (note.quote != null && note.quote!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: tokens.background.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Quote: "${note.quote}"',
                style: TextStyle(
                  color: tokens.onSurfaceMuted,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            note.text,
            style: TextStyle(
              color: tokens.onSurface,
              fontSize: baseFontSize,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.verified_outlined,
                  size: 13, color: tokens.onSurfaceMuted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  note.source,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.onSurfaceMuted,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
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
