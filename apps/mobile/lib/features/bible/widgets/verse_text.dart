import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/bible_verse.dart';

class VerseText extends StatelessWidget {
  final BibleVerse verse;
  final bool isSelected;
  final VoidCallback? onTap;
  final double fontSize;

  const VerseText({
    super.key,
    required this.verse,
    this.isSelected = false,
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
      child: Container(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.2)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (verse.versionLabel != null) ...[
              Container(
                margin: const EdgeInsets.only(right: 8, top: 3),
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: verse.isSecondary
                      ? context.tokens.surfaceVariant
                      : theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  verse.versionLabel!,
                  style: TextStyle(
                    color: verse.isSecondary
                        ? context.tokens.onSurfaceMuted
                        : theme.colorScheme.primary,
                    fontSize: fontSize * 0.55,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
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
