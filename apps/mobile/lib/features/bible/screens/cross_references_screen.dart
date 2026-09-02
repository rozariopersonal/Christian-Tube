import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/layout/adaptivity.dart';
import '../../../core/layout/content_width.dart';
import '../models/cross_reference.dart';
import '../widgets/cross_reference_card.dart';

/// Dedicated "Cross References" page for a single verse that has more than two
/// references (two or fewer are shown inline under the verse instead).
///
/// Responsive layout per the app-wide standard:
/// - `compact`: the main verse is pinned at the top and the full cross
///   reference list scrolls below it.
/// - `medium`/`expanded`: a side-by-side (split) view — the main verse on the
///   left pane, the cross-reference list on the right pane — so neither column
///   stretches edge-to-edge on tablets and web.
class CrossReferencesScreen extends StatelessWidget {
  final String verseText;
  final String verseLabel;
  final String? versionLabel;
  final String? versionId;
  final List<CrossReference> references;
  final Map<String, String> resolvedTexts;
  final double baseFontSize;
  final void Function(CrossReference) onTapReference;

  const CrossReferencesScreen({
    super.key,
    required this.verseText,
    required this.verseLabel,
    this.versionLabel,
    this.versionId,
    required this.references,
    required this.resolvedTexts,
    required this.baseFontSize,
    required this.onTapReference,
  });

  String? get _resolvedVersionId {
    if (versionId != null && versionId!.trim().isNotEmpty) {
      return versionId!.trim();
    }
    if (versionLabel != null && versionLabel!.trim().isNotEmpty) {
      final label = versionLabel!.trim().toLowerCase();
      if (label.contains('tamil') || label.contains('தமிழ்') || label.contains('taobvsi')) {
        return 'TAOBVSI';
      }
      if (label.contains('malayalam') || label.contains('മലയാളം') || label.contains('mal')) {
        return 'MAL_IRV';
      }
      if (label.contains('telugu') || label.contains('తెలుగు') || label.contains('tel')) {
        return 'TEL_IRV';
      }
      if (label.contains('hindi') || label.contains('हिन्दी') || label.contains('hin')) {
        return 'HIN_IRV';
      }
      if (label.contains('kannada') || label.contains('ಕನ್ನಡ') || label.contains('kan')) {
        return 'KAN_IRV';
      }
      return versionLabel;
    }
    return null;
  }

  Widget _buildVerseCard(BuildContext context) {
    final tokens = context.tokens;
    final screen = ScreenClass.of(context);
    final fontSize = screen.isCompact ? baseFontSize : baseFontSize + 1.0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: tokens.accent, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  verseLabel,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              if (versionLabel != null && versionLabel!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    versionLabel!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.onSurfaceMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            verseText,
            style: TextStyle(
              color: tokens.onSurface,
              fontSize: fontSize,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final screen = ScreenClass.of(context);

    final title = Text(
      'Cross References',
      style: TextStyle(
        color: tokens.onSurface,
        fontWeight: FontWeight.bold,
      ),
    );
    final body =
        screen.isCompact ? _buildCompact(context) : _buildSplit(context);

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        elevation: 0,
        title: title,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: tokens.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: body,
    );
  }

  Widget _buildCompact(BuildContext context) {
    // Single scrollable on compact: the main verse is the first item (pinned at
    // the top of the reading position) followed by the reference cards. Keeping
    // it all in one scroll view guarantees no vertical overflow at max font
    // scale on narrow phones.
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _buildVerseCard(context),
        const SizedBox(height: 8),
        for (final ref in references)
          CrossReferenceCard(
            reference: ref,
            text: resolvedTexts[ref.textKey],
            fontSize: baseFontSize,
            versionId: _resolvedVersionId,
            onTap: () => onTapReference(ref),
          ),
      ],
    );
  }

  Widget _buildSplit(BuildContext context) {
    // Split view (tablets/web): verse pinned on the left, references on the
    // right. Capped content width so neither pane stretches absurdly wide.
    return MaxWidthBox(
      child: SizedBox(
        height: double.infinity,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              // Verse pane: ~40% of the readable measure, never wider than the
              // right list so the reference content stays the focus.
              width: 360,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 24),
                child: _buildVerseCard(context),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Text(
                    '${references.length} references',
                    style: TextStyle(
                      color: context.tokens.onSurfaceMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final ref in references)
                    CrossReferenceCard(
                      reference: ref,
                      text: resolvedTexts[ref.textKey],
                      fontSize: baseFontSize,
                      versionId: _resolvedVersionId,
                      onTap: () => onTapReference(ref),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
