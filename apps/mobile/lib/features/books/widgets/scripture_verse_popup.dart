import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../../core/api/github_data_service.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../engines/scripture/models/bible_version_meta.dart';
import '../../engines/scripture/services/book_name_service.dart';
import '../../engines/scripture/services/bible_download_manager.dart';
import '../../engines/scripture/services/local_bible_service.dart';
import '../../bible/models/bible_reference.dart';
import '../../bible/services/bible_passage_navigator.dart';

/// Modal popover or dialog displaying verse text when an inline scripture
/// reference is tapped inside a book.
class ScriptureVersePopup extends StatefulWidget {
  final int bookNumber;
  final int chapter;
  final int startVerse;
  final int? endVerse;
  final String rawReference;

  /// Language of the surrounding text (e.g. the article's `lang`). When set,
  /// the popup prefers an installed Bible version in that language over the
  /// first-installed version so non-English readers see matching scripture.
  final String? languageCode;

  const ScriptureVersePopup({
    super.key,
    required this.bookNumber,
    required this.chapter,
    required this.startVerse,
    this.endVerse,
    required this.rawReference,
    this.languageCode,
  });

  static Future<void> show(
    BuildContext context, {
    required int bookNumber,
    required int chapter,
    required int startVerse,
    int? endVerse,
    required String rawReference,
    String? languageCode,
  }) async {
    final screen = ScreenClass.of(context);
    if (screen.isCompact) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ScriptureVersePopup(
          bookNumber: bookNumber,
          chapter: chapter,
          startVerse: startVerse,
          endVerse: endVerse,
          rawReference: rawReference,
          languageCode: languageCode,
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540, maxHeight: 480),
            child: ScriptureVersePopup(
              bookNumber: bookNumber,
              chapter: chapter,
              startVerse: startVerse,
              endVerse: endVerse,
              rawReference: rawReference,
              languageCode: languageCode,
            ),
          ),
        ),
      );
    }
  }

  @override
  State<ScriptureVersePopup> createState() => _ScriptureVersePopupState();
}

