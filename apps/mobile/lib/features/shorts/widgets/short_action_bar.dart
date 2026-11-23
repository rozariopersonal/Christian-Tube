import 'package:flutter/material.dart';
import '../../../core/models/short.dart';
import '../../../core/theme/app_tokens.dart';
import 'shorts_chrome.dart';

class ShortActionBar extends StatelessWidget {
  final Short short;
  final VoidCallback onShare;
  final VoidCallback? onNote;
  final bool hasNote;

  const ShortActionBar({
    super.key,
    required this.short,
    required this.onShare,
    this.onNote,
    this.hasNote = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onNote != null) ...[
          _buildCircleButton(
            context,
            icon: hasNote
                ? Icons.sticky_note_2_rounded
                : Icons.sticky_note_2_outlined,
            label: hasNote ? 'Note ✓' : 'Note',
            onTap: onNote!,
            highlighted: hasNote,
          ),
          const SizedBox(height: 16),
        ],
        _buildCircleButton(
          context,
          icon: Icons.share_rounded,
          label: 'Share',
          onTap: onShare,
          highlighted: true,
        ),
      ],
    );
  }

  Widget _buildCircleButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool highlighted = false,
  }) {
    final onAccent = context.accent.computeLuminance() > 0.45
        ? context.shortsChromeFg
        : context.shortsChromeFgMuted;
    final fillColor = highlighted
        ? context.accent
        : context.shortsChromeBg.withValues(alpha: 0.72);
    final iconColor = highlighted ? onAccent : context.shortsChromeFg;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fillColor,
              boxShadow: [
                if (highlighted)
                  BoxShadow(
                    color: context.accent.withValues(alpha: 0.65),
                    blurRadius: 12,
                    spreadRadius: 1,
                    offset: const Offset(0, 3),
                  ),
                BoxShadow(
                  color: context.shortsChromeShadow.withValues(alpha: 0.54),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(color: context.shortsChromeFg, width: 1.5),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: context.shortsChromeFg,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              shadows: [
                Shadow(color: context.shortsChromeShadow, blurRadius: 6),
                Shadow(color: context.shortsChromeShadow, blurRadius: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
