import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/engines/scripture/models/scripture_theme_state.dart';
import 'package:mobile/shared/services/reader_appearance.dart';
import 'package:mobile/shared/services/reader_fonts_service.dart';
import 'font_download_action_button.dart';

/// Specimen card demonstrating a typeface with progressive auto-preview,
/// shimmer placeholder during background streaming, and animated cross-fade.
class FontSpecimenCard extends StatelessWidget {
  final ScriptureFontOption fontOption;
  final String languageCode;
  final bool isSelected;
  final bool isManagementMode;
  final VoidCallback? onSelect;
  final ReaderAppearance? appearance;

  const FontSpecimenCard({
    super.key,
    required this.fontOption,
    required this.languageCode,
    this.isSelected = false,
    this.isManagementMode = false,
    this.onSelect,
    this.appearance,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final resolvedFamily = ScriptureThemeCatalog.resolveFontFamily(
      fontOption.id,
      fontOption.languageCode ?? languageCode,
    );

    final effectiveSelected = appearance != null
        ? appearance!.fontFamily == fontOption.id
        : isSelected;

    final listenable = appearance != null
        ? Listenable.merge([ReaderFontsService.instance, appearance!])
        : ReaderFontsService.instance;

    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final service = ReaderFontsService.instance;
        final isFamilyReady = resolvedFamily != null && service.isReady(resolvedFamily);
        final isFamilyLoading = resolvedFamily != null && service.isLoading(resolvedFamily);
        final isInstalled = resolvedFamily != null && service.isFamilyInstalledSync(resolvedFamily);

        final cardBg = effectiveSelected
            ? tokens.accent.withValues(alpha: 0.12)
            : tokens.surface;
        final borderCol = effectiveSelected
            ? tokens.accent
            : tokens.surfaceBorder;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onSelect,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: borderCol,
                  width: effectiveSelected ? 1.8 : 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row: Sample Glyph + Title + Subtitle + Action
                  Row(
                    children: [
                      // Glyph avatar
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: tokens.surfaceVariant,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: tokens.surfaceBorder),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          fontOption.sampleGlyph,
                          style: TextStyle(
                            fontFamily: isFamilyReady ? resolvedFamily : null,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: effectiveSelected ? tokens.accent : tokens.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Title & category badge
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fontOption.name,
                              style: TextStyle(
                                color: effectiveSelected ? tokens.accent : tokens.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                fontFamily: isFamilyReady ? resolvedFamily : null,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: tokens.surfaceVariant,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    fontOption.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: tokens.onSurfaceMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (isInstalled)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 13,
                                        color: tokens.accent,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Installed',
                                        style: TextStyle(
                                          color: tokens.accent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Download / Delete / Selected Checkmark
                      if (isManagementMode)
                        FontDownloadActionButton(
                          family: resolvedFamily ?? fontOption.name,
                          isInstalled: isInstalled,
                          isLoading: isFamilyLoading,
                          showDeleteWhenInstalled: true,
                        )
                      else if (effectiveSelected)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: tokens.accent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: tokens.background,
                          ),
                        )
                      else
                        FontDownloadActionButton(
                          family: resolvedFamily ?? fontOption.name,
                          isInstalled: isInstalled,
                          isLoading: isFamilyLoading,
                          showDeleteWhenInstalled: false,
                        ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Specimen Sample Line (Progressive Auto-Preview with Shimmer & CrossFade)
                  _buildSpecimenPreview(
                    context,
                    resolvedFamily: resolvedFamily,
                    isReady: isFamilyReady,
                    isLoading: isFamilyLoading,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpecimenPreview(
    BuildContext context, {
    required String? resolvedFamily,
    required bool isReady,
    required bool isLoading,
  }) {
    final tokens = context.tokens;
    final sampleText = _getLocalizedScriptureSample(languageCode);

    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 250),
      firstCurve: Curves.easeInOutCubic,
      secondCurve: Curves.easeInOutCubic,
      crossFadeState: (isReady && !isLoading)
          ? CrossFadeState.showSecond
          : CrossFadeState.showFirst,
      firstChild: _ShimmerSpecimenSkeleton(tokens: tokens),
      secondChild: Text(
        sampleText,
        style: TextStyle(
          fontFamily: resolvedFamily,
          fontSize: 15,
          height: 1.5,
          fontWeight: appearance?.fontWeight ?? FontWeight.normal,
          fontStyle: appearance?.fontStyle ?? FontStyle.normal,
          decoration: appearance?.textDecoration ?? TextDecoration.none,
          color: tokens.onSurface,
        ),
      ),
    );
  }

  static String _getLocalizedScriptureSample(String? lang) {
    switch (ScriptureThemeCatalog.normalizeLanguageCode(lang)) {
      case 'tam':
        return 'கர்த்தர் என் வெளிச்சமும் என் இரட்சிப்புமானவர், யாருக்குப் பயப்படுவேன்?';
      case 'mal':
        return 'യഹോവ എന്റെ വെളിച്ചവും എന്റെ രക്ഷയുമാകുന്നു; ഞാൻ ആരെ ഭയപ്പെടും?';
      case 'tel':
        return 'యెహోవా నాకు వెలుగును రక్షణయునై యున్నాడు, నేను ఎవరికి భయపడుదును?';
      case 'hin':
        return 'यहोवा मेरी ज्योति और मेरा उद्धार है; मैं किस से डरूँ?';
      case 'kan':
        return 'ಯೆಹೋವನು ನನ್ನ ಬೆಳಕೂ ರಕ್ಷಣೆಯೂ ಆಗಿದ್ದಾನೆ; ನಾನು ಯಾರಿಗೆ ಭಯಪಡಲಿ?';
      default:
        return 'The Lord is my light and my salvation; whom shall I fear?';
    }
  }
}

class _ShimmerSpecimenSkeleton extends StatefulWidget {
  final AppTokens tokens;

  const _ShimmerSpecimenSkeleton({required this.tokens});

  @override
  State<_ShimmerSpecimenSkeleton> createState() => _ShimmerSpecimenSkeletonState();
}

class _ShimmerSpecimenSkeletonState extends State<_ShimmerSpecimenSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get _isTestEnvironment {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (!_isTestEnvironment) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.tokens.surfaceVariant;
    final highlight = widget.tokens.surfaceBorder.withValues(alpha: 0.6);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 14,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  begin: Alignment(-1.5 + 3.0 * _controller.value, 0),
                  end: Alignment(-0.5 + 3.0 * _controller.value, 0),
                  colors: [base, highlight, base],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 14,
              width: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  begin: Alignment(-1.5 + 3.0 * _controller.value, 0),
                  end: Alignment(-0.5 + 3.0 * _controller.value, 0),
                  colors: [base, highlight, base],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
