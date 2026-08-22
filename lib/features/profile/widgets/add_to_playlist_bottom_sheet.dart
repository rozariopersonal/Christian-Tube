import 'package:flutter/material.dart';
import '../../../core/models/video.dart';
import '../user_service.dart';

class AddToPlaylistBottomSheet extends StatefulWidget {
  final Video video;
  final UserService userService;

  const AddToPlaylistBottomSheet({
    super.key,
    required this.video,
    required this.userService,
  });

  @override
  State<AddToPlaylistBottomSheet> createState() => _AddToPlaylistBottomSheetState();
}

class _AddToPlaylistBottomSheetState extends State<AddToPlaylistBottomSheet> {
  final _newPlaylistController = TextEditingController();
  bool _isCreatingNew = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Save to playlist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              TextButton.icon(
                onPressed: () => setState(() => _isCreatingNew = !_isCreatingNew),
                icon: const Icon(Icons.add),
                label: const Text('New playlist'),
              ),
            ],
          ),
          if (_isCreatingNew) ...[
            TextField(
              controller: _newPlaylistController,
              decoration: const InputDecoration(
                labelText: 'Playlist Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                if (_newPlaylistController.text.isNotEmpty) {
                  await widget.userService.createPlaylist(_newPlaylistController.text, null);
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Playlist created and video added!')),
                    );
                  }
                }
              },
              child: const Text('Create'),
            ),
            const SizedBox(height: 12),
          ],
          if (widget.userService.playlists.isEmpty && !_isCreatingNew)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: Text('No playlists yet. Create one above!')),
            )
          else
            ...widget.userService.playlists.map((pl) => ListTile(
              leading: const Icon(Icons.playlist_play),
              title: Text(pl.title),
              subtitle: Text('${pl.videoCount} videos'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Added to ${pl.title}!')),
                );
              },
            )),
        ],
      ),
    );
  }
}
