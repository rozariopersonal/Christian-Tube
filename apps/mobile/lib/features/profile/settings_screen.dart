import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/theme/theme_service.dart';
import '../update/update_service.dart';
import 'widgets/app_share_dialog.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeService themeService;

  const SettingsScreen({super.key, required this.themeService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '1.28.0';

  final List<Map<String, String>> _languages = [
    {'code': 'en', 'name': 'English', 'native': 'English'},
    {'code': 'es', 'name': 'Spanish', 'native': 'Español'},
    {'code': 'fr', 'name': 'French', 'native': 'Français'},
    {'code': 'ta', 'name': 'Tamil', 'native': 'தமிழ்'},
    {'code': 'hi', 'name': 'Hindi', 'native': 'हिन्दी'},
    {'code': 'pt', 'name': 'Portuguese', 'native': 'Português'},
    {'code': 'de', 'name': 'German', 'native': 'Deutsch'},
  ];

  final List<String> _fonts = [
    'Inter',
    'Outfit',
    'Roboto',
    'Poppins',
    'Nunito',
    'Playfair Display',
  ];

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
        final currentColorTheme = widget.themeService.colorTheme;
        final currentFont = widget.themeService.fontFamily;
        final currentLang = widget.themeService.languageCode;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings & Customization'),
            actions: [
              IconButton(
                icon: const Icon(Icons.qr_code_2_rounded),
                tooltip: 'Share App & QR Code',
                onPressed: () => AppShareDialog.show(context, version: _version),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              // SECTION 1: COLOR THEMES
              _buildSectionHeader('Color Theme & Accent', theme.colorScheme.primary),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Choose an accent color for the entire interface:',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: AppColorTheme.values.map((colTheme) {
                          final isSelected = currentColorTheme == colTheme;
                          return InkWell(
                            onTap: () => widget.themeService.setColorTheme(colTheme),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? colTheme.color.withValues(alpha: 0.15)
                                    : (isDark ? Colors.grey.shade900 : Colors.grey.shade100),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? colTheme.color : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 9,
                                    backgroundColor: colTheme.color,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    colTheme.name,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 12,
                                      color: isSelected ? colTheme.color : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // SECTION 2: APPEARANCE / DARK MODE
              _buildSectionHeader('Theme Mode', theme.colorScheme.primary),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.settings_brightness),
                      title: const Text('System Default'),
                      subtitle: const Text('Match device light/dark mode'),
                      trailing: widget.themeService.themeMode == ThemeMode.system
                          ? Icon(Icons.check, color: theme.colorScheme.primary)
                          : null,
                      onTap: () => widget.themeService.setThemeMode(ThemeMode.system),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.dark_mode_outlined),
                      title: const Text('Dark Mode'),
                      subtitle: const Text('Sleek dark theme for low light'),
                      trailing: widget.themeService.themeMode == ThemeMode.dark
                          ? Icon(Icons.check, color: theme.colorScheme.primary)
                          : null,
                      onTap: () => widget.themeService.setThemeMode(ThemeMode.dark),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.light_mode_outlined),
                      title: const Text('Light Mode'),
                      subtitle: const Text('Bright and clean theme'),
                      trailing: widget.themeService.themeMode == ThemeMode.light
                          ? Icon(Icons.check, color: theme.colorScheme.primary)
                          : null,
                      onTap: () => widget.themeService.setThemeMode(ThemeMode.light),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.brightness_2_outlined),
                      title: const Text('Pure OLED Black'),
                      subtitle: const Text('Deep AMOLED black background in dark mode'),
                      value: widget.themeService.isAmoled,
                      activeThumbColor: theme.colorScheme.primary,
                      onChanged: (val) => widget.themeService.setAmoled(val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // SECTION 3: TYPOGRAPHY & FONT SELECTION
              _buildSectionHeader('Typography & Font Style', theme.colorScheme.primary),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select a font family for the app:',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _fonts.map((font) {
                          final isSelected = currentFont == font;
                          return ChoiceChip(
                            label: Text(font),
                            selected: isSelected,
                            selectedColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                            onSelected: (_) => widget.themeService.setFontFamily(font),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // SECTION 4: APP LANGUAGE
              _buildSectionHeader('App Language', theme.colorScheme.primary),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  children: _languages.map((lang) {
                    final isSelected = currentLang == lang['code'];
                    return ListTile(
                      title: Text(lang['name']!),
                      subtitle: Text(lang['native']!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      trailing: isSelected ? Icon(Icons.check_circle, color: theme.colorScheme.primary) : null,
                      onTap: () => widget.themeService.setLanguage(lang['code']!),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 12),

              // SECTION 5: SHARE & COMMUNITY
              _buildSectionHeader('Share & Community', theme.colorScheme.primary),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.qr_code_2_rounded, color: theme.colorScheme.primary),
                      title: const Text('Share App & QR Code', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Share download link or let friends scan your QR code'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => AppShareDialog.show(context, version: _version),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // SECTION 6: UPDATES & ABOUT
              _buildSectionHeader('About & Updates', theme.colorScheme.primary),
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
                          const SnackBar(content: Text('Checking for new releases...')),
                        );
                        final update = await UpdateService.checkForUpdate();
                        if (!context.mounted) return;
                        if (update != null) {
                          UpdateService.showUpdatePopup(context, update);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('You are on the latest version!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
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

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: color,
        ),
      ),
    );
  }
}
