import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';

class CardScrimOverlay extends StatelessWidget {
  final double opacity;
  final Widget? child;

  const CardScrimOverlay({
    super.key,
    this.opacity = 0.70,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            context.tokens.scrim.withValues(alpha: (opacity * 0.85).clamp(0.0, 1.0)),
            context.tokens.scrim.withValues(alpha: (opacity * 0.75).clamp(0.0, 1.0)),
            context.tokens.scrim.withValues(alpha: (opacity * 0.80).clamp(0.0, 1.0)),
            context.tokens.scrim.withValues(alpha: (opacity * 1.15).clamp(0.0, 1.0)),
          ],
          stops: const [0.0, 0.30, 0.65, 1.0],
        ),
      ),
      child: child,
    );
  }
}
