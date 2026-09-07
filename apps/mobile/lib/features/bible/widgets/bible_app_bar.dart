import 'package:flutter/material.dart';
import '../../../core/layout/content_width.dart';
import '../../books/screens/books_catalog_screen.dart';
import '../../engines/scripture/services/bible_download_manager.dart';
import '../../engines/scripture/widgets/bible_version_picker_modal.dart';
import '../models/bible_version.dart';
import '../controllers/bible_controller.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/services/reader_appearance.dart';

class BibleAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BibleAppBar({
    super.key,
    required this.controller,
    required this.onShowSearch,
    required this.onShowReadingSettings,
    required this.onOpenBookmarks,
    required this.onPushManager,
  });

  final BibleController controller;
  final VoidCallback onShowSearch;
  final VoidCallback onShowReadingSettings;
  final VoidCallback onOpenBookmarks;
  final VoidCallback onPushManager;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    final tokens = context.tokens;
    final appearance = controller.appearance;
    final isDark = appearance.isDark(tokens);
    final width = MediaQuery.sizeOf(context).width;

    return AppBar(
      backgroundColor: appearance.background(tokens),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: appearance.textColor(tokens)),
      title: s.selectedVersion != null
          ? _VersionPicker(
              selectedVersion: s.selectedVersion!,
              versions: s.versions,
              appearance: appearance,
              tokens: tokens,
              onSelect: controller.selectVersion,
              onManage: onPushManager,
            )
          : Text(
              'Bible',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: appearance.textColor(tokens),
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
      actions: [
        IconButton(
          tooltip: 'Search Bible',
          icon: Icon(Icons.search, color: appearance.textColor(tokens)),
          onPressed: onShowSearch,
        ),
        if (width >= 360)
          IconButton(
            tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: appearance.textColor(tokens),
            ),
            onPressed: () => appearance.toggleDarkMode(tokens),
          ),
        IconButton(
          tooltip: 'Appearance Settings',
          icon: Text(
            'Aa',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: appearance.textColor(tokens),
            ),
          ),
          onPressed: onShowReadingSettings,
        ),
        _MoreMenu(
          appearance: appearance,
          tokens: tokens,
          isDark: isDark,
          onToggleDarkMode: () => appearance.toggleDarkMode(tokens),
          onDownloads: onPushManager,
          onBooks: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BooksCatalogScreen()),
          ),
          onBookmarks: onOpenBookmarks,
          onSettings: onShowReadingSettings,
        ),
      ],
    );
  }
}

class _VersionPicker extends StatelessWidget {
  const _VersionPicker({
    required this.selectedVersion,
    required this.versions,
    required this.appearance,
    required this.tokens,
    required this.onSelect,
    required this.onManage,
  });

  final BibleVersion selectedVersion;
  final List<BibleVersion> versions;
  final ReaderAppearance appearance;
  final AppTokens tokens;
  final ValueChanged<BibleVersion> onSelect;
  final VoidCallback onManage;

  void _openPicker(BuildContext context) {
    // Ensure the manager's cached ids are in sync with the controller's
    // installed versions before the modal builds.
    BibleDownloadManager().refreshInstalledList();

    final overrideIds = versions.map((v) => v.shortname).toSet();

    showAdaptiveBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => BibleVersionPickerModal(
        activeVersionId: selectedVersion.shortname,
        installedIdsOverride: overrideIds,
        onSelectVersion: (newVersionId) {
          final version = versions.firstWhere(
            (v) => v.shortname == newVersionId,
            orElse: () {
              final meta = BibleDownloadManager.getMeta(newVersionId);
              return BibleVersion(
                id: newVersionId,
                name: meta.name,
                shortname: newVersionId,
                description: meta.description,
                lang: meta.languageCode,
              );
            },
          );
          onSelect(version);
        },
        onOpenManager: onManage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Version',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openPicker(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  selectedVersion.shortname,
                  style: TextStyle(
                    color: appearance.textColor(tokens),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              Icon(Icons.arrow_drop_down, size: 20, color: appearance.mutedTextColor(tokens)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.appearance,
    required this.tokens,
    required this.isDark,
    required this.onToggleDarkMode,
    required this.onDownloads,
    required this.onBooks,
    required this.onBookmarks,
    required this.onSettings,
  });

  final ReaderAppearance appearance;
  final AppTokens tokens;
  final bool isDark;
  final VoidCallback onToggleDarkMode;
  final VoidCallback onDownloads;
  final VoidCallback onBooks;
  final VoidCallback onBookmarks;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: Icon(Icons.more_vert, color: appearance.textColor(tokens)),
      color: appearance.surface(tokens),
      onSelected: (value) {
        switch (value) {
          case 'toggle_dark':
            onToggleDarkMode();
          case 'books':
            onBooks();
          case 'downloads':
            onDownloads();
          case 'bookmarks':
            onBookmarks();
          case 'settings':
            onSettings();
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'toggle_dark',
          child: Row(
            children: [
              Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                size: 18,
                color: tokens.accent,
              ),
              const SizedBox(width: 10),
              Text(
                isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
                style: TextStyle(color: appearance.textColor(tokens)),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'downloads',
          child: Row(
            children: [
              Icon(Icons.download_for_offline_rounded, size: 18, color: appearance.textColor(tokens)),
              const SizedBox(width: 10),
              Text('Offline Library & Downloads', style: TextStyle(color: appearance.textColor(tokens))),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'books',
          child: Row(
            children: [
              Icon(Icons.library_books_rounded, size: 18, color: appearance.textColor(tokens)),
              const SizedBox(width: 10),
              Text('Books Library', style: TextStyle(color: appearance.textColor(tokens))),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'bookmarks',
          child: Text('Bookmarks', style: TextStyle(color: appearance.textColor(tokens))),
        ),
        PopupMenuItem(
          value: 'settings',
          child: Text('Reading settings', style: TextStyle(color: appearance.textColor(tokens))),
        ),
      ],
    );
  }
}
