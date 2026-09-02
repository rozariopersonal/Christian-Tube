import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/layout/adaptivity.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../../books/models/book_scripture_link.dart';
import '../models/cross_reference.dart';
import '../models/bible_background_note.dart';
import '../widgets/cross_reference_card.dart';

/// Dedicated study screen displaying both Cross References and Historical/Cultural
/// Commentaries for a verse in a cohesive, tabbed presentation.
///
/// Responsive per AGENTS.md:
/// - TabBar pinned at the top inside MaxWidthBox, followed by scrollable TabBarView.
/// - The verse appears as the first element in the references tab.
class VerseStudyScreen extends StatefulWidget {
  final String verseText;
  final String verseLabel;
  final String? versionLabel;
  final List<CrossReference> references;
  final Map<String, String> resolvedTexts;
  final List<BibleBackgroundNote> commentaryNotes;
  final Future<List<BookScriptureLink>> bookCommentariesFuture;
  final double baseFontSize;
  final int initialTab;
  final void Function(CrossReference)? onTapReference;

  const VerseStudyScreen({
    super.key,
    required this.verseText,
    required this.verseLabel,
    this.versionLabel,
    this.references = const [],
    this.resolvedTexts = const {},
    this.commentaryNotes = const [],
    required this.bookCommentariesFuture,
    required this.baseFontSize,
    this.initialTab = 0,
    this.onTapReference,
  });

  @override
  State<VerseStudyScreen> createState() => _VerseStudyScreenState();
}

class _VerseStudyScreenState extends State<VerseStudyScreen> {
  bool _isVerseExpanded = true;
  int? _bookCommentariesCount;

  @override
  void initState() {
    super.initState();
    _loadBookCommentariesCount();
  }

  void _loadBookCommentariesCount() {
    widget.bookCommentariesFuture.then((list) {
      if (mounted) {
        setState(() {
          _bookCommentariesCount = list.length;
        });
      }
    }).catchError((_) {});
  }

