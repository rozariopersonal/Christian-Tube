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
import '../../../../shared/ui/bible_version_pill.dart';

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
    final screen = ScreenClass.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final maxSheetHeight = screen.isCompact
        ? MediaQuery.sizeOf(context).height * 0.75
        : 520.0;
    final bookName = _bookName.isEmpty ? BookNameService.englishNameFor(widget.bookNumber) : _bookName;
    final citation = widget.endVerse != null && widget.endVerse != widget.startVerse
        ? '$bookName ${widget.chapter}:${widget.startVerse}-${widget.endVerse}'
        : '$bookName ${widget.chapter}:${widget.startVerse}';

    return Container(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: screen.isCompact
            ? const BorderRadius.vertical(top: Radius.circular(20))
            : BorderRadius.circular(18),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle (compact bottom sheet only)
          if (screen.isCompact)
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
                    const SizedBox(height: 4),
                    BibleVersionPill(
                      activeVersionId: _versionName.isEmpty ? 'BSB' : _versionName,
                      onSelectVersion: _reload,
                      showLeadingIcon: false,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      fontSize: 11.5,
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

          // Verse Content (Scrollable)
          Flexible(
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: _verseText != null && _verseText!.isNotEmpty
                        ? Container(
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
                        : Container(
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
                  ),
          ),
          const SizedBox(height: 16),

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
