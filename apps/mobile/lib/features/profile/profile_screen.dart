import 'package:flutter/material.dart';
import '../auth/auth_service.dart';
import '../auth/widgets/sign_in_button.dart';
import '../channels/channel_service.dart';
import '../history/history_screen.dart';
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Quick Sign-In to ${AppConfig.appName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your name to personalize your watch history, playlists, and channel subscriptions.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Your Name or Nickname',
                hintText: 'e.g. Alex, Maya',
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
              authService.signInAsGuest(nameCtrl.text);
            },
            child: const Text('Start Watching'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([authService, userService]),
      builder: (context, _) {
        final user = authService.currentUser;

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
                          Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          Text(user.email, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout),
                      tooltip: 'Sign Out',
                      onPressed: () => authService.signOut(),
                    ),
                  ],
                )
              else
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(Icons.account_circle, size: 54, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 10),
                        Text(
                          'Welcome to ${AppConfig.appName}',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Sign in to sync your playlists, favorites & subscriptions across devices',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        SignInButton(
                          isLoading: authService.isLoading,
                          onPressed: () async {
                            final u = await authService.signInWithGoogle();
                            if (u == null && context.mounted) {
                              _showQuickSignInDialog(context);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => _showQuickSignInDialog(context),
                          icon: const Icon(Icons.flash_on, size: 16),
                          label: const Text('Quick Sign-In (Guest Profile)'),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              // Navigation Links
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('History'),
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
              ListTile(
                leading: const Icon(Icons.subscriptions_outlined),
                title: const Text('Subscriptions'),
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
              ListTile(
                leading: const Icon(Icons.playlist_play),
                title: const Text('Your Playlists'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  if (userService.playlists.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => PlaylistDetailScreen(playlist: userService.playlists.first),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
