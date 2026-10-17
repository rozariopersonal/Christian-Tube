import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/color_utils.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/highlight_palette.dart';
import '../../../shared/services/reader_appearance.dart';

/// Progressive disclosure stages for the Bible Verse Action Bottom Sheet.
enum VerseSheetStage {
  expanded, // Level 1: Share, Copy, Bookmark, Note + 15-color grid
  study, // Level 2: Embedded comprehensive Verse Study view
}

/// 2-stage bottom sheet for selected verses in the Bible Reader.
///
/// Complies with AGENTS.md standards:
/// - ScreenClass / MaxWidthBox capped at 640px on tablets/desktop
/// - Universal back & tap dismiss (tapping backdrop or [X] unselects verses)
/// - Theme tokens (AppTokens / context.tokens / context.accent)
class VerseActionBar extends StatefulWidget {
  final int selectedCount;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onBookmark;
  final VoidCallback onHighlight;
  final VoidCallback onNote;
  final VoidCallback? onClear;
  final VoidCallback? onStudy;
  final ReaderAppearance? appearance;
  final EdgeInsetsGeometry? margin;

  // Progressive sheet extensions
  final ValueChanged<int>? onHighlightColor;
  final VoidCallback? onRemoveHighlight;
  final int? currentColorIndex;
  final bool hasHighlight;
  final String? verseLabel;
  final Widget? studyContent;
  final ValueChanged<VerseSheetStage>? onStageChanged;

  static const moreColorsKey = Key('verse_sheet_more_colors');
  static const studyPromptKey = Key('verse_sheet_study_prompt');
  static const collapseStudyKey = Key('verse_sheet_collapse_study');

  const VerseActionBar({
    super.key,
    this.selectedCount = 1,
    required this.onCopy,
    required this.onShare,
    required this.onBookmark,
    required this.onHighlight,
    required this.onNote,
    this.onClear,
    this.onStudy,
    this.appearance,
    this.margin,
    this.onHighlightColor,
    this.onRemoveHighlight,
    this.currentColorIndex,
    this.hasHighlight = false,
    this.verseLabel,
    this.studyContent,
    this.onStageChanged,
  });

  @override
  State<VerseActionBar> createState() => _VerseActionBarState();
}

