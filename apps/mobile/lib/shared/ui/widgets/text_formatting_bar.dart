import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/shared/services/reader_appearance.dart';

/// Segmented toggle bar for bold (B), italic (I), and underline (U) formatting.
class TextFormattingBar extends StatelessWidget {
  final ReaderAppearance appearance;
  final VoidCallback? onChanged;

  const TextFormattingBar({
    super.key,
    required this.appearance,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final borderCol = appearance.surfaceBorder(tokens);
    final bgCol = appearance.surfaceVariant(tokens);

    return ListenableBuilder(
      listenable: appearance,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: bgCol,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderCol),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Expanded(
                child: _FormatToggle(
                  label: 'B',
                  tooltip: 'Bold',
                  isActive: appearance.isBold,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    appearance.isBold = !appearance.isBold;
                    onChanged?.call();
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _FormatToggle(
                  label: 'I',
                  tooltip: 'Italic',
                  isActive: appearance.isItalic,
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    appearance.isItalic = !appearance.isItalic;
                    onChanged?.call();
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _FormatToggle(
                  label: 'U',
                  tooltip: 'Underline',
                  isActive: appearance.isUnderline,
                  style: const TextStyle(
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    appearance.isUnderline = !appearance.isUnderline;
                    onChanged?.call();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FormatToggle extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool isActive;
  final TextStyle style;
  final VoidCallback onTap;

  const _FormatToggle({
    required this.label,
    required this.tooltip,
    required this.isActive,
    required this.style,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final activeBg = tokens.accent.withValues(alpha: 0.22);
    final activeFg = tokens.accent;
    final inactiveFg = tokens.onSurface;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isActive ? activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive ? tokens.accent : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: style.copyWith(
                  color: isActive ? activeFg : inactiveFg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
