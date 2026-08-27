import 'package:flutter/material.dart';

class CardScrimOverlay extends StatelessWidget {
  final double opacity;
  final Widget? child;

  const CardScrimOverlay({
    super.key,
    this.opacity = 0.45,
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
            Colors.black.withOpacity((opacity * 1.1).clamp(0.0, 1.0)),
            Colors.black.withOpacity((opacity * 0.3).clamp(0.0, 1.0)),
            Colors.black.withOpacity((opacity * 0.5).clamp(0.0, 1.0)),
            Colors.black.withOpacity((opacity * 1.3).clamp(0.0, 1.0)),
          ],
          stops: const [0.0, 0.25, 0.70, 1.0],
        ),
      ),
      child: child,
    );
  }
}
