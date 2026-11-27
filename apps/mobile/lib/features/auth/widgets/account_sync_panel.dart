import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/layout/adaptivity.dart';
import '../../../core/models/user.dart';
import '../../../core/theme/app_tokens.dart';
import '../auth_service.dart';

/// Adaptive account & sync status panel:
/// - `compact`: auto-sized scrollable modal bottom sheet with drag handle.
/// - `medium` / `expanded`: centered `AlertDialog` capped at 380dp width.
class AccountSyncPanel extends StatefulWidget {
  final AuthService authService;
  final VoidCallback? onOpenProfile;

  const AccountSyncPanel({
    super.key,
    required this.authService,
    this.onOpenProfile,
  });

  static Future<void> show(
    BuildContext context, {
    required AuthService authService,
    VoidCallback? onOpenProfile,
  }) {
    final screenClass = ScreenClass.of(context);
    if (screenClass.isCompact) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (sheetCtx) => AccountSyncPanel(
          authService: authService,
          onOpenProfile: onOpenProfile,
        ),
      );
    }

    return showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final tokens = dialogCtx.tokens;
        return AlertDialog(
          backgroundColor: tokens.surfaceElevated,
          surfaceTintColor: tokens.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: tokens.surfaceBorder),
          ),
          contentPadding: const EdgeInsets.all(20),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: AccountSyncPanel(
              authService: authService,
              onOpenProfile: onOpenProfile,
            ),
          ),
        );
      },
    );
  }

  @override
  State<AccountSyncPanel> createState() => _AccountSyncPanelState();
}

class _AccountSyncPanelState extends State<AccountSyncPanel> {
  Future<bool> _confirmAccountSwitch(User current, User next) async {
    if (!mounted) return false;
    final currentLabel =
        current.email.isNotEmpty ? current.email : current.displayName;
    final nextLabel = next.email.isNotEmpty ? next.email : next.displayName;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final tokens = ctx.tokens;
        return AlertDialog(
          backgroundColor: tokens.surfaceElevated,
          title: const Text('Switch Google account?'),
          content: Text(
            'Continue as $nextLabel? This removes local data saved for $currentLabel on this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Switch account'),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final tokens = ctx.tokens;
        return AlertDialog(
          backgroundColor: tokens.surfaceElevated,
          title: const Text('Sign out?'),
          content: const Text(
            'Signing out removes cached user data and offline downloads from this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Sign out'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await widget.authService.signOut();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _handleResumeOrSignIn() async {
    final user = await widget.authService.resumeSync(
      onConfirmAccountSwitch: _confirmAccountSwitch,
    );
    if (user != null && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = context.accent;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: widget.authService,
      builder: (context, _) {
        final user = widget.authService.currentUser;
        final expired = widget.authService.sessionExpired;
        final isLoading = widget.authService.isLoading;

        return SingleChildScrollView(
          padding: ScreenClass.of(context).isCompact
              ? const EdgeInsets.fromLTRB(20, 4, 20, 24)
              : EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _PanelAvatar(user: user, tokens: tokens),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? 'Not signed in',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            color: tokens.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user == null
                              ? 'Sign in to sync across devices'
                              : user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: tokens.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (user != null)
                _StatusPill(
                  icon: expired
                      ? Icons.sync_problem
                      : Icons.cloud_done_outlined,
                  text: expired
                      ? 'Sync paused · Local changes are saved on this device'
                      : 'Synced across your devices',
                  highlightBorder: expired ? accent : null,
                  iconColor: expired ? accent : tokens.onSurfaceMuted,
                ),
              if (widget.authService.lastError != null) ...[
                const SizedBox(height: 10),
                Text(
                  widget.authService.lastError!,
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
                ),
              ],
              if (user == null || expired) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: isLoading ? null : _handleResumeOrSignIn,
                  icon: isLoading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : Icon(
                          expired ? Icons.sync : Icons.login,
                          size: 18,
                        ),
                  label: Text(
                    expired ? 'Resume sync' : 'Sign in with Google',
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Divider(height: 1, color: tokens.surfaceBorder),
              const SizedBox(height: 6),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Icon(Icons.tune, color: tokens.onSurface),
                title: Text(
                  'Profile & Settings',
                  style: textTheme.bodyMedium?.copyWith(color: tokens.onSurface),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  if (widget.onOpenProfile != null) {
                    widget.onOpenProfile!();
                  } else {
                    context.push('/profile');
                  }
                },
              ),
              if (user != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _confirmSignOut,
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.error,
                    ),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Sign out'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PanelAvatar extends StatelessWidget {
  final User? user;
  final AppTokens tokens;

  const _PanelAvatar({required this.user, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final photoUrl = user?.photoUrl;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: tokens.surfaceVariant,
        backgroundImage: CachedNetworkImageProvider(photoUrl),
      );
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: tokens.surfaceVariant,
      child: Icon(
        user == null ? Icons.account_circle_outlined : Icons.person_outline,
        color: tokens.onSurface,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? highlightBorder;
  final Color iconColor;

  const _StatusPill({
    required this.icon,
    required this.text,
    this.highlightBorder,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlightBorder ?? tokens.surfaceBorder,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.onSurface,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
