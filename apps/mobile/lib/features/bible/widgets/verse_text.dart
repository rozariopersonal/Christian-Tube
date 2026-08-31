import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/bible_verse.dart';

class VerseText extends StatelessWidget {
  final BibleVerse verse;
  final bool isSelected;
  final bool isHighlighted;
  final VoidCallback? onTap;
  final double fontSize;

  const VerseText({
    super.key,
    required this.verse,
    this.isSelected = false,
    this.isHighlighted = false,
    this.onTap,
    this.fontSize = 18.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (verse.isChapterHeader) {
      return Padding(
        padding: const EdgeInsets.only(top: 32.0, bottom: 16.0, left: 16.0, right: 16.0),
        child: Text(
          verse.chapterTitle ?? '',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.2)
            : isHighlighted
                ? theme.colorScheme.tertiary.withValues(alpha: 0.28)
                : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${verse.number} ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.tokens.onSurfaceMuted,
                        fontWeight: FontWeight.bold,
                        fontSize: fontSize * 0.7,
                      ),
                    ),
                    TextSpan(
                      text: verse.text,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        height: 1.6,
                        fontSize: fontSize,
                        color: verse.isSecondary
                            ? context.tokens.onSurfaceMuted
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

