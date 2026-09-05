import 'dart:async';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../downloads/screens/downloads_manager_screen.dart';
import 'package:flutter/services.dart';
import '../widgets/book_chapter_selector.dart';
import '../../../shared/ui/reader_appearance_sheet.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/bible_verse.dart';
import '../widgets/bible_search_sheet.dart';
import '../screens/bible_bookmarks_screen.dart';
import '../../../core/layout/content_width.dart';
import '../models/bible_book.dart';
import '../screens/verse_study_screen.dart';
import '../../books/services/book_service.dart';
import '../controllers/bible_controller.dart';
import '../../engines/scripture/services/book_name_service.dart';
import '../widgets/bible_app_bar.dart';
import '../widgets/bible_content.dart';
import '../widgets/bible_bottom_nav.dart';

class BibleScreen extends StatefulWidget {
  const BibleScreen({
    super.key,
    this.initialVersionId,
    this.initialBook,
    this.initialChapter,
    this.initialVerse,
    this.saveProgress = true,
    this.controller,
  });

  final String? initialVersionId;
  final String? initialBook;
  final int? initialChapter;
  final int? initialVerse;
  final bool saveProgress;

  /// Optional pre-initialized controller (for testing).
  final BibleController? controller;

  @override
  State<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends State<BibleScreen> {
  late final BibleController _controller;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _verseKeys = {};
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = BibleController(
        initialVersionId: widget.initialVersionId,
        initialBook: widget.initialBook,
        initialChapter: widget.initialChapter,
        initialVerse: widget.initialVerse,
        saveProgress: widget.saveProgress,
      );
      _controller.init();
    }
    _controller.addListener(_onControllerUpdate);
  }

  @override
  void didUpdateWidget(covariant BibleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool reloadNeeded = false;
    if (widget.initialBook != null &&
        widget.initialBook != oldWidget.initialBook &&
        bibleBooks.containsKey(widget.initialBook)) {
      reloadNeeded = true;
    }
    if (widget.initialChapter != null &&
        widget.initialChapter != oldWidget.initialChapter &&
        widget.initialChapter! >= 1) {
      reloadNeeded = true;
    }
    if (widget.initialVerse != null && widget.initialVerse != oldWidget.initialVerse) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToVerse(widget.initialVerse!);
      });
    }
    if (reloadNeeded && mounted) {
      _controller.goToBookAndChapter(
        widget.initialBook ?? _controller.currentBook,
        widget.initialChapter ?? _controller.currentChapter,
      );
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _controller.removeListener(_onControllerUpdate);
    if (widget.controller == null) _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    setState(() {});
    final pendingVerse = _controller.consumePendingScrollVerse();
    if (pendingVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToVerse(pendingVerse);
      });
    }
  }

  void _scrollToVerse(int verseNumber, {int retries = 10}) {
    if (!mounted) return;
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    GlobalKey? key = _verseKeys[verseNumber];
    if (key == null) {
      int best = -1;
      for (final k in _verseKeys.keys) {
        if (best == -1 || (k - verseNumber).abs() < (best - verseNumber).abs()) {
          best = k;
        }
      }
      if (best != -1) key = _verseKeys[best];
    }
    final BuildContext? ctx = key?.currentContext;
    if (ctx == null) {
      if (retries > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToVerse(verseNumber, retries: retries - 1);
        });
      }
      return;
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    Scrollable.ensureVisible(
      ctx,
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
      alignment: 0.1,
    );
    _highlightTimer?.cancel();
    _controller.setHighlight(verseNumber);
    _highlightTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _controller.setHighlight(null);
    });
  }

  // ── Navigation helpers ────────────────────────────────────────────────

  Future<void> _pushManager() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DownloadsManagerScreen(initialTab: 1)),
    );
    _controller.fetchData();
  }

  void _showBookChapterSelector() {
    showAdaptiveBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BookChapterSelector(
        currentBook: _controller.currentBook,
        currentChapter: _controller.currentChapter,
        currentVerse: _controller.currentVerse,
        displayNameOf: (canonicalBook, bookNumber) =>
            _controller.displayBookName(canonicalBook),
        loadVerses: _controller.previewChapterVerses,
        onSelection: (book, chapter, verse) {
          Navigator.pop(context);
          _controller.goToBookAndChapter(book, chapter, verse: verse);
        },
      ),
    );
  }

  void _showReadingSettings() {
    showReaderAppearanceSheet(context, _controller.appearance);
  }

  void _showSearch() {
    if (_controller.selectedVersion == null) return;
    showAdaptiveBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BibleSearchSheet(
        versionId: _controller.selectedVersion!.shortname,
        onJumpTo: (book, chapter, [verse]) {
          _controller.goToBookAndChapter(book, chapter, verse: verse);
        },
      ),
    );
  }

  void _openBookmarks() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BibleBookmarksScreen(
          onJumpTo: (book, chapter, [verse]) {
            _controller.goToBookAndChapter(book, chapter, verse: verse);
          },
        ),
      ),
    );
  }

  void _navigateToPassage({
    required int bookNumber,
    required int chapter,
    required int verse,
  }) {
    final targetBook = bookNumber >= 1 &&
            bookNumber <= BookNameService.englishBookNames.length
        ? BookNameService.englishBookNames[bookNumber - 1]
        : _controller.currentBook;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BibleScreen(
          initialVersionId: _controller.selectedVersion?.shortname,
          initialBook: targetBook,
          initialChapter: chapter,
          initialVerse: verse,
          saveProgress: false,
        ),
      ),
    );
  }

  void _openVerseStudyScreen(int verseNumber, {int initialTab = 0}) {
    final s = _controller.state;
    final verse = s.verses.firstWhere(
      (v) => v.number == verseNumber,
      orElse: () => s.verses.isNotEmpty
          ? s.verses.first
          : BibleVerse(number: verseNumber, text: ''),
    );
    final verseLabel =
        '${_controller.displayBookName(_controller.currentBook)} '
        '${_controller.currentChapter}:$verseNumber';
    final refs = s.chapterCrossRefs[verseNumber] ?? const [];
    var notes = s.chapterBackgrounds[verseNumber] ?? const [];
    if (notes.isEmpty && s.chapterBackgrounds[0] != null) {
      notes = s.chapterBackgrounds[0]!;
    }
    final bookNum = _controller.bookNumber(_controller.currentBook);
    final bookCommentariesFuture = BookService.instance.getCommentariesForVerse(
      bookNum, _controller.currentChapter, verseNumber,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VerseStudyScreen(
          verseText: verse.text,
          verseLabel: verseLabel,
          versionLabel: _controller.selectedVersion?.name,
          versionId: _controller.selectedVersion?.shortname,
          bookNumber: bookNum,
          chapterNumber: _controller.currentChapter,
          verseNumber: verseNumber,
          references: refs,
          resolvedTexts: s.crossRefTexts,
          commentaryNotes: notes,
          bookCommentariesFuture: bookCommentariesFuture,
          baseFontSize: _controller.appearance.fontSize,
          initialTab: initialTab,
          onTapReference: (ref) => _navigateToPassage(
            bookNumber: ref.bookNumber,
            chapter: ref.chapter,
            verse: ref.verse,
          ),
          onTapPassage: (bookNum, chapter, verseNum) => _navigateToPassage(
            bookNumber: bookNum,
            chapter: chapter,
            verse: verseNum,
          ),
        ),
      ),
    );
  }

  // ── Clipboard / Share / Bookmark ──────────────────────────────────────

  void _copySelectedVerses() {
    final s = _controller.state;
    if (s.selectedVerses.isEmpty) return;
    Clipboard.setData(ClipboardData(text: s.selectedText())).then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verses copied to clipboard')),
        );
        _controller.clearSelection();
      }
    });
  }

  void _shareSelectedVerses() {
    final s = _controller.state;
    if (s.selectedVerses.isEmpty) return;
    final header = _controller.selectedVersion != null
        ? '${_controller.currentBook} ${_controller.currentChapter} '
            '· ${_controller.selectedVersion!.shortname}'
        : '${_controller.currentBook} ${_controller.currentChapter}';
    final text = s.selectedText();
    final shareBody = text.isEmpty ? header : '$header\n$text\n\n— Christian Tube Bible';
    Share.share(shareBody);
    _controller.clearSelection();
  }

  Future<void> _bookmarkSelectedVerses() async {
    await _controller.toggleBookmarkSelected();
    if (!mounted) return;
    final message = _controller.consumeBookmarkMessage();
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _controller.state;
    final tokens = context.tokens;
    final appearance = _controller.appearance;
    return Scaffold(
      backgroundColor: appearance.background(tokens),
      appBar: BibleAppBar(
        controller: _controller,
        onShowSearch: _showSearch,
        onShowReadingSettings: _showReadingSettings,
        onOpenBookmarks: _openBookmarks,
        onPushManager: _pushManager,
      ),
      body: BibleContent(
        controller: _controller,
        scrollController: _scrollController,
        verseKeys: _verseKeys,
        onVerseTap: _controller.toggleVerseSelection,
        onCopy: _copySelectedVerses,
        onShare: _shareSelectedVerses,
        onBookmark: _bookmarkSelectedVerses,
        onClear: _controller.clearSelection,
        onOpenStudyPage: _openVerseStudyScreen,
        onPushManager: _pushManager,
        onRedownloadDefault: _controller.redownloadDefault,
      ),
      bottomNavigationBar: BibleBottomNav(
        controller: _controller,
        onShowBookChapterSelector: _showBookChapterSelector,
        onCopy: _copySelectedVerses,
        onShare: _shareSelectedVerses,
        onBookmark: _bookmarkSelectedVerses,
        onClear: _controller.clearSelection,
        onStudy: s.selectedVerses.isNotEmpty
            ? () => _openVerseStudyScreen(s.selectedVerses.first)
            : null,
      ),
    );
  }
}
