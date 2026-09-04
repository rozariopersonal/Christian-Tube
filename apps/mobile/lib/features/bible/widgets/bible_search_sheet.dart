import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../engines/scripture/services/local_bible_service.dart';

class BibleSearchSheet extends StatefulWidget {
  final String versionId;
  final void Function(String book, int chapter, int? verse) onJumpTo;

  const BibleSearchSheet({
    super.key,
    required this.versionId,
    required this.onJumpTo,
  });

  @override
  State<BibleSearchSheet> createState() => _BibleSearchSheetState();
}

class _BibleSearchSheetState extends State<BibleSearchSheet> {
  final LocalBibleService _service = LocalBibleService();
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String value) async {
    final term = value.trim();
    setState(() {
      _query = term;
      _searching = true;
    });
    if (term.isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    final results = await _service.search(widget.versionId, term);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.onSurfaceDisabled,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Text('Search Bible',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    onChanged: _search,
                    decoration: InputDecoration(
                      hintText: 'Search for a word or phrase…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _controller.clear();
                                _search('');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _buildBody(scrollController),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ScrollController scrollController) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_query.isEmpty) {
      return Center(
        child: Text(
          'Type keywords to search the whole Bible',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          'No results found for "$_query"',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      );
    }

    final theme = Theme.of(context);
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final r = _results[index];
        final book = r['book_name'] as String;
        final chapter = r['chapter'] as int;
        final verse = r['verse'] as int;
        final text = r['text'] as String;
        return ListTile(
          dense: true,
          leading: Text(
            '$chapter:$verse',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          title: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          subtitle: Text(
            book,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          onTap: () {
            Navigator.pop(context);
            widget.onJumpTo(book, chapter, verse);
          },
        );
      },
    );
  }
}
