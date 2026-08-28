import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/short.dart';
import '../../../core/models/local_short_item.dart';
import '../../../core/services/bottom_bar_visibility_service.dart';
import '../services/shorts_orchestrator_service.dart';
import '../services/shorts_dialog_service.dart';
import '../players/shorts_player.dart';
import '../players/local_short_player.dart';
import '../native_shorts_player.dart';
import 'short_player_overlay.dart';
import 'my_creations_grid.dart'; // For NonPlayableShortCard

class FullscreenShortsPlayer extends StatefulWidget {
  final List<Short>? shorts;
  final List<LocalShortItem>? localItems;
  final int initialIndex;
  final VoidCallback onClose;
  final VoidCallback? onLoadMore;
  final ShortsOrchestratorService? orchestrator;

  const FullscreenShortsPlayer({
    super.key,
    this.shorts,
    this.localItems,
    required this.initialIndex,
    required this.onClose,
    this.onLoadMore,
    this.orchestrator,
  }) : assert(shorts != null || localItems != null, 'Must provide either shorts or localItems');

  @override
  State<FullscreenShortsPlayer> createState() => _FullscreenShortsPlayerState();
}

class _FullscreenShortsPlayerState extends State<FullscreenShortsPlayer> {
  late PageController _pageController;
  late int _currentPage;

  bool _isPlaying = true;
  bool _areControlsVisible = true;
  Timer? _autoHideTimer;
  bool _isScrubbing = false;
  double _currentPosition = 0.0;
  double _totalDuration = 0.0;

  bool _showPlayPauseOverlay = false;
  bool _playPauseOverlayPlaying = true;
  Timer? _overlayTimer;
  
  int get _itemCount => widget.shorts?.length ?? widget.localItems?.length ?? 0;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialIndex;
    _pageController = PageController(initialPage: _currentPage);
    BottomBarVisibilityService.instance.setShortPlaying(true);
    _startAutoHideTimer();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _autoHideTimer?.cancel();
    _overlayTimer?.cancel();
    // Do not setShortPlaying(false) here, let the parent do it so it doesn't flash.
    super.dispose();
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
      setState(() {
        _areControlsVisible = true;
      });
      _startAutoHideTimer();
    } else {
      _autoHideTimer?.cancel();
      setState(() {
        _isPlaying = !_isPlaying;
      });
      _showPlayPauseIndicator(_isPlaying);
      if (_isPlaying) {
        _startAutoHideTimer();
      }
    }
  }

  Widget _buildShortPlayerStack(int index) {
    final isWithinSlidingWindow = (index - _currentPage).abs() <= 1;
    final isCurrentActive = index == _currentPage;
    final slotIndex = index % 3;

    final short = widget.shorts != null ? widget.shorts![index] : widget.localItems![index].toShort();
    final localItem = widget.localItems != null ? widget.localItems![index] : null;

    final hasLocalVideo = localItem != null &&
        localItem.localVideoPath != null &&
        localItem.localVideoPath!.isNotEmpty;

    final isNonPlayableLocalShort = localItem != null &&
        !hasLocalVideo &&
        localItem.status != ShortCreationStatus.published;

    Widget? topStatusChip;
    if (isNonPlayableLocalShort && widget.orchestrator != null) {
      topStatusChip = CreationStatusChip(
        item: localItem,
        onRetry: () => widget.orchestrator!.retryUpload(localItem.id),
      );
    }

    // Determine height factor for the right rail
    final heightFactor = _itemCount > 0 ? (index / _itemCount) : 0.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (isNonPlayableLocalShort)
          NonPlayableShortCard(
            item: localItem,
            onRetry: () => widget.orchestrator!.retryUpload(localItem.id),
            onClose: widget.onClose,
          )
        else if (hasLocalVideo && isWithinSlidingWindow)
          LocalShortPlayer(
            key: ValueKey('local_slot_${localItem.id}'),
            item: localItem,
            isPlaying: isCurrentActive && _isPlaying,
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
            isPlaying: isCurrentActive && _isPlaying,
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

        ShortPlayerOverlay(
          isNonPlayableLocalShort: isNonPlayableLocalShort,
          showPlayPauseOverlay: _showPlayPauseOverlay,
          playPauseOverlayPlaying: _playPauseOverlayPlaying,
          onScreenTap: _onScreenTap,
          topStatusChip: topStatusChip,
          areControlsVisible: _areControlsVisible,
          short: short,
          localItem: localItem,
          onShare: () => ShortsDialogService.shareShort(context, short, localItem: localItem),
          isScrubbing: _isScrubbing,
          currentPosition: _currentPosition,
          totalDuration: _totalDuration,
          onStopAllPlatformShorts: stopAllPlatformShorts,
          onPushRoute: (route) => context.push(route),
          onShowDetailsSheet: () => ShortsDialogService.showShortDetailsSheet(context, short, stopAllPlatformShorts),
          onPanStart: (pos) {
            setState(() {
              _isScrubbing = true;
              _currentPosition = pos;
            });
            _autoHideTimer?.cancel();
          },
          onPanUpdate: (pos) {
            setState(() {
              _currentPosition = pos;
            });
          },
          onPanEnd: (pos) {
            setState(() {
              _isScrubbing = false;
            });
            seekPlatformShort(slotIndex, pos);
            _startAutoHideTimer();
          },
          verticalRailHeightFactor: heightFactor,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
              widget.onClose();
            }
          },
          child: PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _itemCount,
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
              if (widget.onLoadMore != null && index >= _itemCount - 4) {
                widget.onLoadMore!();
              }
            },
            itemBuilder: (context, index) {
              return _buildShortPlayerStack(index);
            },
          ),
        ),

        // Top-Left Back Button to Return to Grid
        Positioned(
          top: 54,
          left: 12,
          child: GestureDetector(
            onTap: widget.onClose,
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
                    'Back to Grid',
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
}
