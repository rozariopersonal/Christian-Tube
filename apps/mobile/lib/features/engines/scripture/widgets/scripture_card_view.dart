import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mobile/features/micro_feed/widgets/card_scrim_overlay.dart';
import '../models/scripture_card.dart';
import '../models/scripture_filter_state.dart';
import '../models/scripture_theme_state.dart';
import '../services/bible_download_manager.dart';
import '../services/scripture_service.dart';

class ScriptureCardView extends StatefulWidget {
  final ScriptureCard card;
  final ScriptureFilterState filterState;
  final bool isActive;

  const ScriptureCardView({
    super.key,
    required this.card,
    required this.filterState,
    required this.isActive,
  });

  @override
  State<ScriptureCardView> createState() => _ScriptureCardViewState();
}

class _ScriptureCardViewState extends State<ScriptureCardView> {
  final ScriptureService _service = ScriptureService();
  String? _displayedText;
  String? _displayedVersion;

  @override
  void initState() {
    super.initState();
    _displayedText = widget.card.resolvedText;
    _displayedVersion =
        widget.card.resolvedVersion ?? widget.filterState.activeVersionId;
    _checkAndResolveVersion();
  }

  @override
  void didUpdateWidget(covariant ScriptureCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterState.activeVersionId !=
            widget.filterState.activeVersionId ||
        oldWidget.card.id != widget.card.id) {
      _checkAndResolveVersion();
    }
  }

  Future<void> _checkAndResolveVersion() async {
    final targetVersion = widget.filterState.activeVersionId;
    if (_displayedVersion != targetVersion || _displayedText == null) {
      await _service.resolveCardText(widget.card, targetVersion);
      if (mounted) {
        setState(() {
          _displayedText = widget.card.resolvedText;
          _displayedVersion = targetVersion;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preset = ScriptureThemeCatalog.getPreset(widget.card.activeBackground);
    final versionId = _displayedVersion ?? widget.filterState.activeVersionId;
    final versionMeta = BibleDownloadManager.getMeta(versionId);

    final text = _displayedText ??
        widget.card.resolvedText ??
        '“Peace I leave with you; my peace I give you. Do not let your hearts be troubled.”';

    // Auto-calculate dynamic font size based on verse text length & user scale
    final length = text.length;
    final dynamicBaseSize = (32.0 - (length / 26.0)).clamp(17.0, 32.0);
    final effectiveFontSize =
        dynamicBaseSize * widget.filterState.fontSizeScale;

    final activeFontFamily =
        widget.card.customFontFamily ?? widget.filterState.activeFontFamily;
    final textStyle = ScriptureThemeCatalog.getTextStyle(
      fontFamily: activeFontFamily,
      languageCode: versionMeta.languageCode,
      baseSize: effectiveFontSize,
      color: Colors.white,
      fontWeight: FontWeight.w400,
    );

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
        const CardScrimOverlay(opacity: 0.48),

        // 3. Typographic Content Canvas
        Center(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 28.0, vertical: 80.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Opening Quote Mark
                Text(
                  '“',
                  style: TextStyle(
                    fontSize: 48,
                    height: 0.8,
                    fontFamily: 'serif',
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.9),
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

                // Verse Body Text with Smooth Animated Replacement
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
                    text,
                    key: ValueKey('${versionId}_${text.hashCode}'),
                    textAlign: TextAlign.center,
                    style: textStyle.copyWith(
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

                // Reference Attribution Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                      width: 1.0,
                    ),
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
                      Text(
                        '— ${widget.card.referenceLabel}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          versionId,
                          style: const TextStyle(
                            color: Color(0xFFFBBF24),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackground(BackgroundPreset preset) {
    if (preset.isGradient && preset.gradientColors != null) {
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
