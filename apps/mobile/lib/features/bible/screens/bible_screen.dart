import 'package:flutter/material.dart';
import '../models/bible_version.dart';
import '../../engines/scripture/services/local_bible_service.dart';
import '../../engines/scripture/widgets/bible_version_picker_modal.dart';
import '../../engines/scripture/screens/bible_manager_screen.dart';
import '../widgets/verse_text.dart';
import '../widgets/book_chapter_selector.dart';
import '../models/bible_verse.dart';
import '../models/bible_book.dart';

class BibleScreen extends StatefulWidget {
  const BibleScreen({super.key});

  @override
  State<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends State<BibleScreen> {
  final LocalBibleService _localBibleService = LocalBibleService();
  final ScrollController _scrollController = ScrollController();
  List<BibleVersion> _versions = [];
  List<BibleVerse> _verses = [];
  BibleVersion? _selectedVersion;
  String _currentBook = 'Genesis';
  int _currentChapter = 1;
  bool _isLoading = true;
  bool _isFetchingNextChapter = false;
  int _transitionDirection = 1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 500 && !_isFetchingNextChapter) {
      _fetchNextChapter(append: true);
    }
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
        // Scroll to top when data is re-fetched completely
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchNextChapter({bool append = false}) async {
    if (_isFetchingNextChapter || _selectedVersion == null) return;
    
    setState(() {
      _isFetchingNextChapter = true;
      if (!append) _transitionDirection = 1;
    });
    
    int maxChapters = bibleBooks[_currentBook] ?? 1;
    String nextBook = _currentBook;
    int nextChapter = _currentChapter + 1;

    if (nextChapter > maxChapters) {
      final books = bibleBooks.keys.toList();
      final currentIndex = books.indexOf(_currentBook);
      if (currentIndex < books.length - 1) {
        nextBook = books[currentIndex + 1];
        nextChapter = 1;
      } else {
        // End of Bible
        setState(() => _isFetchingNextChapter = false);
        return;
      }
    }

    final versesMap = await _localBibleService.getChapter(
      _selectedVersion!.shortname,
      nextBook,
      nextChapter,
    );

    final newVerses = versesMap.map((map) => BibleVerse(
      number: map['verse'] as int,
      text: map['text'] as String,
    )).toList();

    if (mounted) {
      setState(() {
        _currentBook = nextBook;
        _currentChapter = nextChapter;
        
        if (append) {
          _verses.add(BibleVerse(
            number: 0,
            text: '',
            isChapterHeader: true,
            chapterTitle: '$nextBook $nextChapter',
          ));
          _verses.addAll(newVerses);
        } else {
          _verses = newVerses;
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
        }
        _isFetchingNextChapter = false;
      });
    }
  }

  Future<void> _fetchPrevChapter() async {
    if (_selectedVersion == null) return;

    String prevBook = _currentBook;
    int prevChapter = _currentChapter - 1;

    if (prevChapter < 1) {
      final books = bibleBooks.keys.toList();
      final currentIndex = books.indexOf(_currentBook);
      if (currentIndex > 0) {
        prevBook = books[currentIndex - 1];
        prevChapter = bibleBooks[prevBook] ?? 1;
      } else {
        // Beginning of Bible
        return;
      }
    }

    setState(() {
      _currentBook = prevBook;
      _currentChapter = prevChapter;
      _transitionDirection = -1;
      _isLoading = true;
    });

    await _fetchData();
  }

  void _showVersionSelector() {
    if (_selectedVersion == null) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BibleVersionPickerModal(
        activeVersionId: _selectedVersion!.shortname,
        onSelectVersion: (versionId) {
          final version = _versions.firstWhere(
            (v) => v.shortname == versionId,
            orElse: () => BibleVersion(id: versionId, name: versionId, shortname: versionId),
          );
          setState(() {
            _selectedVersion = version;
          });
          _fetchData();
        },
        onOpenManager: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const BibleManagerScreen()),
          );
          // Refetch versions after returning from the manager
          _versions.clear();
          await _fetchData();
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
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _versions.isEmpty
                    ? const Center(
                        child: Text('No Bibles installed. Please install a Bible from the Scripture Engine.'),
                      )
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) {
                          final inAnimation = Tween<Offset>(
                                  begin: Offset(_transitionDirection.toDouble(), 0.0), 
                                  end: Offset.zero)
                              .animate(animation);
                          final outAnimation = Tween<Offset>(
                                  begin: Offset(-_transitionDirection.toDouble(), 0.0), 
                                  end: Offset.zero)
                              .animate(animation);

                          if (child.key == ValueKey('$_currentBook-$_currentChapter')) {
                            return SlideTransition(position: inAnimation, child: child);
                          } else {
                            return SlideTransition(position: outAnimation, child: child);
                          }
                        },
                        child: ListView.builder(
                          key: ValueKey('$_currentBook-$_currentChapter'),
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          itemCount: _verses.length + (_isFetchingNextChapter ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _verses.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            return VerseText(verse: _verses[index]);
                          },
                        ),
                      ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _fetchPrevChapter,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Prev'),
                ),
                TextButton.icon(
                  onPressed: () => _fetchNextChapter(append: false),
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Next'),
                  iconAlignment: IconAlignment.end,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
