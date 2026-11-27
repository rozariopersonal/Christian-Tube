import 'package:flutter/material.dart';

import '../../../core/dimens.dart';
import '../../../core/theme/app_tokens.dart';

/// Primary Quick Start action button ("Start Exploring").
class OnboardingPrimaryCta extends StatelessWidget {
  final bool isSaving;
  final bool isDisabled;
  final VoidCallback onPressed;

  const OnboardingPrimaryCta({
    super.key,
    required this.isSaving,
    this.isDisabled = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppDimens.minTouchTarget),
          backgroundColor: context.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.lg,
            vertical: AppDimens.md + 2,
          ),
        ),
        onPressed: (isSaving || isDisabled) ? null : onPressed,
        child: isSaving
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.onPrimary,
                ),
              )
            : Text(
                'Start Exploring',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onPrimary,
                ),
              ),
      ),
    );
  }
}
