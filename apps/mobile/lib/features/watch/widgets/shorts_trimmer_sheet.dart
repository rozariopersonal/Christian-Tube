import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/auth_service.dart';
import '../../shorts/services/shorts_orchestrator_service.dart';

class ShortsTrimmerSheet extends StatefulWidget {
  final String sourceVideoId;
  final String sourceVideoTitle;
  final String? sourceVideoThumbnail;
  final double currentPlayheadSeconds;
  final double totalDurationSeconds;
  final Function(double timestamp)? onLiveSeek;

  const ShortsTrimmerSheet({
    super.key,
    required this.sourceVideoId,
    required this.sourceVideoTitle,
    this.sourceVideoThumbnail,
    required this.currentPlayheadSeconds,
    required this.totalDurationSeconds,
    this.onLiveSeek,
  });

  @override
  State<ShortsTrimmerSheet> createState() => _ShortsTrimmerSheetState();
}

class _ShortsTrimmerSheetState extends State<ShortsTrimmerSheet> {
  final AuthService _authService = AuthService();
  late TextEditingController _titleController;
  late TextEditingController _creatorNameController;
  late TextEditingController _creatorEmailController;

  late double _totalDuration;
  double _clipDuration = 60.0; // 15s to 180s (Default: 60s)
  late double _clipStartTime;

  Timer? _seekThrottleTimer;
  final ScrollController _timelineScrollController = ScrollController();

  double get _clipEndTime => (_clipStartTime + _clipDuration).clamp(0.0, _totalDuration);

  @override
  void initState() {
    super.initState();
    _totalDuration = widget.totalDurationSeconds > 0 ? widget.totalDurationSeconds : 1800.0;

    // Auto-capture preceding 60 seconds up to current playhead
    final playhead = widget.currentPlayheadSeconds.clamp(0.0, _totalDuration);
    _clipDuration = 60.0.clamp(15.0, _totalDuration);
    _clipStartTime = (playhead - _clipDuration).clamp(0.0, _totalDuration - _clipDuration);

    final cleanTitle = widget.sourceVideoTitle.trim();
    final initialTitle = cleanTitle.isNotEmpty ? '$cleanTitle #Shorts' : 'Inspirational Short #Shorts';
    _titleController = TextEditingController(text: initialTitle);

    final currentUser = _authService.currentUser;
    _creatorNameController = TextEditingController(
      text: currentUser?.displayName?.isNotEmpty == true ? currentUser!.displayName! : 'Believer in Christ',
    );
    _creatorEmailController = TextEditingController(
      text: currentUser?.email ?? '',
    );
  }

  @override
  void dispose() {
    _seekThrottleTimer?.cancel();
    _timelineScrollController.dispose();
    _titleController.dispose();
    _creatorNameController.dispose();
    _creatorEmailController.dispose();
    super.dispose();
  }

  void _triggerThrottledSeek(double timestamp) {
    if (widget.onLiveSeek == null) return;
    if (_seekThrottleTimer?.isActive ?? false) return;

    _seekThrottleTimer = Timer(const Duration(milliseconds: 50), () {
      widget.onLiveSeek?.call(timestamp);
    });
  }

  String _formatSeconds(double sec) {
    final totalSec = sec.toInt();
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _onPublish() async {
    final title = _titleController.text.trim();
    final creatorName = _creatorNameController.text.trim();
    final creatorEmail = _creatorEmailController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a title for your Short')),
      );
      return;
    }

    // Launch background job
    ShortsOrchestratorService().createShort(
      sourceVideoId: widget.sourceVideoId,
      sourceVideoTitle: widget.sourceVideoTitle,
      sourceVideoThumbnail: widget.sourceVideoThumbnail,
      title: title,
      creatorName: creatorName.isNotEmpty ? creatorName : 'Anonymous',
      creatorEmail: creatorEmail,
      clipStartTime: _clipStartTime,
      clipEndTime: _clipEndTime,
    );

