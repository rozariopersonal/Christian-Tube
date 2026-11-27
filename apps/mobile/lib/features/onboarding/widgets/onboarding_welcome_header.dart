import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/dimens.dart';
import '../../../core/theme/app_tokens.dart';

/// Welcome hero header for the Quick Start onboarding screen.
class OnboardingWelcomeHeader extends StatelessWidget {
  const OnboardingWelcomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: context.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppDimens.radiusMd),
              ),
              child: Icon(
                Icons.church_rounded,
                size: 28,
                color: context.primary,
              ),
            ),
            const SizedBox(width: AppDimens.md),
            Expanded(
              child: Text(
                'Welcome to ${AppConfig.appName}',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: tokens.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.md),
        Text(
          'Your ad-free sanctuary for scripture study, sermons, books, and sacred music.',
          style: textTheme.bodyMedium?.copyWith(
            color: tokens.onSurfaceMuted,
          ),
        ),
        const SizedBox(height: AppDimens.md),
        const Wrap(
          spacing: AppDimens.sm,
          runSpacing: AppDimens.sm,
          children: [
            _FeaturePill(
              icon: Icons.menu_book_rounded,
              label: 'Scripture & Study',
            ),
            _FeaturePill(
              icon: Icons.video_collection_outlined,
              label: 'Curated Sermons',
            ),
            _FeaturePill(
              icon: Icons.headphones_rounded,
              label: 'Audio & Hymns',
            ),
          ],
        ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeaturePill({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.md,
        vertical: AppDimens.sm,
      ),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: context.primary),
          const SizedBox(width: AppDimens.xs + 2),
          Flexible(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: tokens.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
