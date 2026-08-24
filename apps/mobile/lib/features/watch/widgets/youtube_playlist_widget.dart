import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/video.dart';

enum PlaylistLoopMode { off, all, one }

class YouTubePlaylistWidget extends StatefulWidget {
  final String title;
  final List<Video> playlist;
  final int currentIndex;
  final Function(int index) onSelectVideo;
  final Function() onPrevious;
  final Function() onNext;
  final PlaylistLoopMode loopMode;
  final Function(PlaylistLoopMode mode) onToggleLoop;
  final bool isShuffle;
  final Function() onToggleShuffle;
  final bool isAutoplay;
  final Function(bool enabled) onToggleAutoplay;

  const YouTubePlaylistWidget({
    super.key,
    required this.title,
    required this.playlist,
    required this.currentIndex,
    required this.onSelectVideo,
    required this.onPrevious,
    required this.onNext,
    required this.loopMode,
    required this.onToggleLoop,
    required this.isShuffle,
    required this.onToggleShuffle,
    required this.isAutoplay,
    required this.onToggleAutoplay,
  });

  @override
  State<YouTubePlaylistWidget> createState() => _YouTubePlaylistWidgetState();
}

class _YouTubePlaylistWidgetState extends State<YouTubePlaylistWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final total = widget.playlist.length;
    final currentNumber = widget.currentIndex + 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        children: [
          // Playlist Header & Main Controls Bar
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.playlist_play, color: Color(0xFF3B82F6), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Video $currentNumber of $total',
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Action Row: Loop, Shuffle, Autoplay, Prev, Next
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Loop Button
                      IconButton(
                        icon: Icon(
                          widget.loopMode == PlaylistLoopMode.one
                              ? Icons.repeat_one
                              : widget.loopMode == PlaylistLoopMode.all
                                  ? Icons.repeat
                                  : Icons.repeat,
                          color: widget.loopMode != PlaylistLoopMode.off
                              ? const Color(0xFF3B82F6)
                              : Colors.grey,
                          size: 20,
                        ),
                        tooltip: widget.loopMode == PlaylistLoopMode.one
                            ? 'Loop Video'
                            : widget.loopMode == PlaylistLoopMode.all
                                ? 'Loop Playlist'
                                : 'Loop Off',
                        onPressed: () {
                          if (widget.loopMode == PlaylistLoopMode.off) {
                            widget.onToggleLoop(PlaylistLoopMode.all);
                          } else if (widget.loopMode == PlaylistLoopMode.all) {
                            widget.onToggleLoop(PlaylistLoopMode.one);
                          } else {
                            widget.onToggleLoop(PlaylistLoopMode.off);
                          }
                        },
                      ),

                      // Shuffle Button
                      IconButton(
                        icon: Icon(
                          Icons.shuffle,
                          color: widget.isShuffle ? const Color(0xFF3B82F6) : Colors.grey,
                          size: 20,
                        ),
                        tooltip: 'Shuffle',
                        onPressed: widget.onToggleShuffle,
                      ),

                      // Previous Track
                      IconButton(
                        icon: const Icon(Icons.skip_previous, size: 22),
                        onPressed: widget.currentIndex > 0 ? widget.onPrevious : null,
                      ),

                      // Next Track
                      IconButton(
                        icon: const Icon(Icons.skip_next, size: 22),
                        onPressed: (widget.currentIndex < total - 1 || widget.loopMode == PlaylistLoopMode.all)
                            ? widget.onNext
                            : null,
                      ),

                      // Autoplay Switch
                      Row(
                        children: [
                          const Text('Autoplay', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          const SizedBox(width: 4),
                          Switch(
                            value: widget.isAutoplay,
                            activeColor: const Color(0xFF3B82F6),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            onChanged: widget.onToggleAutoplay,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Collapsible Playlist Queue
          if (_isExpanded) ...[
            const Divider(height: 1),
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: widget.playlist.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
                itemBuilder: (context, index) {
                  final video = widget.playlist[index];
                  final isCurrent = index == widget.currentIndex;

                  return InkWell(
                    onTap: () => widget.onSelectVideo(index),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      color: isCurrent
                          ? (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))
                          : Colors.transparent,
                      child: Row(
                        children: [
                          // Track index / Playing indicator
                          SizedBox(
                            width: 24,
                            child: isCurrent
                                ? const Icon(Icons.play_arrow_rounded, color: Color(0xFF3B82F6), size: 20)
                                : Text(
                                    '${index + 1}',
                                    style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                  ),
                          ),
                          const SizedBox(width: 8),

                          // Thumbnail
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 60,
                              height: 38,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CachedNetworkImage(
                                    imageUrl: video.thumbnailUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(color: Colors.grey.shade800),
                                    errorWidget: (_, __, ___) => Container(color: Colors.grey.shade800),
                                  ),
                                  if (video.duration != null && video.duration!.isNotEmpty)
                                    Positioned(
                                      bottom: 2,
                                      right: 2,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.black87,
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                        child: Text(
                                          video.duration!,
                                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Video Title & Channel
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  video.title,
                                  style: TextStyle(
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 13,
                                    color: isCurrent ? const Color(0xFF3B82F6) : null,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  video.channelTitle,
                                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
