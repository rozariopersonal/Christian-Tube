import 'package:flutter/material.dart';
import '../models/bible_version.dart';
import '../../engines/scripture/services/local_bible_service.dart';
import '../widgets/verse_text.dart';
import '../widgets/version_selector_sheet.dart';
import '../widgets/book_chapter_selector.dart';
import '../models/bible_verse.dart';

class BibleScreen extends StatefulWidget {
  const BibleScreen({super.key});

  @override
  State<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends State<BibleScreen> {
  final LocalBibleService _localBibleService = LocalBibleService();
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
      final versionIds = await _localBibleService.getInstalledVersionIds();
      if (mounted) {
        _versions = versionIds.map((id) => BibleVersion(id: id, name: id, shortname: id)).toList();
        if (_versions.isNotEmpty) {
          _selectedVersion = _versions.firstWhere(
            (v) => v.shortname == 'KJV',
            orElse: () => _versions.first,
          );
        }
      }
    }
    
    if (_selectedVersion != null) {
      final versesMap = await _localBibleService.getChapter(
        _selectedVersion!.shortname,
        _currentBook,
        _currentChapter,
      );
      if (mounted) {
        setState(() {
          _verses = versesMap.map((map) => BibleVerse(
            number: map['verse'] as int,
            text: map['text'] as String,
          )).toList();
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
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

  void _showBookChapterSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BookChapterSelector(
        currentBook: _currentBook,
        currentChapter: _currentChapter,
        onSelection: (book, chapter) {
          setState(() {
            _currentBook = book;
            _currentChapter = chapter;
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
        title: GestureDetector(
          onTap: _showBookChapterSelector,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$_currentBook $_currentChapter',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
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
          : _versions.isEmpty
              ? const Center(
                  child: Text('No Bibles installed. Please install a Bible from the Scripture Engine.'),
                )
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
