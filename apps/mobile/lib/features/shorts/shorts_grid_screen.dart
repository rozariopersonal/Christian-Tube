import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/models/short.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/formatters.dart';

class ShortsGridScreen extends StatefulWidget {
  const ShortsGridScreen({super.key});

  @override
  State<ShortsGridScreen> createState() => _ShortsGridScreenState();
}

class _ShortsGridScreenState extends State<ShortsGridScreen> {
  final ApiClient _apiClient = ApiClient();
  List<Short> _shorts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchGridShorts();
  }

  Future<void> _fetchGridShorts() async {
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

        final shortsOnly = allVideos.where((s) {
          if (s.durationSeconds > 0) return s.durationSeconds <= 60;
          final durSec = Short.parseDurationInSeconds(s.duration);
          if (durSec > 0) return durSec <= 60;
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
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.tokens.scrim,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: context.tokens.scrim,
      appBar: AppBar(title: const Text('Explore Shorts')),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150,
          childAspectRatio: 9 / 16,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _shorts.length,
        itemBuilder: (context, index) {
          final short = _shorts[index];
          return GestureDetector(
            onTap: () => context.push('/shorts'),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: short.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: context.tokens.surface,
                      child: Icon(Icons.play_circle_outline, color: context.tokens.onSurfaceDisabled),
                    ),
                  ),
                ),
                // Gradient for readability
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          context.tokens.scrim.withValues(alpha: 0.87),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  bottom: 6,
                  right: 6,
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
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                        ),
                      ),
                      if (short.viewCount > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${Formatters.formatViews(short.viewCount)} views',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
