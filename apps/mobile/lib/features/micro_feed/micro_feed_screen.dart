import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/engines/base_feed_engine.dart';
import '../../core/services/bottom_bar_visibility_service.dart';
import '../../core/theme/app_tokens.dart';
import '../engines/scripture/models/scripture_card.dart';
import '../engines/scripture/models/scripture_filter_state.dart';
import '../engines/scripture/scripture_engine.dart';
import '../engines/scripture/services/offline_feed_database.dart';

class MicroFeedScreen<T, F extends BaseFeedFilterState> extends StatefulWidget {
  final BaseFeedEngine<T, F> engine;

  const MicroFeedScreen({
    super.key,
    required this.engine,
  });

  @override
  State<MicroFeedScreen<T, F>> createState() => _MicroFeedScreenState<T, F>();
}

class _MicroFeedScreenState<T, F extends BaseFeedFilterState>
    extends State<MicroFeedScreen<T, F>> {
  final PageController _pageController = PageController();
  final Map<int, GlobalKey> _boundaryKeys = {};

  List<T> _items = [];
  late F _filterState;
  bool _isLoading = true;
  bool _isFetchingMore = false;
  int _currentPage = 0;
  int _feedPageIndex = 0;
  String? _errorMessage;
  int _loadGeneration = 0;
  bool _isFirstLoad = true;

  StreamSubscription<void>? _resetSubscription;

  @override
  void initState() {
    super.initState();
    _filterState = widget.engine.initialFilterState;
    _initializeAndLoad();
    _resetSubscription = BottomBarVisibilityService.instance.onWordsResetRequested.listen((_) {
      // Reset brings a brand-new random session: return all seen cards to the pool
      if (widget.engine is ScriptureEngine) {
        (widget.engine as ScriptureEngine).resetRandomDeck();
      }
      _initializeAndLoad();
    });
  }

  Future<void> _initializeAndLoad() async {
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _isFetchingMore = false;
      _errorMessage = null;
    });

    try {
      await widget.engine.initialize();
      // Prefs are only loaded during initialize(); on the very first load adopt
      // the engine's persisted filter state instead of the default snapshot.
      if (_isFirstLoad) {
        _filterState = widget.engine.initialFilterState;
        _isFirstLoad = false;
      }
      final items = await widget.engine.fetchItems(
        filterState: _filterState,
        page: 0,
      );
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _items = items;
          _isLoading = false;
          _feedPageIndex = 1;
        });
      }
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load feed. Please try again.';
        });
      }
    }
  }

  Future<void> _loadMoreItems() async {
    if (_isFetchingMore || _isLoading) return;
    final generation = _loadGeneration;
    _isFetchingMore = true;

    try {
      final more = await widget.engine.fetchItems(
        filterState: _filterState,
        page: _feedPageIndex,
      );
      // Only append if this page belongs to the current load generation, so a
      // stale response started before a reset/reload can never leak in.
      if (mounted && generation == _loadGeneration && more.isNotEmpty) {
        setState(() {
          _items.addAll(more);
          _feedPageIndex++;
        });
      }
    } catch (_) {
      // Ignored for infinite scroll seamless feel
    } finally {
      _isFetchingMore = false;
    }
  }

  void _onFilterChanged(F newFilterState) {
    final oldFilterState = _filterState;

    setState(() {
      _filterState = newFilterState;
    });

    if (widget.engine is ScriptureEngine) {
      final scriptureEngine = widget.engine as ScriptureEngine;
      final oldScriptureState = oldFilterState as ScriptureFilterState;
      final newScriptureState = newFilterState as ScriptureFilterState;

      // If structural feed filters changed, we must clear and reload the feed
      if (oldScriptureState.bookFilter != newScriptureState.bookFilter ||
          oldScriptureState.testamentFilter != newScriptureState.testamentFilter) {
        // Drop the seen-cards history so cards from the previous filter can return
        scriptureEngine.resetRandomDeck();
        _initializeAndLoad();
        return;
      }

      // Otherwise, it's a cosmetic/version change, so update in place
      final newVersionId = newScriptureState.activeVersionId;
      final activeChanged =
          oldScriptureState.activeVersionId != newVersionId;
      final comparisonChanged = oldScriptureState.comparisonVersionId !=
          newScriptureState.comparisonVersionId;
      for (final item in _items) {
        if (item is ScriptureCard) {
          if (activeChanged) {
            item.customFontFamily = null;
            scriptureEngine.resolveCard(item, newVersionId).then((_) {
              if (mounted) {
                setState(() {});
              }
            });
          } else if (comparisonChanged) {
            scriptureEngine
                .resolveCardComparison(
                    item, newScriptureState.comparisonVersionId)
                .then((_) {
              if (mounted) {
                setState(() {});
              }
            });
          }
        }
      }
    }
  }

  void _openManager() {
    context.push('/bible-manager');
  }

  // Scroll-past-edge paging fallback for long text: when a card's content is
  // taller than the screen, swiping past its top/bottom edge advances pages.
  void _onEdgePageShift(int direction) {
    final target = _currentPage + direction;
    if (target < 0 || target >= _items.length) return;
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  GlobalKey _getKeyForIndex(int index) {
    return _boundaryKeys.putIfAbsent(index, () => GlobalKey());
  }

  @override
  void dispose() {
    _resetSubscription?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      if (widget.engine is ScriptureEngine) {
        return Scaffold(
          backgroundColor: context.tokens.scrim,
          body: Center(
            child: ValueListenableBuilder<double>(
              valueListenable: OfflineFeedDatabase().downloadProgress,
              builder: (context, progress, child) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: context.accent,
                      strokeWidth: 2.5,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      OfflineFeedDatabase().isInitializing
                          ? (progress > 0 && progress < 1.0
                              ? 'Downloading offline database... ${(progress * 100).toInt()}%'
                              : 'Setting up offline engine...')
                          : 'Loading feed...',
                      style: TextStyle(
                        color: context.tokens.onSurfaceMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (OfflineFeedDatabase().isInitializing && progress > 0 && progress < 1.0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 12),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: context.tokens.surfaceBorder,
                          color: context.accent,
                          minHeight: 4,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      }

      return Scaffold(
        backgroundColor: context.tokens.scrim,
        body: Center(
          child: CircularProgressIndicator(
            color: context.accent,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (_errorMessage != null && _items.isEmpty) {
      return Scaffold(
        backgroundColor: context.tokens.scrim,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.signal_wifi_connected_no_internet_4_rounded,
                  color: context.tokens.onSurfaceDisabled,
                  size: 54,
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _initializeAndLoad,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.accent,
                    foregroundColor: context.tokens.scrim,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_items.isEmpty && _errorMessage == null) {
      return Scaffold(
        backgroundColor: context.tokens.scrim,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.auto_stories_rounded,
                  color: context.tokens.onSurfaceDisabled,
                  size: 54,
                ),
                const SizedBox(height: 16),
                Text(
                  'No verses matched your filters yet.',
                  style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _initializeAndLoad,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.accent,
                    foregroundColor: context.tokens.scrim,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final hasValidCurrentItem =
        _items.isNotEmpty && _currentPage >= 0 && _currentPage < _items.length;
    final currentItem = hasValidCurrentItem ? _items[_currentPage] : null;
    final currentBoundaryKey =
        hasValidCurrentItem ? _getKeyForIndex(_currentPage) : null;

    return Scaffold(
      backgroundColor: context.tokens.scrim,
      body: Stack(
        children: [
          // 1. Vertical PageView (ONLY content cards slide)
          PageView.builder(
            key: const PageStorageKey('micro_feed_page_view'),
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _items.length,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
              if (index >= _items.length - 3) {
                _loadMoreItems();
              }
            },
            itemBuilder: (context, index) {
              final item = _items[index];
              final isCurrent = index == _currentPage;
              final boundaryKey = _getKeyForIndex(index);

              return RepaintBoundary(
                key: boundaryKey,
                child: widget.engine.buildCard(
                  context,
                  item,
                  _filterState,
                  isCurrent,
                  boundaryKey,
                  onEdgePageShift: _onEdgePageShift,
                ),
              );
            },
          ),

          // 2. Fixed Stationary Top Floating Controls
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: widget.engine.buildTopControls(
                      context,
                      _filterState,
                      _onFilterChanged,
                      _openManager,
                    ) ??
                    const SizedBox.shrink(),
              ),
            ),
          ),

          // 3. Fixed Stationary Right Side Action Column (Doesn't slide on swipe)
          if (currentItem != null && currentBoundaryKey != null)
            Positioned(
              right: 14,
              bottom: 36,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.engine.buildSideActions(
                    context,
                    currentItem,
                    _filterState,
                    currentBoundaryKey,
                    () => setState(() {}),
                    _onFilterChanged,
                  ),
                ),
              ),
            ),

          // 4. Fixed Stationary Bottom Context Slot
          if (currentItem != null)
            Positioned(
              left: 16,
              right: 80,
              bottom: 24,
              child: SafeArea(
                child: widget.engine.buildBottomBar(context, currentItem) ??
                    const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}
