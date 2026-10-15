import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/shared/services/reader_appearance.dart';

/// 3-stop line spacing selector (Tight, Standard, Relaxed).
class LineSpacingSelector extends StatelessWidget {
  final ReaderAppearance appearance;
  final VoidCallback? onChanged;

  const LineSpacingSelector({
    super.key,
    required this.appearance,
    this.onChanged,
  });

  static const double tightHeight = 1.35;
  static const double standardHeight = 1.6;
  static const double relaxedHeight = 1.9;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final mutedCol = appearance.mutedTextColor(tokens);
    final borderCol = appearance.surfaceBorder(tokens);
    final bgCol = appearance.surfaceVariant(tokens);

    return ListenableBuilder(
      listenable: appearance,
      builder: (context, _) {
        final current = appearance.lineHeight;
        final selectedStop = _closestStop(current);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Line Spacing',
              style: TextStyle(
                color: mutedCol,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: bgCol,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderCol),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: _SpacingOption(
                      label: 'Tight',
                      icon: Icons.format_line_spacing,
                      iconSize: 14,
                      isSelected: selectedStop == 0,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        appearance.lineHeight = tightHeight;
                        onChanged?.call();
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _SpacingOption(
                      label: 'Standard',
                      icon: Icons.format_line_spacing,
                      iconSize: 17,
                      isSelected: selectedStop == 1,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        appearance.lineHeight = standardHeight;
                        onChanged?.call();
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _SpacingOption(
                      label: 'Relaxed',
                      icon: Icons.format_line_spacing,
                      iconSize: 20,
                      isSelected: selectedStop == 2,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        appearance.lineHeight = relaxedHeight;
                        onChanged?.call();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  int _closestStop(double val) {
    final diff0 = (val - tightHeight).abs();
    final diff1 = (val - standardHeight).abs();
    final diff2 = (val - relaxedHeight).abs();
    if (diff0 <= diff1 && diff0 <= diff2) return 0;
    if (diff1 <= diff2) return 1;
    return 2;
  }
}

class _SpacingOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final double iconSize;
  final bool isSelected;
  final VoidCallback onTap;

  const _SpacingOption({
    required this.label,
    required this.icon,
    required this.iconSize,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final activeBg = tokens.accent.withValues(alpha: 0.22);
    final activeFg = tokens.accent;
    final inactiveFg = tokens.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? tokens.accent : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: iconSize,
                  color: isSelected ? activeFg : inactiveFg.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? activeFg : inactiveFg,
                      fontSize: 12.0,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
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
