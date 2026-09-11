import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/layout/adaptivity.dart';
import '../../../core/layout/content_width.dart';
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
      actions: needsCollapsedActions(MediaQuery.sizeOf(context).width)
          ? [
              _MoreMenu(
                appearance: appearance,
                tokens: tokens,
                onSearch: onShowSearch,
                onAppearance: onShowReadingSettings,
                onDownloads: onPushManager,
                onBooks: () => context.push('/books'),
                onBookmarks: onOpenBookmarks,
                onSettings: onShowReadingSettings,
              ),
            ]
          : [
              IconButton(
                tooltip: 'Search Bible',
                icon: Icon(Icons.search, color: appearance.textColor(tokens)),
                onPressed: onShowSearch,
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
                onDownloads: onPushManager,
                onBooks: () => context.push('/books'),
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
              Icon(Icons.arrow_drop_down,
                  size: 20, color: appearance.mutedTextColor(tokens)),
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
    required this.onDownloads,
    required this.onBooks,
    required this.onBookmarks,
    required this.onSettings,
    this.onSearch,
    this.onAppearance,
  });

  final ReaderAppearance appearance;
  final AppTokens tokens;
  final VoidCallback onDownloads;
  final VoidCallback onBooks;
  final VoidCallback onBookmarks;
  final VoidCallback onSettings;
  final VoidCallback? onSearch;
  final VoidCallback? onAppearance;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: Icon(Icons.more_vert, color: appearance.textColor(tokens)),
      color: appearance.surface(tokens),
      onSelected: (value) {
        switch (value) {
          case 'search':
            onSearch?.call();
            break;
          case 'appearance':
            onAppearance?.call();
            break;
          case 'books':
            onBooks();
            break;
          case 'downloads':
            onDownloads();
            break;
          case 'bookmarks':
            onBookmarks();
            break;
          case 'settings':
            onSettings();
            break;
        }
      },
      itemBuilder: (ctx) => [
        if (onSearch != null)
          PopupMenuItem(
            value: 'search',
            child: Row(
              children: [
                Icon(Icons.search,
                    size: 18, color: appearance.textColor(tokens)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Search',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: appearance.textColor(tokens))),
                ),
              ],
            ),
          ),
        if (onAppearance != null)
          PopupMenuItem(
            value: 'appearance',
            child: Row(
              children: [
                Text(
                  'Aa',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: appearance.textColor(tokens),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Appearance',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: appearance.textColor(tokens))),
                ),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'downloads',
          child: Row(
            children: [
              Icon(Icons.download_for_offline_rounded,
                  size: 18, color: appearance.textColor(tokens)),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Offline Library & Downloads',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: appearance.textColor(tokens))),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'books',
          child: Row(
            children: [
              Icon(Icons.library_books_rounded,
                  size: 18, color: appearance.textColor(tokens)),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Books Library',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: appearance.textColor(tokens))),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'bookmarks',
          child: Text('Bookmarks',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: appearance.textColor(tokens))),
        ),
        PopupMenuItem(
          value: 'settings',
          child: Text('Reading settings',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: appearance.textColor(tokens))),
        ),
      ],
    );
  }
}
