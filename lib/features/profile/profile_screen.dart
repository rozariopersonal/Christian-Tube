import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_service.dart';
import '../auth/widgets/sign_in_button.dart';
import '../channels/channel_service.dart';
import 'history_screen.dart';
import 'playlist_detail_screen.dart';
import 'settings_screen.dart';
import 'subscriptions_screen.dart';
import 'user_service.dart';
import '../../core/theme/theme_service.dart';

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
                      backgroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
                      child: user.photoUrl == null ? Text(user.displayName[0]) : null,
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
                      onPressed: () => authService.signOut(),
                    ),
                  ],
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Icon(Icons.account_circle, size: 48, color: Colors.blue),
                        const SizedBox(height: 8),
                        const Text(
                          'Sign in to sync your playlists & subscriptions',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        SignInButton(
                          isLoading: authService.isLoading,
                          onPressed: () => authService.signInWithGoogle(),
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
