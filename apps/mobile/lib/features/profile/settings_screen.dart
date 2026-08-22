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
      if (mounted) {
        setState(() => _version = info.version);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: widget.themeService,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Appearance',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      title: const Text('System Default'),
                      subtitle: const Text('Match your device theme settings'),
                      secondary: const Icon(Icons.settings_brightness),
                      value: ThemeMode.system,
                      groupValue: widget.themeService.themeMode,
                      onChanged: (mode) {
                        if (mode != null) widget.themeService.setThemeMode(mode);
                      },
                    ),
                    const Divider(height: 1),
                    RadioListTile<ThemeMode>(
                      title: const Text('Dark Mode'),
                      subtitle: const Text('Sleek dark theme for low light'),
                      secondary: const Icon(Icons.dark_mode_outlined),
                      value: ThemeMode.dark,
                      groupValue: widget.themeService.themeMode,
                      onChanged: (mode) {
                        if (mode != null) widget.themeService.setThemeMode(mode);
                      },
                    ),
                    const Divider(height: 1),
                    RadioListTile<ThemeMode>(
                      title: const Text('Light Mode'),
                      subtitle: const Text('Bright and clean theme'),
                      secondary: const Icon(Icons.light_mode_outlined),
                      value: ThemeMode.light,
                      groupValue: widget.themeService.themeMode,
                      onChanged: (mode) {
                        if (mode != null) widget.themeService.setThemeMode(mode);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'About & Updates',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.system_update_rounded),
                      title: const Text('Check for Updates'),
                      subtitle: Text('Current version: v$_version'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Checking for latest version...')),
                        );
                        final update = await UpdateService.checkForUpdate();
                        if (update != null && context.mounted) {
                          UpdateService.showUpdatePopup(context, update);
                        } else if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('You are already on the latest version!'),
                              backgroundColor: Color(0xFF10B981),
                            ),
                          );
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text('${AppConfig.appName} Open Source'),
                      subtitle: Text('https://github.com/${AppConfig.releasesRepo}'),
                      trailing: const Icon(Icons.open_in_new, size: 16),
                      onTap: () {
                        UpdateService.openInBrowser('https://github.com/${AppConfig.releasesRepo}');
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
