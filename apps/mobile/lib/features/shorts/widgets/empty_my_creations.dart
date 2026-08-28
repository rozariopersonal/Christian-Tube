import 'package:flutter/material.dart';

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
                color: const Color(0xFF1E293B),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white12),
              ),
              child: const Icon(
                Icons.content_cut,
                size: 48,
                color: Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No Clips Created Yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'While watching any sermon or worship video, tap the "✂️ Clip Short" button to create an inspiring 1 to 3 minute clip!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
