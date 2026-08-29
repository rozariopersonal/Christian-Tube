import 'package:flutter/material.dart';
import '../models/bible_version.dart';
import '../services/bible_service.dart';
import '../widgets/version_selector_sheet.dart';

class BibleScreen extends StatefulWidget {
  const BibleScreen({super.key});

  @override
  State<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends State<BibleScreen> {
  final BibleService _bibleService = BibleService();
  List<BibleVersion> _versions = [];
  BibleVersion? _selectedVersion;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchVersions();
  }

  Future<void> _fetchVersions() async {
    final versions = await _bibleService.getVersions();
    if (mounted) {
      setState(() {
        _versions = versions;
        if (_versions.isNotEmpty) {
          _selectedVersion = _versions.firstWhere(
            (v) => v.shortname == 'KJV',
            orElse: () => _versions.first,
          );
        }
        _isLoading = false;
      });
    }
  }

  void _showVersionSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => VersionSelectorSheet(
        versions: _versions,
        selectedVersion: _selectedVersion,
        onVersionSelected: (version) {
          setState(() {
            _selectedVersion = version;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bible'),
        actions: [
          if (_selectedVersion != null)
            TextButton(
              onPressed: _showVersionSelector,
              child: Text(
                _selectedVersion!.shortname,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : const Center(child: Text('Bible content coming soon')),
    );
  }
}
