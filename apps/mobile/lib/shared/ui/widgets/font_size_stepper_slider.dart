import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/shared/services/reader_appearance.dart';

/// Combined stepper buttons (A⁻ / A⁺) and tactile continuous slider for font size.
class FontSizeStepperSlider extends StatelessWidget {
  final ReaderAppearance appearance;
  final VoidCallback? onChanged;

  const FontSizeStepperSlider({
    super.key,
    required this.appearance,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textCol = appearance.textColor(tokens);
    final mutedCol = appearance.mutedTextColor(tokens);
    final borderCol = appearance.surfaceBorder(tokens);
    final bgCol = appearance.surfaceVariant(tokens);

    return ListenableBuilder(
      listenable: appearance,
      builder: (context, _) {
        final currentSize = appearance.fontSize;
        final canDecrease = currentSize > appearance.minFontSize;
        final canIncrease = currentSize < appearance.maxFontSize;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Font Size',
                  style: TextStyle(
                    color: mutedCol,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${currentSize.round()} pt',
                  style: TextStyle(
                    color: textCol,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: bgCol,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderCol),
              ),
              child: Row(
                children: [
                  // A⁻ button
                  IconButton(
                    icon: Text(
                      'A⁻',
                      style: TextStyle(
                        color: canDecrease ? textCol : mutedCol.withValues(alpha: 0.4),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    tooltip: 'Decrease font size',
                    onPressed: canDecrease
                        ? () {
                            HapticFeedback.selectionClick();
                            appearance.fontSize =
                                (currentSize - 1.0).clamp(appearance.minFontSize, appearance.maxFontSize);
                            onChanged?.call();
                          }
                        : null,
                  ),

                  // Slider
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        activeTrackColor: tokens.accent,
                        inactiveTrackColor: tokens.surfaceBorder,
                        thumbColor: tokens.accent,
                        overlayColor: tokens.accent.withValues(alpha: 0.15),
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      ),
                      child: Slider(
                        value: currentSize,
                        min: appearance.minFontSize,
                        max: appearance.maxFontSize,
                        divisions: (appearance.maxFontSize - appearance.minFontSize).toInt(),
                        onChanged: (val) {
                          appearance.fontSize = val;
                          onChanged?.call();
                        },
                      ),
                    ),
                  ),

                  // A⁺ button
                  IconButton(
                    icon: Text(
                      'A⁺',
                      style: TextStyle(
                        color: canIncrease ? textCol : mutedCol.withValues(alpha: 0.4),
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    tooltip: 'Increase font size',
                    onPressed: canIncrease
                        ? () {
                            HapticFeedback.selectionClick();
                            appearance.fontSize =
                                (currentSize + 1.0).clamp(appearance.minFontSize, appearance.maxFontSize);
                            onChanged?.call();
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
