import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/micro_feed/widgets/card_scrim_overlay.dart';
import 'package:mobile/core/widgets/animated_fluid_gradient.dart';
import '../models/scripture_card.dart';
import '../models/scripture_filter_state.dart';
import '../models/scripture_theme_state.dart';
import '../services/bible_download_manager.dart';
import '../services/scripture_image_exporter.dart';
import '../services/scripture_service.dart';

class ScriptureCardView extends StatefulWidget {
  final ScriptureCard card;
  final ScriptureFilterState filterState;
  final bool isActive;
  final ValueChanged<int>? onEdgePageShift;
  final VoidCallback? onReferenceTap;

  const ScriptureCardView({
    super.key,
    required this.card,
    required this.filterState,
    required this.isActive,
    this.onEdgePageShift,
    this.onReferenceTap,
  });

  @override
  State<ScriptureCardView> createState() => _ScriptureCardViewState();
}

class _ScriptureCardViewState extends State<ScriptureCardView> {
  final ScriptureService _service = ScriptureService();
  String? _displayedText;
  String? _displayedVersion;
  bool _isResolving = false;
  String? _lastAttemptedVersion;
  DateTime _lastEdgeShift = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
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
    if (widget.isActive) {
      _pregenerateImage();
    }
    final comparison = widget.filterState.comparisonVersionId;
    if (comparison != null && widget.card.comparisonVersion != comparison) {
      _resolveComparison();
    }
  }

  @override
  void didUpdateWidget(covariant ScriptureCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    if (widget.isActive && (!oldWidget.isActive || oldWidget.filterState != widget.filterState)) {
      _pregenerateImage();
    }
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

  // Scroll-past-edge detection: when the card's text overflows the screen,
  // continuing the drag past the top/bottom edge pages to the prev/next card.
  bool _handleScrollNotification(ScrollNotification notification) {
    if (widget.onEdgePageShift == null) return false;
    if (notification is! ScrollUpdateNotification ||
        notification.dragDetails == null) {
      return false;
    }
    final metrics = notification.metrics;
    if (metrics.maxScrollExtent <= 0) return false;
    if (DateTime.now().difference(_lastEdgeShift).inMilliseconds < 600) {
      return false;
    }
    final delta = notification.dragDetails!.primaryDelta ?? 0;
    if (delta < -1 && metrics.pixels >= metrics.maxScrollExtent - 1) {
      _lastEdgeShift = DateTime.now();
      widget.onEdgePageShift!(1);
    } else if (delta > 1 && metrics.pixels <= 1) {
      _lastEdgeShift = DateTime.now();
      widget.onEdgePageShift!(-1);
    }
    return false;
  }

  Future<void> _checkAndResolveVersion() async {
    // Guard against concurrent resolutions for the same version / redundant retries
    if (_isResolving) return;
    final targetVersion = widget.filterState.activeVersionId;
    if (_displayedVersion == targetVersion && _displayedText != null) return;
    if (_lastAttemptedVersion == targetVersion) return;

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
          _pregenerateImage();
        }
        return;
      }

      await _service.resolveCardText(widget.card, targetVersion);
      if (mounted) {
        setState(() {
          _displayedText = widget.card.resolvedText;
          _displayedVersion = widget.card.resolvedVersion ?? targetVersion;
        });
        _pregenerateImage();
      }
    } finally {
      _isResolving = false;
    }
  }

  void _pregenerateImage() {
    final targetVersion = widget.filterState.activeVersionId;
    final currentKey =
        '${widget.card.id}_${targetVersion}_${widget.filterState.activeFontFamily}_${widget.filterState.fontSizeScale}_${widget.filterState.textColorHex}_${widget.card.activeBackground}';
    if (widget.card.precomputedImageKey == currentKey &&
        widget.card.precomputedImageBytes != null) {
      return;
    }

    Future.microtask(() async {
      try {
        final bytes = await ScriptureGraphicGenerator.generateStoryImage(
          card: widget.card,
          activeVersionId: targetVersion,
          fontFamily: widget.filterState.activeFontFamily,
          fontSizeScale: widget.filterState.fontSizeScale,
          textColorHex: widget.filterState.textColorHex,
          isBold: widget.filterState.isBold,
          isItalic: widget.filterState.isItalic,
          textAlign: widget.filterState.textAlign,
        );
        widget.card.precomputedImageBytes = bytes;
        widget.card.precomputedImageKey = currentKey;
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
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

    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final heightFactor = (screenHeight / 800.0).clamp(0.75, 1.15);

    final double effectiveFontSize =
        _dynamicFontSize(primaryText, heightFactor) * widget.filterState.fontSizeScale;

    final comparisonFontSize = comparisonText != null
        ? _dynamicFontSize(comparisonText, heightFactor) * 0.75 * widget.filterState.fontSizeScale
        : 0.0;

    final activeFontFamily =
        widget.card.customFontFamily ?? widget.filterState.activeFontFamily;
    final textColor =
        ScriptureThemeCatalog.parseColor(widget.filterState.textColorHex);
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

    final textStyle = ScriptureThemeCatalog.getTextStyle(
      fontFamily: activeFontFamily,
      languageCode: primaryMeta.languageCode,
      baseSize: effectiveFontSize,
      color: textColor,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
    );

    final verticalPadding = (screenHeight * 0.05).clamp(24.0, 56.0);

    // Reserve horizontal space on the right for the floating side-action rail
    // (Share/Style/Compare/Copy/Save) so the verse text never underlaps it.
    final double horizontalPad = (screenWidth * 0.08).clamp(24.0, 48.0);
    final double rightInset = horizontalPad + 64.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Background Layer with Smooth Animated Crossfade
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          child: KeyedSubtree(
            key: ValueKey('${preset.id}_${preset.imageUrl}'),
            child: _buildBackground(preset),
          ),
        ),

        // 2. Readability Gradient Scrim
        const CardScrimOverlay(opacity: 0.72),

        // 3. Typographic Content Canvas (Scroll-safe, centered, zero-overflow)
        Center(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: horizontalPad,
                    right: rightInset,
                    top: verticalPadding,
                    bottom: verticalPadding,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Opening Quote Mark
                      Text(
                        '“',
                        style: TextStyle(
                          fontSize: 48,
                          height: 0.8,
                          fontFamily: 'serif',
                          color: context.accent.withValues(alpha: 0.9),
                          shadows: const [
                            Shadow(
                              color: Colors.black87,
                              blurRadius: 12,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Primary Verse Body Text with Smooth Animated Replacement
                      AnimatedSwitcher(
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
                            shadows: const [
                              Shadow(
                                color: Colors.black,
                                blurRadius: 16,
                                offset: Offset(0, 2),
                              ),
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 6,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Reference Attribution Badge (Primary)
                      _ReferenceBadge(
                        reference: '— ${widget.card.referenceLabel}',
                        versionId: primaryVersionId,
                        onTap: widget.onReferenceTap,
                      ),

                      if (comparisonText != null &&
                          comparisonVersionId != null) ...[
                        const SizedBox(height: 20),
                        Divider(
                          color: context.tokens.onSurfaceDisabled,
                          height: 1,
                          indent: 60,
                          endIndent: 60,
                        ),                        const SizedBox(height: 16),

                        // Secondary Verse Body Text (smaller, subdued)
                        Text(
                          comparisonText,
                          textAlign: textAlign,
                          softWrap: true,
                          textWidthBasis: TextWidthBasis.parent,
                          style: ScriptureThemeCatalog.getTextStyle(
                            fontFamily: activeFontFamily,
                            languageCode: comparisonMeta?.languageCode ?? 'en',
                            baseSize: comparisonFontSize,
                            color: Colors.white.withValues(alpha: 0.88),
                            fontWeight: FontWeight.w400,
                            fontStyle: FontStyle.italic,
                          ).copyWith(shadows: const [
                            Shadow(
                              color: Colors.black,
                              blurRadius: 16,
                              offset: Offset(0, 2),
                            ),
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 6,
                              offset: Offset(0, 1),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 14),

                        // Reference Attribution Badge (Secondary)
                        _ReferenceBadge(
                          reference: '— ${widget.card.referenceLabel}',
                          versionId: comparisonVersionId,
                          subdued: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _dynamicFontSize(String text, double heightFactor) {
    // Auto-calculate dynamic font size based on verse text length, longest
    // word, screen height & user scale
    final words = text.split(RegExp(r'\s+'));
    int maxWordLength = 0;
    for (final w in words) {
      if (w.length > maxWordLength) maxWordLength = w.length;
    }

    final length = text.length;
    double dynamicBaseSize =
        ((28.0 - (length / 32.0)).clamp(15.0, 26.0) * heightFactor);

    // If verse has extra long compound words (e.g. Indic words with 12+ chars),
    // adaptively scale down font size so words never break mid-word!
    if (maxWordLength > 12) {
      final wordLengthPenalty = (maxWordLength - 12) * 0.7;
      dynamicBaseSize = (dynamicBaseSize - wordLengthPenalty).clamp(13.0, 26.0);
    }
    return dynamicBaseSize;
  }

  Widget _buildBackground(BackgroundPreset preset) {
    if (preset.isGradient && preset.gradientColors != null) {
      if (preset.isAnimatedGradient) {
        return AnimatedFluidGradient(
          colors: preset.gradientColors!,
          overlayOpacity: 0.35, // Enforce readability
        );
      }
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: preset.gradientColors!,
          ),
        ),
      );
    } else if (preset.imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: preset.imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        fadeInDuration: const Duration(milliseconds: 300),
        placeholder: (context, url) => Container(
          color: const Color(0xFF0F172A),
          child: const Center(
            child: CircularProgressIndicator(
              color: Colors.white24,
              strokeWidth: 1.5,
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0F172A), Color(0xFF020617)],
            ),
          ),
        ),
      );
    } else {
      return Container(
        color: const Color(0xFF0A0A0A),
      );
    }
  }
}

/// Small attribution pill showing a reference label plus a version badge.
class _ReferenceBadge extends StatelessWidget {
  final String reference;
  final String versionId;
  final bool subdued;
  final VoidCallback? onTap;

  const _ReferenceBadge({
    required this.reference,
    required this.versionId,
    this.subdued = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = subdued
        ? Colors.white.withValues(alpha: 0.25)
        : context.accent.withValues(alpha: 0.4);
    final accent = subdued ? Colors.white70 : context.tokens.accent;
    final accentBg = subdued
        ? Colors.white10
        : context.accent.withValues(alpha: 0.25);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: onTap != null
              ? Colors.black.withValues(alpha: 0.55)
              : Colors.black.withValues(alpha: 0.45),
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          border: Border.all(color: onTap != null ? context.accent.withValues(alpha: 0.7) : borderColor, width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: accentBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                versionId,
                style: TextStyle(
                  color: accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
