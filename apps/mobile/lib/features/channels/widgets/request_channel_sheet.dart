import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../channel_service.dart';

class RequestChannelBottomSheet extends StatefulWidget {
  final Function(String url, String name) onSubmitRequest;
  final ChannelService channelService;

  const RequestChannelBottomSheet({
    super.key,
    required this.onSubmitRequest,
    required this.channelService,
  });

  @override
  State<RequestChannelBottomSheet> createState() => _RequestChannelBottomSheetState();
}

class _RequestChannelBottomSheetState extends State<RequestChannelBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  void _search(String q) async {
    if (q.trim().isEmpty) return;
    setState(() => _isSearching = true);
    final results = await widget.channelService.searchYouTubeChannels(q.trim());
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.tokens.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Request Channel', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Find a YouTube channel you would like the admin to approve and add to the platform:',
              style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search YouTube channel or paste URL...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _search(_searchController.text),
                ),
                filled: true,
                fillColor: context.tokens.surfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              onSubmitted: _search,
            ),
            const SizedBox(height: 12),
            if (_isSearching)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else
              Flexible(
                child: _searchResults.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search, size: 48, color: context.tokens.onSurfaceDisabled),
                            const SizedBox(height: 8),
                            Text('Search for a YouTube channel above', style: TextStyle(color: context.tokens.onSurfaceMuted)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final r = _searchResults[idx];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: r['thumbnail'] != null ? NetworkImage(r['thumbnail']) : null,
                              child: r['thumbnail'] == null ? const Icon(Icons.tv) : null,
                            ),
                            title: Text(r['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: Text(
                              '${Formatters.formatSubscribers(r['subscriberCount'])} subs',
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                widget.onSubmitRequest(r['id'] ?? '', r['name'] ?? '');
                              },
                              child: const Text('Request'),
                            ),
                          );
                        },
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
