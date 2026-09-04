import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../books/screens/books_catalog_screen.dart';
import '../../engines/scripture/services/bible_download_manager.dart';
import '../models/bible_version.dart';
import '../controllers/bible_controller.dart';

class BibleAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BibleAppBar({
    super.key,
    required this.controller,
    required this.onShowBookChapterSelector,
    required this.onShowSearch,
    required this.onShowReadingSettings,
    required this.onOpenBookmarks,
    required this.onPushManager,
  });

  final BibleController controller;
  final VoidCallback onShowBookChapterSelector;
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
      title: Semantics(
        label: 'Book and chapter selector: '
            '${controller.displayBookName(controller.currentBook)} '
            '${controller.currentChapter}',
        button: true,
        child: GestureDetector(
          onTap: onShowBookChapterSelector,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  '${controller.displayBookName(controller.currentBook)} '
                  '${controller.currentChapter}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 2),
                child: Icon(Icons.arrow_drop_down, size: 20),
              ),
            ],
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Version',
      offset: const Offset(0, 40),
      onSelected: (value) {
        if (value == '__manage__') {
          onManage();
        } else {
          final version = versions.firstWhere(
            (v) => v.shortname == value,
            orElse: () {
              final meta = BibleDownloadManager.getMeta(value);
              return BibleVersion(
                id: value,
                name: meta.name,
                shortname: value,
                description: meta.description,
                lang: meta.languageCode,
              );
            },
          );
          onSelect(version);
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          enabled: false,
          child: Text(
            selectedVersion.shortname,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 13,
            ),
          ),
        ),
        const PopupMenuDivider(height: 1),
        ...versions.map((v) => PopupMenuItem(
              value: v.shortname,
              child: Row(
                children: [
                  Expanded(
                    child: Text(v.name, overflow: TextOverflow.ellipsis),
                  ),
                  if (v.shortname == selectedVersion.shortname)
                    Icon(Icons.check,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary),
                ],
              ),
            )),
        if (!kIsWeb) ...[
          const PopupMenuDivider(height: 1),
          const PopupMenuItem(
            value: '__manage__',
            child: Text('Manage translations…'),
          ),
        ],
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