class _ScriptureVersePopupState extends State<ScriptureVersePopup> {
  final LocalBibleService _bibleService = LocalBibleService();
  final BookNameService _bookNames = BookNameService();
  List<String> _installedIds = const [];
  String? _verseText;
  String _versionName = '';
  String _bookName = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVerse();
  }

  Future<String?> _fetchVerseFromCdn({
    required String versionId,
    required int bookNumber,
    required int chapter,
    required int startVerse,
    int? endVerse,
  }) async {
    try {
      final urls = GitHubDataService.bibleChapterUrls(versionId, bookNumber, chapter);
      final dio = Dio(
        BaseOptions(
          headers: {'User-Agent': 'ChristianApp/${AppConfig.version}'},
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 12),
        ),
      );
      for (final url in urls) {
        try {
          final res = await dio.get<dynamic>(url, options: Options(responseType: ResponseType.json));
          if (res.statusCode == 200 && res.data != null) {
            final dynamic raw = res.data is String ? jsonDecode(res.data as String) : res.data;
            if (raw is List) {
              final end = endVerse ?? startVerse;
              final matching = <String>[];
              for (final item in raw) {
                if (item is Map) {
                  final vNum = (item['verse'] ?? item['verse_number'] ?? item['verseNumber']) as num?;
                  if (vNum != null && vNum >= startVerse && vNum <= end) {
                    final t = (item['text'] as String?)?.trim();
                    if (t != null && t.isNotEmpty) matching.add(t);
                  }
                }
              }
              if (matching.isNotEmpty) return matching.join(' ');
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }

  Future<void> _loadVerse() async {
    await _bibleService.initialize();
    _installedIds = await _bibleService.getInstalledVersionIds();
    await _reload(_preferredVersion(_installedIds));
  }

  /// Loads verse text (and the localized book name) for [versionId],
  /// falling back to WEB on the local DB and then streaming from the CDN.
  Future<void> _reload(String versionId) async {
    if (versionId == _versionName && (_verseText?.isNotEmpty ?? false)) {
      return;
    }

    if (mounted) {
      setState(() {
        _versionName = versionId;
        _isLoading = true;
      });
    }

    var text = await _bibleService.resolvePassage(
      versionId: versionId,
      bookNumber: widget.bookNumber,
      chapter: widget.chapter,
      startVerse: widget.startVerse,
      endVerse: widget.endVerse,
    );

    // Fallback to WEB if translation missing in local database
    if (text == null || text.isEmpty) {
      text = await _bibleService.resolvePassage(
        versionId: 'WEB',
        bookNumber: widget.bookNumber,
        chapter: widget.chapter,
        startVerse: widget.startVerse,
        endVerse: widget.endVerse,
      );
    }

    // Live CDN streaming fallback if not stored in local SQLite
    if (text == null || text.isEmpty) {
      text = await _fetchVerseFromCdn(
        versionId: versionId,
        bookNumber: widget.bookNumber,
        chapter: widget.chapter,
        startVerse: widget.startVerse,
        endVerse: widget.endVerse,
      );
    }
    if (text == null || text.isEmpty) {
      text = await _fetchVerseFromCdn(
        versionId: 'WEB',
        bookNumber: widget.bookNumber,
        chapter: widget.chapter,
        startVerse: widget.startVerse,
        endVerse: widget.endVerse,
      );
    }

    if (mounted) {
      setState(() {
        _verseText = text;
        _bookName = _bookNames.nameFor(versionId, widget.bookNumber);
        _isLoading = false;
      });
    }
  }

  /// Picks the initial version. When [ScriptureVersePopup.languageCode] is
  /// provided (e.g. the article's language), an installed catalog version
  /// matching that language wins; otherwise the first installed version is
  /// used, falling back to 'BSB' streaming when nothing is installed.
  String _preferredVersion(List<String> installed) {
    final lang = _normalizeLang(widget.languageCode ?? '');
    if (lang.isNotEmpty) {
      for (final id in installed) {
        final meta = _metaFor(id);
        if (meta != null && _normalizeLang(meta.languageCode) == lang) {
          return id;
        }
      }
    }
    return installed.isNotEmpty ? installed.first : 'BSB';
  }

  /// Normalizes short article/library codes to the catalog's full ISO-like
  /// language codes (e.g. `ta` -> `tam`, `hi` -> `hin`).
  String _normalizeLang(String code) {
    switch (code.trim().toLowerCase()) {
      case 'ta':
        return 'tam';
      case 'hi':
        return 'hin';
      case 'te':
        return 'tel';
      case 'kn':
        return 'kan';
      case 'ml':
        return 'mal';
      default:
        return code.trim().toLowerCase();
    }
  }

  BibleVersionMeta? _metaFor(String id) {
    for (final meta in BibleDownloadManager.catalog) {
      if (meta.id.toLowerCase() == id.toLowerCase()) return meta;
    }
    return null;
  }

  /// All catalog versions, installed ones first, then grouped by language.
  List<BibleVersionMeta> get _versionOptions {
    final installed = _installedIds.toSet();
    final sorted = [...BibleDownloadManager.catalog]..sort((a, b) {
        final installedA = installed.contains(a.id) ? 0 : 1;
        final installedB = installed.contains(b.id) ? 0 : 1;
        if (installedA != installedB) return installedA - installedB;
        return a.language.compareTo(b.language);
      });
    return sorted;
  }

  void _openInBible() {
    Navigator.of(context).pop();
    BiblePassageNavigator.instance.navigateTo(
      BibleReference(
        bookNumber: widget.bookNumber,
        chapter: widget.chapter,
        verse: widget.startVerse,
        versionId: _versionName.isEmpty ? null : _versionName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bookName = _bookName.isEmpty ? BookNameService.englishNameFor(widget.bookNumber) : _bookName;
    final citation = widget.endVerse != null && widget.endVerse != widget.startVerse
        ? '$bookName ${widget.chapter}:${widget.startVerse}-${widget.endVerse}'
        : '$bookName ${widget.chapter}:${widget.startVerse}';

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: tokens.surfaceBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.menu_book_rounded, color: tokens.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      citation,
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: _reload,
                      tooltip: 'Choose translation',
                      position: PopupMenuPosition.over,
                      itemBuilder: (context) => [
                        for (final meta in _versionOptions)
                          PopupMenuItem<String>(
                            value: meta.id,
                            height: 44,
                            child: Row(
                              children: [
                                if (_versionName == meta.id)
                                  Icon(Icons.check,
                                      size: 16, color: tokens.accent)
                                else
                                  const SizedBox(width: 16),
                                if (_installedIds.contains(meta.id))
                                  Icon(Icons.download_done_rounded,
                                      size: 14, color: tokens.onSurfaceMuted)
                                else
                                  const SizedBox(width: 14),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    meta.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _versionName == meta.id
                                          ? tokens.accent
                                          : tokens.onSurface,
                                      fontSize: 13.5,
                                      fontWeight: _versionName == meta.id
                                          ? FontWeight.bold
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 130),
                            child: Text(
                              _versionName.isEmpty ? 'Select version' : _versionName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.onSurfaceMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.arrow_drop_down_rounded,
                            size: 18,
                            color: tokens.onSurfaceMuted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: tokens.onSurfaceMuted, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: tokens.surfaceBorder, height: 1),
          const SizedBox(height: 16),

          // Verse Content
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_verseText != null && _verseText!.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tokens.surfaceVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tokens.surfaceBorder),
              ),
              child: Text(
                '“$_verseText”',
                style: TextStyle(
                  color: tokens.onSurface,
                  fontSize: 15.5,
                  height: 1.6,
                  fontFamily: 'serif',
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tokens.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Could not load verse text. Tap below to read in Bible.',
                style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13.5),
              ),
            ),
          const SizedBox(height: 18),

          // Action Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: tokens.accent),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _openInBible,
              icon: Icon(Icons.open_in_new_rounded, size: 16, color: tokens.accent),
              label: Text(
                'Open in Bible Reader',
                style: TextStyle(color: tokens.accent, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
