import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/api/api_client.dart';
import '../../core/models/short.dart';
import '../../core/models/local_short_item.dart';
import '../../core/utils/formatters.dart';
import '../../shared/ui/channel_avatar.dart';
import 'native_shorts_player.dart';
import 'players/local_short_player.dart';
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
  ShortsViewTab _activeTab = ShortsViewTab.community;

  // Dynamic HUD Auto-Hide & Playhead Controller
  bool _isPlaying = true;
  bool _areControlsVisible = true;
  Timer? _autoHideTimer;
  bool _isScrubbing = false;
  double _currentPosition = 0.0;
  double _totalDuration = 0.0;

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

          final uri = GoRouterState.of(context).uri;
          final queryId = uri.queryParameters['id'] ?? uri.queryParameters['videoId'];
          int targetIndex = 0;
          if (queryId != null && queryId.isNotEmpty) {
            final idx = shortsOnly.indexWhere((s) => s.id == queryId || s.sourceVideoId == queryId);
            if (idx != -1) targetIndex = idx;
          }

          if (mounted) {
            setState(() {
              _shorts = shortsOnly;
              _isLoading = false;
              _currentPage = targetIndex;
            });
            if (targetIndex > 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_pageController.hasClients) {
                  _pageController.jumpToPage(targetIndex);
                }
              });
            }
            _startAutoHideTimer();
          }
          return;
        }
      }

      if (mounted) {
        setState(() {
          _shorts = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching shorts from video feed: $e');
      if (mounted) {
        setState(() {
          _shorts = [];
          _isLoading = false;
        });
      }
    }
  }

  void _startAutoHideTimer() {
    _autoHideTimer?.cancel();
    if (!_isPlaying || _isScrubbing) return;
    _autoHideTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _isPlaying && !_isScrubbing) {
        setState(() {
          _areControlsVisible = false;
        });
      }
    });
  }

  void _onScreenTap() {
    HapticFeedback.lightImpact();
    if (!_areControlsVisible) {
      // First tap reveals controls
      setState(() {
        _areControlsVisible = true;
      });
      _startAutoHideTimer();
    } else {
      // Subsequent tap toggles play/pause
      setState(() {
        _isPlaying = !_isPlaying;
      });
      if (_isPlaying) {
        _startAutoHideTimer();
      } else {
        _autoHideTimer?.cancel(); // Keep visible when paused
      }
    }
  }

  @override
  void dispose() {
    stopAllPlatformShorts();
    _autoHideTimer?.cancel();
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
          // 1. Main Feed Viewport
          Positioned.fill(
            child: _activeTab == ShortsViewTab.community
                ? _buildCommunityFeed(isTabVisible)
                : _buildMyCreationsFeed(),
          ),

          // 2. Top Smoothed Masking Header (Masks YouTube top title bar & share icon)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_areControlsVisible,
              child: AnimatedOpacity(
                opacity: _areControlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 16,
                    right: 16,
                    bottom: 32,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black,
                        Colors.black,
                        Color(0xCC000000),
                        Color(0x00000000),
                      ],
                      stops: [0.0, 0.55, 0.80, 1.0],
                    ),
                  ),
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
                              final activeCount = _orchestrator.activeJobsCount;
                              return _buildTabChip(
                                label: '🎬 My Creations',
                                tab: ShortsViewTab.myCreations,
                                count: _orchestrator.localShorts.length,
                                activeJobs: activeCount,
                              );
                            },
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white, size: 22),
                        onPressed: () {
                          _fetchShorts();
                          _startAutoHideTimer();
                        },
                      ),
                    ],
                  ),
                ),
              ),
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
    int activeJobs = 0,
  }) {
    final isSelected = _activeTab == tab;
    return GestureDetector(
      onTap: () {
        setState(() => _activeTab = tab);
        _startAutoHideTimer();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF59E0B)
              : Colors.black,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: activeJobs > 0
                ? const Color(0xFFF59E0B)
                : isSelected
                    ? const Color(0xFFF59E0B)
                    : Colors.white30,
            width: activeJobs > 0 ? 1.5 : 1.0,
          ),
          boxShadow: activeJobs > 0
              ? [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  )
                ]
              : null,
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
            if (activeJobs > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black : const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt,
                      size: 11,
                      color: isSelected ? const Color(0xFFF59E0B) : Colors.black,
                    ),
                    Text(
                      '$activeJobs',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (count != null && count > 0) ...[
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
        HapticFeedback.lightImpact();
        setState(() {
          _currentPage = index;
          _isPlaying = true;
          _areControlsVisible = true;
          _currentPosition = 0.0;
          _totalDuration = 0.0;
        });
        _startAutoHideTimer();
      },
      itemBuilder: (context, index) {
        final short = _shorts[index];
        return _buildShortPlayerStack(short, index, isTabVisible);
      },
    );
  }

  Widget _buildShortPlayerStack(Short short, int index, bool isTabVisible) {
    final isWithinSlidingWindow = (index - _currentPage).abs() <= 1;
    final isCurrentActive = index == _currentPage;
    final slotIndex = index % 3;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Sliding Window Slot Player / Static Thumbnail (1:1 Native Resolution)
        if (isWithinSlidingWindow)
          NativeShortsPlayer(
            key: ValueKey('slot_${slotIndex}_${short.id}'),
            short: short,
            isPlaying: isTabVisible && isCurrentActive && _isPlaying,
            slotIndex: slotIndex,
            onProgress: (cur, dur) {
              if (isCurrentActive && !_isScrubbing && mounted) {
                setState(() {
                  _currentPosition = cur;
                  if (dur > 0) _totalDuration = dur;
                });
              }
            },
          )
        else
          CachedNetworkImage(
            imageUrl: short.thumbnailUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: Colors.black),
            errorWidget: (_, __, ___) => Container(color: Colors.black),
          ),

        // 2. Full-Screen Tap Arena (Dynamic HUD Auto-Hide & Play/Pause)
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onScreenTap,
            child: const SizedBox.expand(),
          ),
        ),

        // 3. Floating Right Action Bar (Vibrant Gold Share Button)
        Positioned(
          right: 14,
          bottom: 92,
          child: IgnorePointer(
            ignoring: !_areControlsVisible,
            child: AnimatedOpacity(
              opacity: _areControlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: _buildShareButton(
                onTap: () => _shareShort(short),
              ),
            ),
          ),
        ),

        // 4. Bottom Smoothed Masking Overlay (Masks YouTube bottom logo & houses Playhead)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: !_areControlsVisible,
            child: AnimatedOpacity(
              opacity: _areControlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: Container(
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 48,
                  bottom: 14,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black,
                      Colors.black,
                      Color(0xEE000000),
                      Color(0x88000000),
                      Color(0x00000000),
                    ],
                    stops: [0.0, 0.50, 0.70, 0.88, 1.0],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Watch Full Sermon Deep Link Button
                    if (short.sourceVideoId != null && short.sourceVideoId!.isNotEmpty) ...[
                      GestureDetector(
                        onTap: () {
                          context.push(
                            '/watch/${short.sourceVideoId}?start=${(short.clipStartTime ?? 0).toInt()}',
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
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
                                  shadows: [
                                    Shadow(color: Colors.black, blurRadius: 4),
                                  ],
                                ),
                              ),
                              if (short.creatorName != null && short.creatorName!.isNotEmpty)
                                Text(
                                  '✂️ Clipped by ${short.creatorName}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    shadows: const [
                                      Shadow(color: Colors.black, blurRadius: 4),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
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
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 6),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Mobile Interactive Playhead Track
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final totalWidth = constraints.maxWidth;
                        final effectiveDuration = _totalDuration > 0
                            ? _totalDuration
                            : (short.durationSeconds > 0
                                ? short.durationSeconds.toDouble()
                                : 60.0);
                        final progressRatio = effectiveDuration > 0
                            ? (_currentPosition / effectiveDuration).clamp(0.0, 1.0)
                            : 0.0;
                        final double thumbSize = _isScrubbing ? 22.0 : 16.0;
                        final double trackHeight = _isScrubbing ? 6.0 : 4.0;

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (details) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _isScrubbing = true;
                              final localX = details.localPosition.dx.clamp(0.0, totalWidth);
                              _currentPosition = (localX / totalWidth) * effectiveDuration;
                            });
                            _autoHideTimer?.cancel();
                          },
                          onPanUpdate: (details) {
                            setState(() {
                              final localX = details.localPosition.dx.clamp(0.0, totalWidth);
                              _currentPosition = (localX / totalWidth) * effectiveDuration;
                            });
                          },
                          onPanEnd: (details) {
                            HapticFeedback.lightImpact();
                            final seekTarget = _currentPosition;
                            setState(() {
                              _isScrubbing = false;
                            });
                            seekPlatformShort(slotIndex, seekTarget);
                            _startAutoHideTimer();
                          },
                          child: SizedBox(
                            height: 52,
                            child: Stack(
                              alignment: Alignment.centerLeft,
                              clipBehavior: Clip.none,
                              children: [
                                // Floating Live Seek Time Bubble
                                if (_isScrubbing)
                                  Positioned(
                                    left: (totalWidth * progressRatio - 28)
                                        .clamp(0.0, totalWidth - 56),
                                    top: -24,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF59E0B),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Colors.black54,
                                            blurRadius: 4,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        Formatters.formatDuration(
                                          Duration(seconds: _currentPosition.toInt()),
                                        ),
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),

                                // Inactive Base Rail
                                Container(
                                  height: trackHeight,
                                  width: totalWidth,
                                  decoration: BoxDecoration(
                                    color: Colors.white24,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),

                                // Active Played Progress Rail
                                AnimatedContainer(
                                  duration: _isScrubbing
                                      ? Duration.zero
                                      : const Duration(milliseconds: 100),
                                  height: trackHeight,
                                  width: totalWidth * progressRatio,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFFBBF24),
                                        Color(0xFFF59E0B),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFF59E0B)
                                            .withValues(alpha: 0.6),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),

                                // Glowing Mobile Playhead Thumb
                                Positioned(
                                  left: (totalWidth * progressRatio - (thumbSize / 2))
                                      .clamp(0.0, totalWidth - thumbSize),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    width: thumbSize,
                                    height: thumbSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                      border: Border.all(
                                        color: const Color(0xFFF59E0B),
                                        width: _isScrubbing ? 3.5 : 2.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFF59E0B).withValues(
                                            alpha: _isScrubbing ? 0.8 : 0.4,
                                          ),
                                          blurRadius: _isScrubbing ? 10 : 6,
                                          spreadRadius: _isScrubbing ? 2 : 0,
                                        ),
                                        const BoxShadow(
                                          color: Colors.black54,
                                          blurRadius: 4,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 2),

                    // Timestamps (Current / Total)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          Formatters.formatDuration(
                            Duration(seconds: _currentPosition.toInt()),
                          ),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          Formatters.formatDuration(
                            Duration(
                              seconds: (_totalDuration > 0
                                      ? _totalDuration
                                      : (short.durationSeconds > 0
                                          ? short.durationSeconds.toDouble()
                                          : 60.0))
                                  .toInt(),
                            ),
                          ),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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
            setState(() {
              _currentPage = index;
            });
            _startAutoHideTimer();
          },
          itemBuilder: (context, index) {
            final item = items[index];
            final isPublished = item.status == ShortCreationStatus.published;

            if (isPublished) {
              final short = item.toShort();
              return _buildShortPlayerStack(short, index, true);
            }

            // If video has been rendered locally, allow normal full playback while uploading!
            if (item.localVideoPath != null && item.localVideoPath!.isNotEmpty) {
              return _buildLocalShortPlayerCard(item, index);
            }

            // Background Job Trimming / Extracting Stream View (Pre-Render)
            return _buildProgressCard(item);
          },
        );
      },
    );
  }

  Widget _buildLocalShortPlayerCard(LocalShortItem item, int index) {
    final isCurrentActive = index == _currentPage;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Live Local Rendered MP4 Video Player
        LocalShortPlayer(
          key: ValueKey('local_player_${item.id}_${item.localVideoPath}'),
          item: item,
          isPlaying: isCurrentActive && _isPlaying,
          onProgress: (cur, dur) {
            if (isCurrentActive && !_isScrubbing && mounted) {
              setState(() {
                _currentPosition = cur;
                if (dur > 0) _totalDuration = dur;
              });
            }
          },
        ),

        // 2. Full-Screen Tap Arena (Play/Pause & Controls HUD toggle)
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onScreenTap,
            child: const SizedBox.expand(),
          ),
        ),

        // 3. Floating One-Line Status Chip at Top
        Positioned(
          top: 60,
          left: 16,
          right: 16,
          child: Center(
            child: _buildStatusChip(item),
          ),
        ),

        // 4. Floating Action Bar (Share)
        Positioned(
          right: 14,
          bottom: 92,
          child: IgnorePointer(
            ignoring: !_areControlsVisible,
            child: AnimatedOpacity(
              opacity: _areControlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: _buildShareButton(
                onTap: () => _shareShort(item.toShort()),
              ),
            ),
          ),
        ),

        // 5. Bottom HUD
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: !_areControlsVisible,
            child: AnimatedOpacity(
              opacity: _areControlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: Container(
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 48,
                  bottom: 14,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black,
                      Colors.black,
                      Color(0xEE000000),
                      Color(0x88000000),
                      Color(0x00000000),
                    ],
                    stops: [0.0, 0.50, 0.70, 0.88, 1.0],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () {
                            context.push(
                              '/watch/${item.sourceVideoId}?start=${item.clipStartTime.toInt()}',
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
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
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.white70, size: 20),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Scrubber Track
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final totalWidth = constraints.maxWidth;
                        final dur = _totalDuration > 0
                            ? _totalDuration
                            : (item.clipEndTime - item.clipStartTime > 0
                                ? (item.clipEndTime - item.clipStartTime)
                                : 60.0);
                        final ratio = (_currentPosition / dur).clamp(0.0, 1.0);

                        return Column(
                          children: [
                            Container(
                              height: 4,
                              width: totalWidth,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  width: totalWidth * ratio,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  Formatters.formatDuration(Duration(seconds: _currentPosition.toInt())),
                                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                                ),
                                Text(
                                  Formatters.formatDuration(Duration(seconds: dur.toInt())),
                                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressCard(LocalShortItem item) {
    return Stack(
      fit: StackFit.expand,
      children: [
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
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.7),
                  Colors.black.withValues(alpha: 0.5),
                  Colors.black.withValues(alpha: 0.95),
                ],
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
          ),
        ),

        // Centered One-Line Status Chip for Pre-Render Stage
        Center(
          child: _buildStatusChip(item),
        ),

        // Bottom Info
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
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
  }

  Widget _buildStatusChip(LocalShortItem item) {
    Color borderColor = const Color(0xFFF59E0B);
    Color textColor = Colors.white;

    if (item.status == ShortCreationStatus.failed) {
      borderColor = Colors.redAccent;
    } else if (item.status == ShortCreationStatus.published) {
      borderColor = Colors.greenAccent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor.withValues(alpha: 0.85), width: 1.2),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.status == ShortCreationStatus.downloading) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)),
            ),
            const SizedBox(width: 8),
            Text(
              '📥 Extracting ${(item.progress * 100).toInt()}%',
              style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ] else if (item.status == ShortCreationStatus.trimming) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)),
            ),
            const SizedBox(width: 8),
            Text(
              '✂️ Rendering ${(item.progress * 100).toInt()}%',
              style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ] else if (item.status == ShortCreationStatus.uploading) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)),
            ),
            const SizedBox(width: 8),
            Text(
              '⚡ Uploading ${(item.progress * 100).toInt()}%',
              style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ] else if (item.status == ShortCreationStatus.processing) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent),
            ),
            const SizedBox(width: 8),
            Text(
              '🔄 Syncing...',
              style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ] else if (item.status == ShortCreationStatus.scheduledUpload) ...[
            const Icon(Icons.schedule, size: 14, color: Color(0xFFF59E0B)),
            const SizedBox(width: 6),
            Text(
              '⏰ Scheduled • ',
              style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            GestureDetector(
              onTap: () => _orchestrator.retryUpload(item.id),
              child: const Text(
                'Retry',
                style: TextStyle(
                  color: Color(0xFFF59E0B),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ] else if (item.status == ShortCreationStatus.failed) ...[
            const Icon(Icons.error_outline, size: 14, color: Colors.redAccent),
            const SizedBox(width: 6),
            Text(
              '⚠️ Notice • ',
              style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            GestureDetector(
              onTap: () => _orchestrator.retryUpload(item.id),
              child: const Text(
                'Retry',
                style: TextStyle(
                  color: Color(0xFFF59E0B),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ] else ...[
            const Icon(Icons.play_circle_filled, size: 14, color: Colors.greenAccent),
            const SizedBox(width: 6),
            Text(
              '🎬 Local Video',
              style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  void _shareShort(Short short) {
    HapticFeedback.lightImpact();
    _startAutoHideTimer();
    final appUrl = 'https://christiantube.app/#/watch/${short.sourceVideoId ?? short.id}?start=${(short.clipStartTime ?? 0).toInt()}';
    final ytUrl = 'https://www.youtube.com/shorts/${short.id}';

    Share.share(
      '🎬 "${short.title}"\n\n'
      '📱 Open in ${AppConfig.appName}:\n$appUrl\n\n'
      '▶️ Watch on YouTube:\n$ytUrl',
      subject: 'Watch "${short.title}" on ${AppConfig.appName}',
    );
  }

  Widget _buildShareButton({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
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
