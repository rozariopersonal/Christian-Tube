import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/dimens.dart';
import '../../../core/layout/shell_back_handler.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/services/reader_appearance.dart';
import 'verse_action_sheet_body.dart';

/// A single-stage action sheet. Verse Study opens a separate pushed page.
class VerseActionBar extends StatefulWidget {
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
  });

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
  final ValueChanged<int>? onHighlightColor;
  final VoidCallback? onRemoveHighlight;
  final int? currentColorIndex;
  final bool hasHighlight;
  final String? verseLabel;

  static const studyPromptKey = Key('verse_sheet_study_prompt');
  static const closeButtonKey = Key('verse_sheet_close_button');

  @override
  State<VerseActionBar> createState() => _VerseActionBarState();
}

class _VerseActionBarState extends State<VerseActionBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  late final Animation<Offset> _slide;
  late final VoidCallback _removeBackInterceptor;
  bool _didDismiss = false;

  @override
  void initState() {
    super.initState();
    _animation = BottomSheet.createAnimationController(this)
      ..addStatusListener(_onAnimationStatus);
    _slide =
        Tween(begin: const Offset(0, 1), end: Offset.zero).animate(_animation);
    _removeBackInterceptor = ShellBackHandler.registerInterceptor(_handleBack);
    _animation.forward();
  }

  @override
  void dispose() {
    _removeBackInterceptor();
    _animation.dispose();
    super.dispose();
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !_didDismiss) {
      _didDismiss = true;
      widget.onClear?.call();
    }
  }

  bool _handleBack() {
    // A pushed Study page owns Back while this sheet stays in the reader.
    if (!mounted ||
        widget.selectedCount == 0 ||
        ModalRoute.of(context)?.isCurrent == false ||
        widget.onClear == null) {
      return false;
    }
    widget.onClear!();
    return true;
  }

  void _dismiss() => _animation.reverse();

  @override
  Widget build(BuildContext context) {
    if (widget.selectedCount == 0) return const SizedBox.shrink();
    final tokens = context.tokens;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height;
          return Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: widget.margin ?? EdgeInsets.zero,
              child: ClipRect(
                child: SlideTransition(
                  position: _slide,
                  child: Listener(
                    // Recover a partial drag when the pointer is canceled.
                    onPointerCancel: (_) {
                      if (!_animation.isAnimating && !_didDismiss) {
                        _animation.forward();
                      }
                    },
                    child: BottomSheet(
                      animationController: _animation,
                      onClosing: _dismiss,
                      enableDrag: widget.onClear != null,
                      showDragHandle: widget.onClear != null,
                      backgroundColor: tokens.surface,
                      shadowColor: tokens.scrim,
                      elevation: 8,
                      clipBehavior: Clip.antiAlias,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(AppDimens.radiusLg),
                        ),
                      ),
                      constraints: BoxConstraints(
                        maxWidth: 640,
                        maxHeight: math.min(
                          370 + MediaQuery.paddingOf(context).bottom,
                          availableHeight * 0.85,
                        ),
                      ),
                      builder: (context) => SafeArea(
                        top: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: AppDimens.contentPadding,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.verseLabel ??
                                          '${widget.selectedCount} verses selected',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (widget.onClear != null)
                                    IconButton(
                                      key: VerseActionBar.closeButtonKey,
                                      onPressed: widget.onClear,
                                      tooltip: 'Deselect',
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                                ],
                              ),
                            ),
                            Flexible(
                              child: SingleChildScrollView(
                                child: VerseActionSheetBody(
                                  onCopy: widget.onCopy,
                                  onShare: widget.onShare,
                                  onBookmark: widget.onBookmark,
                                  onNote: widget.onNote,
                                  onHighlight: widget.onHighlight,
                                  onHighlightColor: widget.onHighlightColor,
                                  onRemoveHighlight: widget.onRemoveHighlight,
                                  currentColorIndex: widget.currentColorIndex,
                                  hasHighlight: widget.hasHighlight,
                                ),
                              ),
                            ),
                            if (widget.onStudy != null)
                              Padding(
                                padding: AppDimens.contentPadding.copyWith(
                                  bottom: AppDimens.sm,
                                ),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.tonalIcon(
                                    key: VerseActionBar.studyPromptKey,
                                    onPressed: widget.onStudy,
                                    icon:
                                        const Icon(Icons.auto_stories_outlined),
                                    label: const Text('Open Verse Study'),
                                  ),
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
          );
        },
      ),
    );
  }
}
