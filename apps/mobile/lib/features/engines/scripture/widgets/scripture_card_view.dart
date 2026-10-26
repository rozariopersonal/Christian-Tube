import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/micro_feed/widgets/card_scrim_overlay.dart';
import 'package:mobile/core/widgets/animated_fluid_gradient.dart';
import '../models/scripture_card.dart';
import '../models/scripture_filter_state.dart';
import '../models/scripture_theme_state.dart';
import '../services/bible_download_manager.dart';
import '../services/scripture_service.dart';

class ScriptureCardView extends StatefulWidget {
  final ScriptureCard card;
  final ScriptureFilterState filterState;
  final bool isActive;
  final ValueChanged<int>? onEdgePageShift;
  final VoidCallback? onReferenceTap;
  final VoidCallback? onCardTap;

  const ScriptureCardView({
    super.key,
    required this.card,
    required this.filterState,
    required this.isActive,
    this.onEdgePageShift,
    this.onReferenceTap,
    this.onCardTap,
  });

  @override
  State<ScriptureCardView> createState() => _ScriptureCardViewState();
}

class _ScriptureCardViewState extends State<ScriptureCardView>
    with SingleTickerProviderStateMixin {
  final ScriptureService _service = ScriptureService();
  String? _displayedText;
  String? _displayedVersion;
  bool _isResolving = false;
  String? _lastAttemptedVersion;
  double _edgeDragDelta = 0;

  late final AnimationController _entranceController;
  late final Animation<double> _quoteFade;
  late final Animation<double> _quoteScale;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _badgeFade;
  late final Animation<Offset> _badgeSlide;

  bool _hasScrollableText = false;
  final ScrollController _textScrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _quoteFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );
    _quoteScale = Tween<double>(begin: 0.80, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.50, curve: Curves.easeOutBack),
      ),
    );

    _textFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.12, 0.85, curve: Curves.easeOut),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0.0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.12, 0.90, curve: Curves.easeOutCubic),
      ),
    );

    _badgeFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.30, 1.0, curve: Curves.easeOut),
    );
    _badgeSlide = Tween<Offset>(
      begin: const Offset(0.0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.30, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    if (widget.isActive) {
      _entranceController.forward();
    } else {
      _entranceController.value = 1.0;
    }

    final targetVersion = widget.filterState.activeVersionId;
    if (widget.card.resolvedVersion == targetVersion &&
        widget.card.resolvedText != null) {
      _displayedText = widget.card.resolvedText;
      _displayedVersion = targetVersion;
    } else {
      final syncText = _service.resolvePassageSync(widget.card, targetVersion);
      if (syncText != null) {
        widget.card.resolvedText = syncText;
        widget.card.resolvedVersion = targetVersion;
        _displayedText = syncText;
        _displayedVersion = targetVersion;
      } else {
        _displayedText = null;
        _displayedVersion = null;
        _checkAndResolveVersion();
      }
    }
    final comparison = widget.filterState.comparisonVersionId;
    if (comparison != null && widget.card.comparisonVersion != comparison) {
      _resolveComparison();
    }
  }

  @override
  void didUpdateWidget(covariant ScriptureCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _entranceController.forward(from: 0.0);
      } else {
        _entranceController.reset();
      }
    }
    if (oldWidget.filterState.activeVersionId !=
            widget.filterState.activeVersionId ||
        oldWidget.card.id != widget.card.id ||
        widget.card.resolvedVersion != widget.filterState.activeVersionId ||
        _displayedVersion != widget.filterState.activeVersionId) {
      _checkAndResolveVersion();
    }
    if (oldWidget.filterState.comparisonVersionId !=
            widget.filterState.comparisonVersionId ||
        (widget.filterState.comparisonVersionId != null &&
            widget.card.comparisonVersion !=
                widget.filterState.comparisonVersionId)) {
      _resolveComparison();
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _textScrollController.dispose();
    super.dispose();
  }

  Future<void> _resolveComparison() async {
    final comparison = widget.filterState.comparisonVersionId;
    if (comparison == null ||
        comparison == widget.filterState.activeVersionId) {
      widget.card.comparisonText = null;
      widget.card.comparisonVersion = null;
      return;
    }
    await _service.resolveCardComparisonText(widget.card, comparison);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _checkAndResolveVersion() async {
    // Guard against concurrent resolutions for the same version / redundant retries
    if (_isResolving) return;
    final targetVersion = widget.filterState.activeVersionId;
    if (_displayedVersion == targetVersion && _displayedText != null) return;
    if (_lastAttemptedVersion == targetVersion && widget.card.resolvedVersion == targetVersion) return;

    _lastAttemptedVersion = targetVersion;
    _isResolving = true;
    try {
      final syncText = _service.resolvePassageSync(widget.card, targetVersion);
      if (syncText != null) {
        widget.card.resolvedText = syncText;
        widget.card.resolvedVersion = targetVersion;
        if (mounted) {
          setState(() {
            _displayedText = syncText;
            _displayedVersion = targetVersion;
          });
        }
        return;
      }

      await _service.resolveCardText(widget.card, targetVersion);
      if (mounted) {
        if (widget.card.resolvedVersion == targetVersion && widget.card.resolvedText != null) {
          setState(() {
            _displayedText = widget.card.resolvedText;
            _displayedVersion = targetVersion;
          });
        } else {
          // If resolution failed to obtain targetVersion, reset attempt so it can retry
          _lastAttemptedVersion = null;
        }
      }
    } catch (_) {
      _lastAttemptedVersion = null;
    } finally {
      _isResolving = false;
    }
  }


  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final preset = ScriptureThemeCatalog.getPreset(widget.card.activeBackground);
    final targetVersion = widget.filterState.activeVersionId;

    String primaryText;
    String primaryVersionId;
    bool primaryIsFallback = false;

    if (_displayedVersion == targetVersion && _displayedText != null) {
      primaryText = _displayedText!;
      primaryVersionId = targetVersion;
    } else if (widget.card.resolvedVersion == targetVersion && widget.card.resolvedText != null) {
      primaryText = widget.card.resolvedText!;
      primaryVersionId = targetVersion;
    } else {
      final syncText = _service.resolvePassageSync(widget.card, targetVersion);
      if (syncText != null) {
        primaryText = syncText;
        primaryVersionId = targetVersion;
      } else if (widget.card.resolvedText != null) {
        primaryText = widget.card.resolvedText!;
        primaryVersionId = widget.card.resolvedVersion ?? targetVersion;
      } else {
        primaryText = '“Peace I leave with you; my peace I give you. Do not let your hearts be troubled.”';
        primaryVersionId = targetVersion;
        primaryIsFallback = true;
      }
    }

    // Comparison column (secondary version) — read from the card's pre-resolved
    // state with a synchronous local lookup as a fast path.
    String? comparisonText;
    String? comparisonVersionId;
    final desiredComparison = widget.filterState.comparisonVersionId;
    if (desiredComparison != null && desiredComparison != targetVersion) {
      String? text;
      String? version;
      if (widget.card.comparisonVersion == desiredComparison &&
          widget.card.comparisonText != null) {
        text = widget.card.comparisonText;
        version = desiredComparison;
      } else {
        final syncText =
            _service.resolvePassageSync(widget.card, desiredComparison);
        if (syncText != null) {
          text = syncText;
          version = desiredComparison;
        }
      }
      // "Pick the best": if the active version has no real text yet, promote
      // the comparison text to the primary (hero) slot instead of the
      // hardcoded placeholder so the feed never shows dead text.
      if (primaryIsFallback && text != null) {
        primaryText = text;
        primaryVersionId = version!;
        primaryIsFallback = false;
      } else {
        comparisonText = text;
        comparisonVersionId = version;
      }
    }

    final primaryMeta = BibleDownloadManager.getMeta(primaryVersionId);
    final comparisonMeta = comparisonVersionId != null
        ? BibleDownloadManager.getMeta(comparisonVersionId)
        : null;

    final screenHeight = MediaQuery.sizeOf(context).height;
    final heightFactor = (screenHeight / 800.0).clamp(0.75, 1.15);

    final double effectiveFontSize =
        _dynamicFontSize(primaryText, heightFactor) * widget.filterState.fontSizeScale;

    final comparisonFontSize = comparisonText != null
        ? _dynamicFontSize(comparisonText, heightFactor) * 0.75 * widget.filterState.fontSizeScale
        : 0.0;

    final activeFontFamily =
        widget.card.customFontFamily ?? widget.filterState.activeFontFamily;
    Color textColor =
        ScriptureThemeCatalog.parseColor(widget.filterState.textColorHex);
    if (!context.isDark && widget.filterState.textColorHex == '#FFFFFF') {
      textColor = preset.resolveTextColor(context);
    }
    final fontWeight =
        widget.filterState.isBold ? FontWeight.w700 : FontWeight.w400;
    final fontStyle =
        widget.filterState.isItalic ? FontStyle.italic : FontStyle.normal;

    final TextAlign textAlign;
    switch (widget.filterState.textAlign) {
      case 'left':
        textAlign = TextAlign.left;
        break;
      case 'right':
        textAlign = TextAlign.right;
        break;
      case 'center':
      default:
        textAlign = TextAlign.center;
        break;
    }

    final List<Shadow>? textShadows = context.isDark
        ? [
            Shadow(
              color: tokens.scrim,
              blurRadius: 16,
              offset: const Offset(0, 2),
            ),
            Shadow(
              color: tokens.scrim.withValues(alpha: 0.54),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ]
        : null;

    final textStyle = ScriptureThemeCatalog.getTextStyle(
      fontFamily: activeFontFamily,
      languageCode: primaryMeta.languageCode,
      baseSize: effectiveFontSize,
      color: textColor,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
    );


    final double scrimOpacity = context.isDark
        ? (preset.isGradient ? 0.20 : 0.0)
        : 0.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Floating Scripture Card Container (Background scoped strictly inside)
        Positioned.fill(
          top: 60.0,
          bottom: 20.0,
          left: 16.0,
          right: 16.0,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: tokens.surfaceBorder,
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: tokens.scrim
                          .withValues(alpha: context.isDark ? 0.35 : 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // A. Wallpaper / Gradient Background Layer (scoped strictly inside card)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        switchInCurve: Curves.easeInOut,
                        switchOutCurve: Curves.easeInOut,
                        child: KeyedSubtree(
                          key: ValueKey('${preset.id}_${context.isDark}'),
                          child: _buildBackground(preset),
                        ),
                      ),

                      // B. Readability Gradient Scrim
                      if (scrimOpacity > 0.0) CardScrimOverlay(opacity: scrimOpacity),

                      // C. Typographic Content Canvas
                      GestureDetector(
                        onTap: widget.onCardTap,
                        behavior: HitTestBehavior.translucent,
                        child: Center(
                          child: NotificationListener<ScrollMetricsNotification>(
                            onNotification: (notification) {
                              final canScroll = notification.metrics.maxScrollExtent > 4.0;
                              if (canScroll != _hasScrollableText) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) {
                                    setState(() {
                                      _hasScrollableText = canScroll;
                                    });
                                  }
                                });
                              }
                              return false;
                            },
                            child: SingleChildScrollView(
                              controller: _textScrollController,
                              physics: _hasScrollableText
                                  ? const ClampingScrollPhysics()
                                  : const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(
                                left: 20,
                                right: 20,
                                top: 28,
                                bottom: 64, // Space for pinned reference badge
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Opening Quote Mark (Stagger 1)
                                  FadeTransition(
                                    opacity: _quoteFade,
                                    child: ScaleTransition(
                                      scale: _quoteScale,
                                      child: Text(
                                        '"',
                                        style: TextStyle(
                                          fontSize: 48,
                                          height: 0.8,
                                          fontFamily: 'serif',
                                          color: context.accent.withValues(alpha: 0.9),
                                          shadows: context.isDark
                                              ? [
                                                  Shadow(
                                                    color: tokens.scrim.withValues(alpha: 0.87),
                                                    blurRadius: 12,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // Primary Verse Body Text (Stagger 2)
                                  FadeTransition(
                                    opacity: _textFade,
                                    child: SlideTransition(
                                      position: _textSlide,
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 250),
                                        transitionBuilder: (child, animation) {
                                          return FadeTransition(
                                            opacity: animation,
                                            child: SlideTransition(
                                              position: Tween<Offset>(
                                                begin: const Offset(0.0, 0.04),
                                                end: Offset.zero,
                                              ).animate(animation),
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: Text(
                                          primaryText,
                                          key: ValueKey(
                                              '${primaryVersionId}_${primaryText.hashCode}_${widget.filterState.textColorHex}_${activeFontFamily}_${widget.filterState.fontSizeScale}_${widget.filterState.isBold}_${widget.filterState.isItalic}_${widget.filterState.textAlign}'),
                                          textAlign: textAlign,
                                          softWrap: true,
                                          textWidthBasis: TextWidthBasis.parent,
                                          style: textStyle.copyWith(
                                            color: textColor,
                                            shadows: textShadows,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (comparisonText != null &&
                                      comparisonVersionId != null) ...[
                                    const SizedBox(height: 18),
                                    Divider(
                                      color: context.tokens.onSurfaceDisabled.withValues(alpha: 0.3),
                                      height: 1,
                                      indent: 40,
                                      endIndent: 40,
                                    ),
                                    const SizedBox(height: 14),

                                    // Secondary Verse Body Text
                                    FadeTransition(
                                      opacity: _badgeFade,
                                      child: SlideTransition(
                                        position: _badgeSlide,
                                        child: Text(
                                          comparisonText,
                                          textAlign: textAlign,
                                          softWrap: true,
                                          textWidthBasis: TextWidthBasis.parent,
                                          style: ScriptureThemeCatalog.getTextStyle(
                                            fontFamily: activeFontFamily,
                                            languageCode:
                                                comparisonMeta?.languageCode ?? 'en',
                                            baseSize: comparisonFontSize,
                                            color: context.isDark
                                                ? tokens.onScrim.withValues(alpha: 0.88)
                                                : tokens.onSurfaceMuted,
                                            fontWeight: FontWeight.w400,
                                            fontStyle: FontStyle.italic,
                                          ).copyWith(shadows: textShadows),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // D. Pinned Bottom Reference Badge (inside card)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12.0,
                        child: Center(
                          child: FadeTransition(
                            opacity: _badgeFade,
                            child: SlideTransition(
                              position: _badgeSlide,
                              child: _ReferenceBadge(
                                reference: '— ${widget.card.referenceLabel}',
                                versionId: primaryVersionId,
                                comparisonVersionId: comparisonVersionId,
                                onTap: widget.onReferenceTap ?? widget.onCardTap,
                              ),
                            ),
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

        // 2. Left & Right Edge-Margin Swipe Zones (Outside card / edge-paging fallback)
        Positioned(
          left: 0,
          top: 60,
          bottom: 20,
          width: 36,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (_) => _edgeDragDelta = 0,
            onVerticalDragUpdate: (d) =>
                _edgeDragDelta += (d.primaryDelta ?? 0),
            onVerticalDragEnd: (details) {
              final vy = details.primaryVelocity ?? 0;
              if (vy < -150 || _edgeDragDelta < -40) {
                widget.onEdgePageShift?.call(1);
              } else if (vy > 150 || _edgeDragDelta > 40) {
                widget.onEdgePageShift?.call(-1);
              }
              _edgeDragDelta = 0;
            },
          ),
        ),
        Positioned(
          right: 0,
          top: 60,
          bottom: 20,
          width: 36,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (_) => _edgeDragDelta = 0,
            onVerticalDragUpdate: (d) =>
                _edgeDragDelta += (d.primaryDelta ?? 0),
            onVerticalDragEnd: (details) {
              final vy = details.primaryVelocity ?? 0;
              if (vy < -150 || _edgeDragDelta < -40) {
                widget.onEdgePageShift?.call(1);
              } else if (vy > 150 || _edgeDragDelta > 40) {
                widget.onEdgePageShift?.call(-1);
              }
              _edgeDragDelta = 0;
            },
          ),
        ),
      ],
    );
  }

  static final RegExp _whitespaceRegExp = RegExp(r'\s+');

  double _dynamicFontSize(String text, double heightFactor) {
    // Auto-calculate dynamic font size based on verse text length, longest
    // word, screen height & user scale
    final words = text.split(_whitespaceRegExp);
    int maxWordLength = 0;
    for (final w in words) {
      if (w.length > maxWordLength) maxWordLength = w.length;
    }

    final length = text.length;
    double dynamicBaseSize =
        ((28.0 - (length / 32.0)).clamp(15.0, 26.0) * heightFactor);

    // If verse has extra long compound words (e.g. Indic words with 12+ chars),
    // apply a gentle penalty so words wrap naturally without collapsing font size.
    if (maxWordLength > 12) {
      final wordLengthPenalty = (maxWordLength - 12) * 0.2;
      dynamicBaseSize = (dynamicBaseSize - wordLengthPenalty).clamp(16.0, 26.0);
    }
    return dynamicBaseSize;
  }

  Widget _buildBackground(BackgroundPreset preset) {
    final tokens = context.tokens;
    final colors = preset.resolveColors(context);

    if (preset.isGradient) {
      if (preset.isAnimatedGradient) {
        return AnimatedFluidGradient(
          colors: colors,
          overlayOpacity: context.isDark ? 0.20 : 0.0,
          animate: widget.isActive,
        );
      }
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
      );
    } else {
      return Container(
        color: colors.isNotEmpty
            ? colors.first
            : (context.isDark ? tokens.scrim : tokens.background),
      );
    }
  }
}

/// Small attribution pill showing a reference label plus a version badge.
class _ReferenceBadge extends StatelessWidget {
  final String reference;
  final String versionId;
  final String? comparisonVersionId;
  final VoidCallback? onTap;

  const _ReferenceBadge({
    required this.reference,
    required this.versionId,
    this.comparisonVersionId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isDark = context.isDark;

    final borderColor = onTap != null
        ? context.accent.withValues(alpha: isDark ? 0.6 : 0.45)
        : (isDark
            ? context.accent.withValues(alpha: 0.4)
            : context.accent.withValues(alpha: 0.4));

    final accent = context.tokens.accent;
    final accentBg = context.accent.withValues(alpha: isDark ? 0.25 : 0.15);

    final pillBg = isDark
        ? (onTap != null
            ? tokens.scrim.withValues(alpha: 0.60)
            : tokens.scrim.withValues(alpha: 0.45))
        : (onTap != null
            ? tokens.surface.withValues(alpha: 0.95)
            : tokens.surface.withValues(alpha: 0.85));

    final pillTextColor = isDark ? tokens.onScrim : tokens.onSurface;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6.5),
            decoration: BoxDecoration(
              color: pillBg,
              borderRadius: const BorderRadius.all(Radius.circular(20)),
              border: Border.all(color: borderColor, width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: tokens.scrim.withValues(alpha: isDark ? 0.3 : 0.08),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    reference,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: pillTextColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: accentBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    versionId,
                    style: TextStyle(
                      color: accent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (comparisonVersionId != null) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: isDark
                          ? tokens.onScrim.withValues(alpha: 0.12)
                          : tokens.surfaceVariant,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      comparisonVersionId!,
                      style: TextStyle(
                        color:
                            isDark ? tokens.onScrimMuted : tokens.onSurfaceMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                if (onTap != null) ...[
                  const SizedBox(width: 5),
                  Icon(
                    Icons.menu_book_rounded,
                    size: 13,
                    color: accent,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
