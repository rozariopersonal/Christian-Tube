import 'package:flutter/material.dart';
import '../../../core/layout/content_width.dart';
import '../../books/screens/books_catalog_screen.dart';
import '../../engines/scripture/services/bible_download_manager.dart';
import '../../engines/scripture/widgets/bible_version_picker_modal.dart';
import '../models/bible_version.dart';
import '../controllers/bible_controller.dart';

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
    return AppBar(
      title: Text(
        controller.selectedVersion?.name ?? 'Bible',
        style: const TextStyle(fontWeight: FontWeight.bold),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      actions: [
        if (s.selectedVersion != null)
          _VersionPicker(
            selectedVersion: s.selectedVersion!,
            versions: s.versions,
            onSelect: controller.selectVersion,
            onManage: onPushManager,
          ),
        IconButton(
          tooltip: 'Search Bible',
          icon: const Icon(Icons.search),
          onPressed: onShowSearch,
        ),
        IconButton(
          tooltip: 'Appearance Settings',
          icon: const Text('Aa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          onPressed: onShowReadingSettings,
        ),
        _MoreMenu(
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
    required this.onSelect,
    required this.onManage,
  });

  final BibleVersion selectedVersion;
  final List<BibleVersion> versions;
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
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openPicker(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                selectedVersion.shortname,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 2),
                child: Icon(Icons.arrow_drop_down, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.onDownloads,
    required this.onBooks,
    required this.onBookmarks,
    required this.onSettings,
  });

  final VoidCallback onDownloads;
  final VoidCallback onBooks;
  final VoidCallback onBookmarks;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      onSelected: (value) {
        switch (value) {
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
        const PopupMenuItem(
          value: 'downloads',
          child: Row(
            children: [
              Icon(Icons.download_for_offline_rounded, size: 18),
              SizedBox(width: 10),
              Text('Offline Library & Downloads'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'books',
          child: Row(
            children: [
              Icon(Icons.library_books_rounded, size: 18),
              SizedBox(width: 10),
              Text('Books Library'),
            ],
          ),
        ),
        const PopupMenuItem(value: 'bookmarks', child: Text('Bookmarks')),
        const PopupMenuItem(value: 'settings', child: Text('Reading settings')),
      ],
    );
  }
}
