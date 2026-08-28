import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/short.dart';

class ShortActionBar extends StatelessWidget {
  final Short short;
  final VoidCallback onShare;

  const ShortActionBar({
    super.key,
    required this.short,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildShareButton(),
      ],
    );
  }

  Widget _buildShareButton() {
    return GestureDetector(
      onTap: onShare,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFBBF24),
                  Color(0xFFF59E0B),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.65),
                  blurRadius: 12,
                  spreadRadius: 1,
                  offset: const Offset(0, 3),
                ),
                const BoxShadow(
                  color: Colors.black54,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: const Icon(
              Icons.share_rounded,
              color: Colors.black,
              size: 24,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Share',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              shadows: [
                Shadow(color: Colors.black, blurRadius: 6),
                Shadow(color: Colors.black, blurRadius: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
