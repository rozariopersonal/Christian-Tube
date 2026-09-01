import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/cross_reference.dart';
import '../models/bible_background_note.dart';
import 'cross_reference_card.dart';

/// An inline expansion shown directly underneath a verse when there is only
/// one reference and/or one commentary note.
///
/// Gives the reader instant access without leaving the reading flow.
class VerseStudyInline extends StatelessWidget {
  final List<CrossReference> references;
  final List<BibleBackgroundNote> commentaryNotes;
  final Map<String, String> resolvedTexts;
  final double baseFontSize;
  final void Function(CrossReference)? onReferenceTap;
  final VoidCallback? onOpenFullPage;

  const VerseStudyInline({
    super.key,
    required this.references,
    required this.commentaryNotes,
    required this.resolvedTexts,
    required this.baseFontSize,
    this.onReferenceTap,
    this.onOpenFullPage,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasReference = references.isNotEmpty;
    final hasCommentary = commentaryNotes.isNotEmpty;

    if (!hasReference && !hasCommentary) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surfaceVariant.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.surfaceBorder),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Single Reference Preview
            if (hasReference) ...[
              for (final ref in references)
                CrossReferenceCard(
                  reference: ref,
                  text: resolvedTexts[ref.textKey],
                  fontSize: baseFontSize,
                  onTap: () => onReferenceTap?.call(ref),
                ),
            ],

            if (hasReference && hasCommentary)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Divider(color: tokens.surfaceBorder, height: 1),
              ),

            // Single Commentary Preview
            if (hasCommentary) ...[
              for (final note in commentaryNotes)
                _buildCommentaryCard(context, note, tokens),
            ],

            if (onOpenFullPage != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: onOpenFullPage,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Open Study View',
                          style: TextStyle(
                            color: tokens.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right,
                            size: 14, color: tokens.accent),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCommentaryCard(
    BuildContext context,
    BibleBackgroundNote note,
    AppTokens tokens,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history_edu, size: 14, color: tokens.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                note.topic,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: tokens.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                note.isChapterOverview ? 'Overview' : 'Context',
                style: TextStyle(
                  color: tokens.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (note.quote != null && note.quote!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Quote: "${note.quote}"',
            style: TextStyle(
              color: tokens.onSurfaceMuted,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          note.text,
          style: TextStyle(
            color: tokens.onSurface,
            fontSize: baseFontSize - 1.0,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.verified_outlined, size: 11, color: tokens.onSurfaceMuted),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                note.source,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.onSurfaceMuted,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
