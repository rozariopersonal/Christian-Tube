import 'package:flutter/material.dart';
import '../models/bible_settings.dart';

class ReadingSettingsSheet extends StatelessWidget {
  final BibleSettings settings;
  final ValueChanged<BibleSettings> onSettingsChanged;

  const ReadingSettingsSheet({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Reading Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Font Size Slider
          const Text(
            'Font Size',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('A', style: TextStyle(color: Colors.white, fontSize: 14)),
              Expanded(
                child: Slider(
                  value: settings.fontSize,
                  min: 12.0,
                  max: 32.0,
                  divisions: 10,
                  activeColor: const Color(0xFFF59E0B),
                  inactiveColor: Colors.white24,
                  onChanged: (value) {
                    onSettingsChanged(settings.copyWith(fontSize: value));
                  },
                ),
              ),
              const Text('A', style: TextStyle(color: Colors.white, fontSize: 24)),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
