import 'package:flutter/material.dart';
import '../models/bible_version.dart';
import '../services/bible_service.dart';
import '../widgets/verse_text.dart';
import '../widgets/version_selector_sheet.dart';
import '../models/bible_verse.dart';

class BibleScreen extends StatefulWidget {
  const BibleScreen({super.key});

  @override
  State<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends State<BibleScreen> {
  final BibleService _bibleService = BibleService();
  List<BibleVersion> _versions = [];
  List<BibleVerse> _verses = [];
  BibleVersion? _selectedVersion;
  String _currentBook = 'Genesis';
  int _currentChapter = 1;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    if (_versions.isEmpty) {
      final versions = await _bibleService.getVersions();
      if (mounted) {
        _versions = versions;
        if (_versions.isNotEmpty) {
          _selectedVersion = _versions.firstWhere(
            (v) => v.shortname == 'KJV',
            orElse: () => _versions.first,
          );
        }
      }
    }
    
    if (_selectedVersion != null) {
      final verses = await _bibleService.getChapter(
        _selectedVersion!.shortname,
        _currentBook,
        _currentChapter,
      );
      if (mounted) {
        setState(() {
          _verses = verses;
          _isLoading = false;
        });
      }
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
          _fetchData();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$_currentBook $_currentChapter'),
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
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: _verses.length,
              itemBuilder: (context, index) {
                return VerseText(verse: _verses[index]);
              },
            ),
    );
  }
}
