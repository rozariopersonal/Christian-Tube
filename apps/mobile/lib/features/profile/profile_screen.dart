import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_service.dart';
import '../channels/channel_service.dart';
import '../engines/scripture/services/saved_scripture_service.dart';
import 'user_service.dart';
import 'widgets/app_share_dialog.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/theme_service.dart';
import '../../core/layout/adaptivity.dart';
import '../../core/layout/content_width.dart';
import '../../core/models/video.dart';

class ProfileScreen extends StatelessWidget {
  final AuthService authService;
  final UserService userService;
  final ChannelService channelService;
  final ThemeService themeService;

  const ProfileScreen({
    super.key,
    required this.authService,
    required this.userService,
    required this.channelService,
    required this.themeService,
  });

  void _handleGoogleSignIn(BuildContext context) async {
    final user = await authService.signInWithGoogle();
    if (context.mounted) {
      if (user != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Welcome, ${user.displayName}!')),
        );
      } else if (authService.lastError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authService.lastError!),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([authService, userService]),
      builder: (context, _) {
        final user = authService.currentUser;
        final isAdmin = authService.isAdmin;
        final history = userService.history;
        final playlists = userService.playlists;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/logo.png',
                  height: 26,
                  fit: BoxFit.contain,
                  errorBuilder: (ctx, __, ___) => Icon(Icons.menu_book_rounded,
                      color: Theme.of(ctx).colorScheme.primary),
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text('You',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            actions: needsCollapsedActions(MediaQuery.sizeOf(context).width)
                ? [
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      tooltip: 'More',
                      onSelected: (value) {
                        if (value == 'settings') {
                          context.push('/settings');
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'settings',
                          child: ListTile(
                            leading: Icon(Icons.settings_outlined),
                            title: Text('Settings'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ]
                : [
                    IconButton(
                      icon: const Icon(Icons.cast_outlined),
                      tooltip: 'Cast',
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.notifications_none_outlined),
                      tooltip: 'Notifications',
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: 'Settings',
                      onPressed: () {
                        context.push('/settings');
                      },
                    ),
                  ],
          ),
          body: MaxWidthBox(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // User Account Header Card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: user != null
                      ? Row(
                          children: [
                            CircleAvatar(
                              radius: 34,
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              backgroundImage: user.photoUrl != null
                                  ? NetworkImage(user.photoUrl!)
                                  : null,
                              child: user.photoUrl == null
                                  ? Text(
                                      user.displayName.isNotEmpty
                                          ? user.displayName[0].toUpperCase()
                                          : 'U',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimary,
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          user.displayName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18),
                                        ),
                                      ),
                                      if (isAdmin) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text('ADMIN',
                                              style: TextStyle(
                                                  color: ColorScheme.of(context)
                                                      .onPrimary,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(user.email,
                                      style: TextStyle(
                                          color: context.tokens.onSurfaceMuted,
                                          fontSize: 13)),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      InkWell(
                                        onTap: () => _handleGoogleSignIn(context),
                                        child: Text('Switch account',
                                            style: TextStyle(
                                                color: context.tokens.accent,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600)),
                                      ),
                                      Text('  •  ',
                                          style: TextStyle(
                                              color: context
                                                  .tokens.onSurfaceDisabled,
                                              fontSize: 13)),
                                      InkWell(
                                        onTap: () => authService.signOut(),
                                        child: Text('Sign out',
                                            style: TextStyle(
                                                color: context
                                                    .tokens.onSurfaceMuted,
                                                fontSize: 13)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: context.tokens.surfaceVariant,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'Sign in to sync your subscriptions, watch plans, and access admin tools.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 14),
                              if (authService.isLoading)
                                const Center(
                                    child: Padding(
                                        padding: EdgeInsets.all(8),
                                        child: CircularProgressIndicator()))
                              else ...[
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: context.tokens.onSurface,
                                    foregroundColor: context.tokens.background,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(20)),
                                  ),
                                  onPressed: () => _handleGoogleSignIn(context),
                                  icon: Image.network(
                                    'https://www.gstatic.com/images/branding/product/2x/googleg_48dp.png',
                                    height: 18,
                                    errorBuilder: (ctx, __, ___) => Icon(
                                        Icons.account_circle,
                                        color:
                                            Theme.of(ctx).colorScheme.primary),
                                  ),
                                  label: const Text('Continue with Google',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 16),

                // ADMIN CONSOLE SECTION (If Admin)
                if (isAdmin) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.tokens.surfaceVariant,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.tokens.surfaceBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.admin_panel_settings,
                                  color: context.tokens.accent, size: 20),
                              const SizedBox(width: 8),
                              Text('Admin Console',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: context.tokens.onSurface)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.people_alt_outlined,
                                color: context.tokens.accent),
                            title: const Text('User Management',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: const Text(
                                'View registered users, block or unblock accounts',
                                style: TextStyle(fontSize: 13)),
                            trailing: const Icon(Icons.chevron_right, size: 20),
                            onTap: () {
                              context.push('/admin-users');
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // History Section with Horizontal Carousel
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('History',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      TextButton(
                        onPressed: () {
                          context.push('/history');
                        },
                        child: const Text('View all',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),

                if (history.isEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'Videos you watch will show up here.',
                      style: TextStyle(
                          color: context.tokens.onSurfaceMuted, fontSize: 13),
                    ),
                  )
                else
                  SizedBox(
                    height: 150,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: history.length > 8 ? 8 : history.length,
                      itemBuilder: (context, index) {
                        final video = history[index];
                        return _buildHistoryItem(context, video);
                      },
                    ),
                  ),

                const Divider(height: 24),

                // Saved Scriptures & Verses Section
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.tokens.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.bookmark_rounded,
                        color: context.tokens.accent),
                  ),
                  title: const Text('Saved Scriptures & Verses',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  subtitle: ValueListenableBuilder<int>(
                    valueListenable: SavedScriptureService().savedCountNotifier,
                    builder: (context, count, _) => Text(
                      count == 1
                          ? '1 favorite verse saved'
                          : '$count favorite verses saved',
                      style: TextStyle(
                          color: context.tokens.onSurfaceMuted, fontSize: 13),
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {
                    context.push('/saved-scriptures');
                  },
                ),

                if (!kIsWeb)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: context.tokens.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.download_for_offline_rounded,
                          color: context.tokens.accent),
                    ),
                    title: const Text('Offline Library & Downloads',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    subtitle: Text(
                      'Bibles, Dictionaries, Books & Commentaries',
                      style: TextStyle(
                          color: context.tokens.onSurfaceMuted, fontSize: 13),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () {
                      context.push('/downloads');
                    },
                  ),

                const Divider(height: 24),

                // Playlists & Watch Plans Section Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Playlists & Watch Plans',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 20),
                        tooltip: 'New Playlist',
                        onPressed: () => _showCreatePlaylistDialog(context),
                      ),
                      TextButton(
                        onPressed: () {
                          context.push('/watch-plans');
                        },
                        child: const Text('Watch Plans',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),

                if (playlists.isEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'No playlists yet. Tap + to create your first playlist!',
                      style: TextStyle(
                          color: context.tokens.onSurfaceMuted, fontSize: 13),
                    ),
                  )
                else
                  ...playlists.map(
                    (p) => ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: context.tokens.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.playlist_play,
                            color: Theme.of(context).colorScheme.error),
                      ),
                      title: Text(p.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text('${p.videoCount} videos',
                          style: TextStyle(
                              color: context.tokens.onSurfaceMuted,
                              fontSize: 13)),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () {
                        context.push('/playlists/${p.id}', extra: p);
                      },
                    ),
                  ),

                const Divider(height: 24),

                // Subscriptions Section
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Icon(Icons.subscriptions_outlined),
                  title: const Text('Your Subscriptions',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {
                    context.push('/subscriptions');
                  },
                ),

                // Channels Section
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Channels',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {
                    context.push('/channels');
                  },
                ),

                // Settings Section
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Appearance, Fonts & Language',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  subtitle: const Text(
                      'Dark Mode, AMOLED Black, Colors, Typography',
                      style: TextStyle(fontSize: 13)),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {
                    context.push('/settings');
                  },
                ),

                // Share App & QR Code Section
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Icon(Icons.qr_code_2_rounded),
                  title: const Text('Share App & QR Code',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  subtitle: const Text('Share download link or scan QR code',
                      style: TextStyle(fontSize: 13)),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => AppShareDialog.show(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryItem(BuildContext context, Video video) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: () {
          context.push('/watch/${video.id}', extra: {'video': video});
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: CachedNetworkImage(
                      imageUrl: video.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          Container(color: context.tokens.surfaceVariant),
                    ),
                  ),
                ),
                if (video.duration != null && video.duration!.isNotEmpty)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: context.tokens.scrim,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        video.duration!,
                        style: TextStyle(
                            color: context.tokens.onSurface,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, height: 1.2),
            ),
            Text(
              video.channelTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontSize: 13, color: context.tokens.onSurfaceMuted),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final titleController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(
              labelText: 'Playlist Title', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.trim().isNotEmpty) {
                userService.createPlaylist(titleController.text.trim(), null);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
