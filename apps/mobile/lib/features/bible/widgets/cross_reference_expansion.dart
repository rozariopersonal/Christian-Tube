import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/cross_reference.dart';
import 'cross_reference_card.dart';

/// The inline expandable cross-reference section shown below a verse.
///
/// Used for verses with at most two references (the reader routes verses with
/// more than two to the dedicated [CrossReferencesScreen] instead). Renders
/// each reference as a compact card; if it is ever handed more than two, it
/// shows a "View all" affordance so the rest are never hidden.
class CrossReferenceExpansion extends StatelessWidget {
  final List<CrossReference> references;
  final Map<String, String> resolvedTexts;
  final double baseFontSize;
  final String? versionId;
  final VoidCallback? onViewAll;
  final void Function(CrossReference) onTapReference;

  const CrossReferenceExpansion({
    super.key,
    required this.references,
    required this.resolvedTexts,
    required this.baseFontSize,
    this.versionId,
    this.onViewAll,
    required this.onTapReference,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final visible =
        references.length > 2 ? references.sublist(0, 2) : references;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final ref in visible)
              CrossReferenceCard(
                reference: ref,
                text: resolvedTexts[ref.textKey],
                fontSize: baseFontSize,
                versionId: versionId,
                onTap: () => onTapReference(ref),
              ),
            if (references.length > 2) ...[
              const SizedBox(height: 2),
              InkWell(
                onTap: onViewAll,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View all ${references.length} references',
                        style: TextStyle(
                          color: tokens.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: tokens.accent,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
