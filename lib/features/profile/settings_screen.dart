import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/theme/theme_service.dart';
import '../update/update_service.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeService themeService;

  const SettingsScreen({super.key, required this.themeService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '1.28.0';

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() => _version = info.version);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const ListTile(
            title: Text('Appearance', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Dark Mode'),
            trailing: Switch(
              value: widget.themeService.isDarkMode,
              onChanged: (val) {
                widget.themeService.setThemeMode(val ? ThemeMode.dark : ThemeMode.light);
              },
            ),
          ),
          const Divider(),
          const ListTile(
            title: Text('About & Updates', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          ),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('Check for Updates'),
            subtitle: Text('Current version: v$_version'),
            onTap: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Checking for latest version...')),
              );
              final update = await UpdateService.checkForUpdate();
              if (update != null && mounted) {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('Update to ${update['latestVersion']}'),
                    content: Text(update['releaseNotes'] ?? 'A new update is available.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          UpdateService.downloadAndInstallApk(
                            downloadUrl: update['downloadUrl'],
                            onProgress: (p) {},
                            onComplete: () {},
                            onError: (e) {},
                          );
                        },
                        child: const Text('Install Now'),
                      ),
                    ],
                  ),
                );
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('You are on the latest version!')),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('ChristianTube Open Source'),
            subtitle: const Text('https://github.com/rozariopersonal/Christian-Tube-Releases'),
          ),
        ],
      ),
    );
  }
}
