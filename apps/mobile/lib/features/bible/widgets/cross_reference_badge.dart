import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/layout/adaptivity.dart';

/// A small tappable chip shown below a verse when it has cross-references.
///
/// Two modes:
/// - [openPage] `false` (verse has 1–2 references): tapping toggles the small
///   inline expansion; [expanded] flips its icon to show collapse.
/// - [openPage] `true` (verse has more than two references): tapping opens the
///   dedicated cross-references page, labelled "View all N references".
class CrossReferenceBadge extends StatelessWidget {
  final int count;
  final bool expanded;
  final bool openPage;
  final VoidCallback onTap;

  const CrossReferenceBadge({
    super.key,
    required this.count,
    required this.expanded,
    this.openPage = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final screen = ScreenClass.of(context);
    final fontSize = screen.isCompact ? 12.0 : 13.0;

    final label = openPage
        ? 'View all $count references'
        : expanded
            ? 'Collapse'
            : 'Cross-references';
    final trailingIcon = openPage
        ? Icons.chevron_right
        : expanded
            ? Icons.keyboard_arrow_up
            : Icons.keyboard_arrow_down;

    final semanticsLabel = openPage
        ? 'View all $count cross-references'
        : '$count cross-reference${count == 1 ? '' : 's'}, tap to ${expanded ? 'collapse' : 'expand'}';

    return Semantics(
      label: semanticsLabel,
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
                  Icons.link,
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
                  label,
                  style: TextStyle(
                    color: tokens.onSurfaceMuted,
                    fontSize: fontSize,
                  ),
                ),
                Icon(
                  trailingIcon,
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
