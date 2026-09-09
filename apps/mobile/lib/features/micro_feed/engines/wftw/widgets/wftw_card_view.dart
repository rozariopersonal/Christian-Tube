import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile/core/layout/content_width.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/core/widgets/animated_fluid_gradient.dart';
import 'package:mobile/features/engines/scripture/models/scripture_theme_state.dart';
import 'package:mobile/features/engines/scripture/services/bible_download_manager.dart';
import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';
import 'package:mobile/features/micro_feed/widgets/card_scrim_overlay.dart';
import '../models/wftw_card.dart';
import '../models/wftw_filter_state.dart';

class WftwCardView extends StatefulWidget {
  final WftwCard card;
  final WftwFilterState filterState;
  final bool isActive;
  final ValueChanged<int>? onEdgePageShift;
  final VoidCallback? onReferenceTap;
  final VoidCallback? onReadArticleTap;

  const WftwCardView({
    super.key,
    required this.card,
    required this.filterState,
    required this.isActive,
    this.onEdgePageShift,
    this.onReferenceTap,
    this.onReadArticleTap,
  });

  @override
  State<WftwCardView> createState() => _WftwCardViewState();
}

class _WftwCardViewState extends State<WftwCardView> {
  final LocalBibleService _bibleService = LocalBibleService();
  String? _displayedText;
  String? _displayedVersion;
  DateTime _lastEdgeShift = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _resolveVerseText();
  }

  @override
  void didUpdateWidget(covariant WftwCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterState.activeVersionId != widget.filterState.activeVersionId ||
        oldWidget.card.articleId != widget.card.articleId) {
      _resolveVerseText();
    }
  }

  Future<void> _resolveVerseText() async {
    if (!widget.card.hasPrimaryVerse) {
      setState(() {
        _displayedText = widget.card.fallbackExcerpt ?? widget.card.articleTitle;
        _displayedVersion = null;
      });
      return;
    }

    final targetVersion = widget.filterState.activeVersionId;
    final syncText = _bibleService.resolvePassageSync(
      versionId: targetVersion,
      bookNumber: widget.card.bookNumber!,
      chapter: widget.card.chapter!,
      startVerse: widget.card.startVerse!,
      endVerse: widget.card.endVerse,
    );

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

    // Try async lookup
    final asyncText = await _bibleService.resolvePassage(
      versionId: targetVersion,
      bookNumber: widget.card.bookNumber!,
      chapter: widget.card.chapter!,
      startVerse: widget.card.startVerse!,
      endVerse: widget.card.endVerse,
    );

    if (mounted) {
      setState(() {
        _displayedText = asyncText ?? widget.card.fallbackExcerpt ?? widget.card.articleTitle;
        _displayedVersion = asyncText != null ? targetVersion : null;
      });
    }
  }

  // Scroll-past-edge detection: when the card's content overflows the screen,
  // continuing the drag past the top/bottom edge pages to the prev/next card.
  // While content fits, ClampingScrollPhysics registers no drag recognizer at
  // rest, so the parent PageView handles swipes naturally.
  bool _handleScrollNotification(ScrollNotification notification) {
    if (widget.onEdgePageShift == null) return false;
    final DragUpdateDetails? details;
    if (notification is ScrollUpdateNotification) {
      details = notification.dragDetails;
    } else if (notification is OverscrollNotification) {
      details = notification.dragDetails;
    } else {
      return false;
    }
    if (details == null) return false;
    final metrics = notification.metrics;
    if (metrics.maxScrollExtent <= 0) return false;
    if (DateTime.now().difference(_lastEdgeShift) < const Duration(milliseconds: 600)) {
      return false;
    }
    final delta = details.primaryDelta ?? 0;
    if (delta < -1 && metrics.pixels >= metrics.maxScrollExtent - 1) {
      _lastEdgeShift = DateTime.now();
      widget.onEdgePageShift!(1);
    } else if (delta > 1 && metrics.pixels <= 1) {
      _lastEdgeShift = DateTime.now();
      widget.onEdgePageShift!(-1);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final preset = ScriptureThemeCatalog.getPreset(
      widget.card.activeBackground.isNotEmpty
          ? widget.card.activeBackground
          : widget.filterState.backgroundPreset,
    );

    final targetVersion = widget.filterState.activeVersionId;
    final primaryText = _displayedText ?? widget.card.resolvedText ?? widget.card.fallbackExcerpt ?? '';
    final primaryVersionId = _displayedVersion ?? targetVersion;

    final meta = BibleDownloadManager.getMeta(primaryVersionId);
    final lang = meta.languageCode;

    TextAlign textAlign = TextAlign.center;
    if (widget.filterState.textAlign == 'left') textAlign = TextAlign.left;
    if (widget.filterState.textAlign == 'right') textAlign = TextAlign.right;

    final tokens = context.tokens;
    final mediaQuery = MediaQuery.of(context);
    final height = mediaQuery.size.height;
    final heightFactor = (height / 800.0).clamp(0.75, 1.25);
    final baseFontSize = _dynamicFontSize(primaryText, heightFactor);
    final finalFontSize = baseFontSize * widget.filterState.fontSizeScale;

    final textColor = ScriptureThemeCatalog.parseColor(widget.filterState.textColorHex);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Background preset
        _buildBackground(preset, tokens),

        // 2. Scrim overlay for legibility
        const CardScrimOverlay(),

        // 3. Scrollable content canvas
        SafeArea(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.only(
                left: 24.0,
                right: 24.0,
                top: 72.0,
                bottom: 120.0,
              ),
              child: Center(
                child: MaxWidthBox(
                  maxWidth: 720,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: textAlign == TextAlign.left
                        ? CrossAxisAlignment.start
                        : (textAlign == TextAlign.right
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.center),
                    children: [
                      // Article Title & Date Badge
                      _ArticleHeaderBadge(
                        title: widget.card.articleTitle,
                        formattedDate: widget.card.formattedDate,
                        onTap: widget.onReadArticleTap,
                      ),
                      const SizedBox(height: 24),

                      // Verse / Excerpt Text
                      Text(
                        primaryText,
                        textAlign: textAlign,
                        softWrap: true,
                        style: ScriptureThemeCatalog.getTextStyle(
                          fontFamily: widget.card.customFontFamily ??
                              widget.filterState.activeFontFamily,
                          languageCode: lang,
                          baseSize: finalFontSize,
                          color: textColor,
                          fontWeight: widget.filterState.isBold
                              ? FontWeight.w700
                              : FontWeight.w400,
                          fontStyle: widget.filterState.isItalic
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ).copyWith(
                          shadows: [
                            Shadow(
                              color: tokens.scrim,
                              blurRadius: 18,
                              offset: const Offset(0, 2),
                            ),
                            Shadow(
                              color: tokens.scrim.withValues(alpha: 0.54),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Reference Badge if primary verse is present
                      if (widget.card.hasPrimaryVerse)
                        _ReferenceBadge(
                          reference: '— ${widget.card.referenceLabel}',
                          versionId: primaryVersionId,
                          onTap: widget.onReferenceTap,
                        ),
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
    final length = text.length;
    double dynamicBaseSize = ((28.0 - (length / 32.0)).clamp(15.0, 26.0) * heightFactor);
    return dynamicBaseSize;
  }

  Widget _buildBackground(BackgroundPreset preset, AppTokens tokens) {
    if (preset.isGradient && preset.gradientColors != null) {
      if (preset.isAnimatedGradient) {
        return AnimatedFluidGradient(
          colors: preset.gradientColors!,
          overlayOpacity: 0.35,
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
          color: tokens.surface,
        ),
        errorWidget: (context, url, error) => Container(
          color: tokens.surface,
        ),
      );
    }
    return Container(color: tokens.surface);
  }
}

class _ArticleHeaderBadge extends StatelessWidget {
  final String title;
  final String formattedDate;
  final VoidCallback? onTap;

  const _ArticleHeaderBadge({
    required this.title,
    required this.formattedDate,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.scrim.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: tokens.surfaceBorder.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.article_rounded,
              size: 15,
              color: tokens.accent,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '$title • $formattedDate',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.onScrim,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 10,
                color: tokens.onScrimMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReferenceBadge extends StatelessWidget {
  final String reference;
  final String versionId;
  final VoidCallback? onTap;

  const _ReferenceBadge({
    required this.reference,
    required this.versionId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: tokens.scrim.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: tokens.surfaceBorder.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                reference,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.onScrim,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: tokens.accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                versionId,
                style: TextStyle(
                  color: tokens.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.open_in_new_rounded,
                size: 13,
                color: tokens.onScrimMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
