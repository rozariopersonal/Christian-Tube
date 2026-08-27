import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/engines/base_feed_engine.dart';

class MicroFeedScreen<T, F extends BaseFeedFilterState> extends StatefulWidget {
  final BaseFeedEngine<T, F> engine;

  const MicroFeedScreen({super.key, required this.engine});

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

  @override
  void initState() {
    super.initState();
    _filterState = widget.engine.initialFilterState;
    _initializeAndLoad();
  }

  Future<void> _initializeAndLoad() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.engine.initialize();
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
    setState(() {
      _filterState = newFilterState;
    });
    _initializeAndLoad();
  }

  void _openManager() {
    context.push('/bible-manager');
  }

  GlobalKey _getKeyForIndex(int index) {
    return _boundaryKeys.putIfAbsent(index, () => GlobalKey());
  }

  @override
  void dispose() {
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
            color: Colors.white,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (_errorMessage != null || _items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.engine.defaultTabIcon,
                  size: 64,
                  color: Colors.white54,
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage ?? 'No content available right now.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _initializeAndLoad,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white24,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Vertical PageView
          PageView.builder(
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

              return Stack(
                fit: StackFit.expand,
                children: [
                  // Main Card Canvas (wrapped in RepaintBoundary for 4K sharing)
                  RepaintBoundary(
                    key: boundaryKey,
                    child: widget.engine.buildCard(
                      context,
                      item,
                      _filterState,
                      isCurrent,
                      boundaryKey,
                    ),
                  ),

                  // Right Side Action Buttons
                  Positioned(
                    right: 14,
                    bottom: 36,
                    child: SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: widget.engine.buildSideActions(
                          context,
                          item,
                          _filterState,
                          boundaryKey,
                          () => setState(() {}),
                        ),
                      ),
                    ),
                  ),

                  // Bottom Context Slot
                  Positioned(
                    left: 16,
                    right: 76,
                    bottom: 24,
                    child: SafeArea(
                      child: widget.engine.buildBottomBar(context, item) ??
                          const SizedBox.shrink(),
                    ),
                  ),
                ],
              );
            },
          ),

          // Top Floating Control Bar Slot
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
        ],
      ),
    );
  }
}
