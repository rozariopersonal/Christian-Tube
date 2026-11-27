import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/dimens.dart';
import '../../../core/models/user.dart';
import '../../../core/theme/app_tokens.dart';

/// Optional Google Sign-In card that restores returning users or prepares
/// cloud sync for new users.
class OnboardingGoogleSignInCard extends StatelessWidget {
  final User? user;
  final bool isLoading;
  final bool isCheckingReturningUser;
  final VoidCallback? onSignInPressed;

  const OnboardingGoogleSignInCard({
    super.key,
    required this.user,
    required this.isLoading,
    required this.isCheckingReturningUser,
    this.onSignInPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimens.lg),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: user == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sync your account (optional)',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: tokens.onSurface,
                  ),
                ),
                const SizedBox(height: AppDimens.xs),
                Text(
                  'Already have an account or want cloud backup? Sign in with Google to restore or sync across devices.',
                  style: textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: tokens.onSurfaceMuted,
                  ),
                ),
                const SizedBox(height: AppDimens.md),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, AppDimens.minTouchTarget),
                      backgroundColor: tokens.surfaceVariant,
                      foregroundColor: tokens.onSurface,
                      side: BorderSide(color: tokens.surfaceBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.lg,
                        vertical: AppDimens.md,
                      ),
                    ),
                    onPressed: (isLoading || isCheckingReturningUser)
                        ? null
                        : onSignInPressed,
                    child: (isLoading || isCheckingReturningUser)
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.account_circle_outlined,
                                color: context.primary,
                              ),
                              const SizedBox(width: AppDimens.sm),
                              Flexible(
                                child: Text(
                                  'Sign in with Google',
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: tokens.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            )
          : _SignedInSummary(
              user: user!,
              isCheckingReturningUser: isCheckingReturningUser,
            ),
    );
  }
}

class _SignedInSummary extends StatelessWidget {
  final User user;
  final bool isCheckingReturningUser;

  const _SignedInSummary({
    required this.user,
    required this.isCheckingReturningUser,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final initial =
        user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : 'U';

    return Row(
      children: [
        CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.onPrimaryContainer,
          backgroundImage: user.photoUrl != null && user.photoUrl!.isNotEmpty
              ? CachedNetworkImageProvider(user.photoUrl!)
              : null,
          child: (user.photoUrl == null || user.photoUrl!.isEmpty)
              ? Text(initial)
              : null,
        ),
        const SizedBox(width: AppDimens.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.displayName.isNotEmpty ? user.displayName : 'Signed In',
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: tokens.onSurface,
                ),
              ),
              if (user.email.isNotEmpty)
                Text(
                  user.email,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: tokens.onSurfaceMuted,
                  ),
                ),
              if (isCheckingReturningUser) ...[
                const SizedBox(height: AppDimens.xs),
                Text(
                  'Checking your saved preferences...',
                  style: textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: context.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppDimens.sm),
        if (isCheckingReturningUser)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.primary,
            ),
          )
        else
          Icon(
            Icons.check_circle_rounded,
            color: context.accent,
            size: 22,
          ),
      ],
    );
  }
}
