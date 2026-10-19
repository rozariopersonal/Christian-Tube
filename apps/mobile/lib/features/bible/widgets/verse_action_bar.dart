import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/color_utils.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/layout/shell_back_handler.dart';
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
  static const closeButtonKey = Key('verse_sheet_close_button');

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
  VoidCallback? _backInterceptorRemover;
  double _dragStartY = 0.0;
  double _dragStartHeight = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _stage = VerseSheetStage.expanded;
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
    _backInterceptorRemover =
        ShellBackHandler.registerInterceptor(_handleBackAction);
  }

  @override
  void dispose() {
    _backInterceptorRemover?.call();
    _backInterceptorRemover = null;
    _animController.dispose();
    super.dispose();
  }

  bool _handleBackAction() {
    if (!mounted || widget.selectedCount == 0) return false;
    final maxHeight = MediaQuery.sizeOf(context).height;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    if (_stage == VerseSheetStage.study) {
      _animateTo(VerseSheetStage.expanded, maxHeight, bottomInset);
      return true;
    }
    if (widget.onClear != null) {
      widget.onClear!();
      return true;
    }
    return false;
  }

  double _targetHeightFor(
      VerseSheetStage stage, double maxHeight, double bottomInset) {
    switch (stage) {
      case VerseSheetStage.expanded:
        final desired = 370.0 + bottomInset;
        final maxAllowed = maxHeight * 0.85;
        return desired > maxAllowed ? maxAllowed : desired;
      case VerseSheetStage.study:
        final topInset = MediaQuery.paddingOf(context).top;
        final desired = maxHeight - (topInset > 0 ? topInset : 8.0);
        return desired > maxHeight ? maxHeight : desired;
    }
  }

  void _animateTo(
      VerseSheetStage newStage, double maxHeight, double bottomInset) {
    final target = _targetHeightFor(newStage, maxHeight, bottomInset);
    if (_stage == newStage && (_currentHeight - target).abs() < 1.0) return;
    _animController.stop();
    final startH = _currentHeight == 0.0
        ? _targetHeightFor(_stage, maxHeight, bottomInset)
        : _currentHeight;
    _heightAnimation = Tween<double>(
      begin: startH,
      end: target,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    if (_stage != newStage) {
      setState(() {
        _stage = newStage;
      });
      widget.onStageChanged?.call(newStage);
    }
    _animController.forward(from: 0.0);
  }

  void _dismissSheet(double maxHeight, double bottomInset) {
    _animController.stop();
    _heightAnimation = Tween<double>(
      begin: _currentHeight,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInCubic,
    ));
    _animController.forward(from: 0.0).then((_) {
      if (mounted) {
        widget.onClear?.call();
      }
    });
  }

  void _onDragStart(DragStartDetails details) {
    _animController.stop();
    _isDragging = true;
    _dragStartY = details.globalPosition.dy;
    _dragStartHeight = _currentHeight;
  }

  void _onDragUpdate(
      DragUpdateDetails details, double maxHeight, double bottomInset) {
    final delta = _dragStartY - details.globalPosition.dy;
    final studyH = _targetHeightFor(VerseSheetStage.study, maxHeight, bottomInset);
    setState(() {
      _currentHeight = (_dragStartHeight + delta).clamp(0.0, studyH);
    });
  }

  void _onDragEnd(
      DragEndDetails details, double maxHeight, double bottomInset) {
    _isDragging = false;
    final velocity = details.primaryVelocity ?? 0.0;
    final expandedH = _targetHeightFor(VerseSheetStage.expanded, maxHeight, bottomInset);
    final studyH = _targetHeightFor(VerseSheetStage.study, maxHeight, bottomInset);

    if (_stage == VerseSheetStage.expanded) {
      if (velocity < -250 || _currentHeight > expandedH + 45) {
        _animateTo(VerseSheetStage.study, maxHeight, bottomInset);
      } else if (velocity > 250 || _currentHeight < expandedH * 0.75) {
        _dismissSheet(maxHeight, bottomInset);
      } else {
        _animateTo(VerseSheetStage.expanded, maxHeight, bottomInset);
      }
    } else {
      if (velocity > 850 || _currentHeight < expandedH * 0.65) {
        _dismissSheet(maxHeight, bottomInset);
      } else if (velocity > 250 || _currentHeight < (studyH + expandedH) / 2) {
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackAction();
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

          if (!_isDragging && !_animController.isAnimating) {
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
                          top: _stage == VerseSheetStage.study,
                          bottom: false,
                          child: _stage == VerseSheetStage.expanded
                              ? GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onVerticalDragStart: _onDragStart,
                                  onVerticalDragUpdate: (d) =>
                                      _onDragUpdate(d, maxHeight, bottomInset),
                                  onVerticalDragEnd: (d) =>
                                      _onDragEnd(d, maxHeight, bottomInset),
                                  child: SingleChildScrollView(
                                    physics: const ClampingScrollPhysics(),
                                    child: _buildExpandedStage(
                                        context, tokens, maxHeight, bottomInset),
                                  ),
                                )
                              : _buildStudyStage(
                                  context, tokens, maxHeight, bottomInset),
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
  /// Context header with close button, Action Row (Share, Copy, Bookmark, Note),
  /// Highlight Grid (15 Colors), and pull-up Verse Study section below highlight.
  Widget _buildExpandedStage(
    BuildContext context,
    AppTokens tokens,
    double maxHeight,
    double bottomInset,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top drag handle indicator
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 38,
            height: 4.5,
            decoration: BoxDecoration(
              color: tokens.onSurfaceMuted.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
        ),

        // Header Row: Reference & Close [X] Button
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
                  key: VerseActionBar.closeButtonKey,
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

        const SizedBox(height: 10),

        // Verse Study section below highlight: Pull-up card
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: InkWell(
            key: VerseActionBar.studyPromptKey,
            onTap: () =>
                _animateTo(VerseSheetStage.study, maxHeight, bottomInset),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
              decoration: BoxDecoration(
                color: tokens.surfaceVariant,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: tokens.surfaceBorder),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.auto_stories_outlined,
                        size: 18, color: tokens.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Open Verse Study',
                          style: TextStyle(
                            color: tokens.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Pull up to study concepts, references & commentary',
                          style: TextStyle(
                            color: tokens.onSurfaceMuted,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.keyboard_arrow_up_rounded,
                      size: 20, color: tokens.accent),
                ],
              ),
            ),
          ),
        ),
      ],
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
        // Study Header with drag handle, collapse chevron, title & close button
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: _onDragStart,
          onVerticalDragUpdate: (d) =>
              _onDragUpdate(d, maxHeight, bottomInset),
          onVerticalDragEnd: (d) =>
              _onDragEnd(d, maxHeight, bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: tokens.onSurfaceMuted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      key: VerseActionBar.collapseStudyKey,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          size: 26),
                      tooltip: 'Collapse',
                      onPressed: () {
                        _animateTo(
                            VerseSheetStage.expanded, maxHeight, bottomInset);
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
                        key: VerseActionBar.closeButtonKey,
                        icon: const Icon(Icons.close_rounded, size: 20),
                        tooltip: 'Deselect',
                        onPressed: widget.onClear,
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: tokens.surfaceBorder),
            ],
          ),
        ),

        // Scrollable Study Hub Content
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
