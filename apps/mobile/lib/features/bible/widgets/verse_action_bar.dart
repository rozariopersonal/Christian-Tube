import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/color_utils.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/highlight_palette.dart';
import '../../../shared/services/reader_appearance.dart';

/// Progressive disclosure stages for the Bible Verse Action Bottom Sheet.
enum VerseSheetStage {
  peek, // Stage 1: Quick highlight color dots (left) + Share & Copy (right)
  expanded, // Stage 2: Share, Copy, Bookmark, Note (row 1) + 15-color grid (row 2)
  study, // Stage 3: Embedded comprehensive Verse Study view
}

/// Draggable 3-stage bottom sheet for selected verses in the Bible Reader.
///
/// Complies with AGENTS.md standards:
/// - ScreenClass / MaxWidthBox capped at 640px on tablets/desktop
/// - Universal back & gesture dismiss (swiping down unselects verses)
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
  });

  @override
  State<VerseActionBar> createState() => _VerseActionBarState();
}

class _VerseActionBarState extends State<VerseActionBar>
    with SingleTickerProviderStateMixin {
  VerseSheetStage _stage = VerseSheetStage.peek;
  late final AnimationController _animController;
  Animation<double>? _heightAnimation;
  double _currentHeight = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
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

  double _targetHeightFor(VerseSheetStage stage, double maxHeight, double bottomInset) {
    switch (stage) {
      case VerseSheetStage.peek:
        return (78.0 + bottomInset).clamp(76.0, 104.0);
      case VerseSheetStage.expanded:
        final target = 360.0 + bottomInset;
        return target.clamp(300.0, maxHeight * 0.65);
      case VerseSheetStage.study:
        return (maxHeight * 0.90).clamp(380.0, maxHeight);
    }
  }

  void _animateTo(VerseSheetStage newStage, double maxHeight, double bottomInset) {
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
    _animController.forward(from: 0.0);
  }

  void _handleVerticalDragStart(DragStartDetails details) {
    _animController.stop();
    _isDragging = true;
  }

  void _handleVerticalDragUpdate(
    DragUpdateDetails details,
    double maxHeight,
    double bottomInset,
  ) {
    if (!_isDragging) return;
    setState(() {
      _currentHeight = (_currentHeight - details.delta.dy).clamp(0.0, maxHeight);
    });
  }

  void _handleVerticalDragEnd(
    DragEndDetails details,
    double maxHeight,
    double bottomInset,
  ) {
    _isDragging = false;
    final velocity = details.primaryVelocity ?? 0.0;
    final peekH = _targetHeightFor(VerseSheetStage.peek, maxHeight, bottomInset);
    final expandedH = _targetHeightFor(VerseSheetStage.expanded, maxHeight, bottomInset);
    final studyH = _targetHeightFor(VerseSheetStage.study, maxHeight, bottomInset);

    // Downward swipe from peek -> dismiss and deselect verses
    if (_currentHeight < peekH - 24.0 || (velocity > 300 && _stage == VerseSheetStage.peek)) {
      widget.onClear?.call();
      return;
    }

    if (velocity < -300) {
      // Fast upward fling
      if (_stage == VerseSheetStage.peek) {
        _animateTo(VerseSheetStage.expanded, maxHeight, bottomInset);
      } else if (_stage == VerseSheetStage.expanded) {
        _animateTo(VerseSheetStage.study, maxHeight, bottomInset);
      } else {
        _animateTo(VerseSheetStage.study, maxHeight, bottomInset);
      }
    } else if (velocity > 300) {
      // Fast downward fling
      if (_stage == VerseSheetStage.study) {
        _animateTo(VerseSheetStage.expanded, maxHeight, bottomInset);
      } else if (_stage == VerseSheetStage.expanded) {
        _animateTo(VerseSheetStage.peek, maxHeight, bottomInset);
      } else {
        widget.onClear?.call();
      }
    } else {
      // Positional threshold snapping
      final mid1 = (peekH + expandedH) / 2.0;
      final mid2 = (expandedH + studyH) / 2.0;

      if (_currentHeight < mid1) {
        if (_currentHeight < peekH * 0.70) {
          widget.onClear?.call();
        } else {
          _animateTo(VerseSheetStage.peek, maxHeight, bottomInset);
        }
      } else if (_currentHeight < mid2) {
        _animateTo(VerseSheetStage.expanded, maxHeight, bottomInset);
      } else {
        _animateTo(VerseSheetStage.study, maxHeight, bottomInset);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedCount == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final tokens = context.tokens;
    final isDark = theme.brightness == Brightness.dark ||
        (widget.appearance?.isDark(tokens) ?? false);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;

        // Initialize current height if first frame
        final peekH = _targetHeightFor(VerseSheetStage.peek, maxHeight, bottomInset);
        if (_currentHeight == 0.0 && !_isDragging) {
          _currentHeight = peekH;
        }

        // Calculate progress between stages (0: peek, 1: expanded, 2: study)
        final expandedH = _targetHeightFor(VerseSheetStage.expanded, maxHeight, bottomInset);
        final studyH = _targetHeightFor(VerseSheetStage.study, maxHeight, bottomInset);
        final double backdropAlpha;
        if (_currentHeight <= peekH) {
          backdropAlpha = 0.0;
        } else if (_currentHeight <= expandedH) {
          final t = ((_currentHeight - peekH) / (expandedH - peekH)).clamp(0.0, 1.0);
          backdropAlpha = t * 0.28;
        } else {
          final t = ((_currentHeight - expandedH) / (studyH - expandedH)).clamp(0.0, 1.0);
          backdropAlpha = 0.28 + (t * 0.22);
        }

        final sheetColor = isDark
            ? tokens.surface.withValues(alpha: 0.94)
            : tokens.surface.withValues(alpha: 0.96);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Dimmed backdrop (active only in Stage 2 & Stage 3)
            if (backdropAlpha > 0.01)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_stage == VerseSheetStage.study) {
                      _animateTo(VerseSheetStage.expanded, maxHeight, bottomInset);
                    } else {
                      _animateTo(VerseSheetStage.peek, maxHeight, bottomInset);
                    }
                  },
                  child: Container(
                    color: tokens.scrim.withValues(alpha: backdropAlpha),
                  ),
                ),
              ),

            // Draggable Sheet Container
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _currentHeight,
              child: GestureDetector(
                onVerticalDragStart: _stage == VerseSheetStage.study ? null : _handleVerticalDragStart,
                onVerticalDragUpdate: _stage == VerseSheetStage.study
                    ? null
                    : (d) => _handleVerticalDragUpdate(d, maxHeight, bottomInset),
                onVerticalDragEnd: _stage == VerseSheetStage.study
                    ? null
                    : (d) => _handleVerticalDragEnd(d, maxHeight, bottomInset),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: MaxWidthBox(
                    maxWidth: 640,
                    child: Container(
                      decoration: BoxDecoration(
                        color: sheetColor,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                        border: Border(
                          top: BorderSide(color: tokens.surfaceBorder, width: 0.8),
                          left: BorderSide(color: tokens.surfaceBorder, width: 0.5),
                          right: BorderSide(color: tokens.surfaceBorder, width: 0.5),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: tokens.scrim.withValues(alpha: isDark ? 0.40 : 0.16),
                            blurRadius: 18,
                            spreadRadius: 2,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
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
                                  // Drag Handle
                                  GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onVerticalDragStart: _handleVerticalDragStart,
                                    onVerticalDragUpdate: (d) =>
                                        _handleVerticalDragUpdate(d, maxHeight, bottomInset),
                                    onVerticalDragEnd: (d) =>
                                        _handleVerticalDragEnd(d, maxHeight, bottomInset),
                                    child: _DragHandle(tokens: tokens),
                                  ),

                                  // Stage Content
                                  Expanded(
                                    child: _buildStageContent(
                                      context,
                                      tokens,
                                      maxHeight,
                                      bottomInset,
                                    ),
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
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStageContent(
    BuildContext context,
    AppTokens tokens,
    double maxHeight,
    double bottomInset,
  ) {
    switch (_stage) {
      case VerseSheetStage.peek:
        return _buildPeekStage(context, tokens, maxHeight, bottomInset);
      case VerseSheetStage.expanded:
        return _buildExpandedStage(context, tokens, maxHeight, bottomInset);
      case VerseSheetStage.study:
        return _buildStudyStage(context, tokens, maxHeight, bottomInset);
    }
  }

  /// STAGE 1: Single compact row
  /// Left: quick highlight colors | Right: Share & Copy
  Widget _buildPeekStage(
    BuildContext context,
    AppTokens tokens,
    double maxHeight,
    double bottomInset,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Quick Highlight Color Dots (Left) - Flexible to avoid overflow on narrow screens
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final i in const [0, 1, 2, 4]) ...[
                    _ColorDot(
                      size: 26,
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
                    const SizedBox(width: 6),
                  ],
                  // Palette icon to expand to Stage 2
                  Tooltip(
                    message: 'More colors',
                    child: InkWell(
                      key: VerseActionBar.moreColorsKey,
                      onTap: () => _animateTo(VerseSheetStage.expanded, maxHeight, bottomInset),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: tokens.surfaceVariant,
                          shape: BoxShape.circle,
                          border: Border.all(color: tokens.surfaceBorder, width: 0.5),
                        ),
                        child: Icon(
                          Icons.palette_outlined,
                          size: 16,
                          color: tokens.onSurfaceMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Right Actions: Share & Copy
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CompactActionButton(
                icon: Icons.ios_share_rounded,
                label: 'Share',
                onTap: widget.onShare,
                tokens: tokens,
              ),
              const SizedBox(width: 6),
              _CompactActionButton(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: widget.onCopy,
                tokens: tokens,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// STAGE 2: Expanded Half-Sheet
  /// Context header, Action Row 1 (Share, Copy, Bookmark, Note),
  /// Row 2: Full 15-color highlight grid with Remove option,
  /// Bottom prompt to swipe up for Study View.
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
                    icon: Icon(Icons.close_rounded, size: 20, color: tokens.onSurfaceMuted),
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
                      icon: Icon(Icons.format_color_reset, size: 16, color: tokens.onSurfaceMuted),
                      label: Text(
                        'Remove highlight',
                        style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Swipe up for Study View prompter pill
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: InkWell(
              key: VerseActionBar.studyPromptKey,
              onTap: () => _animateTo(VerseSheetStage.study, maxHeight, bottomInset),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                decoration: BoxDecoration(
                  color: tokens.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.surfaceBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_stories_outlined, size: 16, color: tokens.accent),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Swipe up for Verse Study',
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
                    Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: tokens.accent),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// STAGE 3: Full-height Verse Study Sheet
  Widget _buildStudyStage(
    BuildContext context,
    AppTokens tokens,
    double maxHeight,
    double bottomInset,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Study Header with collapse button (also draggable down)
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: _handleVerticalDragStart,
          onVerticalDragUpdate: (d) =>
              _handleVerticalDragUpdate(d, maxHeight, bottomInset),
          onVerticalDragEnd: (d) =>
              _handleVerticalDragEnd(d, maxHeight, bottomInset),
          child: Padding(
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

class _DragHandle extends StatelessWidget {
  final AppTokens tokens;
  const _DragHandle({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(top: 8, bottom: 6),
        decoration: BoxDecoration(
          color: tokens.onSurfaceMuted.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
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

class _CompactActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final AppTokens tokens;

  const _CompactActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: tokens.surfaceVariant,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tokens.surfaceBorder, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: tokens.onSurface),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
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
