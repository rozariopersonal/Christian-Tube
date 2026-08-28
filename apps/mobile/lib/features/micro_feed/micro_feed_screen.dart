import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/engines/base_feed_engine.dart';
import '../../core/services/bottom_bar_visibility_service.dart';
import '../engines/scripture/models/scripture_card.dart';
import '../engines/scripture/models/scripture_filter_state.dart';
import '../engines/scripture/scripture_engine.dart';

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

  StreamSubscription<void>? _resetSubscription;

  @override
  void initState() {
    super.initState();
    _filterState = widget.engine.initialFilterState;
    _initializeAndLoad();
    _resetSubscription = BottomBarVisibilityService.instance.onWordsResetRequested.listen((_) {
      _initializeAndLoad();
    });
  }

  Future<void> _initializeAndLoad() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.engine.initialize();
      _filterState = widget.engine.initialFilterState;
      final items = await widget.engine.fetchItems(
        filterState: _filterState,
        page: 0,
      );
      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
          _feedPageIndex = 1;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load feed. Please try again.';
        });
      }
    }
  }

  Future<void> _loadMoreItems() async {
    if (_isFetchingMore) return;
    _isFetchingMore = true;

    try {
      final more = await widget.engine.fetchItems(
        filterState: _filterState,
        page: _feedPageIndex,
      );
      if (mounted && more.isNotEmpty) {
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
        _initializeAndLoad();
        return;
      }

      // Otherwise, it's a cosmetic/version change, so update in place
      final newVersionId = newScriptureState.activeVersionId;
      for (final item in _items) {
        if (item is ScriptureCard) {
          item.customFontFamily = null;
          scriptureEngine.resolveCard(item, newVersionId).then((_) {
            if (mounted) {
              setState(() {});
            }
          });
        }
      }
    }
  }

  void _openManager() {
    context.push('/bible-manager');
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
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFF59E0B),
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (_errorMessage != null && _items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.signal_wifi_connected_no_internet_4_rounded,
                  color: Colors.white38,
                  size: 54,
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _initializeAndLoad,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.black,
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
      backgroundColor: Colors.black,
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
