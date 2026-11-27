import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/dimens.dart';
import '../../../core/layout/adaptivity.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/services/user_preference_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_service.dart';
import '../../auth/auth_service.dart';
import '../../channels/channel_service.dart';
import '../controllers/onboarding_controller.dart';
import '../widgets/onboarding_google_signin_card.dart';
import '../widgets/onboarding_language_selector.dart';
import '../widgets/onboarding_primary_cta.dart';
import '../widgets/onboarding_welcome_header.dart';

/// Single-screen Quick Start onboarding for first-time and returning users.
class OnboardingScreen extends StatefulWidget {
  final AuthService authService;
  final ThemeService themeService;
  final ChannelService? channelService;
  final UserPreferenceService? preferenceService;

  const OnboardingScreen({
    super.key,
    required this.authService,
    required this.themeService,
    this.channelService,
    this.preferenceService,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final OnboardingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = OnboardingController(
      authService: widget.authService,
      channelService: widget.channelService,
      preferenceService: widget.preferenceService,
    );
    _controller.addListener(_onControllerChanged);
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final route = _controller.state.pendingNavigationRoute;
    if (route == null || !mounted) return;
    _controller.consumeNavigation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      GoRouter.maybeOf(context)?.go(route);
    });
  }

  void _handleLanguageTap(String code) {
    final changed = _controller.toggleLanguage(code);
    if (!changed && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('At least one language is required.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final screenClass = ScreenClass.of(context);

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: tokens.background,
        titleSpacing: AppDimens.lg,
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              height: 26,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.menu_book_rounded, color: context.primary),
            ),
            const SizedBox(width: AppDimens.sm),
            Flexible(
              child: Text(
                AppConfig.appName,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: tokens.onSurface,
                    ),
              ),
            ),
          ],
        ),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([_controller, widget.authService]),
        builder: (context, _) {
          final state = _controller.state;
          if (screenClass == ScreenClass.expanded) {
            return _buildExpandedBody(context, state);
          }
          return _buildCompactOrMediumBody(context, state);
        },
      ),
    );
  }

  Widget _buildCompactOrMediumBody(
    BuildContext context,
    OnboardingState state,
  ) {
    final tokens = context.tokens;

    return MaxWidthBox(
      maxWidth: 640,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.lg,
                vertical: AppDimens.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const OnboardingWelcomeHeader(),
                  const SizedBox(height: AppDimens.lg),
                  OnboardingGoogleSignInCard(
                    user: widget.authService.currentUser,
                    isLoading: widget.authService.isLoading || state.isSigningIn,
                    isCheckingReturningUser: state.isCheckingReturningUser,
                    onSignInPressed: _controller.signInWithGoogle,
                  ),
                  if (state.errorMessage != null) ...[
                    const SizedBox(height: AppDimens.md),
                    _ErrorBanner(
                      message: state.errorMessage!,
                      onDismiss: _controller.clearError,
                    ),
                  ],
                  const SizedBox(height: AppDimens.lg),
                  OnboardingLanguageSelector(
                    languages: _controller.availableLanguages,
                    selectedLanguages: state.selectedLanguages,
                    primaryBibleVersionId: state.primaryBibleVersionId,
                    onToggleLanguage: _handleLanguageTap,
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.lg,
              vertical: AppDimens.md,
            ),
            decoration: BoxDecoration(
              color: tokens.surface,
              border: Border(top: BorderSide(color: tokens.surfaceBorder)),
            ),
            child: SafeArea(
              top: false,
              child: OnboardingPrimaryCta(
                isSaving: state.isSaving,
                isDisabled: state.isCheckingReturningUser,
                onPressed: _controller.startExploring,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedBody(BuildContext context, OnboardingState state) {
    return MaxWidthBox(
      maxWidth: 960,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.xl,
        vertical: AppDimens.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const OnboardingWelcomeHeader(),
                  const SizedBox(height: AppDimens.lg),
                  OnboardingGoogleSignInCard(
                    user: widget.authService.currentUser,
                    isLoading: widget.authService.isLoading || state.isSigningIn,
                    isCheckingReturningUser: state.isCheckingReturningUser,
                    onSignInPressed: _controller.signInWithGoogle,
                  ),
                  if (state.errorMessage != null) ...[
                    const SizedBox(height: AppDimens.md),
                    _ErrorBanner(
                      message: state.errorMessage!,
                      onDismiss: _controller.clearError,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: AppDimens.xl),
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OnboardingLanguageSelector(
                    languages: _controller.availableLanguages,
                    selectedLanguages: state.selectedLanguages,
                    primaryBibleVersionId: state.primaryBibleVersionId,
                    onToggleLanguage: _handleLanguageTap,
                  ),
                  const SizedBox(height: AppDimens.lg),
                  OnboardingPrimaryCta(
                    isSaving: state.isSaving,
                    isDisabled: state.isCheckingReturningUser,
                    onPressed: _controller.startExploring,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.md,
        vertical: AppDimens.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: AppDimens.sm),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: colorScheme.onErrorContainer,
            ),
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}
