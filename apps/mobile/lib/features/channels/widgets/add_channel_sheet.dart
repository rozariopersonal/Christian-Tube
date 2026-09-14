import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_tokens.dart';
import '../channel_service.dart';

class AddChannelBottomSheet extends StatefulWidget {
  final Function(String url, String name) onAddDirect;
  final ChannelService channelService;

  const AddChannelBottomSheet({
    super.key,
    required this.onAddDirect,
    required this.channelService,
  });

  @override
  State<AddChannelBottomSheet> createState() => _AddChannelBottomSheetState();
}

class _AddChannelBottomSheetState extends State<AddChannelBottomSheet> {
  final TextEditingController _queryController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  void _performSearch(String q) async {
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
                Text('Add Channel (Admin)', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _queryController,
              decoration: InputDecoration(
                hintText: 'Search YouTube channel or paste URL...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _performSearch(_queryController.text),
                ),
                filled: true,
                fillColor: context.tokens.surfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              onSubmitted: _performSearch,
            ),
            const SizedBox(height: 16),
            if (_queryController.text.trim().isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.flash_on_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ingest "${_queryController.text.trim()}" directly',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        final input = _queryController.text.trim();
                        if (input.isNotEmpty) {
                          Navigator.pop(context);
                          widget.onAddDirect(input, input);
                        }
                      },
                      child: const Text('Add Now'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_isSearching)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else
              Flexible(
              child: _searchResults.isEmpty
                  ? Center(
                      child: Text(
                        'Search YouTube to directly ingest channels into the instance',
                        style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 13),
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
                            r['handle'] != null ? '${r['handle']}' : (r['description'] != null ? '${r['description']}' : 'YouTube Channel'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onAddDirect(r['id'] ?? '', r['name'] ?? '');
                            },
                            child: const Text('Add'),
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