    // Dismiss bottom sheet immediately so user can resume watching
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFFF59E0B), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '✂️ Clipping Short (${_formatSeconds(_clipDuration)})... You can check progress under "My Creations"!',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.content_cut, color: Color(0xFFF59E0B), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Create Short (Up to 3 mins)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. DURATION CONTROL (TOP FULL-WIDTH SLIDER)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '1. CLIP DURATION',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFF59E0B)),
                        ),
                        child: Text(
                          _formatSeconds(_clipDuration),
                          style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 6,
                      activeTrackColor: const Color(0xFFF59E0B),
                      inactiveTrackColor: Colors.white12,
                      thumbColor: const Color(0xFFF59E0B),
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                      overlayColor: const Color(0xFFF59E0B).withOpacity(0.2),
                      valueIndicatorColor: const Color(0xFFF59E0B),
                      valueIndicatorTextStyle: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: Slider(
                      value: _clipDuration,
                      min: 15.0,
                      max: 180.0,
                      divisions: 33, // 5s increments
                      label: _formatSeconds(_clipDuration),
                      onChanged: (val) {
                        setState(() {
                          _clipDuration = val;
                          if (_clipStartTime + _clipDuration > _totalDuration) {
                            _clipStartTime = (_totalDuration - _clipDuration).clamp(0.0, _totalDuration);
                          }
                        });
                        _triggerThrottledSeek(_clipStartTime);
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('0:15 (Min)', style: TextStyle(color: Colors.white38, fontSize: 11)),
                      Text('01:00 (Standard)', style: TextStyle(color: Colors.white38, fontSize: 11)),
                      Text('03:00 (Max)', style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // 2. TIMELINE TRACK SCROLLER (DYNAMIC ZOOM + 25% HIGHLIGHT VIEWFINDER)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '2. POSITION IN FULL VIDEO',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                      Text(
                        '${_formatSeconds(_clipStartTime)}  ➔  ${_formatSeconds(_clipEndTime)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Interactive Timeline Scrubber Bar
                  Container(
                    height: 64,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final trackWidth = constraints.maxWidth;
                        // Calculate position percentage
                        final double startPct = (_clipStartTime / _totalDuration).clamp(0.0, 1.0);
                        final double durationPct = (_clipDuration / _totalDuration).clamp(0.05, 1.0);

                        return Stack(
                          children: [
                            // Background Filmstrip Grid Mock
                            Positioned.fill(
                              child: Row(
                                children: List.generate(
                                  10,
                                  (i) => Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          right: BorderSide(color: Colors.white.withOpacity(0.05)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Highlight Window (Selected Clip Box)
                            Positioned(
                              left: startPct * trackWidth,
                              width: (durationPct * trackWidth).clamp(trackWidth * 0.20, trackWidth),
                              top: 0,
                              bottom: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFF59E0B), width: 2),
                                ),
                                child: Center(
                                  child: Text(
                                    _formatSeconds(_clipDuration),
                                    style: const TextStyle(
                                      color: Color(0xFFF59E0B),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Gesture Detector over track to pan position
                            Positioned.fill(
                              child: GestureDetector(
                                onHorizontalDragUpdate: (details) {
                                  final double deltaPct = details.primaryDelta! / trackWidth;
                                  final double deltaSec = deltaPct * _totalDuration;
                                  setState(() {
                                    _clipStartTime = (_clipStartTime + deltaSec).clamp(
                                      0.0,
                                      _totalDuration - _clipDuration,
                                    );
                                  });
                                  _triggerThrottledSeek(_clipStartTime);
                                },
                                onTapDown: (details) {
                                  final tapX = details.localPosition.dx;
                                  final tapPct = (tapX / trackWidth).clamp(0.0, 1.0);
                                  final tapSec = tapPct * _totalDuration;
                                  setState(() {
                                    _clipStartTime = (tapSec - (_clipDuration / 2)).clamp(
                                      0.0,
                                      _totalDuration - _clipDuration,
                                    );
                                  });
                                  _triggerThrottledSeek(_clipStartTime);
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '◀ Drag the track to pan your clip window across the entire sermon ▶',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),

                  const SizedBox(height: 24),

                  // 3. METADATA INPUTS
                  const Text(
                    '3. SHORT DETAILS',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Title Field
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Short Title',
                      labelStyle: const TextStyle(color: Colors.white60),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFF59E0B)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Creator Name Field
                  TextField(
                    controller: _creatorNameController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Clipped by (Your Name)',
                      labelStyle: const TextStyle(color: Colors.white60),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFF59E0B)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // 4. PUBLISH BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _onPublish,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 4,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.rocket_launch, size: 20),
                          SizedBox(width: 10),
                          Text(
                            'Publish Short (720p)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
