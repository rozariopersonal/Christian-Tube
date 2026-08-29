import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
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
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                color: tokens.onSurfaceDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Reading Settings',
                style: TextStyle(
                  color: tokens.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: tokens.onSurfaceMuted, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Font Size Slider
          Text(
            'Font Size',
            style: TextStyle(
              color: tokens.onSurfaceMuted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('A', style: TextStyle(color: tokens.onSurface, fontSize: 14)),
              Expanded(
                child: Slider(
                  value: settings.fontSize,
                  min: 12.0,
                  max: 32.0,
                  divisions: 10,
                  activeColor: tokens.accent,
                  inactiveColor: tokens.onSurfaceDisabled,
                  onChanged: (value) {
                    onSettingsChanged(settings.copyWith(fontSize: value));
                  },
                ),
              ),
              Text('A', style: TextStyle(color: tokens.onSurface, fontSize: 24)),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
