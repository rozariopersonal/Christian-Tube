import 'package:flutter/material.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../bible/services/bible_background_service.dart';
import '../../bible/services/cross_reference_service.dart';
import '../../bible/services/study/bible_study_updater.dart';
import '../../books/models/book.dart';
import '../../books/services/book_service.dart';
import '../../dictionary/services/dictionary_download_manager.dart';
import '../../engines/scripture/models/bible_version_meta.dart';
import '../../engines/scripture/services/bible_download_manager.dart';
import '../../engines/scripture/widgets/bible_version_info_sheet.dart';

/// Single unified screen managing all offline downloads for Christian Tube:
/// Bibles, Cross-References, Dictionaries, Books, and Verse Commentaries.
class DownloadsManagerScreen extends StatefulWidget {
  final int initialTab;

  const DownloadsManagerScreen({
    super.key,
    this.initialTab = 0,
  });

  @override
  State<DownloadsManagerScreen> createState() => _DownloadsManagerScreenState();
}

class _DownloadsManagerScreenState extends State<DownloadsManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final BibleDownloadManager _bibleManager = BibleDownloadManager();
  final DictionaryDownloadManager _dictManager = DictionaryDownloadManager();
  final BookService _bookService = BookService.instance;
  final CrossReferenceService _crossRefService = CrossReferenceService();
  final BibleBackgroundService _bgService = BibleBackgroundService();

  // State caches
  bool _crossRefsInstalled = false;
  bool _bgInstalled = false;
  bool _booksInstalled = false;
  bool _studyDbInstalled = false;
  bool _isStudyDbDownloading = false;
  double _studyDbProgress = 0.0;
  Set<String> _installedBookIds = {};
  List<Book> _catalogBooks = [];

  // Filter & Search states
  String _bibleSearch = '';
  String _bibleLanguageFilter = 'All';

  String _dictFilter = 'All'; // All, Biblical, Indian, Global
  String _dictSearch = '';

  String _bookSearch = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );

    _bibleManager.addListener(_onStateUpdated);
    _dictManager.addListener(_onStateUpdated);
    _bookService.addListener(_onStateUpdated);
    _crossRefService.addListener(_onStateUpdated);
    _bgService.addListener(_onStateUpdated);

    _refreshAllStatus();
  }

  @override
  void dispose() {
    _bibleManager.removeListener(_onStateUpdated);
    _dictManager.removeListener(_onStateUpdated);
    _bookService.removeListener(_onStateUpdated);
    _crossRefService.removeListener(_onStateUpdated);
    _bgService.removeListener(_onStateUpdated);
    _tabController.dispose();
    super.dispose();
  }

  void _onStateUpdated() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshAllStatus() async {
    _bibleManager.refreshInstalledList();
    await _dictManager.initialize();
    await _bookService.initialize();

    final crossRefs = await _crossRefService.isInstalled();
    final bg = await _bgService.isInstalled();
    final books = await _bookService.isInstalled();
    final studyDb = await BibleStudyUpdater.isDownloaded();
    final installedBookIds = await _bookService.getInstalledBookIds();
    final catalog = await _bookService.getCatalogFromAsset();

    if (mounted) {
      setState(() {
        _crossRefsInstalled = crossRefs;
        _bgInstalled = bg;
        _booksInstalled = books;
        _studyDbInstalled = studyDb;
        _installedBookIds = installedBookIds;
        _catalogBooks = catalog;
      });
    }
  }

  // --- Quick Bundle Helper ---
  Future<void> _downloadEssentialBundle() async {
    // 1. Download default Bible (WEB or KJV or default)
    if (!_bibleManager.isInstalled(BibleDownloadManager.defaultVersionId)) {
      _bibleManager.downloadVersion(
          BibleDownloadManager.getMeta(BibleDownloadManager.defaultVersionId));
    }
    // 2. Download Easton's & Strong's
    if (!_dictManager.installedIds.contains('eastons')) {
      _dictManager.downloadDictionary('eastons');
    }
    if (!_dictManager.installedIds.contains('strongs')) {
      _dictManager.downloadDictionary('strongs');
    }
    // 3. Download Cross references & Backgrounds
    if (!_crossRefsInstalled && !_crossRefService.isDownloading) {
      _crossRefService.downloadAndInstall();
    }
    if (!_bgInstalled && !_bgService.isDownloading) {
      _bgService.downloadAndInstall();
    }
    // 4. Download Books & Commentary bundle
    if (!_booksInstalled && !_bookService.isDownloading) {
      _bookService.downloadAndInstall();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Starting download of Core Study Bundle…'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        elevation: 0,
        title: Text(
          'Offline Library & Downloads',
          style: TextStyle(
            color: tokens.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: tokens.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: tokens.onSurfaceMuted),
            tooltip: 'Refresh Status',
            onPressed: _refreshAllStatus,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: tokens.accent,
          labelColor: tokens.accent,
          unselectedLabelColor: tokens.onSurfaceMuted,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Bibles & Study Tools'),
            Tab(text: 'Dictionaries'),
            Tab(text: 'Books & Commentaries'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(tokens),
          _buildBiblesTab(tokens),
          _buildDictionariesTab(tokens),
          _buildBooksTab(tokens),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 1: OVERVIEW
  // ===========================================================================
  Widget _buildOverviewTab(AppTokens tokens) {
    final biblesCount = BibleDownloadManager.catalog
        .where((v) => _bibleManager.isInstalled(v.id))
        .length;
    final dictsCount = _dictManager.installedIds.length;
    final booksCount = _installedBookIds.length;

    return MaxWidthBox(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Storage & Offline Readiness Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [tokens.surface, tokens.surfaceElevated],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: tokens.surfaceBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: tokens.accent.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.offline_pin_rounded,
                        color: tokens.accent,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Offline Library Status',
                            style: TextStyle(
                              color: tokens.onSurface,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'All downloaded resources work 100% offline without internet connection.',
                            style: TextStyle(
                              color: tokens.onSurfaceMuted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Divider(color: tokens.surfaceBorder, height: 1),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    _buildStatChip(
                      icon: Icons.menu_book_rounded,
                      label: '$biblesCount Bibles',
                      isReady: biblesCount > 0,
                      tokens: tokens,
                      onTap: () => _tabController.animateTo(1),
                    ),
                    _buildStatChip(
                      icon: Icons.spellcheck_rounded,
                      label: '$dictsCount Dictionaries',
                      isReady: dictsCount > 0,
                      tokens: tokens,
                      onTap: () => _tabController.animateTo(2),
                    ),
                    _buildStatChip(
                      icon: Icons.library_books_rounded,
                      label: booksCount > 0
                          ? '$booksCount Books & Commentaries'
                          : 'Books & Commentaries',
                      isReady: booksCount > 0 || _booksInstalled,
                      tokens: tokens,
                      onTap: () => _tabController.animateTo(3),
                    ),
                    _buildStatChip(
                      icon: Icons.alt_route_rounded,
                      label: 'Cross-References',
                      isReady: _crossRefsInstalled,
                      tokens: tokens,
                      onTap: () => _tabController.animateTo(1),
                    ),
                    _buildStatChip(
                      icon: Icons.history_edu_rounded,
                      label: 'Cultural Backgrounds',
                      isReady: _bgInstalled,
                      tokens: tokens,
                      onTap: () => _tabController.animateTo(1),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. Core Study Bundle Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: tokens.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tokens.surfaceBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.stars_rounded, color: tokens.accent, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Core Study Essentials Bundle',
                        style: TextStyle(
                          color: tokens.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 15.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Installs the recommended foundational package: Default Bible, Easton\'s 1897 Bible Dictionary, Strong\'s Concordance, 344,000+ Cross-References, and Zac Poonen Books & Verse Commentaries (~11 MB total).',
                  style: TextStyle(
                    color: tokens.onSurfaceMuted,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _downloadEssentialBundle,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Download Core Study Bundle'),
                    style: FilledButton.styleFrom(
                      backgroundColor: tokens.accent,
                      foregroundColor: tokens.background,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 3. Quick Navigation Tiles
          _buildNavTile(
            title: 'Bible Translations & Study Tools',
            subtitle:
                'English, Indian Languages (Tamil, Malayalam, Telugu, Kannada, Hindi), European translations, Cross-References & Background notes.',
            icon: Icons.menu_book_rounded,
            badge: '$biblesCount installed',
            tokens: tokens,
            onTap: () => _tabController.animateTo(1),
          ),
          const SizedBox(height: 12),
          _buildNavTile(
            title: 'Offline Dictionaries (13 Available)',
            subtitle:
                'Strong\'s Greek/Hebrew, Easton\'s Bible Dictionary, Indian language dictionaries (Tamil, Malayalam, Telugu, Kannada, Hindi) & global languages.',
            icon: Icons.spellcheck_rounded,
            badge: '$dictsCount installed',
            tokens: tokens,
            onTap: () => _tabController.animateTo(2),
          ),
          const SizedBox(height: 12),
          _buildNavTile(
            title: 'Books & Zac Poonen Verse Commentaries',
            subtitle:
                'Download all 34 books for offline pageless & dual-page reading, plus unlock verse-by-verse commentary expositions in Bible study.',
            icon: Icons.library_books_rounded,
            badge: _booksInstalled ? 'Complete Library' : '$booksCount books',
            tokens: tokens,
            onTap: () => _tabController.animateTo(3),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required bool isReady,
    required AppTokens tokens,
    required VoidCallback onTap,
  }) {
    final color = isReady ? tokens.accent : tokens.onSurfaceMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isReady ? Icons.check_circle : icon,
              size: 15,
              color: color,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required String badge,
    required AppTokens tokens,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.surfaceBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tokens.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: tokens.accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: tokens.onSurface,
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: tokens.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: tokens.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: tokens.onSurfaceMuted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: tokens.onSurfaceMuted, size: 20),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 2: BIBLES & STUDY TOOLS
  // ===========================================================================
  Widget _buildBiblesTab(AppTokens tokens) {
    var bibles = BibleDownloadManager.catalog.toList();

    if (_bibleLanguageFilter != 'All') {
      bibles = bibles.where((b) {
        if (_bibleLanguageFilter == 'English') {
          return b.language.toLowerCase() == 'english';
        }
        if (_bibleLanguageFilter == 'Indian') {
          return [
            'tamil',
            'malayalam',
            'telugu',
            'kannada',
            'hindi'
          ].contains(b.language.toLowerCase());
        }
        if (_bibleLanguageFilter == 'European') {
          return ![
            'english',
            'tamil',
            'malayalam',
            'telugu',
            'kannada',
            'hindi'
          ].contains(b.language.toLowerCase());
        }
        return true;
      }).toList();
    }

    if (_bibleSearch.trim().isNotEmpty) {
      final q = _bibleSearch.trim().toLowerCase();
      bibles = bibles
          .where((b) =>
              b.name.toLowerCase().contains(q) ||
              b.id.toLowerCase().contains(q) ||
              b.language.toLowerCase().contains(q))
          .toList();
    }

    return MaxWidthBox(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Study Datasets Section
          Text(
            'STUDY DATASETS',
            style: TextStyle(
              color: tokens.onSurfaceMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          _buildStudyDatasetCard(
            title: 'Treasury of Scripture Knowledge Cross-References',
            subtitle:
                '344,000+ bidirectional Bible cross-references. Translation-independent.',
            sizeDisplay: '2.1 MB',
            isInstalled: _crossRefsInstalled,
            isDownloading: _crossRefService.isDownloading,
            progress: _crossRefService.progress,
            onDownload: () => _crossRefService.downloadAndInstall(),
            tokens: tokens,
          ),
          const SizedBox(height: 10),
          _buildStudyDatasetCard(
            title: 'Words & Theological Concepts (Tamil OV)',
            subtitle: 'Study dataset for deep dive into Hebrew/Greek word meanings and concepts.',
            sizeDisplay: '3.5 MB',
            isInstalled: _studyDbInstalled,
            isDownloading: _isStudyDbDownloading,
            progress: _studyDbProgress,
            onDownload: () async {
              setState(() {
                _isStudyDbDownloading = true;
                _studyDbProgress = 0.0;
              });
              try {
                await BibleStudyUpdater.downloadUpdate((progress) {
                  if (mounted) {
                    setState(() {
                      _studyDbProgress = progress;
                    });
                  }
                });
                if (mounted) {
                  setState(() {
                    _isStudyDbDownloading = false;
                    _studyDbInstalled = true;
                  });
                }
              } catch (e) {
                if (mounted) {
                  setState(() {
                    _isStudyDbDownloading = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Download failed: $e')),
                  );
                }
              }
            },
            tokens: tokens,
          ),
          const SizedBox(height: 10),
          _buildStudyDatasetCard(
            title: 'Historical & Cultural Background Notes',
            subtitle:
                'unfoldingWord open translation notes covering ancient Near Eastern customs, archaeology, and idioms.',
            sizeDisplay: '1.8 MB',
            isInstalled: _bgInstalled,
            isDownloading: _bgService.isDownloading,
            progress: _bgService.progress,
            onDownload: () => _bgService.downloadAndInstall(),
            tokens: tokens,
          ),
          const SizedBox(height: 24),

          // 2. Translations Section Header & Filters
          Row(
            children: [
              Text(
                'BIBLE TRANSLATIONS',
                style: TextStyle(
                  color: tokens.onSurfaceMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                '${bibles.length} Available',
                style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Search Field
          TextField(
            onChanged: (val) => setState(() => _bibleSearch = val),
            style: TextStyle(color: tokens.onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search translations, language, abbreviation…',
              hintStyle: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
              prefixIcon: Icon(Icons.search, color: tokens.onSurfaceMuted, size: 20),
              isDense: true,
              filled: true,
              fillColor: tokens.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tokens.surfaceBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tokens.surfaceBorder),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Language Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final opt in ['All', 'English', 'Indian', 'European'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(opt),
                      selected: _bibleLanguageFilter == opt,
                      onSelected: (_) =>
                          setState(() => _bibleLanguageFilter = opt),
                      selectedColor: tokens.accent.withValues(alpha: 0.2),
                      checkmarkColor: tokens.accent,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: _bibleLanguageFilter == opt
                            ? tokens.accent
                            : tokens.onSurfaceMuted,
                        fontWeight: _bibleLanguageFilter == opt
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Bible List
          for (final bible in bibles) ...[
            _buildBibleItem(bible, tokens),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildStudyDatasetCard({
    required String title,
    required String subtitle,
    required String sizeDisplay,
    required bool isInstalled,
    required bool isDownloading,
    required double progress,
    required VoidCallback onDownload,
    required AppTokens tokens,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isInstalled
                      ? tokens.accent.withValues(alpha: 0.15)
                      : tokens.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isInstalled ? Icons.check_circle : Icons.dataset_rounded,
                  color: isInstalled ? tokens.accent : tokens.onSurfaceMuted,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: tokens.onSurfaceMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Size: $sizeDisplay',
                      style: TextStyle(
                        color: tokens.onSurfaceDisabled,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isInstalled)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Installed',
                    style: TextStyle(
                      color: tokens.accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                )
              else if (isDownloading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else
                FilledButton.tonal(
                  onPressed: onDownload,
                  child: const Text('Download'),
                ),
            ],
          ),
          if (isDownloading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              color: tokens.accent,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBibleItem(BibleVersionMeta bible, AppTokens tokens) {
    final isInstalled = _bibleManager.isInstalled(bible.id);
    final isDownloading = _bibleManager.isDownloading(bible.id);
    final progress = _bibleManager.getProgress(bible.id);
    final isDefault = bible.id == BibleDownloadManager.defaultVersionId;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            bible.name,
                            style: TextStyle(
                              color: tokens.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        if (isDefault) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: tokens.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'DEFAULT',
                              style: TextStyle(
                                color: tokens.accent,
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${bible.language} • ${bible.id} • ${bible.sizeDisplay}',
                      style: TextStyle(
                        color: tokens.onSurfaceMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.info_outline,
                    color: tokens.onSurfaceMuted, size: 20),
                tooltip: 'Version Details & License',
                onPressed: () => BibleVersionInfoSheet.show(context, bible),
              ),
              if (isInstalled)
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: tokens.onSurfaceMuted, size: 20),
                  tooltip: 'Delete Download',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('Delete ${bible.name}?'),
                        content: const Text(
                            'This Bible translation will be removed from your device. You can download it again at any time.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _bibleManager.removeVersion(bible.id);
                    }
                  },
                )
              else if (isDownloading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else
                FilledButton.tonal(
                  onPressed: () => _bibleManager.downloadVersion(bible),
                  child: const Text('Download'),
                ),
            ],
          ),
          if (isDownloading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              color: tokens.accent,
            ),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 3: DICTIONARIES
  // ===========================================================================
  Widget _buildDictionariesTab(AppTokens tokens) {
    var dicts = DictionaryDownloadManager.catalog.toList();

    if (_dictFilter == 'Biblical') {
      dicts = dicts.where((d) => d.isBiblical).toList();
    } else if (_dictFilter == 'Indian') {
      dicts = dicts
          .where((d) => ['ta', 'ml', 'te', 'kn', 'hi'].contains(d.id))
          .toList();
    } else if (_dictFilter == 'Global') {
      dicts = dicts
          .where((d) =>
              !d.isBiblical &&
              !['ta', 'ml', 'te', 'kn', 'hi'].contains(d.id))
          .toList();
    }

    if (_dictSearch.trim().isNotEmpty) {
      final q = _dictSearch.trim().toLowerCase();
      dicts = dicts
          .where((d) =>
              d.name.toLowerCase().contains(q) ||
              d.language.toLowerCase().contains(q) ||
              d.description.toLowerCase().contains(q))
          .toList();
    }

    return MaxWidthBox(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Banner explaining dictionary lookup
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tokens.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tokens.surfaceBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.spellcheck_rounded, color: tokens.accent, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Installed dictionaries power instant "Define" popovers in both the Bible Reader and Book Reader without internet.',
                    style: TextStyle(
                      color: tokens.onSurface,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Search Field
          TextField(
            onChanged: (val) => setState(() => _dictSearch = val),
            style: TextStyle(color: tokens.onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search dictionaries by language or name…',
              hintStyle: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
              prefixIcon: Icon(Icons.search, color: tokens.onSurfaceMuted, size: 20),
              isDense: true,
              filled: true,
              fillColor: tokens.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tokens.surfaceBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tokens.surfaceBorder),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final opt in ['All', 'Biblical', 'Indian', 'Global'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(opt),
                      selected: _dictFilter == opt,
                      onSelected: (_) => setState(() => _dictFilter = opt),
                      selectedColor: tokens.accent.withValues(alpha: 0.2),
                      checkmarkColor: tokens.accent,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: _dictFilter == opt
                            ? tokens.accent
                            : tokens.onSurfaceMuted,
                        fontWeight: _dictFilter == opt
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Dictionary Items
          for (final dict in dicts) ...[
            _buildDictionaryItem(dict, tokens),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildDictionaryItem(DictionaryMeta dict, AppTokens tokens) {
    final isInstalled = _dictManager.installedIds.contains(dict.id);
    final isDownloading = _dictManager.isDownloading(dict.id);
    final progress = _dictManager.getProgress(dict.id);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            dict.name,
                            style: TextStyle(
                              color: tokens.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        if (dict.isBiblical) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: tokens.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'BIBLICAL',
                              style: TextStyle(
                                color: tokens.accent,
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${dict.language} • ${dict.sizeDisplay}',
                      style: TextStyle(
                        color: tokens.onSurfaceMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dict.description,
                      style: TextStyle(
                        color: tokens.onSurfaceMuted,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (isInstalled)
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: tokens.onSurfaceMuted, size: 20),
                  tooltip: 'Delete Dictionary',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('Delete ${dict.name}?'),
                        content: const Text(
                            'This dictionary will be removed from your device. You can download it again at any time.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _dictManager.deleteDictionary(dict.id);
                    }
                  },
                )
              else if (isDownloading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else
                FilledButton.tonal(
                  onPressed: () => _dictManager.downloadDictionary(dict.id),
                  child: const Text('Download'),
                ),
            ],
          ),
          if (isDownloading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              color: tokens.accent,
            ),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 4: BOOKS & COMMENTARIES
  // ===========================================================================
  Widget _buildBooksTab(AppTokens tokens) {
    var books = _catalogBooks;
    if (_bookSearch.trim().isNotEmpty) {
      final q = _bookSearch.trim().toLowerCase();
      books = books
          .where((b) =>
              b.title.toLowerCase().contains(q) ||
              b.author.toLowerCase().contains(q) ||
              b.subject.toLowerCase().contains(q))
          .toList();
    }

    final isDownloadingAll = _bookService.isDownloading;
    final progressAll = _bookService.downloadProgress;

    return MaxWidthBox(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Big Explanatory Commentary & Books Bundle Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [tokens.surface, tokens.surfaceElevated],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tokens.surfaceBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: tokens.accent.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.auto_stories_rounded,
                        color: tokens.accent,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Complete Books & Commentaries',
                            style: TextStyle(
                              color: tokens.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Zac Poonen Library (34 Books • ~2.7 MB)',
                            style: TextStyle(
                              color: tokens.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Downloading this single compact package unlocks all 34 books for pageless mobile & dual-page tablet reading, AND links thousands of verse-by-verse commentary expositions directly into the Bible Study screen.',
                  style: TextStyle(
                    color: tokens.onSurfaceMuted,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                if (_booksInstalled)
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: tokens.accent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Full 34-Book Library & Commentaries Active',
                          style: TextStyle(
                            color: tokens.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => _bookService.downloadAndInstall(),
                        child: const Text('Re-sync'),
                      ),
                    ],
                  )
                else if (isDownloadingAll) ...[
                  LinearProgressIndicator(
                    value: progressAll > 0 ? progressAll : null,
                    color: tokens.accent,
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Downloading library: ${(progressAll * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: tokens.onSurfaceMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ] else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _bookService.downloadAndInstall(),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text(
                          'Download Complete Books & Commentaries (2.7 MB)'),
                      style: FilledButton.styleFrom(
                        backgroundColor: tokens.accent,
                        foregroundColor: tokens.background,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Search Field
          TextField(
            onChanged: (val) => setState(() => _bookSearch = val),
            style: TextStyle(color: tokens.onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search books by title, author, or topic…',
              hintStyle: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
              prefixIcon: Icon(Icons.search, color: tokens.onSurfaceMuted, size: 20),
              isDense: true,
              filled: true,
              fillColor: tokens.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tokens.surfaceBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tokens.surfaceBorder),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Individual Books
          Row(
            children: [
              Text(
                'INDIVIDUAL BOOKS (${books.length})',
                style: TextStyle(
                  color: tokens.onSurfaceMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                '${_installedBookIds.length} Installed',
                style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 10),

          for (final book in books) ...[
            _buildBookItem(book, tokens),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildBookItem(Book book, AppTokens tokens) {
    final isInstalled =
        _installedBookIds.contains(book.id) || _booksInstalled;
    final isDownloading = _bookService.isBookDownloading(book.id);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isInstalled
                  ? tokens.accent.withValues(alpha: 0.15)
                  : tokens.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isInstalled ? Icons.check_circle : Icons.book_rounded,
              color: isInstalled ? tokens.accent : tokens.onSurfaceMuted,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${book.author} • ${book.totalPages} pages',
                  style: TextStyle(
                    color: tokens.onSurfaceMuted,
                    fontSize: 12,
                  ),
                ),
                if (book.downloadSizeFormatted.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Size: ${book.downloadSizeFormatted}',
                    style: TextStyle(
                      color: tokens.onSurfaceDisabled,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (isInstalled)
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: tokens.onSurfaceMuted, size: 20),
              tooltip: 'Delete Book Download',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('Remove ${book.title}?'),
                    content: const Text(
                        'This book will be removed from offline storage. Your reading progress and highlights will be preserved.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _bookService.removeBookDownload(book.id);
                  _refreshAllStatus();
                }
              },
            )
          else if (isDownloading)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            FilledButton.tonal(
              onPressed: () async {
                await _bookService.downloadSingleBook(book.id);
                _refreshAllStatus();
              },
              child: const Text('Download'),
            ),
        ],
      ),
    );
  }
}
