import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';

/// A realistic digital book jacket placeholder rendered when a physical
/// cover image is unavailable. Features a book spine effect, title typography,
/// author badge, and decorative book embossing.
class BookCoverFallback extends StatelessWidget {
  final String title;
  final String author;
  final double? width;
  final double? height;

  const BookCoverFallback({
    super.key,
    required this.title,
    required this.author,
    this.width,
    this.height,
  });

  static final List<List<Color>> _jacketGradients = [
    [const Color(0xFF1A2A3A), const Color(0xFF0F1722)], // Deep Navy
    [const Color(0xFF3B1A24), const Color(0xFF240E15)], // Rich Burgundy
    [const Color(0xFF1E3326), const Color(0xFF112017)], // Forest Emerald
    [const Color(0xFF3D2C1B), const Color(0xFF24190E)], // Warm Amber
    [const Color(0xFF291E38), const Color(0xFF171021)], // Royal Purple
    [const Color(0xFF2C3238), const Color(0xFF1A1E22)], // Slate Charcoal
  ];

  List<Color> _gradientFor(String str) {
    var hash = 0;
    for (var i = 0; i < str.length; i++) {
      hash = (hash * 31 + str.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return _jacketGradients[hash % _jacketGradients.length];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final gradientColors = _gradientFor(title);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.scrim.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(2, 3),
          ),
        ],
        border: Border.all(
          color: tokens.surfaceBorder.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            // Spine highlight/shadow on left edge
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 10,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.18),
                      Colors.black.withValues(alpha: 0.4),
                    ],
                  ),
                ),
              ),
            ),

            // Subtle gold/accent inner border line
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: tokens.accent.withValues(alpha: 0.25),
                      width: 0.8,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),

            // Book title, author, and icon
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.menu_book_rounded,
                      size: 20,
                      color: tokens.accent.withValues(alpha: 0.75),
                    ),
                    const Spacer(),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        height: 1.25,
                        letterSpacing: 0.2,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 24,
                      height: 1,
                      color: tokens.accent.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      author,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.onSurfaceMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 10.5,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
