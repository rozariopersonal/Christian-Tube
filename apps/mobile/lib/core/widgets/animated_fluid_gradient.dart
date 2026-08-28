import 'dart:math' as math;
import 'package:flutter/material.dart';

class AnimatedFluidGradient extends StatefulWidget {
  final List<Color> colors;
  final double overlayOpacity;

  const AnimatedFluidGradient({
    Key? key,
    required this.colors,
    this.overlayOpacity = 0.35,
  }) : super(key: key);

  @override
  State<AnimatedFluidGradient> createState() => _AnimatedFluidGradientState();
}

class _AnimatedFluidGradientState extends State<AnimatedFluidGradient>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 15 seconds for a complete fluid rotation/breathing cycle
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Calculate dynamic alignments using sine and cosine waves
        // This gives a beautiful rotating/breathing effect to the gradient
        final double t = _controller.value * 2 * math.pi; // 0 to 2π
        
        final double beginX = math.cos(t) * 0.8;
        final double beginY = math.sin(t) * 0.8;
        
        final double endX = math.cos(t + math.pi) * 0.8;
        final double endY = math.sin(t + math.pi) * 0.8;

        // Make sure we have 3 colors for the stops to map to
        final safeColors = widget.colors.length >= 3 
            ? widget.colors.take(3).toList() 
            : [
                widget.colors.first,
                widget.colors.length > 1 ? widget.colors[1] : widget.colors.first,
                widget.colors.last,
              ];

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(beginX, beginY),
              end: Alignment(endX, endY),
              colors: safeColors,
              // Soften the stops so the gradient stretches nicely
              stops: const [0.0, 0.5, 1.0], 
            ),
          ),
          child: Container(
            // Safety Overlay: Guarantees high contrast for white text
            color: Colors.black.withOpacity(widget.overlayOpacity),
          ),
        );
      },
    );
  }
}
