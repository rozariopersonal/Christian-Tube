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
import 'players/shorts_player.dart';
import '../../core/config/app_config.dart';
import '../../core/services/bottom_bar_visibility_service.dart';
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

  final ScrollController _communityScrollController = ScrollController();

  List<Short> _shorts = [];
  bool _isLoading = true;
  int _currentPage = 0;
  ShortsViewTab _activeTab = ShortsViewTab.community;

  // View state: null = Grid View, int = Fullscreen Short Player
  int? _selectedCommunityIndex;
  int? _selectedCreationIndex;

  // Infinite Scroll Pagination
  int _communityPage = 1;
  bool _hasMoreShorts = true;
  bool _isLoadingMore = false;

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
    BottomBarVisibilityService.instance.setShortPlaying(true);
    _fetchShorts();
    _orchestrator.fetchCloudCreations();
    _communityScrollController.addListener(_onCommunityScroll);
  }

  @override
  void dispose() {
    BottomBarVisibilityService.instance.setShortPlaying(false);
    _communityScrollController.removeListener(_onCommunityScroll);
    _communityScrollController.dispose();
    _pageController.dispose();
    _localPageController.dispose();
    _autoHideTimer?.cancel();
    super.dispose();
  }

  void _onCommunityScroll() {
    if (_communityScrollController.hasClients &&
        _communityScrollController.position.pixels >=
            _communityScrollController.position.maxScrollExtent - 400) {
      _loadMoreShorts();
    }
  }

  Future<void> _fetchShorts() async {
    try {
      _communityPage = 1;
      _hasMoreShorts = true;
      final response = await _apiClient.dio.get(
        '/videos',
        queryParameters: {'type': 'SHORT', 'limit': 30, 'page': 1},
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
          int targetIndex = -1;
          if (queryId != null && queryId.isNotEmpty) {
            final idx = shortsOnly.indexWhere((s) => s.id == queryId || s.sourceVideoId == queryId);
            if (idx != -1) targetIndex = idx;
          }

          if (mounted) {
            setState(() {
              _shorts = shortsOnly;
              _isLoading = false;
              if (targetIndex >= 0) {
                _selectedCommunityIndex = targetIndex;
                _currentPage = targetIndex;
              }
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
      debugPrint('Error fetching shorts: $e');
      if (mounted) {
        setState(() {
          _shorts = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreShorts() async {
    if (_isLoadingMore || !_hasMoreShorts) return;
    _isLoadingMore = true;
    try {
      final nextPage = _communityPage + 1;
      final response = await _apiClient.dio.get(
        '/videos',
        queryParameters: {'type': 'SHORT', 'limit': 30, 'page': nextPage},
      );
      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list =
            raw is List ? raw : (raw['videos'] ?? raw['data'] ?? []);

        final newVideos = list
            .whereType<Map<String, dynamic>>()
            .map((v) => Short.fromJson(v))
            .where((s) => s.durationSeconds <= 180 || s.type == 'SHORT')
            .toList();

        if (newVideos.isEmpty) {
          _hasMoreShorts = false;
        } else {
          _communityPage = nextPage;
          final existingIds = _shorts.map((s) => s.id).toSet();
          final uniqueNew = newVideos.where((s) => !existingIds.contains(s.id)).toList();
          if (mounted) {
            setState(() {
              _shorts.addAll(uniqueNew);
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Load more shorts error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
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
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                            tooltip: 'Back',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            onPressed: () {
                              if (Navigator.of(context).canPop()) {
                                Navigator.of(context).pop();
                              } else {
                                context.go('/feed');
                              }
                            },
                          ),
                          const SizedBox(width: 8),
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
        setState(() {
          _activeTab = tab;
          if (tab == ShortsViewTab.community) {
            _selectedCreationIndex = null;
          }
        });
        if (tab == ShortsViewTab.myCreations) {
          _orchestrator.fetchCloudCreations();
        }
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

    // 1. Initial State: Infinite Scroll Grid
    if (_selectedCommunityIndex == null) {
      return _buildCommunityGrid();
    }

    // 2. Expanded State: Full-Screen Vertical Shorts Player
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: _shorts.length,
          onPageChanged: (index) {
            HapticFeedback.lightImpact();
            setState(() {
              _currentPage = index;
              _selectedCommunityIndex = index;
              _isPlaying = true;
              _areControlsVisible = true;
              _currentPosition = 0.0;
              _totalDuration = 0.0;
            });
            _startAutoHideTimer();
            if (index >= _shorts.length - 4) {
              _loadMoreShorts();
            }
          },
          itemBuilder: (context, index) {
            final short = _shorts[index];
            return _buildShortPlayerStack(short, index, isTabVisible);
          },
        ),

        // Top-Left Back Button to Return to Shorts Grid
        Positioned(
          top: 54,
          left: 12,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedCommunityIndex = null;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white30),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_ios_new, size: 13, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Shorts Grid',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCommunityGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900
            ? 4
            : constraints.maxWidth > 600
                ? 3
                : 2;

        return CustomScrollView(
          controller: _communityScrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 75, 16, 14),
              sliver: SliverToBoxAdapter(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_shorts.length} Shorts',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _fetchShorts,
                      icon: const Icon(Icons.refresh, size: 16, color: Color(0xFFF59E0B)),
                      label: const Text(
                        'Refresh',
                        style: TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 9 / 16,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final short = _shorts[index];
                    return _buildCommunityGridCard(short, index);
                  },
                  childCount: _shorts.length,
                ),
              ),
            ),
            if (_isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFF59E0B)),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        );
      },
    );
  }

  Widget _buildCommunityGridCard(Short short, int index) {
    final durSec = short.durationSeconds > 0
        ? short.durationSeconds
        : Short.parseDurationInSeconds(short.duration);

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCommunityIndex = index;
          _currentPage = index;
          _pageController.jumpToPage(index);
          _isPlaying = true;
          _areControlsVisible = true;
          _currentPosition = 0.0;
          _totalDuration = 0.0;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Thumbnail
            if (short.thumbnailUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: short.thumbnailUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: const Color(0xFF0F172A)),
                errorWidget: (_, __, ___) => Container(
                  color: const Color(0xFF0F172A),
                  child: const Center(child: Icon(Icons.movie, color: Colors.white24, size: 36)),
                ),
              )
            else
              Container(
                color: const Color(0xFF0F172A),
                child: const Center(child: Icon(Icons.movie, color: Colors.white24, size: 36)),
              ),

            // 2. Gradient Overlay
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x77000000),
                    Color(0x00000000),
                    Color(0xDD000000),
                  ],
                  stops: [0.0, 0.4, 1.0],
                ),
              ),
            ),

            // 3. View Count / Verified Chip Top-Left
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24, width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.remove_red_eye, size: 10, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 4),
                    Text(
                      short.viewCount > 0 ? Formatters.formatViews(short.viewCount) : 'Short',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

            // 4. Duration Badge Top-Right
            if (durSec > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    Formatters.formatDuration(Duration(seconds: durSec)),
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

            // 5. Play Icon in Center
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white70,
                size: 38,
              ),
            ),

            // 6. Bottom Title & Channel
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    short.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (short.channelAvatarUrl != null && short.channelAvatarUrl!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: short.channelAvatarUrl!,
                            width: 16,
                            height: 16,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const Icon(Icons.person, size: 16, color: Colors.white70),
                          ),
                        )
                      else
                        const Icon(Icons.account_circle, size: 16, color: Colors.white70),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          short.channelTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortPlayerStack(
    Short short,
    int index,
    bool isTabVisible, {
    Widget? topStatusChip,
  }) {
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

        // 2.5 Floating Status Chip (One-Line Indicator)
        if (topStatusChip != null)
          Positioned(
            top: 60,
            left: 16,
            right: 16,
            child: Center(
              child: topStatusChip,
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

        // 1. Initial State: Grid View of User's Creations
        if (_selectedCreationIndex == null) {
          return _buildCreationsGrid(items);
        }

        // 2. Expanded State: Full-Screen Interactive Shorts Player
        return Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _localPageController,
              scrollDirection: Axis.vertical,
              itemCount: items.length,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                  _selectedCreationIndex = index;
                  _isPlaying = true;
                  _areControlsVisible = true;
                  _currentPosition = 0.0;
                  _totalDuration = 0.0;
                });
                _startAutoHideTimer();
              },
              itemBuilder: (context, index) {
                final item = items[index];
                final short = item.toShort();
                final isPublished = item.status == ShortCreationStatus.published;
                final statusChip = isPublished ? null : _buildStatusChip(item);

                return _buildShortPlayerStack(
                  short,
                  index,
                  true,
                  topStatusChip: statusChip,
                );
              },
            ),

            // Top-Left Back Button to Return to Creations Grid
            Positioned(
              top: 54,
              left: 12,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedCreationIndex = null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white30),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_ios_new, size: 13, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'Creations Grid',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCreationsGrid(List<LocalShortItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900
            ? 4
            : constraints.maxWidth > 600
                ? 3
                : 2;

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 75, 16, 14),
              sliver: SliverToBoxAdapter(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${items.length} ${items.length == 1 ? 'Creation' : 'Creations'}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _orchestrator.fetchCloudCreations(),
                      icon: const Icon(Icons.sync, size: 16, color: Color(0xFFF59E0B)),
                      label: const Text(
                        'Refresh',
                        style: TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 9 / 16,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = items[index];
                    return _buildCreationGridCard(item, index);
                  },
                  childCount: items.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        );
      },
    );
  }

  Widget _buildCreationGridCard(LocalShortItem item, int index) {
    final durSec = (item.clipEndTime - item.clipStartTime).toInt();

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCreationIndex = index;
          _currentPage = index;
          _localPageController.jumpToPage(index);
          _isPlaying = true;
          _areControlsVisible = true;
          _currentPosition = 0.0;
          _totalDuration = 0.0;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: item.status == ShortCreationStatus.failed
                ? Colors.redAccent.withValues(alpha: 0.6)
                : item.status == ShortCreationStatus.uploading
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.8)
                    : Colors.white12,
            width: item.status == ShortCreationStatus.uploading ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail
            if (item.sourceVideoThumbnail != null && item.sourceVideoThumbnail!.isNotEmpty)
              CachedNetworkImage(
                imageUrl: item.sourceVideoThumbnail!,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: const Color(0xFF0F172A)),
                errorWidget: (_, __, ___) => Container(
                  color: const Color(0xFF0F172A),
                  child: const Center(child: Icon(Icons.movie, color: Colors.white24, size: 36)),
                ),
              )
            else
              Container(
                color: const Color(0xFF0F172A),
                child: const Center(child: Icon(Icons.movie, color: Colors.white24, size: 36)),
              ),

            // Subtle Gradient Overlay
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x77000000),
                    Color(0x00000000),
                    Color(0xDD000000),
                  ],
                  stops: [0.0, 0.4, 1.0],
                ),
              ),
            ),

            // Top Status Badge Chip
            Positioned(
              top: 8,
              left: 8,
              child: _buildGridBadge(item),
            ),

            // Duration Badge Top-Right
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  Formatters.formatDuration(Duration(seconds: durSec > 0 ? durSec : 60)),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            // Play Icon in Center
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white70,
                size: 38,
              ),
            ),

            // Bottom Title & Sermon Source
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
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
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.sourceVideoTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridBadge(LocalShortItem item) {
    if (item.status == ShortCreationStatus.uploading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 9,
              height: 9,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.black),
            ),
            const SizedBox(width: 4),
            Text(
              '${(item.progress * 100).toInt()}%',
              style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    } else if (item.status == ShortCreationStatus.downloading || item.status == ShortCreationStatus.trimming) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFF59E0B), width: 1),
        ),
        child: Text(
          item.status == ShortCreationStatus.downloading ? 'Extracting' : 'Rendering',
          style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.bold),
        ),
      );
    } else if (item.status == ShortCreationStatus.failed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'Notice',
          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
        ),
      );
    } else if (item.status == ShortCreationStatus.scheduledUpload) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.orangeAccent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'Scheduled',
          style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'Live',
        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
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
              '🎬 Standard Short',
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