class _VerseActionBarState extends State<VerseActionBar>
    with SingleTickerProviderStateMixin {
  VerseSheetStage _stage = VerseSheetStage.expanded;
  late final AnimationController _animController;
  Animation<double>? _heightAnimation;
  double _currentHeight = 0.0;

  @override
  void initState() {
    super.initState();
    _stage = VerseSheetStage.expanded;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        if (_heightAnimation != null && mounted) {
          setState(() {
            _currentHeight = _heightAnimation!.value;
          });
        }
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  double _targetHeightFor(
      VerseSheetStage stage, double maxHeight, double bottomInset) {
    switch (stage) {
      case VerseSheetStage.expanded:
        final desired = 350.0 + bottomInset;
        final maxAllowed = maxHeight * 0.85;
        return desired > maxAllowed ? maxAllowed : desired;
      case VerseSheetStage.study:
        final desired = maxHeight * 0.92;
        return desired > maxHeight ? maxHeight : desired;
    }
  }

  void _animateTo(
      VerseSheetStage newStage, double maxHeight, double bottomInset) {
    if (_stage == newStage) return;
    final target = _targetHeightFor(newStage, maxHeight, bottomInset);
    _animController.stop();
    _heightAnimation = Tween<double>(
      begin: _currentHeight,
      end: target,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    setState(() {
      _stage = newStage;
    });
    widget.onStageChanged?.call(newStage);
    _animController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedCount == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final tokens = context.tokens;
    final isDark = theme.brightness == Brightness.dark ||
        (widget.appearance?.isDark(tokens) ?? false);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return PopScope(
      canPop: _stage != VerseSheetStage.study,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_stage == VerseSheetStage.study) {
          final maxHeight = MediaQuery.sizeOf(context).height;
          _animateTo(VerseSheetStage.expanded, maxHeight, bottomInset);
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height;

          final expandedH =
              _targetHeightFor(VerseSheetStage.expanded, maxHeight, bottomInset);
          final studyH =
              _targetHeightFor(VerseSheetStage.study, maxHeight, bottomInset);

          if (_currentHeight == 0.0 || !_animController.isAnimating) {
            _currentHeight = _stage == VerseSheetStage.study ? studyH : expandedH;
          }

          final sheetColor = isDark
              ? tokens.surface.withValues(alpha: 0.94)
              : tokens.surface.withValues(alpha: 0.96);

          return Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: _currentHeight,
              width: double.infinity,
              child: MaxWidthBox(
                maxWidth: 640,
                child: Container(
                  decoration: BoxDecoration(
                    color: sheetColor,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(22)),
                    border: Border(
                      top: BorderSide(
                          color: tokens.surfaceBorder, width: 0.8),
                      left: BorderSide(
                          color: tokens.surfaceBorder, width: 0.5),
                      right: BorderSide(
                          color: tokens.surfaceBorder, width: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: tokens.scrim
                            .withValues(alpha: isDark ? 0.40 : 0.16),
                        blurRadius: 18,
                        spreadRadius: 2,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(22)),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
                      child: Material(
                        color: Colors.transparent,
                        child: SafeArea(
                          top: false,
                          child: Column(
                            mainAxisSize: MainAxisSize.max,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 10),
                              Expanded(
                                child: _stage == VerseSheetStage.expanded
                                    ? _buildExpandedStage(
                                        context, tokens, maxHeight, bottomInset)
                                    : _buildStudyStage(
                                        context, tokens, maxHeight, bottomInset),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// LEVEL 1: Expanded Sheet
  /// Context header, Action Row 1 (Share, Copy, Bookmark, Note),
  /// Row 2: Full 15-color highlight grid with Remove option,
  /// Bottom button to open Study View.
  Widget _buildExpandedStage(
    BuildContext context,
    AppTokens tokens,
    double maxHeight,
    double bottomInset,
  ) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row: Reference & Close Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.verseLabel ??
                        '${widget.selectedCount} verse${widget.selectedCount == 1 ? '' : 's'} selected',
                    style: TextStyle(
                      color: tokens.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.onClear != null)
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        size: 20, color: tokens.onSurfaceMuted),
                    tooltip: 'Deselect',
                    onPressed: widget.onClear,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 2),

          // Row 1: Actions (Share, Copy, Bookmark, Note)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionItem(
                  icon: Icons.ios_share_rounded,
                  label: 'Share',
                  textColor: tokens.onSurface,
                  onPressed: widget.onShare,
                ),
                _ActionItem(
                  icon: Icons.copy_rounded,
                  label: 'Copy',
                  textColor: tokens.onSurface,
                  onPressed: widget.onCopy,
                ),
                _ActionItem(
                  icon: Icons.bookmark_add_outlined,
                  label: 'Bookmark',
                  textColor: tokens.onSurface,
                  onPressed: widget.onBookmark,
                ),
                _ActionItem(
                  icon: Icons.edit_note_rounded,
                  label: 'Note',
                  textColor: tokens.onSurface,
                  onPressed: widget.onNote,
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          Divider(height: 1, color: tokens.surfaceBorder),
          const SizedBox(height: 8),

          // Row 2: Full Highlight Grid (15 Colors)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Highlight',
                  style: TextStyle(
                    color: tokens.onSurfaceMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var i = 0; i < HighlightPalette.count; i++)
                        _ColorDot(
                          size: 32,
                          color: HighlightPalette.colorFor(i),
                          selected: widget.currentColorIndex == i,
                          onTap: () {
                            if (widget.onHighlightColor != null) {
                              widget.onHighlightColor!(i);
                            } else {
                              widget.onHighlight();
                            }
                          },
                        ),
                    ],
                  ),
                ),
                if (widget.hasHighlight && widget.onRemoveHighlight != null) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton.icon(
                      onPressed: widget.onRemoveHighlight,
                      icon: Icon(Icons.format_color_reset,
                          size: 16, color: tokens.onSurfaceMuted),
                      label: Text(
                        'Remove highlight',
                        style: TextStyle(
                            color: tokens.onSurfaceMuted, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Open Verse Study button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: InkWell(
              key: VerseActionBar.studyPromptKey,
              onTap: () =>
                  _animateTo(VerseSheetStage.study, maxHeight, bottomInset),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
                decoration: BoxDecoration(
                  color: tokens.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.surfaceBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_stories_outlined,
                        size: 16, color: tokens.accent),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Open Verse Study',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.accent,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded,
                        size: 16, color: tokens.accent),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// LEVEL 2: Full-height Verse Study Sheet
  Widget _buildStudyStage(
    BuildContext context,
    AppTokens tokens,
    double maxHeight,
    double bottomInset,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Study Header with collapse button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                key: VerseActionBar.collapseStudyKey,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 26),
                tooltip: 'Collapse',
                onPressed: () {
                  _animateTo(VerseSheetStage.expanded, maxHeight, bottomInset);
                },
              ),
              Expanded(
                child: Text(
                  widget.verseLabel != null
                      ? 'Study · ${widget.verseLabel}'
                      : 'Verse Study',
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.onClear != null)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'Deselect',
                  onPressed: widget.onClear,
                ),
            ],
          ),
        ),
        Divider(height: 1, color: tokens.surfaceBorder),

        // Study Hub Content
        Expanded(
          child: widget.studyContent ??
              Center(
                child: TextButton.icon(
                  onPressed: widget.onStudy,
                  icon: const Icon(Icons.auto_stories_outlined),
                  label: const Text('Open Verse Study'),
                ),
              ),
        ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final double size;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    final onColor = contrastColor(color);
    return Semantics(
      label: 'Highlight color',
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(
                    color: onColor == const Color(0xFFFFFFFF)
                        ? Colors.white
                        : Theme.of(context).colorScheme.primary,
                    width: 2.5,
                  )
                : Border.all(color: Colors.black.withValues(alpha: 0.12), width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: selected
              ? Icon(Icons.check, color: onColor, size: size * 0.55)
              : null,
        ),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.textColor,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color textColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: textColor, size: 22),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
