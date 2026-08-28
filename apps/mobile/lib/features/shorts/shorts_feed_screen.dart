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
import 'players/local_short_player.dart';
import '../search/shorts_search_delegate.dart';
import '../../core/config/app_config.dart';
import '../../core/services/bottom_bar_visibility_service.dart';
import 'services/shorts_orchestrator_service.dart';

enum ShortsViewTab {
  community,
  myCreations,
}

class ShortsFeedScreen extends StatefulWidget {
  final String? initialShortId;
  final int? initialIndex;

  const ShortsFeedScreen({
    super.key,
    this.initialShortId,
    this.initialIndex,
  });

  @override
  State<ShortsFeedScreen> createState() => _ShortsFeedScreenState();
}

class _ShortsFeedScreenState extends State<ShortsFeedScreen> {
  late final ApiClient _apiClient;
  PageController _pageController = PageController();
  PageController _localPageController = PageController();
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

  // Play/Pause Animated Overlay
  bool _showPlayPauseOverlay = false;
  bool _playPauseOverlayPlaying = true;
  Timer? _overlayTimer;
  
  bool _isMuted = false;

  // Engagement & Filter State
  final Set<String> _blessedShortIds = {};
  final Set<String> _savedShortIds = {};
  bool _showHeartOverlay = false;
  Timer? _heartOverlayTimer;
  String _communityFilter = 'all'; // 'all', 'popular', 'recent'

  StreamSubscription<void>? _shortsResetSub;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient(); // Issue #12: initialized once, not on every rebuild
    _fetchShorts();
    _orchestrator.fetchCloudCreations();
    _communityScrollController.addListener(_onCommunityScroll);

