import 'package:flutter/material.dart';
import '../auth/auth_service.dart';
import '../channels/channel_service.dart';
import '../history/history_screen.dart';
import 'admin_users_screen.dart';
import 'playlist_detail_screen.dart';
import 'settings_screen.dart';
import 'subscriptions_screen.dart';
import 'user_service.dart';
import '../../core/theme/theme_service.dart';
import '../../core/config/app_config.dart';

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
              'Enter your email to sign in or access Admin features if configured.',
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
            onPressed: () {
              Navigator.pop(ctx);
              authService.signInAsGuest(nameCtrl.text, emailCtrl.text);
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: Listenable.merge([authService, userService]),
      builder: (context, _) {
        final user = authService.currentUser;
        final isAdmin = authService.isAdmin;

        return Scaffold(
          appBar: AppBar(
            title: const Text('You'),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
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
            padding: const EdgeInsets.all(16),
            children: [
              // User Account Header
              if (user != null)
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      backgroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
                      child: user.photoUrl == null
                          ? Text(
                              user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : 'U',
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
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
                                child: Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
                          Text(user.email, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.grey),
                      tooltip: 'Sign Out',
                      onPressed: () => authService.signOut(),
                    ),
                  ],
                )
              else
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
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
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black87,
                              elevation: 1,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => authService.signInWithGoogle(),
                            icon: Image.network(
                              'https://www.gstatic.com/images/branding/product/2x/googleg_48dp.png',
                              height: 20,
                              errorBuilder: (_, __, ___) => const Icon(Icons.account_circle, color: Colors.blue),
                            ),
                            label: const Text('Continue with Google', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => _showQuickSignInDialog(context),
                            icon: const Icon(Icons.email_outlined, size: 18),
                            label: const Text('Sign In with Email / Name'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              // ADMIN CONSOLE SECTION (If Admin)
              if (isAdmin) ...[
                Container(
                  padding: const EdgeInsets.all(16),
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
                          const Icon(Icons.admin_panel_settings, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text('Admin Console', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.blue.shade900)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.people_alt_outlined, color: Colors.blue),
                        title: const Text('User Management', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: const Text('View registered users, block or unblock accounts', style: TextStyle(fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right),
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
                const SizedBox(height: 20),
              ],

              // History Section
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history),
                title: const Text('History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => HistoryScreen(history: userService.history),
                    ),
                  );
                },
              ),

              // Subscriptions Section
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.subscriptions_outlined),
                title: const Text('Subscriptions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => SubscriptionsScreen(channelService: channelService),
                    ),
                  );
                },
              ),

              const Divider(height: 32),

              // Playlists Section Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Playlists', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: () => _showCreatePlaylistDialog(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New'),
                  ),
                ],
              ),

              if (userService.playlists.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No playlists yet. Create your first playlist!', style: TextStyle(color: Colors.grey))),
                )
              else
                ...userService.playlists.map(
                  (p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.playlist_play, color: Colors.black87),
                    ),
                    title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${p.videoCount} videos', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right),
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
            ],
          ),
        );
      },
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
