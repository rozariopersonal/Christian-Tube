import 'package:flutter/material.dart';

import '../../core/dimens.dart';
import '../../core/layout/shell_back_handler.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/highlight_palette.dart';
import '../services/highlight_usage_service.dart';

/// One icon action in a [FloatingSelectionBar].
class SelectionBarAction {
  const SelectionBarAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
    this.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isActive;
  final Key? key;
}

/// A text entry in the bar's trailing overflow menu.
class SelectionBarMenuItem {
  const SelectionBarMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Floating, single-line selection action bar shared by every reader.
///
/// Layout: `[ ● ● ● ⌄ ] | icon icon icon ⋯`
/// * The first three swatches are the user's most-used highlight colours
///   ([HighlightUsageService]), snapshotted when the bar appears so they never
///   reorder under the finger.
/// * The chevron expands an in-place panel above the row with the full
///   [HighlightPalette]; the row itself never wraps.
class FloatingSelectionBar extends StatefulWidget {
  const FloatingSelectionBar({
    super.key,
    required this.actions,
    required this.onSwatch,
    this.onClearHighlight,
    this.currentColorIndex,
    this.hasHighlight = false,
    this.overflow = const [],
    this.onDismiss,
    this.countBadge,
    this.usage,
  });

  final List<SelectionBarAction> actions;
  final ValueChanged<int> onSwatch;
  final VoidCallback? onClearHighlight;
  final int? currentColorIndex;
  final bool hasHighlight;
  final List<SelectionBarMenuItem> overflow;

  /// Invoked on Back once the palette panel is collapsed.
  final VoidCallback? onDismiss;

  /// Optional small count (e.g. selected verses) shown before the swatches.
  final int? countBadge;

  /// Overridable for tests.
  final HighlightUsageService? usage;

  static const double maxBarWidth = 420;
  static const expandKey = Key('selection_bar_expand');
  static const panelKey = Key('selection_bar_panel');
  static const clearKey = Key('selection_bar_clear');
  static const overflowKey = Key('selection_bar_overflow');
  static Key swatchKey(int index) => Key('selection_bar_swatch_$index');
  static Key panelSwatchKey(int index) =>
      Key('selection_bar_panel_swatch_$index');

  @override
  State<FloatingSelectionBar> createState() => _FloatingSelectionBarState();
}

class _FloatingSelectionBarState extends State<FloatingSelectionBar> {
  late final VoidCallback _removeBackInterceptor;
  late List<int> _topColors;
  bool _expanded = false;

  HighlightUsageService get _usage =>
      widget.usage ?? HighlightUsageService.instance;

  @override
  void initState() {
    super.initState();
    _topColors = _usage.topColors();
    if (!_usage.isLoaded) {
      _usage.load().then((_) {
        if (mounted) setState(() => _topColors = _usage.topColors());
      });
    }
    _removeBackInterceptor = ShellBackHandler.registerInterceptor(_handleBack);
  }

  @override
  void dispose() {
    _removeBackInterceptor();
    super.dispose();
  }

  bool _handleBack() {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return false;
    if (_expanded) {
      setState(() => _expanded = false);
      return true;
    }
    if (widget.onDismiss == null) return false;
    widget.onDismiss!();
    return true;
  }

  void _pick(int index) {
    _usage.record(index);
    final toggleOff =
        index == widget.currentColorIndex && widget.onClearHighlight != null;
    if (_expanded) setState(() => _expanded = false);
    if (toggleOff) {
      widget.onClearHighlight!();
    } else {
      widget.onSwatch(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final width = MediaQuery.sizeOf(context).width;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: (width - 24).clamp(0.0, FloatingSelectionBar.maxBarWidth),
      ),
      child: Material(
        color: tokens.surface,
        elevation: 8,
        shadowColor: tokens.scrim,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          side: BorderSide(color: tokens.surfaceBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: _expanded
                  ? _buildPanel(context)
                  : const SizedBox(width: double.infinity),
            ),
            _buildRow(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      key: FloatingSelectionBar.panelKey,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.surfaceBorder)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: [
          for (var i = 0; i < HighlightPalette.count; i++)
            _Swatch(
              key: FloatingSelectionBar.panelSwatchKey(i),
              index: i,
              selected: widget.currentColorIndex == i,
              onTap: () => _pick(i),
            ),
          if (widget.hasHighlight && widget.onClearHighlight != null)
            _IconTap(
              key: FloatingSelectionBar.clearKey,
              icon: Icons.format_color_reset_rounded,
              tooltip: 'Remove highlight',
              onTap: () {
                setState(() => _expanded = false);
                widget.onClearHighlight!();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.countBadge != null && widget.countBadge! > 1)
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 2),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: tokens.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                  ),
                  child: Text(
                    '${widget.countBadge}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: tokens.onSurface,
                        ),
                  ),
                ),
              ),
            for (final idx in _topColors)
              _Swatch(
                key: FloatingSelectionBar.swatchKey(idx),
                index: idx,
                selected: widget.currentColorIndex == idx,
                onTap: () => _pick(idx),
              ),
            _IconTap(
              key: FloatingSelectionBar.expandKey,
              icon: _expanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              tooltip: _expanded ? 'Fewer colours' : 'More colours',
              onTap: () => setState(() => _expanded = !_expanded),
            ),
            Container(
              width: 1,
              height: 22,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: tokens.surfaceBorder,
            ),
            for (final a in widget.actions)
              _IconTap(
                key: a.key,
                icon: a.icon,
                tooltip: a.tooltip,
                isActive: a.isActive,
                onTap: () {
                  if (_expanded) setState(() => _expanded = false);
                  a.onTap();
                },
              ),
            if (widget.overflow.isNotEmpty)
              PopupMenuButton<int>(
                key: FloatingSelectionBar.overflowKey,
                tooltip: 'More actions',
                icon: Icon(Icons.more_horiz_rounded,
                    size: 22, color: tokens.onSurface),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
                onSelected: (i) => widget.overflow[i].onTap(),
                itemBuilder: (context) => [
                  for (var i = 0; i < widget.overflow.length; i++)
                    PopupMenuItem<int>(
                      value: i,
                      child: Row(
                        children: [
                          Icon(widget.overflow[i].icon, size: 20),
                          const SizedBox(width: 12),
                          Text(widget.overflow[i].label),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final name = HighlightPalette.nameFor(index);
    return Tooltip(
      message: 'Highlight ($name)',
      child: Semantics(
        label: 'Highlight $name',
        button: true,
        selected: selected,
        child: InkResponse(
          onTap: onTap,
          radius: 20,
          child: SizedBox(
            width: 30,
            height: 44,
            child: Center(
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: HighlightPalette.colorFor(index),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? tokens.onSurface : tokens.surfaceBorder,
                    width: selected ? 2 : 1.2,
                  ),
                ),
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: HighlightPalette.onColorFor(index),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconTap extends StatelessWidget {
  const _IconTap({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        button: true,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: SizedBox(
            width: 36,
            height: 44,
            child: Center(
              child: Icon(
                icon,
                size: 22,
                color: isActive ? context.accent : tokens.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
