import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
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
                        fillColor: isDark ? Colors.white10 : Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white12 : Colors.black12,
                          ),
                        ),
                      ),
                      onChanged: _onSearch,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatCard('Total Users', '$total', Colors.blue, isDark),
                        _buildStatCard('Active', '$activeCount', Colors.green, isDark),
                        _buildStatCard('Blocked', '$blockedCount', Colors.red, isDark),
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
                                  Icon(Icons.people_outline, size: 56, color: Colors.grey.shade400),
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
                                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isBlocked
                                          ? Colors.red.withValues(alpha: 0.3)
                                          : isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                                        backgroundColor: isBlocked ? Colors.red.shade100 : Colors.blue.shade100,
                                        child: photoUrl == null
                                            ? Text(
                                                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: isBlocked ? Colors.red : Colors.blue,
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
                                                      color: Colors.blue.withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: const Text(
                                                      'ADMIN',
                                                      style: TextStyle(color: Colors.blue, fontSize: 9, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              email,
                                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Active: $lastLogin',
                                              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Block / Unblock Toggle Button
                                      if (role != 'ADMIN')
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isBlocked ? Colors.green.shade600 : Colors.red.shade600,
                                            foregroundColor: Colors.white,
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

  Widget _buildStatCard(String label, String value, Color color, bool isDark) {
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
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
              backgroundColor: currentlyBlocked ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await widget.userService.toggleBlockUser(userId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? (currentlyBlocked ? 'User unblocked' : 'User blocked') : 'Action failed'),
                    backgroundColor: currentlyBlocked ? Colors.green : Colors.red,
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