    // Reset to grid when the Shorts bottom-nav tab is re-tapped
    _shortsResetSub = BottomBarVisibilityService.instance
        .onShortsResetRequested
        .listen((_) => _handleTabReset());
  }

  @override
  void didUpdateWidget(ShortsFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.initialShortId != null && widget.initialShortId != oldWidget.initialShortId) ||
        (widget.initialIndex != null && widget.initialIndex != oldWidget.initialIndex)) {
      _applyInitialTarget();
    }
  }

  void _openCommunityShortAt(int index) {
    if (index < 0 || index >= _shorts.length) return;
    if (_pageController.hasClients) {
      _pageController.jumpToPage(index);
    } else {
      _pageController = PageController(initialPage: index);
    }
    setState(() {
      _selectedCommunityIndex = index;
      _currentPage = index;
      _isPlaying = true;
      _areControlsVisible = true;
      _currentPosition = 0.0;
      _totalDuration = 0.0;
    });
    BottomBarVisibilityService.instance.setShortPlaying(true);
    _startAutoHideTimer();
  }

  void _openCreationShortAt(int index) {
    final list = _orchestrator.localShorts;
    if (index < 0 || index >= list.length) return;
    if (_localPageController.hasClients) {
      _localPageController.jumpToPage(index);
    } else {
      _localPageController = PageController(initialPage: index);
    }
    setState(() {
      _selectedCreationIndex = index;
      _currentPage = index;
      _isPlaying = true;
      _areControlsVisible = true;
      _currentPosition = 0.0;
      _totalDuration = 0.0;
    });
    BottomBarVisibilityService.instance.setShortPlaying(true);
    _startAutoHideTimer();
  }

  void _closeShortPlayer() {
    stopAllPlatformShorts();
    if (mounted) {
      setState(() {
        _selectedCommunityIndex = null;
        _selectedCreationIndex = null;
        _isPlaying = true;
        _areControlsVisible = true;
        _currentPosition = 0.0;
        _totalDuration = 0.0;
      });
    }
    _autoHideTimer?.cancel();
    _overlayTimer?.cancel();
    _heartOverlayTimer?.cancel();
    BottomBarVisibilityService.instance.setShortPlaying(false);
  }

  void _applyInitialTarget() {
    if (_shorts.isEmpty) return;
    int target = -1;
    if (widget.initialShortId != null && widget.initialShortId!.isNotEmpty) {
      final idx = _shorts.indexWhere(
        (s) => s.id == widget.initialShortId || s.sourceVideoId == widget.initialShortId,
      );
      if (idx != -1) target = idx;
    }
    if (target == -1 && widget.initialIndex != null && widget.initialIndex! >= 0 && widget.initialIndex! < _shorts.length) {
      target = widget.initialIndex!;
    }
    if (target >= 0) {
      _openCommunityShortAt(target);
    }
  }

  @override
  void dispose() {
    _shortsResetSub?.cancel();
    stopAllPlatformShorts();
    BottomBarVisibilityService.instance.setShortPlaying(false);
    _communityScrollController.removeListener(_onCommunityScroll);
    _communityScrollController.dispose();
    _pageController.dispose();
    _localPageController.dispose();
    _autoHideTimer?.cancel();
    _overlayTimer?.cancel();
    _heartOverlayTimer?.cancel();
    super.dispose();
  }

  /// Called when the Shorts tab is re-tapped. Closes the player (if open) and
  /// scrolls the grid back to the top.
  void _handleTabReset() {
    if (!mounted) return;
    _closeShortPlayer();
    // Scroll community grid to top if it is the active feed
    if (_activeTab == ShortsViewTab.community &&
        _communityScrollController.hasClients &&
        _communityScrollController.offset > 0) {
      _communityScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
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
        queryParameters: {'type': 'SHORT', 'limit': 30, 'offset': 0},
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

          if (mounted) {
            setState(() {
              _shorts = shortsOnly;
              _isLoading = false;
            });
            _applyInitialTarget();
            if (_selectedCommunityIndex == null) {
              final uri = GoRouterState.of(context).uri;
              final queryId = uri.queryParameters['id'] ?? uri.queryParameters['videoId'];
              if (queryId != null && queryId.isNotEmpty) {
                final idx = shortsOnly.indexWhere((s) => s.id == queryId || s.sourceVideoId == queryId);
                if (idx != -1) {
                  _openCommunityShortAt(idx);
                }
              }
            }
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
      final offset = (nextPage - 1) * 30;
      final response = await _apiClient.dio.get(
        '/videos',
        queryParameters: {'type': 'SHORT', 'limit': 30, 'offset': offset},
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

  void _showPlayPauseIndicator(bool isPlaying) {
    _overlayTimer?.cancel();
    setState(() {
      _showPlayPauseOverlay = true;
      _playPauseOverlayPlaying = isPlaying;
    });
    _overlayTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() {
          _showPlayPauseOverlay = false;
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
      _autoHideTimer?.cancel(); // Kill stale timer from scrub or prior state
      setState(() {
        _isPlaying = !_isPlaying;
      });
      _showPlayPauseIndicator(_isPlaying);
      if (_isPlaying) {
        _startAutoHideTimer(); // Fresh 10s window from resume
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

    final bool isPlayerOpen = _selectedCommunityIndex != null || _selectedCreationIndex != null;

    return PopScope(
      canPop: !isPlayerOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isPlayerOpen) {
          _closeShortPlayer();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // 1. Main Feed Viewport
            Positioned.fill(
              child: _activeTab == ShortsViewTab.community
                  ? _buildCommunityFeed(isTabVisible)
                  : _buildMyCreationsFeed(),
            ),

            // 2a. Top Gradient + HUD Controls (fade with auto-hide)
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
                        // Back button placeholder — same width as the icon so tab chips
                        // align correctly when the full row is measured
                        const SizedBox(width: 32),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.search, color: Colors.white, size: 22),
                              tooltip: 'Search Shorts',
                              onPressed: () async {
                                _autoHideTimer?.cancel();
                                final selectedShort = await showSearch<Short?>(
                                  context: context,
                                  delegate: ShortsSearchDelegate(),
                                );
                                if (selectedShort != null && mounted) {
                                  final idx = _shorts.indexWhere((s) => s.id == selectedShort.id);
                                  if (idx != -1) {
                                    _openCommunityShortAt(idx);
                                  } else {
                                    setState(() {
                                      _shorts.insert(0, selectedShort);
                                    });
                                    _openCommunityShortAt(0);
                                  }
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh, color: Colors.white, size: 22),
                              tooltip: 'Refresh',
                              onPressed: () {
                                _fetchShorts();
                                _startAutoHideTimer();
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 2b. Back button — fades with HUD (separate so it doesn't shift tab chips)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 4,
              child: IgnorePointer(
                ignoring: !_areControlsVisible,
                child: AnimatedOpacity(
                  opacity: _areControlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                    tooltip: 'Back',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () {
                      if (_selectedCommunityIndex != null || _selectedCreationIndex != null) {
                        _closeShortPlayer();
                      } else {
                        stopAllPlatformShorts();
                        BottomBarVisibilityService.instance.setShortPlaying(false);
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        } else {
                          context.go('/feed');
                        }
                      }
                    },
                  ),
                ),
              ),
            ),

            // 2c. Tab chips — ALWAYS visible so users can switch tabs in immersive mode
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 44,
              child: Row(
                mainAxisSize: MainAxisSize.min,
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
            ),
          ],
        ),
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
        _closeShortPlayer();
        setState(() {
          _activeTab = tab;
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
    final Widget currentView;
    if (_selectedCommunityIndex == null) {
      currentView = _buildCommunityGrid();
    } else {
      // 2. Expanded State: Full-Screen Vertical Shorts Player
      currentView = Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
                _closeShortPlayer();
              }
            },
            child: PageView.builder(
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
          ),

          // Top-Left Back Button to Return to Shorts Grid
          Positioned(
            top: 54,
            left: 12,
            child: GestureDetector(
              onTap: _closeShortPlayer,
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

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: KeyedSubtree(
        key: ValueKey(_selectedCommunityIndex == null ? 'grid' : 'player'),
        child: currentView,
      ),
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

        return RefreshIndicator(
          color: const Color(0xFFF59E0B),
          backgroundColor: const Color(0xFF1E293B),
          onRefresh: _fetchShorts,
          child: CustomScrollView(
            controller: _communityScrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 75, 16, 14),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                    const SizedBox(height: 10),
                    // Quick Filter Chips Row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('All Shorts', 'all', Icons.auto_awesome),
                          const SizedBox(width: 8),
                          _buildFilterChip('🔥 Popular', 'popular', Icons.local_fire_department_rounded),
                          const SizedBox(width: 8),
                          _buildFilterChip('✨ Recent', 'recent', Icons.schedule_rounded),
                        ],
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
                    final items = _getFilteredShorts();
                    final short = items[index];
                    return _buildCommunityGridCard(short, index);
                  },
                  childCount: _getFilteredShorts().length,
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
        ),
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
        final realIndex = _shorts.indexWhere((s) => s.id == short.id);
        _openCommunityShortAt(realIndex != -1 ? realIndex : index);
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
    LocalShortItem? localItem,
  }) {
    final isWithinSlidingWindow = (index - _currentPage).abs() <= 1;
    final isCurrentActive = index == _currentPage;
    final slotIndex = index % 3;

    final hasLocalVideo = localItem != null &&
        localItem.localVideoPath != null &&
        localItem.localVideoPath!.isNotEmpty;

    final isNonPlayableLocalShort = localItem != null &&
        !hasLocalVideo &&
        localItem.status != ShortCreationStatus.published;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Local Offline Video Player or Sliding Window Slot Player / Static Thumbnail / Processing Card
        if (isNonPlayableLocalShort)
          _buildNonPlayableShortCard(localItem)
        else if (hasLocalVideo && isWithinSlidingWindow)
          LocalShortPlayer(
            key: ValueKey('local_slot_${localItem.id}'),
            item: localItem,
            isPlaying: isTabVisible && isCurrentActive && _isPlaying,
            onProgress: (cur, dur) {
              if (isCurrentActive && !_isScrubbing && mounted) {
                setState(() {
                  _currentPosition = cur;
                  if (dur > 0) _totalDuration = dur;
                });
              }
            },
          )
        else if (isWithinSlidingWindow)
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

        // 2. Full-Screen Tap Arena (Dynamic HUD Auto-Hide & Play/Pause & Double-Tap Bless)
        if (!isNonPlayableLocalShort)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onScreenTap,
              onDoubleTap: () => _onDoubleTapBless(short),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const SizedBox.expand(),
                  // Play/Pause Animated Feedback Overlay
                  if (_showPlayPauseOverlay)
                    AnimatedOpacity(
                      opacity: _showPlayPauseOverlay ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _playPauseOverlayPlaying ? Icons.play_arrow_rounded : Icons.pause_rounded,
                          size: 64,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  // Double-Tap Heart Burst Feedback Overlay
                  if (_showHeartOverlay)
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.elasticOut,
                      builder: (context, val, child) {
                        return Transform.scale(
                          scale: val * 1.3,
                          child: Opacity(
                            opacity: (1.0 - (val > 0.75 ? (val - 0.75) / 0.25 : 0.0)).clamp(0.0, 1.0),
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.35),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.redAccent.withValues(alpha: 0.6),
                                    blurRadius: 28,
                                    spreadRadius: 6,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.favorite_rounded,
                                color: Colors.redAccent,
                                size: 80,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),

        // 2.5 Floating Status Chip (One-Line Indicator)
        if (topStatusChip != null && !isNonPlayableLocalShort)
          Positioned(
            top: 60,
            left: 16,
            right: 16,
            child: Center(
              child: topStatusChip,
            ),
          ),

        // 3. Floating Right Action Bar (Bless, Save, Sound, Share)
        Positioned(
          right: 14,
          bottom: 92,
          child: IgnorePointer(
            ignoring: !_areControlsVisible,
            child: AnimatedOpacity(
              opacity: _areControlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBlessButton(short),
                  const SizedBox(height: 18),
                  _buildSaveButton(short),
                  const SizedBox(height: 18),
                  _buildMuteButton(),
                  const SizedBox(height: 18),
                  _buildShareButton(
                    onTap: () => _shareShort(short, localItem: localItem),
                  ),
                ],
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
                          stopAllPlatformShorts();
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
                    GestureDetector(
                      onTap: () => _showShortDetailsSheet(short),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
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
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'More',
                                  style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                                SizedBox(width: 2),
                                Icon(Icons.expand_more_rounded, size: 12, color: Colors.white70),
                              ],
                            ),
                          ),
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

        // 5. Vertical Position Rail
        if (!isNonPlayableLocalShort)
          Positioned(
            right: 2,
            top: MediaQuery.of(context).padding.top + 60,
            bottom: 250,
            child: IgnorePointer(
              ignoring: !_areControlsVisible,
              child: AnimatedOpacity(
                opacity: _areControlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.topCenter,
                    heightFactor: _activeTab == ShortsViewTab.community && _shorts.isNotEmpty
                        ? (_selectedCommunityIndex ?? 0) / _shorts.length
                        : (_activeTab == ShortsViewTab.myCreations && _orchestrator.localShorts.isNotEmpty
                            ? (_selectedCreationIndex ?? 0) / _orchestrator.localShorts.length
                            : 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
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
        final Widget currentView;
        if (_selectedCreationIndex == null) {
          currentView = _buildCreationsGrid(items);
        } else {
          // 2. Expanded State: Full-Screen Interactive Shorts Player
          currentView = Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
                    _closeShortPlayer();
                  }
                },
                child: PageView.builder(
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
                      localItem: item,
                    );
                  },
                ),
              ),

              // Top-Left Back Button to Return to Creations Grid
              Positioned(
                top: 54,
                left: 12,
                child: GestureDetector(
                  onTap: _closeShortPlayer,
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
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: KeyedSubtree(
            key: ValueKey(_selectedCreationIndex == null ? 'grid' : 'player'),
            child: currentView,
          ),
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

        return RefreshIndicator(
          color: const Color(0xFFF59E0B),
          backgroundColor: const Color(0xFF1E293B),
          onRefresh: () async {
            _orchestrator.fetchCloudCreations();
            await Future.delayed(const Duration(milliseconds: 800));
          },
          child: CustomScrollView(
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
        ),
        );
      },
    );
  }

  void _confirmDeleteCreation(LocalShortItem item) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.redAccent, size: 24),
            SizedBox(width: 8),
            Text('Delete Creation', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to remove "${item.title}"? This cannot be undone.',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _orchestrator.deleteShort(item.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Removed "${item.title}"'),
                    backgroundColor: const Color(0xFF1E293B),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildCreationGridCard(LocalShortItem item, int index) {
    final durSec = (item.clipEndTime - item.clipStartTime).toInt();

    return GestureDetector(
      onTap: () {
        if (item.status == ShortCreationStatus.failed) {
          _showFailedCreationDialog(item);
        } else {
          _openCreationShortAt(index);
        }
      },
      onLongPress: () => _confirmDeleteCreation(item),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: item.status == ShortCreationStatus.published
                ? Colors.white12
                : item.statusColor.withValues(alpha: 0.75),
            width: item.status == ShortCreationStatus.published ? 1.0 : 1.5,
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

            // Duration Badge & Delete Icon Top-Right
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
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
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _confirmDeleteCreation(item),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline, size: 14, color: Colors.white70),
                    ),
                  ),
                ],
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
                  // Progress Bar for actively processing items
                  if (item.status == ShortCreationStatus.downloading ||
                      item.status == ShortCreationStatus.trimming ||
                      item.status == ShortCreationStatus.uploading) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: item.progress > 0 ? item.progress : null,
                        minHeight: 3,
                        backgroundColor: Colors.white24,
                        color: item.statusColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridBadge(LocalShortItem item) {
    final color = item.statusColor;
    final isProgressing = item.status == ShortCreationStatus.downloading ||
        item.status == ShortCreationStatus.trimming ||
        item.status == ShortCreationStatus.uploading ||
        item.status == ShortCreationStatus.processing;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.75), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 6,
            spreadRadius: 0.5,
          ),
          const BoxShadow(
            color: Colors.black54,
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isProgressing)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                value: (item.progress > 0 && item.status == ShortCreationStatus.uploading)
                    ? item.progress
                    : null,
                color: color,
              ),
            )
          else
            Icon(
              item.statusIcon,
              size: 11,
              color: color,
            ),
          const SizedBox(width: 5),
          Text(
            item.statusLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(LocalShortItem item) {
    final color = item.statusColor;
    final isProgressing = item.status == ShortCreationStatus.downloading ||
        item.status == ShortCreationStatus.trimming ||
        item.status == ShortCreationStatus.uploading ||
        item.status == ShortCreationStatus.processing;
    final isActionable = item.status == ShortCreationStatus.failed ||
        item.status == ShortCreationStatus.scheduledUpload;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.8), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 10,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
          const BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isProgressing)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: (item.progress > 0 && item.status == ShortCreationStatus.uploading)
                    ? item.progress
                    : null,
                color: color,
              ),
            )
          else
            Icon(
              item.statusIcon,
              size: 14,
              color: color,
            ),
          const SizedBox(width: 8),
          Text(
            item.statusLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isActionable) ...[
            const SizedBox(width: 6),
            const Text('•', style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(width: 6),
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
          ],
        ],
      ),
    );
  }

  void _shareShort(Short short, {LocalShortItem? localItem}) {
    HapticFeedback.lightImpact();
    _startAutoHideTimer();

    if (localItem != null && localItem.status != ShortCreationStatus.published) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '✂️ This Short is currently ${localItem.statusDisplay.toLowerCase()} and will be shareable once published!',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return;
    }

    final appUrl = 'https://christiantube.app/#/watch/${short.sourceVideoId ?? short.id}?start=${(short.clipStartTime ?? 0).toInt()}';
    final ytUrl = 'https://www.youtube.com/shorts/${short.id}';

    Share.share(
      '🎬 "${short.title}"\n\n'
      '📱 Open in ${AppConfig.appName}:\n$appUrl\n\n'
      '▶️ Watch on YouTube:\n$ytUrl',
      subject: 'Watch "${short.title}" on ${AppConfig.appName}',
    );
  }

  Widget _buildNonPlayableShortCard(LocalShortItem item) {
    final color = item.statusColor;
    final isFailed = item.status == ShortCreationStatus.failed;
    final isScheduled = item.status == ShortCreationStatus.scheduledUpload;
    final isProgressing = item.status == ShortCreationStatus.downloading ||
        item.status == ShortCreationStatus.trimming ||
        item.status == ShortCreationStatus.uploading ||
        item.status == ShortCreationStatus.processing;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background thumbnail with blur
        if (item.sourceVideoThumbnail != null && item.sourceVideoThumbnail!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: item.sourceVideoThumbnail!,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: const Color(0xFF0F172A)),
            errorWidget: (_, __, ___) => Container(color: const Color(0xFF0F172A)),
          )
        else
          Container(color: const Color(0xFF0F172A)),

        // Dark frosted overlay
        Container(
          color: Colors.black.withValues(alpha: 0.78),
        ),

        // Central Status Card
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: color.withValues(alpha: 0.75),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status Icon / Progress Spinner
                  if (isProgressing)
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: CircularProgressIndicator(
                            value: (item.progress > 0 && item.status == ShortCreationStatus.uploading)
                                ? item.progress
                                : null,
                            strokeWidth: 3.5,
                            color: color,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                        Text(
                          '${(item.progress * 100).toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        item.statusIcon,
                        size: 44,
                        color: color,
                      ),
                    ),

                  const SizedBox(height: 18),

                  // Title
                  Text(
                    item.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Status Message
                  Text(
                    item.statusDisplay,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isFailed ? Colors.redAccent : Colors.white70,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),

                  if (isFailed && item.errorMessage != null && item.errorMessage!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.errorMessage!,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Action Buttons (Retry / Re-render / Back)
                  if (isFailed || isScheduled)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            _orchestrator.retryUpload(item.id);
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text(
                            'Retry Now',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          onPressed: _closeShortPlayer,
                          child: const Text('Back to Grid', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    )
                  else
                    const Text(
                      '✂️ You can return to the grid or continue watching while this processes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showFailedCreationDialog(LocalShortItem item) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 8),
            Text('Creation Notice', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Failed to process "${item.title}".',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            if (item.errorMessage != null && item.errorMessage!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  item.errorMessage!,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Would you like to retry rendering and uploading this clip?',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _confirmDeleteCreation(item);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _orchestrator.retryUpload(item.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🔄 Retrying Short creation pipeline...'),
                    backgroundColor: Color(0xFF1E293B),
                  ),
                );
              }
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
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

  Widget _buildMuteButton() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _isMuted = !_isMuted;
        });
        // TODO: Pass mute state to NativeShortsPlayer when backend supports it
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black54,
              border: Border.all(color: Colors.white24, width: 1.5),
            ),
            child: Icon(
              _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _isMuted ? 'Muted' : 'Sound',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              shadows: [
                Shadow(color: Colors.black, blurRadius: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Engagement & Filter Helper Methods ---

  List<Short> _getFilteredShorts() {
    if (_communityFilter == 'popular') {
      final list = List<Short>.from(_shorts);
      list.sort((a, b) => b.viewCount.compareTo(a.viewCount));
      return list;
    } else if (_communityFilter == 'recent') {
      final list = List<Short>.from(_shorts);
      list.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      return list;
    }
    return _shorts;
  }

  Widget _buildFilterChip(String label, String filterKey, IconData icon) {
    final isSelected = _communityFilter == filterKey;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _communityFilter = filterKey;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFF59E0B) : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.black : Colors.white70,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onDoubleTapBless(Short short) {
    HapticFeedback.heavyImpact();
    setState(() {
      _blessedShortIds.add(short.id);
      _showHeartOverlay = true;
    });
    _heartOverlayTimer?.cancel();
    _heartOverlayTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() {
          _showHeartOverlay = false;
        });
      }
    });
  }

  Widget _buildBlessButton(Short short) {
    final isBlessed = _blessedShortIds.contains(short.id);
    final count = short.likeCount > 0
        ? (short.likeCount + (isBlessed ? 1 : 0))
        : (isBlessed ? 1 : 0);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          if (isBlessed) {
            _blessedShortIds.remove(short.id);
          } else {
            _blessedShortIds.add(short.id);
          }
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isBlessed
                  ? Colors.redAccent.withValues(alpha: 0.25)
                  : Colors.black54,
              border: Border.all(
                color: isBlessed ? Colors.redAccent : Colors.white24,
                width: 1.5,
              ),
            ),
            child: Icon(
              isBlessed ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isBlessed ? Colors.redAccent : Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            count > 0 ? Formatters.formatViews(count) : 'Bless',
            style: TextStyle(
              color: isBlessed ? Colors.redAccent : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton(Short short) {
    final isSaved = _savedShortIds.contains(short.id);
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          if (isSaved) {
            _savedShortIds.remove(short.id);
          } else {
            _savedShortIds.add(short.id);
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF1E293B),
              duration: const Duration(seconds: 2),
              content: Text(
                isSaved ? 'Removed from saved clips' : '🔖 Saved clip for later',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          );
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSaved
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.25)
                  : Colors.black54,
              border: Border.all(
                color: isSaved ? const Color(0xFFF59E0B) : Colors.white24,
                width: 1.5,
              ),
            ),
            child: Icon(
              isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: isSaved ? const Color(0xFFF59E0B) : Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isSaved ? 'Saved' : 'Save',
            style: TextStyle(
              color: isSaved ? const Color(0xFFF59E0B) : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }

  void _showShortDetailsSheet(Short short) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              Row(
                children: [
                  ChannelAvatar(
                    avatarUrl: short.channelAvatarUrl,
                    channelTitle: short.channelTitle,
                    radius: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          short.channelTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (short.creatorName != null && short.creatorName!.isNotEmpty)
                          Text(
                            '✂️ Clipped by ${short.creatorName}',
                            style: const TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                short.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              if (short.description != null && short.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: SingleChildScrollView(
                    child: Text(
                      short.description!.trim(),
                      style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '👁️ ${short.viewCount > 0 ? Formatters.formatViews(short.viewCount) : '0'} views',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (short.durationSeconds > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '⏱️ ${Formatters.formatDuration(Duration(seconds: short.durationSeconds))}',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                ],
              ),
              if (short.sourceVideoId != null && short.sourceVideoId!.isNotEmpty) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      stopAllPlatformShorts();
                      context.push(
                        '/watch/${short.sourceVideoId}?start=${(short.clipStartTime ?? 0).toInt()}',
                      );
                    },
                    icon: const Icon(Icons.play_circle_fill, size: 18),
                    label: const Text(
                      'Watch Full Sermon Video',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
