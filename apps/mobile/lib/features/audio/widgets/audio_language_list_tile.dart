import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../books/models/book_language_meta.dart';

/// One selectable language row inside the audio language picker: badge, names,
/// native script, track count, and a multi-select checkbox.
class AudioLanguageListTile extends StatelessWidget {
  final String code;
  final bool isSelected;
  final int trackCount;
  final VoidCallback onTap;

  const AudioLanguageListTile({
    super.key,
    required this.code,
    required this.isSelected,
    required this.trackCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final meta = BookLanguageMeta.fromCode(code);

    return Material(
      color: isSelected
          ? tokens.accent.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected
                      ? tokens.accent
                      : tokens.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? tokens.accent
                        : tokens.surfaceBorder,
                  ),
                ),
                alignment: Alignment.center,
                child: code == 'All'
                    ? Icon(
                        Icons.all_inclusive_rounded,
                        size: 18,
                        color: isSelected
                            ? tokens.onScrim
                            : tokens.onSurface,
                      )
                    : Text(
                        meta.code.toUpperCase(),
                        style: TextStyle(
                          color: isSelected
                              ? tokens.onScrim
                              : tokens.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.englishName,
                      style: TextStyle(
                        color: isSelected
                            ? tokens.accent
                            : tokens.onSurface,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    if (code != 'All' &&
                        meta.nativeName.isNotEmpty &&
                        meta.nativeName != meta.englishName)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          meta.nativeName,
                          style: TextStyle(
                            color: tokens.onSurfaceMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? tokens.accent.withValues(alpha: 0.15)
                      : tokens.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? tokens.accent.withValues(alpha: 0.3)
                        : tokens.surfaceBorder,
                  ),
                ),
                child: Text(
                  '$trackCount tracks',
                  style: TextStyle(
                    color: isSelected
                        ? tokens.accent
                        : tokens.onSurfaceMuted,
                    fontSize: 11,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              Icon(
                isSelected
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                color: isSelected
                    ? tokens.accent
                    : tokens.onSurfaceDisabled.withValues(alpha: 0.6),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}