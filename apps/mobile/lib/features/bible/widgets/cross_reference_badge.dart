import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/layout/adaptivity.dart';

/// A small tappable chip shown below a verse when it has cross-references.
///
/// Displayed only when the verse has at least one reference and the reader has
/// cross-reference data installed. Tapping it toggles the inline expansion for
/// that verse. When [expanded] it flips its icon, giving a clear affordance.
class CrossReferenceBadge extends StatelessWidget {
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  const CrossReferenceBadge({
    super.key,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final screen = ScreenClass.of(context);
    final fontSize = screen.isCompact ? 12.0 : 13.0;

    return Semantics(
      label: '$count cross-reference${count == 1 ? '' : 's'}, tap to ${expanded ? 'collapse' : 'expand'}',
      button: true,
      child: Padding(
        // Pad the hit area up to the minimum 48dp touch target while keeping
        // the visible chip compact.
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tokens.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.surfaceBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expanded ? Icons.link_off : Icons.link,
                  size: fontSize,
                  color: tokens.accent,
                ),
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  expanded ? 'Collapse' : 'Cross-references',
                  style: TextStyle(
                    color: tokens.onSurfaceMuted,
                    fontSize: fontSize,
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: fontSize,
                  color: tokens.onSurfaceMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
