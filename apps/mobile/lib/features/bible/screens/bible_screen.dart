import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import '../widgets/book_chapter_selector.dart';
import '../../../shared/ui/reader_appearance_sheet.dart';
import '../../../shared/ui/highlight_color_picker.dart';
import '../../../shared/ui/note_editor_sheet.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/link/deep_link_service.dart';
import '../models/bible_verse.dart';
import '../widgets/bible_search_sheet.dart';
import '../screens/bible_bookmarks_screen.dart';
import '../../../core/layout/content_width.dart';
import '../models/bible_book.dart';
import '../models/bible_reference.dart';
import '../screens/verse_study_screen.dart';
import '../../books/services/book_service.dart';
import '../controllers/bible_controller.dart';
import '../services/bible_chapter_stream.dart';
import '../services/bible_passage_navigator.dart';
import '../widgets/bible_app_bar.dart';
import '../widgets/bible_content.dart';
import '../widgets/bible_bottom_nav.dart';
import '../../../core/services/bottom_bar_visibility_service.dart';

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
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  bool _initialPositioned = false;
  bool _isProgrammaticScrolling = false;
  Timer? _highlightTimer;
  Timer? _programmaticScrollTimer;

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
    _itemPositionsListener.itemPositions.addListener(_onItemPositionsChanged);
    _controller.addListener(_onControllerUpdate);
    _controller.appearance.addListener(_onAppearanceChanged);
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
        if (mounted) _scrollToVerse(widget.initialVerse!, highlight: true);
      });
    }
    if (reloadNeeded && mounted) {
      _initialPositioned = false;
      _controller.goToBookAndChapter(
        widget.initialBook ?? _controller.currentBook,
        widget.initialChapter ?? _controller.currentChapter,
        verse: widget.initialVerse,
      );
    }
  }

  @override
  void dispose() {
    BottomBarVisibilityService.instance.resetBibleNav();
    _highlightTimer?.cancel();
    _programmaticScrollTimer?.cancel();
    _itemPositionsListener.itemPositions.removeListener(_onItemPositionsChanged);
    _controller.removeListener(_onControllerUpdate);
    _controller.appearance.removeListener(_onAppearanceChanged);
    if (widget.controller == null) _controller.dispose();
    BiblePassageNavigator.instance.detach(context, _moveToReference);
    super.dispose();
  }

  void _onAppearanceChanged() {
    if (!mounted || _isProgrammaticScrolling) return;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    final visible = positions.where((p) => p.itemTrailingEdge > 0).toList();
    if (visible.isEmpty) return;

    visible.sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
    final topItem = visible.first;
    final topIndex = topItem.index;
    final topAlignment = topItem.itemLeadingEdge;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _itemScrollController.jumpTo(index: topIndex, alignment: topAlignment);
      } catch (_) {}
    });
  }

  void _onItemPositionsChanged() {
    if (_isProgrammaticScrolling) return;
    final s = _controller.state;
    if (s.index == null || s.isLoading) return;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    final chaptersSeen = <int>{};
    for (final p in positions) {
      if (p.index >= 0 && p.index < s.index!.totalVerses) {
        final r = s.index!.rowToReference(p.index);
        final cid = bibleChapterId(r.bookNumber, r.chapter);
        if (chaptersSeen.add(cid)) {
          _controller.ensureChapterVisible(r.bookNumber, r.chapter);
        }
      }
    }

    ItemPosition? first;
    for (final p in positions) {
      if (first == null || p.index < first.index) first = p;
    }
    if (first == null) return;
    final ref = s.index!.rowToReference(first.index);
    _controller.updateVisibleChapter(ref.bookNumber, ref.chapter, verse: ref.verse);
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    setState(() {});
    final s = _controller.state;
    if (s.isLoading) return;

    final target = _controller.consumeScrollTargetIfReady();
    if (target != null) {
      _initialPositioned = true;
      final idx = s.index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (idx != null && idx.totalVerses > 0) {
          final bn = _controller.bookNumber(target.book);
          final row = idx
              .globalRowFor(
                bookNumber: bn,
                chapter: target.chapter,
                verse: target.verse,
              )
              .clamp(0, idx.totalVerses - 1);
          _scrollToGlobalIndex(row, target.verse, highlight: target.highlight);
        } else {
          _scrollToVerse(target.verse, highlight: target.highlight);
        }
      });
    } else if (!_initialPositioned) {
      _initialPositioned = true;
      final idx = s.index;
      if (idx != null && idx.totalVerses > 0) {
        final bn = _controller.bookNumber(_controller.currentBook);
        final row = idx.chapterStartRow(
          bookNumber: bn,
          chapter: _controller.currentChapter,
        );
        if (row > 0) {
          _isProgrammaticScrolling = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _itemScrollController.jumpTo(index: row, alignment: 0);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _isProgrammaticScrolling = false;
              });
            }
          });
        }
      }
    }
  }

  void _scrollToGlobalIndex(int index, int verseNumber, {bool highlight = true}) {
    if (!mounted) return;
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    if (!_itemScrollController.isAttached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToGlobalIndex(index, verseNumber, highlight: highlight);
      });
      return;
    }

    _isProgrammaticScrolling = true;
    _programmaticScrollTimer?.cancel();
    _programmaticScrollTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) _isProgrammaticScrolling = false;
    });

    final alignment = verseNumber <= 1 ? 0.0 : 0.1;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    if (reduceMotion || !highlight || verseNumber <= 1) {
      _itemScrollController.jumpTo(index: index, alignment: alignment);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _isProgrammaticScrolling = false;
      });
    } else {
      _itemScrollController.scrollTo(
        index: index,
        alignment: alignment,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      ).then((_) {
        if (mounted) _isProgrammaticScrolling = false;
      }).catchError((_) {
        if (mounted) _isProgrammaticScrolling = false;
      });
    }

    if (highlight) {
      _highlightTimer?.cancel();
      _controller.setHighlight(verseNumber);
      _highlightTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) _controller.setHighlight(null);
      });
    }
  }

  void _scrollToVerse(int verseNumber, {bool highlight = true}) {
    if (!mounted) return;
    final s = _controller.state;
    final idx = s.index;
    if (idx != null && idx.totalVerses > 0) {
      final bn = _controller.bookNumber(_controller.currentBook);
      final row = idx
          .globalRowFor(
            bookNumber: bn,
            chapter: _controller.currentChapter,
            verse: verseNumber,
          )
          .clamp(0, idx.totalVerses - 1);
      _scrollToGlobalIndex(row, verseNumber, highlight: highlight);
      return;
    }
    final index = s.verses.indexWhere((v) => v.number == verseNumber);
    if (index < 0) return;
    _scrollToGlobalIndex(index, verseNumber, highlight: highlight);
  }

  // ── Navigation helpers ────────────────────────────────────────────────

  Future<void> _pushManager() async {
    await context.push('/bible-manager');
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
    BiblePassageNavigator.instance.navigateTo(
      BibleReference(
        bookNumber: bookNumber,
        chapter: chapter,
        verse: verse,
      ),
      context: context,
    );
  }

  /// In-place receiver registered with [BiblePassageNavigator]: moves this
  /// reader to [reference] (switching version first if requested) so the
  /// target verse is loaded, scrolled to, and highlighted.
  void _moveToReference(BibleReference reference) {
    if (!mounted) return;
    final s = _controller.state;
    if (reference.versionId != null &&
        s.selectedVersion?.shortname != reference.versionId) {
      final match = s.versions.where((v) => v.shortname == reference.versionId);
      if (match.isNotEmpty) {
        _controller.selectVersion(match.first);
      }
    }
    _controller.goToBookAndChapter(
      reference.bookName,
      reference.chapter,
      verse: reference.verse,
    );
  }

  void _openVerseStudyScreen(
    int verseNumber, {
    int initialTab = 0,
    String? book,
    int? chapter,
  }) {
    final s = _controller.state;
    final targetBook = book ?? s.selectedBook ?? _controller.currentBook;
    final targetChapter = chapter ?? s.selectedChapter ?? _controller.currentChapter;
    final bookNum = _controller.bookNumber(targetBook);
    final cid = bibleChapterId(bookNum, targetChapter);
    final chVerses = s.loadedChapters[cid] ?? s.verses;
    final verse = chVerses.firstWhere(
      (v) => v.number == verseNumber,
      orElse: () => chVerses.isNotEmpty
          ? chVerses.first
          : BibleVerse(number: verseNumber, text: ''),
    );
    final verseLabel =
        '${_controller.displayBookName(targetBook)} '
        '$targetChapter:$verseNumber';
    final refs = s.loadedCrossRefs[cid]?[verseNumber] ??
        (targetBook == _controller.currentBook && targetChapter == _controller.currentChapter
            ? (s.chapterCrossRefs[verseNumber] ?? const [])
            : const []);
    var notes = s.loadedBackgrounds[cid]?[verseNumber] ??
        (targetBook == _controller.currentBook && targetChapter == _controller.currentChapter
            ? (s.chapterBackgrounds[verseNumber] ?? const [])
            : const []);
    if (notes.isEmpty && s.chapterBackgrounds[0] != null) {
      notes = s.chapterBackgrounds[0]!;
    }
    final bookCommentariesFuture = BookService.instance.getCommentariesForVerse(
      bookNum, targetChapter, verseNumber,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VerseStudyScreen(
          verseText: verse.text,
          verseLabel: verseLabel,
          versionLabel: _controller.selectedVersion?.name,
          versionId: _controller.selectedVersion?.shortname,
          bookNumber: bookNum,
          chapterNumber: targetChapter,
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
        _controller.clearSelection();
      }
    });
  }

  void _shareSelectedVerses() {
    final s = _controller.state;
    if (s.selectedVerses.isEmpty) return;
    final book = s.selectedBook ?? _controller.currentBook;
    final chapter = s.selectedChapter ?? _controller.currentChapter;
    final bookDisplay = _controller.displayBookName(book);
    final header = _controller.selectedVersion != null
        ? '$bookDisplay $chapter · ${_controller.selectedVersion!.shortname}'
        : '$bookDisplay $chapter';
    final text = s.selectedText();
    final firstVerse = s.selectedVerses.first;
    final link = DeepLinkService.bible(
      version: _controller.selectedVersion?.shortname,
      book: book,
      chapter: chapter,
      verse: firstVerse,
    );
    final shareBody = text.isEmpty
        ? '$header\n\n$link'
        : '$header\n$text\n\n— Christian Tube Bible\n$link';
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

  Future<void> _highlightSelectedVerses() async {
    final s = _controller.state;
    if (s.selectedVerses.isEmpty) return;

    final book = s.selectedBook ?? _controller.currentBook;
    final chapter = s.selectedChapter ?? _controller.currentChapter;
    final chId = bibleChapterId(_controller.bookNumber(book), chapter);
    final chVerses = s.loadedChapters[chId] ?? s.verses;
    final selected = chVerses
        .where((v) => s.selectedVerses.contains(v.number))
        .toList();
    if (selected.isEmpty) return;

    final label = selected.length == 1
        ? '${_controller.displayBookName(book)} $chapter:${selected.first.verseDisplay}'
        : '${_controller.displayBookName(book)} $chapter:'
            '${selected.first.number}-${selected.last.endNumber ?? selected.last.number}';

    final result = await HighlightColorPicker.show(
      context,
      titles: [label],
      currentColorIndex: s.highlightColorForSelection,
      hasHighlight: s.selectionHasHighlight,
      onColorSelected: (colorIndex) {
        _controller.applyHighlight(colorIndex);
      },
      onHighlightRemoved: () {
        _controller.removeHighlight();
      },
    );
    if (!mounted || result == null) return;

    switch (result) {
      case HighlightPickerPicked(:final colorIndex):
        if (_controller.state.selectedVerses.isNotEmpty) {
          await _controller.applyHighlight(colorIndex);
        }
      case HighlightPickerRemoved():
        if (_controller.state.selectedVerses.isNotEmpty) {
          await _controller.removeHighlight();
        }
    }
  }

  /// Opens the note editor for the first verse of the current selection (or
  /// [verseNumber] when provided) and persists the result through the
  /// controller.
  Future<void> _openNoteEditor([int? verseNumber]) async {
    final s = _controller.state;
    if (s.selectedVerses.isEmpty && verseNumber == null) return;
    final targetVerse = verseNumber ?? s.selectedVerses.first;
    final book = s.selectedBook ?? _controller.currentBook;
    final chapter = s.selectedChapter ?? _controller.currentChapter;
    final existing = await _controller.getNoteForVerse(targetVerse, book: book, chapter: chapter);
    if (!mounted) return;

    final verseLabel =
        '${_controller.displayBookName(book)} '
        '$chapter:$targetVerse';

    final result = await NoteEditorSheet.show(
      context,
      initialText: existing?.text ?? '',
      contextText: _controller.verseTextFor(targetVerse, book: book, chapter: chapter),
      title: verseLabel,
      hasExistingNote: existing != null && existing.text.trim().isNotEmpty,
    );
    if (!mounted || result == null) return;

    try {
      switch (result) {
        case NoteEditorSave(:final text):
          await _controller.saveNoteForVerse(targetVerse, text, book: book, chapter: chapter);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Note saved'),
                duration: Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        case NoteEditorDelete():
          await _controller.deleteNoteForVerse(targetVerse, book: book, chapter: chapter);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Note deleted'),
                duration: Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        case NoteEditorDismiss():
          break;
      }
    } catch (e, stackTrace) {
      debugPrint('Error saving/deleting note: $e\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Note could not be saved: $e'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      _controller.clearSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    if (isCurrent) {
      BiblePassageNavigator.instance.attach(context, _moveToReference);
    } else {
      BiblePassageNavigator.instance.detach(context, _moveToReference);
    }
    final s = _controller.state;
    final tokens = context.tokens;
    final appearance = _controller.appearance;
    return ListenableBuilder(
      listenable: Listenable.merge([appearance, BottomBarVisibilityService.instance]),
      builder: (context, _) {
        final isNavHidden = BottomBarVisibilityService.instance.isBibleNavHidden;
        final hasInScreenInterception = s.selectedVerses.isNotEmpty || isNavHidden;
        return PopScope(
          canPop: !hasInScreenInterception,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (s.selectedVerses.isNotEmpty) {
              _controller.clearSelection();
              return;
            }
            if (BottomBarVisibilityService.instance.isBibleNavHidden) {
              BottomBarVisibilityService.instance.showBibleNav();
              return;
            }
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              return;
            }
          },
          child: Scaffold(
          backgroundColor: appearance.background(tokens),
        appBar: BibleAppBar(
          controller: _controller,
          onShowSearch: _showSearch,
          onShowReadingSettings: _showReadingSettings,
          onOpenBookmarks: _openBookmarks,
          onPushManager: _pushManager,
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  Expanded(
                    child: BibleContent(
                      controller: _controller,
                      itemScrollController: _itemScrollController,
                      itemPositionsListener: _itemPositionsListener,
                      onVerseTap: (v, {book, chapter}) =>
                          _controller.toggleVerseSelection(v, book: book, chapter: chapter),
                      onCopy: _copySelectedVerses,
                      onShare: _shareSelectedVerses,
                      onBookmark: _bookmarkSelectedVerses,
                      onClear: _controller.clearSelection,
                      onOpenStudyPage: _openVerseStudyScreen,
                      onPushManager: _pushManager,
                      onRedownloadDefault: _controller.redownloadDefault,
                    ),
                  ),
                  if (s.selectedVerses.isEmpty)
                    BibleBottomNav(
                      controller: _controller,
                      onShowBookChapterSelector: _showBookChapterSelector,
                      onCopy: _copySelectedVerses,
                      onShare: _shareSelectedVerses,
                      onBookmark: _bookmarkSelectedVerses,
                      onHighlight: _highlightSelectedVerses,
                      onNote: _openNoteEditor,
                      onClear: _controller.clearSelection,
                      onStudy: null,
                    ),
                ],
              ),
            ),
            if (s.selectedVerses.isNotEmpty)
              Positioned.fill(
                child: BibleBottomNav(
                  controller: _controller,
                  onShowBookChapterSelector: _showBookChapterSelector,
                  onCopy: _copySelectedVerses,
                  onShare: _shareSelectedVerses,
                  onBookmark: _bookmarkSelectedVerses,
                  onHighlight: _highlightSelectedVerses,
                  onNote: _openNoteEditor,
                  onClear: _controller.clearSelection,
                  onStudy: () => _openVerseStudyScreen(
                    s.selectedVerses.first,
                    book: s.selectedBook,
                    chapter: s.selectedChapter,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  },
);
}
}
