import 'package:flutter/material.dart';

import '../../../core/dimens.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/ui/language_meta.dart';
import '../../engines/scripture/services/bible_download_manager.dart';

/// Quick Start language chips selector that auto-updates the primary Bible
/// translation preview.
class OnboardingLanguageSelector extends StatelessWidget {
  final List<LanguageMeta> languages;
  final Set<String> selectedLanguages;
  final String primaryBibleVersionId;
  final ValueChanged<String> onToggleLanguage;

  const OnboardingLanguageSelector({
    super.key,
    required this.languages,
    required this.selectedLanguages,
    required this.primaryBibleVersionId,
    required this.onToggleLanguage,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bibleMeta = BibleDownloadManager.getMeta(primaryBibleVersionId);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimens.lg),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose Your Languages',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: tokens.onSurface,
            ),
          ),
          const SizedBox(height: AppDimens.xs),
          Text(
            'Pick one or more languages for your Bible, books, songs, and audio.',
            style: textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              color: tokens.onSurfaceMuted,
            ),
          ),
          const SizedBox(height: AppDimens.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.md,
              vertical: AppDimens.sm,
            ),
            decoration: BoxDecoration(
              color: tokens.surfaceVariant,
              borderRadius: BorderRadius.circular(AppDimens.radiusMd),
              border: Border.all(color: tokens.surfaceBorder),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.auto_stories_outlined,
                  size: 18,
                  color: context.primary,
                ),
                const SizedBox(width: AppDimens.sm),
                Expanded(
                  child: Text(
                    'Primary Bible: ${bibleMeta.id} — ${bibleMeta.name}',
                    style: textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: tokens.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.md),
          Wrap(
            spacing: AppDimens.sm,
            runSpacing: AppDimens.sm,
            children: languages.map((lang) {
              final isSelected =
                  selectedLanguages.contains(lang.code.toLowerCase());
              return FilterChip(
                selected: isSelected,
                showCheckmark: true,
                checkmarkColor: colorScheme.onPrimary,
                selectedColor: colorScheme.primary,
                backgroundColor: tokens.surfaceVariant,
                side: BorderSide(
                  color: isSelected ? colorScheme.primary : tokens.surfaceBorder,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                ),
                label: Text(
                  lang.displayName,
                  style: textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? colorScheme.onPrimary : tokens.onSurface,
                  ),
                ),
                onSelected: (_) => onToggleLanguage(lang.code),
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }
}
