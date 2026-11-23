import 'package:flutter/material.dart';
import '../../../core/layout/adaptivity.dart';
import '../../../core/models/channel.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/ui/channel_avatar.dart';

class ShortsChannelFilterSheet extends StatefulWidget {
  final List<Channel> channels;
  final Set<String> selectedChannelIds;

  const ShortsChannelFilterSheet({
    super.key,
    required this.channels,
    required this.selectedChannelIds,
  });

  static Future<Set<String>?> show(
    BuildContext context, {
    required List<Channel> channels,
    required Set<String> selectedChannelIds,
  }) {
    final isCompact = ScreenClass.of(context).isCompact;
    return showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: isCompact ? null : const BoxConstraints(maxWidth: 640),
      builder: (_) => ShortsChannelFilterSheet(
        channels: channels,
        selectedChannelIds: selectedChannelIds,
      ),
    );
  }

  @override
  State<ShortsChannelFilterSheet> createState() =>
      _ShortsChannelFilterSheetState();
}

class _ShortsChannelFilterSheetState extends State<ShortsChannelFilterSheet> {
  late final TextEditingController _searchController;
  late final Set<String> _selectedIds;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _selectedIds = Set<String>.of(widget.selectedChannelIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Channel> get _filteredChannels {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.channels;
    return widget.channels
        .where((channel) => channel.name.toLowerCase().contains(query))
        .toList();
  }

  void _toggleChannel(String id) {
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  void _removeChannel(String id) {
    setState(() => _selectedIds.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final filteredChannels = _filteredChannels;
    final selectedChannels = widget.channels
        .where((channel) => _selectedIds.contains(channel.id))
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.52,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Select channels',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton(
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : () => setState(_selectedIds.clear),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                Text(
                  'Show Shorts from any selected channel.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.tokens.onSurfaceMuted,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search channels',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close),
                          ),
                    filled: true,
                    fillColor: context.tokens.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (selectedChannels.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Selected · ${selectedChannels.length}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final channel in selectedChannels) ...[
                            InputChip(
                              avatar: ChannelAvatar(
                                avatarUrl: channel.avatarUrl,
                                channelTitle: channel.name,
                                radius: 12,
                              ),
                              label: Text(channel.name),
                              onDeleted: () => _removeChannel(channel.id),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                  ),
                ],
                const SizedBox(height: 8),
                Expanded(
                  child: filteredChannels.isEmpty
                      ? Center(
                          child: Text(
                            _query.isEmpty
                                ? 'No followed channels with Shorts.'
                                : 'No channels match “$_query”.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: context.tokens.onSurfaceMuted,
                                ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: filteredChannels.length,
                          itemBuilder: (context, index) {
                            final channel = filteredChannels[index];
                            final selected = _selectedIds.contains(channel.id);
                            return CheckboxListTile(
                              value: selected,
                              onChanged: (_) => _toggleChannel(channel.id),
                              controlAffinity: ListTileControlAffinity.trailing,
                              secondary: ChannelAvatar(
                                avatarUrl: channel.avatarUrl,
                                channelTitle: channel.name,
                                radius: 20,
                              ),
                              title: Text(
                                channel.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selectedIds),
                    child: Text(
                      _selectedIds.isEmpty
                          ? 'Show all Shorts'
                          : 'Show Shorts (${_selectedIds.length})',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
