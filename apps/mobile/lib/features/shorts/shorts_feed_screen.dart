import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/api/api_client.dart';
import '../../core/models/short.dart';
import '../../core/models/local_short_item.dart';
import '../../core/utils/formatters.dart';
import '../../shared/ui/channel_avatar.dart';
import 'native_shorts_player.dart';
import 'players/shorts_player.dart';
import '../../core/config/app_config.dart';
import 'services/shorts_orchestrator_service.dart';

enum ShortsViewTab {
  community,
  myCreations,
}

class ShortsFeedScreen extends StatefulWidget {
  const ShortsFeedScreen({super.key});

  @override
  State<ShortsFeedScreen> createState() => _ShortsFeedScreenState();
}

class _ShortsFeedScreenState extends State<ShortsFeedScreen> {
  final ApiClient _apiClient = ApiClient();
  final PageController _pageController = PageController();
  final PageController _localPageController = PageController();
  final ShortsOrchestratorService _orchestrator = ShortsOrchestratorService();

  List<Short> _shorts = [];
  bool _isLoading = true;
  int _currentPage = 0;
  int _currentLocalPage = 0;
  ShortsViewTab _activeTab = ShortsViewTab.community;

  @override
  void initState() {
    super.initState();
    _fetchShorts();
  }

  Future<void> _fetchShorts() async {
    try {
      final response = await _apiClient.dio.get(
        '/videos',
        queryParameters: {'type': 'SHORT', 'limit': 100},
      );
      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list =
            raw is List ? raw : (raw['videos'] ?? raw['data'] ?? []);

        final allVideos = list
            .whereType<Map<String, dynamic>>()
            .map((v) => Short.fromJson(v))
            .toList();

        if (allVideos.isNotEmpty) {
          // STRICT: Allow up to 3 minutes (180s) or explicitly SHORT
          final shortsOnly = allVideos.where((s) {
            if (s.durationSeconds > 0) {
              return s.durationSeconds <= 180;
            }
            final durSec = Short.parseDurationInSeconds(s.duration);
            if (durSec > 0) {
              return durSec <= 180;
            }
            final isShortUrl = s.videoUrl.toLowerCase().contains('/shorts/');
            final isShortTitle = s.title.toLowerCase().contains('#short');
            final isShortDesc =
                (s.description ?? '').toLowerCase().contains('#short');
            return isShortUrl || isShortTitle || isShortDesc || s.type == 'SHORT';
          }).toList();

          setState(() {
            _shorts = shortsOnly;
            _isLoading = false;
          });
          return;
        }
      }

      setState(() {
        _shorts = [];
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching shorts from video feed: $e');
      setState(() {
        _shorts = [];
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    stopAllPlatformShorts();
    _pageController.dispose();
    _localPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String currentPath = GoRouterState.of(context).uri.path;
    final bool isShortsTabActive = currentPath.startsWith('/shorts');
    final modalRoute = ModalRoute.of(context);
    final bool isRouteCurrent = modalRoute?.isCurrent ?? true;
    final bool isTabVisible = isShortsTabActive && isRouteCurrent;

    if (!isTabVisible) {
      stopAllPlatformShorts();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main Body
          Positioned.fill(
            child: _activeTab == ShortsViewTab.community
                ? _buildCommunityFeed(isTabVisible)
                : _buildMyCreationsFeed(),
          ),

          // Top Header & Tab Chips (Floating)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _buildTabChip(
                      label: '🌐 Community',
                      tab: ShortsViewTab.community,
                      count: null,
                    ),
                    const SizedBox(width: 8),
                    ListenableBuilder(
                      listenable: _orchestrator,
                      builder: (context, _) {
                        return _buildTabChip(
                          label: '🎬 My Creations',
                          tab: ShortsViewTab.myCreations,
                          count: _orchestrator.localShorts.length,
                        );
                      },
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white, size: 22),
                  onPressed: _fetchShorts,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip({
    required String label,
    required ShortsViewTab tab,
    int? count,
  }) {
    final isSelected = _activeTab == tab;
    return GestureDetector(
      onTap: () {
        setState(() => _activeTab = tab);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF59E0B)
              : Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFF59E0B) : Colors.white24,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            if (count != null && count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black : const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCommunityFeed(bool isTabVisible) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFF59E0B)),
      );
    }

    if (_shorts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.movie_outlined, size: 64, color: Colors.white54),
            const SizedBox(height: 12),
            Text(
              'No ${AppConfig.appName} Shorts available',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _fetchShorts,
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: _shorts.length,
      onPageChanged: (index) {
        setState(() => _currentPage = index);
      },
      itemBuilder: (context, index) {
        final short = _shorts[index];
        final isPlaying = isTabVisible && (index == _currentPage);

        return Stack(
          fit: StackFit.expand,
          children: [
            NativeShortsPlayer(short: short, isPlaying: isPlaying),

            // Gradient Overlay for readability
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black38,
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black87,
                      ],
                      stops: [0.0, 0.2, 0.65, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // Right Action Bar (Like, Share, etc.)
            Positioned(
              right: 12,
              bottom: 80,
              child: Column(
                children: [
                  _buildActionButton(
                    Icons.thumb_up_alt_outlined,
                    Formatters.formatViews(short.likeCount),
                  ),
                  const SizedBox(height: 16),
                  _buildActionButton(Icons.comment_outlined, 'Comments'),
                  const SizedBox(height: 16),
                  _buildActionButton(
                    Icons.share_outlined,
                    'Share',
                    onTap: () => Share.share(
                      'Watch this ${AppConfig.appName} Short: https://www.youtube.com/shorts/${short.id}',
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Info (Channel + Title + Watch Full Sermon Link)
            Positioned(
              left: 16,
              right: 70,
              bottom: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Watch Full Sermon Deep Link Button
                  if (short.sourceVideoId != null && short.sourceVideoId!.isNotEmpty) ...[
                    GestureDetector(
                      onTap: () {
                        context.push(
                          '/watch/${short.sourceVideoId}?start=${short.clipStartTime ?? 0}',
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withOpacity(0.9),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF59E0B).withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.play_circle_fill, size: 16, color: Colors.black),
                            SizedBox(width: 6),
                            Text(
                              'Watch Full Sermon',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.arrow_forward_ios, size: 10, color: Colors.black),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Channel & Creator Attribution
                  Row(
                    children: [
                      ChannelAvatar(
                        avatarUrl: short.channelAvatarUrl,
                        channelTitle: short.channelTitle,
                        radius: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '@${short.channelTitle}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            if (short.creatorName != null && short.creatorName!.isNotEmpty)
                              Text(
                                '✂️ Clipped by ${short.creatorName}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (short.duration != null && short.duration != '0:00') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white24, width: 0.5),
                          ),
                          child: Text(
                            short.duration!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    short.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMyCreationsFeed() {
    return ListenableBuilder(
      listenable: _orchestrator,
      builder: (context, _) {
        final items = _orchestrator.localShorts;

        if (items.isEmpty) {
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

        return PageView.builder(
          controller: _localPageController,
          scrollDirection: Axis.vertical,
          itemCount: items.length,
          onPageChanged: (index) {
            setState(() => _currentLocalPage = index);
          },
          itemBuilder: (context, index) {
            final item = items[index];

            return Stack(
              fit: StackFit.expand,
              children: [
                // Background Thumbnail / Video Preview
                Container(
                  color: const Color(0xFF0F172A),
                  child: Center(
                    child: item.sourceVideoThumbnail != null
                        ? Image.network(
                            item.sourceVideoThumbnail!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.movie,
                              size: 64,
                              color: Colors.white24,
                            ),
                          )
                        : const Icon(Icons.movie, size: 64, color: Colors.white24),
                  ),
                ),

                // Dark Readability Overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.5),
                          Colors.black.withOpacity(0.3),
                          Colors.black.withOpacity(0.85),
                        ],
                        stops: const [0.0, 0.4, 1.0],
                      ),
                    ),
                  ),
                ),

                // Center Status Banner & Play Icon
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: item.status == ShortCreationStatus.published
                            ? Colors.greenAccent
                            : item.status == ShortCreationStatus.failed
                                ? Colors.redAccent
                                : const Color(0xFFF59E0B),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.status == ShortCreationStatus.downloading ||
                            item.status == ShortCreationStatus.trimming ||
                            item.status == ShortCreationStatus.uploading) ...[
                          CircularProgressIndicator(
                            value: item.progress > 0 ? item.progress : null,
                            color: const Color(0xFFF59E0B),
                          ),
                          const SizedBox(height: 12),
                        ] else if (item.status == ShortCreationStatus.published) ...[
                          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 36),
                          const SizedBox(height: 8),
                        ] else if (item.status == ShortCreationStatus.scheduledUpload) ...[
                          const Icon(Icons.schedule, color: Color(0xFFF59E0B), size: 36),
                          const SizedBox(height: 8),
                        ] else ...[
                          const Icon(Icons.info_outline, color: Colors.white70, size: 36),
                          const SizedBox(height: 8),
                        ],
                        Text(
                          item.statusDisplay,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (item.status == ShortCreationStatus.scheduledUpload ||
                            item.status == ShortCreationStatus.failed) ...[
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: () => _orchestrator.retryUpload(item.id),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Retry Upload Now'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF59E0B),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Bottom Clip Info & Watch Full Sermon
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 28,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () {
                              context.push(
                                '/watch/${item.sourceVideoId}?start=${item.clipStartTime}',
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.play_circle_fill, size: 16, color: Colors.black),
                                  SizedBox(width: 6),
                                  Text(
                                    'Watch Full Sermon',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () => _orchestrator.deleteShort(item.id),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'From: ${item.sourceVideoTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildActionButton(IconData icon, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}