  @override
  void didUpdateWidget(covariant VerseStudyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookCommentariesFuture != widget.bookCommentariesFuture) {
      _loadBookCommentariesCount();
    }
  }

  int get _totalCommentaryCount =>
      (_bookCommentariesCount ?? 0) + widget.commentaryNotes.length;

  Widget _buildVerseCard(BuildContext context) {
    final tokens = context.tokens;
    final screen = ScreenClass.of(context);
    final fontSize = screen.isCompact ? widget.baseFontSize : widget.baseFontSize + 1.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: tokens.accent, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.verseLabel,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              if (widget.versionLabel != null && widget.versionLabel!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.versionLabel!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.onSurfaceMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.verseText,
            maxLines: _isVerseExpanded ? null : 3,
            overflow: _isVerseExpanded ? null : TextOverflow.fade,
            style: TextStyle(
              color: tokens.onSurface,
              fontSize: fontSize,
              height: 1.6,
            ),
          ),
          if (widget.verseText.length > 160) ...[
            const SizedBox(height: 8),
            Center(
              child: InkWell(
                onTap: () => setState(() => _isVerseExpanded = !_isVerseExpanded),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isVerseExpanded ? 'Show less' : 'Show more',
                        style: TextStyle(
                          color: tokens.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _isVerseExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: tokens.accent,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReferencesTab(BuildContext context) {
    final tokens = context.tokens;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildVerseCard(context),
        const SizedBox(height: 16),
        if (widget.references.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.link_off, size: 48, color: tokens.onSurfaceMuted),
                const SizedBox(height: 12),
                Text(
                  'No cross-references for this verse',
                  style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 14),
                ),
              ],
            ),
          )
        else ...[
          Text(
            '${widget.references.length} cross-reference${widget.references.length == 1 ? '' : 's'}',
            style: TextStyle(
              color: tokens.onSurfaceMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          for (final ref in widget.references)
            CrossReferenceCard(
              reference: ref,
              text: widget.resolvedTexts[ref.textKey],
              fontSize: widget.baseFontSize,
              onTap: () => widget.onTapReference?.call(ref),
            ),
        ],
      ],
    );
  }

  Widget _buildCommentaryTab(BuildContext context) {
    return FutureBuilder<List<BookScriptureLink>>(
      future: widget.bookCommentariesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          final tokens = context.tokens;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: tokens.onSurfaceMuted),
                  const SizedBox(height: 12),
                  Text(
                    'Error loading commentaries',
                    style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 14),
                  ),
                ],
              ),
            ),
          );
        }

        final bookCommentaries = snapshot.data ?? [];
        final totalCount = bookCommentaries.length + widget.commentaryNotes.length;

        final tokens = context.tokens;

        if (totalCount == 0) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.menu_book_outlined, size: 48, color: tokens.onSurfaceMuted),
                  const SizedBox(height: 12),
                  Text(
                    'No commentary for this verse',
                    style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 14),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (bookCommentaries.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.auto_stories_rounded, size: 16, color: tokens.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${bookCommentaries.length} Zac Poonen ${bookCommentaries.length == 1 ? 'Exposition' : 'Expositions'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final link in bookCommentaries) _buildBookCommentaryItem(context, link),
              const SizedBox(height: 16),
            ],
            if (widget.commentaryNotes.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.history_edu_rounded, size: 16, color: tokens.onSurfaceMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${widget.commentaryNotes.length} Historical & Cultural Commentary',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.onSurfaceMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final note in widget.commentaryNotes) _buildCommentaryItem(context, note),
            ],
          ],
        );
      },
    );
  }

  Widget _buildBookCommentaryItem(BuildContext context, BookScriptureLink link) {
    final tokens = context.tokens;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.bookTitle,
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      'by ${link.author}',
                      style: TextStyle(
                        color: tokens.onSurfaceMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Page ${link.pageNumber}',
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (link.headline.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              link.headline,
              style: TextStyle(
                color: tokens.accent,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
          if (link.excerpt.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: tokens.accent, width: 2.5)),
                color: tokens.background.withValues(alpha: 0.4),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(6),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: MarkdownBody(
                data: link.excerpt,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                    color: tokens.onSurface.withValues(alpha: 0.9),
                    fontSize: 13,
                    height: 1.45,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCommentaryItem(BuildContext context, BibleBackgroundNote note) {
    final tokens = context.tokens;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  note.topic,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  note.isChapterOverview ? 'Overview' : 'Context',
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (note.quote != null && note.quote!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: tokens.background.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Quote: "${note.quote}"',
                style: TextStyle(
                  color: tokens.onSurfaceMuted,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          MarkdownBody(
            data: note.text,
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(
                color: tokens.onSurface,
                fontSize: widget.baseFontSize,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.verified_outlined, size: 13, color: tokens.onSurfaceMuted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  note.source,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.onSurfaceMuted,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final safeInitialTab = (widget.initialTab >= 0 && widget.initialTab < 2) ? widget.initialTab : 0;

    return DefaultTabController(
      length: 2,
      initialIndex: safeInitialTab,
      child: Scaffold(
        backgroundColor: tokens.background,
        appBar: AppBar(
          backgroundColor: tokens.background,
          elevation: 0,
          title: Text(
            'Study (${widget.verseLabel})',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: tokens.onSurface),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _buildLayout(context),
      ),
    );
  }

  Widget _buildLayout(BuildContext context) {
    final tokens = context.tokens;

    return MaxWidthBox(
      child: Column(
        children: [
          // Tab bar
          Container(
            color: tokens.background,
            child: TabBar(
              indicatorColor: tokens.accent,
              labelColor: tokens.accent,
              unselectedLabelColor: tokens.onSurfaceMuted,
              tabs: [
                Tab(
                  icon: const Icon(Icons.link, size: 18),
                  text: 'References (${widget.references.length})',
                ),
                Tab(
                  icon: const Icon(Icons.menu_book_rounded, size: 18),
                  text: 'Commentary ($_totalCommentaryCount)',
                ),
              ],
            ),
          ),

          // Scrollable content per tab
          Expanded(
            child: TabBarView(
              children: [
                _buildReferencesTab(context),
                _buildCommentaryTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
