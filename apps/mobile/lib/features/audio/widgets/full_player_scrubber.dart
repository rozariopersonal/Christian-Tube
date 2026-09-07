import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';

/// Draggable progress scrubber with live inbound/outbound time labels.
/// Holds drag state locally (presentational) and reports seek targets via
/// [onScrub].
class FullPlayerScrubber extends StatefulWidget {
  final double value;
  final Duration duration;
  final ValueChanged<Duration> onScrub;

  const FullPlayerScrubber({
    super.key,
    required this.value,
    required this.duration,
    required this.onScrub,
  });

  @override
  State<FullPlayerScrubber> createState() => _FullPlayerScrubberState();
}

class _FullPlayerScrubberState extends State<FullPlayerScrubber> {
  bool _isDragging = false;
  double _dragProgress = 0.0;

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    final currentProgress = _isDragging ? _dragProgress : widget.value;
    final displayPosition = _isDragging
        ? Duration(
            milliseconds:
                (_dragProgress * widget.duration.inMilliseconds).toInt())
        : Duration(
            milliseconds:
                (widget.value * widget.duration.inMilliseconds).toInt());

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3.5,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 6,
            ),
            overlayShape: const RoundSliderOverlayShape(
              overlayRadius: 14,
            ),
            activeTrackColor: theme.colorScheme.primary,
            inactiveTrackColor: tokens.surfaceVariant,
            thumbColor: theme.colorScheme.primary,
          ),
          child: Slider(
            value: currentProgress,
            onChanged: (val) {
              setState(() {
                _isDragging = true;
                _dragProgress = val;
              });
            },
            onChangeEnd: (val) {
              widget.onScrub(
                Duration(
                  milliseconds: (val * widget.duration.inMilliseconds).toInt(),
                ),
              );
              setState(() {
                _isDragging = false;
              });
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(displayPosition),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
              ),
              Text(
                _formatDuration(widget.duration),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}