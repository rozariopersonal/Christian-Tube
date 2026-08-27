import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../auth/auth_service.dart';
import '../channels/channel_service.dart';
import '../engines/scripture/screens/saved_scriptures_screen.dart';
import '../engines/scripture/services/saved_scripture_service.dart';
import '../history/history_screen.dart';
import '../watch_plans/watch_plans_screen.dart';
import 'admin_users_screen.dart';
import 'playlist_detail_screen.dart';
import 'settings_screen.dart';
import 'subscriptions_screen.dart';
import 'user_service.dart';
import '../../core/theme/theme_service.dart';
import '../../core/config/app_config.dart';
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

  void _showQuickSignInDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign In to ${AppConfig.appName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your email to sign in or test Admin access if configured.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email Address',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final user = await authService.signInAsGuest(nameCtrl.text, emailCtrl.text);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Signed in as ${user.displayName}')),
                );
              }
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

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
            action: SnackBarAction(
              label: 'Quick Sign-In',
              onPressed: () => _showQuickSignInDialog(context),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
              children: [
                Image.asset(
                  'assets/logo.png',
                  height: 24,
                  width: 24,
                  errorBuilder: (_, __, ___) => const Icon(Icons.play_circle_fill, color: Colors.red),
                ),
                const SizedBox(width: 8),
                const Text('You', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              ],
            ),
            actions: [
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => SettingsScreen(themeService: themeService),
                    ),
                  );
                },
              ),
            ],
          ),
          body: ListView(
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
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            backgroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
                            child: user.photoUrl == null
                                ? Text(
                                    user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : 'U',
                                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
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
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                      ),
                                    ),
                                    if (isAdmin) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text('ADMIN', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(user.email, style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 13)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    InkWell(
                                      onTap: () => _showQuickSignInDialog(context),
                                      child: const Text('Switch account', style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.w600)),
                                    ),
                                    const Text('  •  ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                    InkWell(
                                      onTap: () => authService.signOut(),
                                      child: const Text('Sign out', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                          color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
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
                              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
                            else ...[
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isDark ? Colors.white : Colors.black,
                                  foregroundColor: isDark ? Colors.black : Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                                onPressed: () => _handleGoogleSignIn(context),
                                icon: Image.network(
                                  'https://www.gstatic.com/images/branding/product/2x/googleg_48dp.png',
                                  height: 18,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.account_circle, color: Colors.blue),
                                ),
                                label: const Text('Continue with Google', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: () => _showQuickSignInDialog(context),
                                icon: const Icon(Icons.email_outlined, size: 16),
                                label: const Text('Sign In with Email / Name', style: TextStyle(fontSize: 12)),
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
                      color: isDark ? const Color(0xFF1E293B) : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.blue.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.admin_panel_settings, color: Colors.blue, size: 20),
                            const SizedBox(width: 8),
                            Text('Admin Console', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.blue.shade900)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.people_alt_outlined, color: Colors.blue),
                          title: const Text('User Management', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: const Text('View registered users, block or unblock accounts', style: TextStyle(fontSize: 11)),
                          trailing: const Icon(Icons.chevron_right, size: 20),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (ctx) => AdminUsersScreen(userService: userService),
                              ),
                            );
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
                    const Text('History', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => HistoryScreen(history: history),
                          ),
                        );
                      },
                      child: const Text('View all', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),

              if (history.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Videos you watch will show up here.',
                    style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 13),
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
                      return _buildHistoryItem(context, video, isDark);
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
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bookmark_rounded, color: Color(0xFFF59E0B)),
                ),
                title: const Text('Saved Scriptures & Verses', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                subtitle: ValueListenableBuilder<int>(
                  valueListenable: SavedScriptureService().savedCountNotifier,
                  builder: (context, count, _) => Text(
                    count == 1 ? '1 favorite verse saved' : '$count favorite verses saved',
                    style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 12),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => const SavedScripturesScreen(),
                    ),
                  );
                },
              ),

              const Divider(height: 24),

              // Playlists & Watch Plans Section Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Playlists & Watch Plans', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add, size: 20),
                          tooltip: 'New Playlist',
                          onPressed: () => _showCreatePlaylistDialog(context),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (ctx) => const WatchPlansScreen(),
                              ),
                            );
                          },
                          child: const Text('Watch Plans', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (playlists.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'No playlists yet. Tap + to create your first playlist!',
                    style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 13),
                  ),
                )
              else
                ...playlists.map(
                  (p) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.playlist_play, color: Colors.red),
                    ),
                    title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('${p.videoCount} videos', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => PlaylistDetailScreen(playlist: p),
                        ),
                      );
                    },
                  ),
                ),

              const Divider(height: 24),

              // Subscriptions Section
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: const Icon(Icons.subscriptions_outlined),
                title: const Text('Your Subscriptions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => SubscriptionsScreen(channelService: channelService),
                    ),
                  );
                },
              ),

              // Settings Section
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Appearance, Fonts & Language', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                subtitle: const Text('Dark Mode, AMOLED Black, Colors, Typography', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => SettingsScreen(themeService: themeService),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryItem(BuildContext context, Video video, bool isDark) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(context, '/watch/${video.id}', arguments: {'video': video});
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
                      errorWidget: (_, __, ___) => Container(color: Colors.grey.shade800),
                    ),
                  ),
                ),
                if (video.duration != null && video.duration!.isNotEmpty)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        video.duration!,
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
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
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.2),
            ),
            Text(
              video.channelTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.black54),
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
          decoration: const InputDecoration(labelText: 'Playlist Title', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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

