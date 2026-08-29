import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';

class EmptyMyCreations extends StatelessWidget {
  const EmptyMyCreations({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.tokens.surface,
                shape: BoxShape.circle,
                border: Border.all(color: context.tokens.surfaceBorder),
              ),
              child: Icon(
                Icons.content_cut,
                size: 48,
                color: context.accent,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No Clips Created Yet',
              style: TextStyle(
                color: context.tokens.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'While watching any sermon or worship video, tap the "✂️ Clip Short" button to create an inspiring 1 to 3 minute clip!',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
