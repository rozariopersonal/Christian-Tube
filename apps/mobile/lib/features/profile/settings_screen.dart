import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/config/app_config.dart';
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
                UpdateService.showUpdatePopup(context, update);
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('You are on the latest version!'),
                    backgroundColor: Color(0xFF10B981),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text('${AppConfig.appName} Open Source'),
            subtitle: Text('https://github.com/${AppConfig.releasesRepo}'),
          ),
        ],
      ),
    );
  }
}
