import 'package:flutter/material.dart';
import '../models/bible_verse.dart';

class VerseText extends StatelessWidget {
  final BibleVerse verse;

  const VerseText({
    super.key,
    required this.verse,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
      child: SelectableText.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${verse.number} ',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark ? Colors.white54 : Colors.black54,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: verse.text,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.6,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
