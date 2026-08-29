import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_tokens.dart';
import 'user_service.dart';

class AdminUsersScreen extends StatefulWidget {
  final UserService userService;

  const AdminUsersScreen({super.key, required this.userService});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.userService.fetchRegisteredUsers();
  }

  void _onSearch(String query) {
    widget.userService.fetchRegisteredUsers(query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'User Management',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 19),
        ),
      ),
      body: AnimatedBuilder(
        animation: widget.userService,
        builder: (context, _) {
          final users = widget.userService.registeredUsers;
          final total = users.length;
          final blockedCount = users.where((u) => u['isBlocked'] == true).length;
          final activeCount = total - blockedCount;

          return Column(
            children: [
              // Search & Stats Bar
              Container(
                padding: const EdgeInsets.all(16),
                color: context.tokens.surfaceVariant,
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search users by name or email...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearch('');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: context.tokens.surface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: context.tokens.surfaceBorder,
                          ),
                        ),
                      ),
                      onChanged: _onSearch,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatCard('Total Users', '$total', Theme.of(context).colorScheme.primary),
                        _buildStatCard('Active', '$activeCount', Colors.green),
                        _buildStatCard('Blocked', '$blockedCount', Theme.of(context).colorScheme.error),
                      ],
                    ),
                  ],
                ),
              ),

              // Users List
              Expanded(
                child: widget.userService.isLoadingUsers && users.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : users.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.people_outline, size: 56, color: context.tokens.onSurfaceDisabled),
                                  const SizedBox(height: 12),
                                  const Text('No users found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () async => widget.userService.fetchRegisteredUsers(_searchController.text),
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: users.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final user = users[index];
                                final id = user['id'] ?? '';
                                final name = user['displayName'] ?? 'User';
                                final email = user['email'] ?? '';
                                final photoUrl = user['photoUrl'];
                                final isBlocked = user['isBlocked'] == true;
                                final role = user['role'] ?? 'USER';
                                final lastLogin = user['lastLoginAt'] != null
                                    ? DateFormat.yMMMd().format(DateTime.tryParse(user['lastLoginAt'].toString()) ?? DateTime.now())
                                    : 'Recently';

                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: context.tokens.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isBlocked
                                          ? Theme.of(context).colorScheme.error.withValues(alpha: 0.3)
                                          : context.tokens.surfaceBorder,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                                        backgroundColor: isBlocked
                                            ? Theme.of(context).colorScheme.errorContainer
                                            : Theme.of(context).colorScheme.primaryContainer,
                                        child: photoUrl == null
                                            ? Text(
                                                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: isBlocked
                                                      ? Theme.of(context).colorScheme.onErrorContainer
                                                      : Theme.of(context).colorScheme.onPrimaryContainer,
                                                ),
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    name,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                if (role == 'ADMIN')
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      'ADMIN',
                                                      style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 9, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              email,
                                              style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 12),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Active: $lastLogin',
                                              style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Block / Unblock Toggle Button
                                      if (role != 'ADMIN')
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isBlocked ? Colors.green.shade600 : Theme.of(context).colorScheme.error,
                                            foregroundColor: isBlocked ? Colors.white : Theme.of(context).colorScheme.onError,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            elevation: 0,
                                          ),
                                          onPressed: () => _confirmToggleBlock(context, id, name, isBlocked),
                                          child: Text(
                                            isBlocked ? 'Unblock' : 'Block',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: context.tokens.onSurfaceMuted)),
        ],
      ),
    );
  }

  void _confirmToggleBlock(BuildContext context, String userId, String name, bool currentlyBlocked) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(currentlyBlocked ? 'Unblock User?' : 'Block User?'),
        content: Text(
          currentlyBlocked
              ? 'Are you sure you want to unblock "$name"? They will regain access to the platform.'
              : 'Are you sure you want to block "$name"? They will be immediately suspended from the platform.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: currentlyBlocked ? Colors.green : Theme.of(context).colorScheme.error,
              foregroundColor: currentlyBlocked ? Colors.white : Theme.of(context).colorScheme.onError,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await widget.userService.toggleBlockUser(userId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? (currentlyBlocked ? 'User unblocked' : 'User blocked') : 'Action failed'),
                    backgroundColor: currentlyBlocked ? Colors.green : Theme.of(context).colorScheme.error,
                  ),
                );
              }
            },
            child: Text(currentlyBlocked ? 'Unblock' : 'Block'),
          ),
        ],
      ),
    );
  }
}
