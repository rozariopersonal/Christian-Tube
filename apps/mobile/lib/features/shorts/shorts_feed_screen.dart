import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/short.dart';
import 'players/shorts_player.dart';
import '../search/shorts_search_delegate.dart';
import '../../core/config/app_config.dart';
import '../../core/services/bottom_bar_visibility_service.dart';
import 'services/shorts_orchestrator_service.dart';
import 'widgets/my_creations_grid.dart';
import 'widgets/community_shorts_grid.dart';
import 'widgets/empty_community_shorts.dart';
import 'widgets/empty_my_creations.dart';
import 'widgets/fullscreen_shorts_player.dart';
import 'widgets/shorts_tab_chip.dart';
import 'services/shorts_dialog_service.dart';
import 'services/community_shorts_controller.dart';

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
  PageController _pageController = PageController();
  PageController _localPageController = PageController();
  final ShortsOrchestratorService _orchestrator = ShortsOrchestratorService();
  final CommunityShortsController _communityController = CommunityShortsController();

  final ScrollController _communityScrollController = ScrollController();

  ShortsViewTab _activeTab = ShortsViewTab.community;

  // View state: null = Grid View, int = Fullscreen Short Player
  int? _selectedCommunityIndex;
  int? _selectedCreationIndex;

  StreamSubscription<void>? _shortsResetSub;

  @override
  void initState() {
    super.initState();
    _communityController.fetchShorts().then((_) {
      if (mounted) _applyInitialTarget();
    });
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
    if (index < 0 || index >= _communityController.shorts.length) return;
    setState(() {
      _selectedCommunityIndex = index;
    });
  }

  void _openCreationShortAt(int index) {
    final list = _orchestrator.localShorts;
    if (index < 0 || index >= list.length) return;
    setState(() {
      _selectedCreationIndex = index;
    });
  }

  void _closeShortPlayer() {
    stopAllPlatformShorts();
    if (mounted) {
      setState(() {
        _selectedCommunityIndex = null;
        _selectedCreationIndex = null;
      });
    }
    BottomBarVisibilityService.instance.setShortPlaying(false);
  }

  void _applyInitialTarget() {
    if (_communityController.shorts.isEmpty) return;
    int target = -1;
    if (widget.initialShortId != null && widget.initialShortId!.isNotEmpty) {
      final idx = _communityController.shorts.indexWhere(
        (s) => s.id == widget.initialShortId || s.sourceVideoId == widget.initialShortId,
      );
      if (idx != -1) target = idx;
    }
    if (target == -1 && widget.initialIndex != null && widget.initialIndex! >= 0 && widget.initialIndex! < _communityController.shorts.length) {
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
    _communityController.dispose();
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
      _communityController.loadMoreShorts();
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

            // 2a. Top Gradient + HUD Controls
            Positioned(
              top: 0,
              left: 0,
              right: 0,
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
                            final selectedShort = await showSearch<Short?>(
                              context: context,
                              delegate: ShortsSearchDelegate(),
                            );
                            if (selectedShort != null && mounted) {
                              final idx = _communityController.shorts.indexWhere((s) => s.id == selectedShort.id);
                              if (idx != -1) {
                                _openCommunityShortAt(idx);
                              } else {
                                _communityController.insertShortAtBeginning(selectedShort);
                                _openCommunityShortAt(0);
                              }
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white, size: 22),
                          tooltip: 'Refresh',
                          onPressed: () {
                            _communityController.fetchShorts();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // 2b. Back button (separate so it doesn't shift tab chips)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 4,
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

            // 2c. Tab chips — ALWAYS visible so users can switch tabs in immersive mode
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 44,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShortsTabChip(
                    label: '🌐 Community',
                    isSelected: _activeTab == ShortsViewTab.community,
                    onTap: () {
                      _closeShortPlayer();
                      setState(() {
                        _activeTab = ShortsViewTab.community;
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  ListenableBuilder(
                    listenable: _orchestrator,
                    builder: (context, _) {
                      final activeCount = _orchestrator.activeJobsCount;
                      return ShortsTabChip(
                        label: '🎬 My Creations',
                        isSelected: _activeTab == ShortsViewTab.myCreations,
                        count: _orchestrator.localShorts.length,
                        activeJobs: activeCount,
                        onTap: () {
                          _closeShortPlayer();
                          setState(() {
                            _activeTab = ShortsViewTab.myCreations;
                          });
                          _orchestrator.fetchCloudCreations();
                        },
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


  Widget _buildCommunityFeed(bool isTabVisible) {
    return ListenableBuilder(
      listenable: _communityController,
      builder: (context, _) {
        if (_communityController.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFF59E0B)),
          );
        }

        if (_communityController.shorts.isEmpty) {
          return EmptyCommunityShorts(
            onRefresh: _communityController.fetchShorts,
          );
        }

        // 1. Initial State: Infinite Scroll Grid
        final Widget currentView;
        if (_selectedCommunityIndex == null) {
          currentView = CommunityShortsGrid(
            allShorts: _communityController.shorts,
            filteredShorts: _communityController.filteredShorts,
            scrollController: _communityScrollController,
            onRefresh: _communityController.fetchShorts,
            isLoadingMore: _communityController.isLoadingMore,
            onShortTap: _openCommunityShortAt,
            currentFilter: _communityController.filter,
            onFilterSelected: _communityController.setFilter,
          );
        } else {
          // 2. Expanded State: Full-Screen Vertical Shorts Player
          currentView = FullscreenShortsPlayer(
            shorts: _communityController.shorts,
            initialIndex: _selectedCommunityIndex!,
            onClose: _closeShortPlayer,
            onLoadMore: _communityController.loadMoreShorts,
          );
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: KeyedSubtree(
            key: ValueKey(_selectedCommunityIndex == null ? 'grid' : 'player'),
            child: currentView,
          ),
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
          return const EmptyMyCreations();
        }

        // 1. Initial State: Grid View of User's Creations
        final Widget currentView;
        if (_selectedCreationIndex == null) {
          currentView = MyCreationsGrid(
            items: items,
            onRefresh: () async {
              _orchestrator.fetchCloudCreations();
              await Future.delayed(const Duration(milliseconds: 800));
            },
            onShortTap: _openCreationShortAt,
            onDeleteTap: (item) => ShortsDialogService.confirmDeleteCreation(context, item, _orchestrator),
          );
        } else {
          // 2. Expanded State: Full-Screen Interactive Shorts Player
          currentView = FullscreenShortsPlayer(
            localItems: items,
            initialIndex: _selectedCreationIndex!,
            onClose: _closeShortPlayer,
            orchestrator: _orchestrator,
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



}
