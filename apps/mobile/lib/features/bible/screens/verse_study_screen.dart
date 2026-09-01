import 'package:flutter/material.dart';
import '../../../core/layout/adaptivity.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../../books/models/book_scripture_link.dart';
import '../../books/screens/book_reader_screen.dart';
import '../models/cross_reference.dart';
import '../models/bible_background_note.dart';
import '../widgets/cross_reference_card.dart';

/// Dedicated study screen displaying both Cross References and Historical/Cultural
/// Commentaries for a verse in a cohesive, tabbed presentation.
///
/// Responsive per AGENTS.md:
/// - `compact`: Pinned verse card at top, followed by TabBar and scrollable TabBarView.
/// - `medium`/`expanded`: Side-by-side split view inside [MaxWidthBox] (verse on left,
///   tabs + study content on right).
class VerseStudyScreen extends StatelessWidget {
  final String verseText;
  final String verseLabel;
  final String? versionLabel;
  final List<CrossReference> references;
  final Map<String, String> resolvedTexts;
  final List<BibleBackgroundNote> commentaryNotes;
  final List<BookScriptureLink> bookCommentaries;
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
    this.bookCommentaries = const [],
    required this.baseFontSize,
    this.initialTab = 0,
    this.onTapReference,
  });

  Widget _buildVerseCard(BuildContext context) {
    final tokens = context.tokens;
    final screen = ScreenClass.of(context);
    final fontSize = screen.isCompact ? baseFontSize : baseFontSize + 1.0;

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
                  verseLabel,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              if (versionLabel != null && versionLabel!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    versionLabel!,
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
            verseText,
            style: TextStyle(
              color: tokens.onSurface,
              fontSize: fontSize,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferencesTab(BuildContext context) {
    final tokens = context.tokens;
    if (references.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
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
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${references.length} cross-reference${references.length == 1 ? '' : 's'}',
          style: TextStyle(
            color: tokens.onSurfaceMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        for (final ref in references)
          CrossReferenceCard(
            reference: ref,
            text: resolvedTexts[ref.textKey],
            fontSize: baseFontSize,
            onTap: () => onTapReference?.call(ref),
          ),
      ],
    );
  }

  Widget _buildCommentaryTab(BuildContext context) {
    final tokens = context.tokens;
    final totalCount = bookCommentaries.length + commentaryNotes.length;

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
                'No commentary or background notes for this verse',
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
        if (commentaryNotes.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.history_edu_rounded, size: 16, color: tokens.onSurfaceMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${commentaryNotes.length} Historical & Cultural Context',
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
          for (final note in commentaryNotes) _buildCommentaryItem(context, note),
        ],
      ],
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
              child: Text(
                '"${link.excerpt}"',
                style: TextStyle(
                  color: tokens.onSurface.withValues(alpha: 0.9),
                  fontSize: 13,
                  height: 1.45,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: tokens.accent.withValues(alpha: 0.12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: Icon(Icons.arrow_forward_rounded, size: 16, color: tokens.accent),
              label: Text(
                'Read in Book (p. ${link.pageNumber})',
                style: TextStyle(
                  color: tokens.accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BookReaderScreen(
                      bookId: link.bookId,
                      initialPage: link.pageNumber,
                      highlightStartLine: link.startLine,
                      highlightEndLine: link.endLine,
                    ),
                  ),
                );
              },
            ),
          ),
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
          Text(
            note.text,
            style: TextStyle(
              color: tokens.onSurface,
              fontSize: baseFontSize,
              height: 1.55,
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
    final screen = ScreenClass.of(context);
    final safeInitialTab = (initialTab >= 0 && initialTab < 2) ? initialTab : 0;

    return DefaultTabController(
      length: 2,
      initialIndex: safeInitialTab,
      child: Scaffold(
        backgroundColor: tokens.background,
        appBar: AppBar(
          backgroundColor: tokens.background,
          elevation: 0,
          title: Text(
            'Study ($verseLabel)',
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
        body: screen.isCompact ? _buildCompact(context) : _buildSplit(context),
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    final tokens = context.tokens;

    return Column(
      children: [
        // Verse preview pinned at top
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: _buildVerseCard(context),
        ),

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
                text: 'References (${references.length})',
              ),
              Tab(
                icon: const Icon(Icons.history_edu, size: 18),
                text: 'Commentary (${commentaryNotes.length})',
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
    );
  }

  Widget _buildSplit(BuildContext context) {
    final tokens = context.tokens;

    return MaxWidthBox(
      child: SizedBox(
        height: double.infinity,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left pane: pinned verse card
            SizedBox(
              width: 360,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 24),
                child: _buildVerseCard(context),
              ),
            ),

            // Right pane: Tabs + Study details
            Expanded(
              child: Column(
                children: [
                  TabBar(
                    indicatorColor: tokens.accent,
                    labelColor: tokens.accent,
                    unselectedLabelColor: tokens.onSurfaceMuted,
                    tabs: [
                      Tab(
                        icon: const Icon(Icons.link, size: 18),
                        text: 'References (${references.length})',
                      ),
                      Tab(
                        icon: const Icon(Icons.history_edu, size: 18),
                        text: 'Commentary (${commentaryNotes.length})',
                      ),
                    ],
                  ),
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
            ),
          ],
        ),
      ),
    );
  }
}
