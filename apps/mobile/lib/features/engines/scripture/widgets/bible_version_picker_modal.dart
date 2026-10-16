import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/bible_version_meta.dart';
import '../services/bible_download_manager.dart';
import '../services/bible_recent_versions_service.dart';

class BibleVersionPickerModal extends StatefulWidget {
  final String activeVersionId;
  final ValueChanged<String> onSelectVersion;
  final VoidCallback onOpenManager;

  /// Optional override for the set of installed/available IDs to display.
  /// When null, the modal uses [BibleDownloadManager.installedIds] or the
  /// full catalogue if none are explicitly installed.
  final Set<String>? installedIdsOverride;

  const BibleVersionPickerModal({
    super.key,
    required this.activeVersionId,
    required this.onSelectVersion,
    required this.onOpenManager,
    this.installedIdsOverride,
  });

  @override
  State<BibleVersionPickerModal> createState() =>
      _BibleVersionPickerModalState();
}

class _BibleVersionPickerModalState extends State<BibleVersionPickerModal> {
  final TextEditingController _searchController = TextEditingController();
  final BibleRecentVersionsService _recentService =
      BibleRecentVersionsService();

  List<String> _recentVersionIds = [];
  List<String> _frequentVersionIds = [];
  Map<String, int> _frequencyMap = {};
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query != _searchQuery) {
      setState(() {
        _searchQuery = query;
      });
    }
  }

  Future<void> _loadHistory() async {
    final recents = await _recentService.getRecentVersions();
    final frequent = await _recentService.getFrequentlyUsedVersions();
    final freqMap = await _recentService.getFrequencyMap();

    // Preseed active version if not yet present
    final active = widget.activeVersionId.trim();
    if (active.isNotEmpty) {
      if (!recents.any((id) => id.toUpperCase() == active.toUpperCase())) {
        recents.insert(0, active);
      }
      if (!frequent.any((id) => id.toUpperCase() == active.toUpperCase())) {
        frequent.insert(0, active);
      }
    }

    if (mounted) {
      setState(() {
        _recentVersionIds = recents;
        _frequentVersionIds = frequent;
        _frequencyMap = freqMap;
        _isLoading = false;
      });
    }
  }

  void _handleSelectVersion(String versionId) async {
    await _recentService.recordRecentVersion(versionId);
    if (!mounted) return;
    widget.onSelectVersion(versionId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final downloadManager = BibleDownloadManager();

    // Determine available versions
    final effectiveIds = widget.installedIdsOverride ??
        (downloadManager.installedIds.isEmpty
            ? BibleDownloadManager.catalog.map((v) => v.id).toSet()
            : downloadManager.installedIds);

    // Map catalog by uppercase ID for case-insensitive lookup
    final catalogMap = <String, BibleVersionMeta>{
      for (final v in BibleDownloadManager.catalog) v.id.toUpperCase(): v,
    };

    final List<BibleVersionMeta> allVersions = [];
    final seenIds = <String>{};
    for (final id in effectiveIds) {
      final upper = id.toUpperCase();
      if (seenIds.add(upper)) {
        final meta = catalogMap[upper] ?? BibleDownloadManager.getMeta(id);
        allVersions.add(meta);
      }
    }

    // Apply quick search filtering
    final query = _searchQuery.toLowerCase();
    final filteredVersions = query.isEmpty
        ? allVersions
        : allVersions.where((v) {
            return v.name.toLowerCase().contains(query) ||
                v.id.toLowerCase().contains(query) ||
                v.language.toLowerCase().contains(query);
          }).toList();

    // 1. Frequently Used Items (sorted descending by frequency count)
    final List<BibleVersionMeta> frequentItems = [];
    final seenFrequent = <String>{};
    for (final fId in _frequentVersionIds) {
      final upper = fId.toUpperCase();
      if (seenFrequent.contains(upper)) continue;

      final meta = allVersions.cast<BibleVersionMeta?>().firstWhere(
            (v) => v?.id.toUpperCase() == upper,
            orElse: () => null,
          );

      if (meta != null) {
        if (query.isNotEmpty) {
          final matches = meta.name.toLowerCase().contains(query) ||
              meta.id.toLowerCase().contains(query) ||
              meta.language.toLowerCase().contains(query);
          if (!matches) continue;
        }
        seenFrequent.add(upper);
        frequentItems.add(meta);
      }
    }

    // 2. Recently Used Items (in exact chronological order)
    final List<BibleVersionMeta> recentItems = [];
    final seenRecent = <String>{};
    for (final rId in _recentVersionIds) {
      final upper = rId.toUpperCase();
      if (seenRecent.contains(upper)) continue;

      final meta = allVersions.cast<BibleVersionMeta?>().firstWhere(
            (v) => v?.id.toUpperCase() == upper,
            orElse: () => null,
          );

      if (meta != null) {
        if (query.isNotEmpty) {
          final matches = meta.name.toLowerCase().contains(query) ||
              meta.id.toLowerCase().contains(query) ||
              meta.language.toLowerCase().contains(query);
          if (!matches) continue;
        }
        seenRecent.add(upper);
        recentItems.add(meta);
      }
    }

    // 3. Group remaining versions by language
    final Map<String, List<BibleVersionMeta>> groupedByLanguage = {};
    for (final meta in filteredVersions) {
      final lang =
          meta.language.trim().isNotEmpty ? meta.language.trim() : 'Other';
      groupedByLanguage.putIfAbsent(lang, () => []).add(meta);
    }

    // Sort versions within each language group
    for (final lang in groupedByLanguage.keys) {
      groupedByLanguage[lang]!.sort((a, b) => a.name.compareTo(b.name));
    }

    // Determine smart language order:
    // Active/recent languages first, English next, then alphabetical
    final activeLang = allVersions
        .cast<BibleVersionMeta?>()
        .firstWhere(
          (v) => v?.id.toUpperCase() == widget.activeVersionId.toUpperCase(),
          orElse: () => null,
        )
        ?.language;

    final sortedLanguages = groupedByLanguage.keys.toList()
      ..sort((a, b) {
        if (activeLang != null) {
          if (a.toLowerCase() == activeLang.toLowerCase()) return -1;
          if (b.toLowerCase() == activeLang.toLowerCase()) return 1;
        }
        if (a.toLowerCase() == 'english') return -1;
        if (b.toLowerCase() == 'english') return 1;
        return a.compareTo(b);
      });

    final screenHeight = MediaQuery.sizeOf(context).height;

    // Combined chips list for quick access row
    final quickChips = <BibleVersionMeta>[];
    final seenChips = <String>{};
    for (final item in [...frequentItems, ...recentItems]) {
      if (seenChips.add(item.id.toUpperCase())) {
        quickChips.add(item);
      }
    }

    final isDark = context.isDark;

    return MaxWidthBox(
      maxWidth: kSheetMaxWidth,
      child: Container(
        constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
        decoration: BoxDecoration(
          color: isDark
              ? tokens.surface.withValues(alpha: 0.94)
              : tokens.surface.withValues(alpha: 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: tokens.surfaceBorder, width: 1.0),
            left: BorderSide(color: tokens.surfaceBorder, width: 0.5),
            right: BorderSide(color: tokens.surfaceBorder, width: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: tokens.scrim.withValues(alpha: isDark ? 0.45 : 0.12),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag Handle
                  Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: tokens.onSurfaceDisabled.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            children: [
              Icon(Icons.menu_book_rounded, color: tokens.accent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Bible Translation',
                        style: TextStyle(
                          color: tokens.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: tokens.surfaceVariant,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: tokens.surfaceBorder),
                      ),
                      child: Text(
                        '${allVersions.length}',
                        style: TextStyle(
                          color: tokens.onSurfaceMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: tokens.onSurfaceMuted, size: 20),
                tooltip: 'Close',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Search Bar
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: tokens.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.surfaceBorder),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(Icons.search_rounded,
                    color: tokens.onSurfaceMuted, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(
                      color: tokens.onSurface,
                      fontSize: 13.5,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search translation, code, or language...',
                      hintStyle: TextStyle(
                        color: tokens.onSurfaceMuted,
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(
                        Icons.close_rounded,
                        color: tokens.onSurfaceMuted,
                        size: 16,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Quick Chips (when not actively searching)
          if (_searchQuery.isEmpty && quickChips.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: quickChips.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final meta = quickChips[index];
                    final isSelected = meta.id.toUpperCase() ==
                        widget.activeVersionId.toUpperCase();
                    return _QuickRecentChip(
                      meta: meta,
                      isSelected: isSelected,
                      onTap: () => _handleSelectVersion(meta.id),
                    );
                  },
                ),
              ),
            ),
          ],

          // Main List of Translations (Frequently Used on top + Recently Used + Grouped by Language)
          Flexible(
            child: filteredVersions.isEmpty &&
                    recentItems.isEmpty &&
                    frequentItems.isEmpty
                ? _buildEmptyState(tokens)
                : ListView(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      // 1. Frequently Used Section (on top!)
                      if (!_isLoading && frequentItems.isNotEmpty) ...[
                        _buildSectionHeader(
                          title: 'Frequently Used',
                          icon: Icons.trending_up_rounded,
                          count: frequentItems.length,
                          isAccent: true,
                          tokens: tokens,
                        ),
                        const SizedBox(height: 4),
                        ...frequentItems.map((meta) {
                          final isSelected = meta.id.toUpperCase() ==
                              widget.activeVersionId.toUpperCase();
                          final count =
                              _frequencyMap[meta.id.toUpperCase()] ?? 0;
                          return _buildVersionTile(
                            meta: meta,
                            isSelected: isSelected,
                            tokens: tokens,
                            frequencyCount: count,
                          );
                        }),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child:
                              Divider(color: tokens.surfaceBorder, height: 1),
                        ),
                      ],

                      // 2. Recently Used Section (in exact chronological order)
                      if (!_isLoading && recentItems.isNotEmpty) ...[
                        _buildSectionHeader(
                          title: 'Recently Used',
                          icon: Icons.history_rounded,
                          count: recentItems.length,
                          tokens: tokens,
                        ),
                        const SizedBox(height: 4),
                        ...recentItems.map((meta) {
                          final isSelected = meta.id.toUpperCase() ==
                              widget.activeVersionId.toUpperCase();
                          return _buildVersionTile(
                            meta: meta,
                            isSelected: isSelected,
                            tokens: tokens,
                          );
                        }),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child:
                              Divider(color: tokens.surfaceBorder, height: 1),
                        ),
                      ],

                      // 3. Language Groups
                      for (final lang in sortedLanguages) ...[
                        _buildSectionHeader(
                          title: lang,
                          icon: Icons.language_rounded,
                          count: groupedByLanguage[lang]!.length,
                          tokens: tokens,
                        ),
                        const SizedBox(height: 4),
                        ...groupedByLanguage[lang]!.map((meta) {
                          final isSelected = meta.id.toUpperCase() ==
                              widget.activeVersionId.toUpperCase();
                          return _buildVersionTile(
                            meta: meta,
                            isSelected: isSelected,
                            tokens: tokens,
                          );
                        }),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 12),

          // Manage & Download Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                widget.onOpenManager();
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Manage & Download More Translations'),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.onSurface,
                side: BorderSide(color: tokens.surfaceBorder),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
),
),
);
  }

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    required int count,
    required AppTokens tokens,
    bool isAccent = false,
  }) {
    final color = isAccent ? tokens.accent : tokens.onSurfaceMuted;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: isAccent
                  ? tokens.accent.withValues(alpha: 0.12)
                  : tokens.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionTile({
    required BibleVersionMeta meta,
    required bool isSelected,
    required AppTokens tokens,
    int? frequencyCount,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _handleSelectVersion(meta.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              // Shortname pill
              Container(
                width: 62,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? tokens.accent.withValues(alpha: 0.14)
                      : tokens.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? tokens.accent.withValues(alpha: 0.4)
                        : tokens.surfaceBorder,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  meta.id,
                  style: TextStyle(
                    color: isSelected ? tokens.accent : tokens.onSurface,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),

              // Title and details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.name,
                      style: TextStyle(
                        color: isSelected ? tokens.accent : tokens.onSurface,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${meta.language} • ${meta.sizeDisplay}',
                            style: TextStyle(
                              color: isSelected
                                  ? tokens.accent.withValues(alpha: 0.8)
                                  : tokens.onSurfaceMuted,
                              fontSize: 11.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (frequencyCount != null && frequencyCount > 1) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: tokens.accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$frequencyCount reads',
                              style: TextStyle(
                                color: tokens.accent,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Selection checkmark
              isSelected
                  ? Icon(
                      Icons.check_circle_rounded,
                      color: tokens.accent,
                      size: 20,
                    )
                  : Icon(
                      Icons.radio_button_unchecked,
                      color: tokens.onSurfaceDisabled,
                      size: 20,
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppTokens tokens) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 38, color: tokens.onSurfaceMuted),
            const SizedBox(height: 10),
            Text(
              'No translations found',
              style: TextStyle(
                color: tokens.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try searching with a different name or language code',
              style: TextStyle(
                color: tokens.onSurfaceMuted,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickRecentChip extends StatelessWidget {
  final BibleVersionMeta meta;
  final bool isSelected;
  final VoidCallback onTap;

  const _QuickRecentChip({
    required this.meta,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      label: 'Switch to ${meta.name}',
      child: Material(
        color: isSelected
            ? tokens.accent.withValues(alpha: 0.15)
            : tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? tokens.accent : tokens.surfaceBorder,
                width: isSelected ? 1.2 : 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  Icon(Icons.check, size: 12, color: tokens.accent),
                  const SizedBox(width: 4),
                ],
                Text(
                  meta.id,
                  style: TextStyle(
                    color: isSelected ? tokens.accent : tokens.onSurface,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  meta.language,
                  style: TextStyle(
                    color: isSelected
                        ? tokens.accent.withValues(alpha: 0.8)
                        : tokens.onSurfaceMuted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
