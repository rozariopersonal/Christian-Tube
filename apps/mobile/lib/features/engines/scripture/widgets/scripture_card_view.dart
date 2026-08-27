import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mobile/features/micro_feed/widgets/card_scrim_overlay.dart';
import '../models/scripture_card.dart';
import '../models/scripture_filter_state.dart';
import '../models/scripture_theme_state.dart';
import '../services/bible_download_manager.dart';

class ScriptureCardView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final preset = ScriptureThemeCatalog.getPreset(card.activeBackground);
    final versionMeta =
        BibleDownloadManager.getMeta(card.resolvedVersion ?? filterState.activeVersionId);
    final text = card.resolvedText ??
        '“Peace I leave with you; my peace I give you. Do not let your hearts be troubled.”';

    // Auto-calculate dynamic font size based on verse text length
    final length = text.length;
    final dynamicBaseSize = (32.0 - (length / 26.0)).clamp(17.0, 32.0);
    final effectiveFontSize = dynamicBaseSize * filterState.fontSizeScale;

    final activeFontFamily = card.customFontFamily ?? filterState.activeFontFamily;
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
        // 1. Background Layer (Photo or Procedural Gradient)
        if (preset.isGradient && preset.gradientColors != null)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: preset.gradientColors!,
              ),
            ),
          )
        else if (preset.imageUrl != null)
          CachedNetworkImage(
            imageUrl: preset.imageUrl!,
            fit: BoxFit.cover,
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
          ),

        // 2. Readability Gradient Scrim
        CardScrimOverlay(opacity: 0.48),

        // 3. Typographic Content Canvas
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 80.0),
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
                    color: const Color(0xFFF59E0B).withOpacity(0.9),
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

                // Verse Body Text
                Text(
                  text,
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
                const SizedBox(height: 20),

                // Reference Attribution Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withOpacity(0.4),
                      width: 1.0,
                    ),
                  ),
                  child: Text(
                    '— ${card.referenceLabel} (${card.resolvedVersion ?? filterState.activeVersionId}) —',
                    style: const TextStyle(
                      color: Color(0xFFFBBF24),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 4. Subtle Watermark (Visible on Exported Story Images)
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 11,
                  color: Colors.white38,
                ),
                const SizedBox(width: 4),
                Text(
                  'ChristianTube Words',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.35),
                    fontSize: 10,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
