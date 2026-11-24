import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/models/user.dart';
import '../../core/theme/app_tokens.dart';
import '../../features/auth/auth_service.dart';
import '../../features/auth/widgets/account_sync_panel.dart';

/// Profile avatar trigger that surfaces sync-paused / session-expired state
/// via an accent ring and `sync_problem` badge without layout shift.
class SyncAvatarButton extends StatelessWidget {
  final AuthService? authService;
  final double radius;
  final VoidCallback? onTapOverride;

  const SyncAvatarButton({
    super.key,
    this.authService,
    this.radius = 15,
    this.onTapOverride,
  });

  @override
  Widget build(BuildContext context) {
    final auth = authService ?? AuthService.shared;
    if (auth == null) {
      return _buildTrigger(context, user: null, expired: false, auth: null);
    }

    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        return _buildTrigger(
          context,
          user: auth.currentUser,
          expired: auth.sessionExpired,
          auth: auth,
        );
      },
    );
  }

  Widget _buildTrigger(
    BuildContext context, {
    required User? user,
    required bool expired,
    required AuthService? auth,
  }) {
    final tokens = context.tokens;
    final accent = context.accent;
    final semanticLabel = expired
        ? 'Account. Sync paused, tap to resume.'
        : 'Account & Settings';

    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Tooltip(
        message: semanticLabel,
        excludeFromSemantics: true,
        child: InkWell(
          key: const ValueKey('btn_profile'),
          borderRadius: BorderRadius.circular(radius + 8),
          onTap: onTapOverride ??
              () {
                if (auth != null) {
                  AccountSyncPanel.show(context, authService: auth);
                }
              },
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: EdgeInsets.all(expired ? 2 : 0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: expired
                        ? Border.all(color: accent, width: 2)
                        : null,
                  ),
                  child: _AvatarGraphic(
                    user: user,
                    radius: radius,
                    tokens: tokens,
                  ),
                ),
                if (expired)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: tokens.surface, width: 1.5),
                      ),
                      child: Icon(
                        Icons.sync_problem,
                        size: 9,
                        color: tokens.background,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarGraphic extends StatelessWidget {
  final User? user;
  final double radius;
  final AppTokens tokens;

  const _AvatarGraphic({
    required this.user,
    required this.radius,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final photoUrl = user?.photoUrl;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: tokens.surfaceVariant,
        backgroundImage: CachedNetworkImageProvider(photoUrl),
      );
    }
    if (user != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: tokens.surfaceVariant,
        child: Text(
          _initials(user!.displayName),
          style: TextStyle(
            fontSize: radius * 0.72,
            fontWeight: FontWeight.w700,
            color: tokens.onSurface,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: tokens.surfaceVariant.withValues(alpha: 0),
      child: Icon(
        Icons.account_circle,
        size: radius * 2,
        color: tokens.onSurface,
      ),
    );
  }

  String _initials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return 'U';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
  }
}
