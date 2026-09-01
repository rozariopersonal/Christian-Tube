import 'package:flutter/material.dart';
import '../../../core/layout/adaptivity.dart';
import '../../../core/theme/app_tokens.dart';

/// A unified badge shown under a Bible verse that has cross-references and/or
/// commentary notes.
///
/// Behavior:
/// - When [canExpandInline] is true (at most 1 reference and at most 1 commentary),
///   tapping toggles an inline expansion directly below the verse.
/// - When [canExpandInline] is false (multiple references or multiple commentaries),
///   tapping opens the dedicated tabbed study page.
class VerseStudyBadge extends StatelessWidget {
  final int referenceCount;
  final int commentaryCount;
  final bool isInlineExpanded;
  final bool canExpandInline;
  final void Function(int targetTab) onOpenStudyPage;
  final VoidCallback onToggleInline;

  const VerseStudyBadge({
    super.key,
    required this.referenceCount,
    required this.commentaryCount,
    required this.isInlineExpanded,
    required this.canExpandInline,
    required this.onOpenStudyPage,
    required this.onToggleInline,
  });

  @override
  Widget build(BuildContext context) {
    if (referenceCount == 0 && commentaryCount == 0) {
      return const SizedBox.shrink();
    }

    final tokens = context.tokens;
    final screen = ScreenClass.of(context);
    final fontSize = screen.isCompact ? 12.0 : 13.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // References chip
          if (referenceCount > 0)
            _buildChip(
              context: context,
              icon: Icons.link,
              label: canExpandInline
                  ? (referenceCount == 1 ? '1 reference' : '$referenceCount refs')
                  : '$referenceCount references',
              trailingIcon: canExpandInline
                  ? (isInlineExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down)
                  : Icons.chevron_right,
              fontSize: fontSize,
              tokens: tokens,
              onTap: () {
                if (canExpandInline) {
                  onToggleInline();
                } else {
                  onOpenStudyPage(0);
                }
              },
            ),

          // Commentary chip
          if (commentaryCount > 0)
            _buildChip(
              context: context,
              icon: Icons.history_edu,
              label: canExpandInline
                  ? (commentaryCount == 1 ? '1 note' : '$commentaryCount notes')
                  : '$commentaryCount commentary',
              trailingIcon: canExpandInline
                  ? (isInlineExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down)
                  : Icons.chevron_right,
              fontSize: fontSize,
              tokens: tokens,
              onTap: () {
                if (canExpandInline) {
                  onToggleInline();
                } else {
                  onOpenStudyPage(1);
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required BuildContext context,
    required IconData icon,
    required String label,
    required IconData trailingIcon,
    required double fontSize,
    required AppTokens tokens,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
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
              Icon(icon, size: fontSize, color: tokens.accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(trailingIcon, size: fontSize + 1, color: tokens.onSurfaceMuted),
            ],
          ),
        ),
      ),
    );
  }
}
