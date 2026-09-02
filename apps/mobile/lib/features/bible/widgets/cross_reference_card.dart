import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/layout/adaptivity.dart';
import '../models/cross_reference.dart';

/// A single cross-reference card shown inside the inline expansion.
///
/// Renders the target's reference label as a badge and the resolved verse text
/// below it. The entire card is tappable and navigates to the target passage.
class CrossReferenceCard extends StatelessWidget {
  final CrossReference reference;
  final String? text;
  final double fontSize;
  final VoidCallback onTap;
  final String? versionId;

  const CrossReferenceCard({
    super.key,
    required this.reference,
    required this.text,
    required this.fontSize,
    required this.onTap,
    this.versionId,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final screen = ScreenClass.of(context);
    final cardTextSize = screen.isCompact ? fontSize * 0.85 : fontSize * 0.88;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(color: tokens.accent, width: 3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Reference label badge with full book name matching current bible version.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    reference.formatLabel(versionId),
                    style: TextStyle(
                      color: tokens.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                if (text != null && text!.isNotEmpty)
                  Text(
                    text!,
                    style: TextStyle(
                      color: tokens.onSurfaceMuted,
                      fontSize: cardTextSize,
                      height: 1.5,
                    ),
                  )
                else
                  Text(
                    'Text not available in this translation',
                    style: TextStyle(
                      color: tokens.onSurfaceDisabled,
                      fontSize: cardTextSize,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
