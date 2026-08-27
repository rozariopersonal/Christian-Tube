import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class LocalBibleService {
  static final LocalBibleService _instance = LocalBibleService._internal();
  factory LocalBibleService() => _instance;
  LocalBibleService._internal();

  Database? _db;

  // In-Memory map for Web compatibility
  final Map<String, String> _webVerses = {};
  final Set<String> _webInstalledVersions = {'WEB', 'KJV', 'TAOBVSI'};

  Future<void> initialize() async {
    if (kIsWeb) {
      _seedWebVerses();
      return;
    }

    if (_db != null) return;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'christian_tube_bibles.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE verses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            version_id TEXT NOT NULL,
            book_number INTEGER NOT NULL,
            book_name TEXT NOT NULL,
            chapter INTEGER NOT NULL,
            verse INTEGER NOT NULL,
            text TEXT NOT NULL
          );
        ''');
        await db.execute('''
          CREATE INDEX idx_bible_lookup 
          ON verses (version_id, book_number, chapter, verse);
        ''');

        await db.execute('''
          CREATE TABLE installed_versions (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            language TEXT NOT NULL,
            language_code TEXT NOT NULL,
            size_display TEXT NOT NULL,
            installed_at TEXT NOT NULL
          );
        ''');

        // Seed initial default version (WEB) and seed verses
        await _seedDefaultBibles(db);
      },
    );
  }

  void _seedWebVerses() {
    _addWebVerse('WEB', 43, 14, 27,
        'Peace I leave with you. My peace I give to you; not as the world gives, give I to you. Don’t let your heart be troubled, neither let it be fearful.');
    _addWebVerse('KJV', 43, 14, 27,
        'Peace I leave with you, my peace I give unto you: not as the world giveth, give I unto you. Let not your heart be troubled, neither let it be afraid.');
    _addWebVerse('TAOBVSI', 43, 14, 27,
        'சமாதானத்தை உங்களுக்கு வைத்துப்போகிறேன், என்னுடைய சமாதானத்தையே உங்களுக்குக் கொடுக்கிறேன்; உலகம் கொடுக்கிறபிரகாரம் நான் உங்களுக்குக் கொடுக்கிறதில்லை. உங்கள் இருதயம் கலங்காமலும் பயப்படாமலும் இருப்பதாக.');

    _addWebVerse('WEB', 43, 3, 16,
        'For God so loved the world, that he gave his one and only Son, that whoever believes in him should not perish, but have eternal life.');
    _addWebVerse('KJV', 43, 3, 16,
        'For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.');
    _addWebVerse('TAOBVSI', 43, 3, 16,
        'தேவன், தம்முடைய ஒரேபேறான குமாரனை விசுவாசிக்கிற எவனும் கெட்டுப்போகாமல் நித்தியஜீவனை அடையும்படிக்கு, அவரைத் தந்தருளி, இவ்வளவாய் உலகத்தில் அன்புகூர்ந்தார்.');

    _addWebVerse('WEB', 24, 29, 11,
        '“For I know the thoughts that I think toward you,” says Yahweh, “thoughts of peace, and not of evil, to give you hope and a future.”');
    _addWebVerse('KJV', 24, 29, 11,
        'For I know the thoughts that I think toward you, saith the LORD, thoughts of peace, and not of evil, to give you an expected end.');
    _addWebVerse('TAOBVSI', 24, 29, 11,
        'நீங்கள் எதிர்பார்த்திருக்கும் முடிவை உங்களுக்குக் கொடுக்கும்படிக்கு நான் உங்கள்பேரில் நினைத்திருக்கிற நினைவுகளை அறிவேன் என்று கர்த்தர் சொல்லுகிறார்; அவைகள் தீமைக்கல்ல, சமாதானத்துக்கேதுவான நினைவுகளே.');

    _addWebVerse('WEB', 50, 4, 6,
        'In nothing be anxious, but in everything, by prayer and petition with thanksgiving, let your requests be made known to God.');
    _addWebVerse('WEB', 50, 4, 7,
        'And the peace of God, which surpasses all understanding, will guard your hearts and your thoughts in Christ Jesus.');
    _addWebVerse('TAOBVSI', 50, 4, 6,
        'நீங்கள் ஒன்றுக்குங் கவலைப்படாமல், எல்லாவற்றையுங்குறித்து உங்கள் விண்ணப்பங்களை ஸ்தோத்திரத்தோடே கூடிய ஜெபத்தினாலும் வேண்டுதலினாலும் தேவனுக்குத் தெரியப்படுத்துங்கள்.');
    _addWebVerse('TAOBVSI', 50, 4, 7,
        'அப்பொழுது, எல்லாப் புத்திக்கும் மேலான தேவ சமாதானம் உங்கள் இருதயங்களையும் உங்கள் சிந்தைகளையும் கிறிஸ்து இயேசுவுக்குள்ளாகக் காத்துக்கொள்ளும்.');

    _addWebVerse('WEB', 19, 23, 1, 'Yahweh is my shepherd: I shall lack nothing.');
    _addWebVerse('WEB', 19, 23, 2,
        'He makes me lie down in green pastures. He leads me beside still waters.');
    _addWebVerse('WEB', 19, 23, 3,
        'He restores my soul. He guides me in the paths of righteousness for his name’s sake.');

    _addWebVerse('TAOBVSI', 19, 23, 1,
        'கர்த்தர் என் மேய்ப்பராயிருக்கிறார்; நான் தாழ்ச்சியடையேன்.');
    _addWebVerse('TAOBVSI', 19, 23, 2,
        'அவர் என்னைப் புல்லுள்ள இடங்களில் படுக்கப்பண்ணி, அமர்ந்த தண்ணீர்கள் அண்டையில் என்னைக் கொண்டுபோய் விடுகிறார்.');
    _addWebVerse('TAOBVSI', 19, 23, 3,
        'அவர் என் ஆத்துமாவைத் தேற்றி, தம்முடைய நாமத்தினிமித்தம் என்னை நீதியின் பாதைகளில் நடத்துகிறார்.');

    _addWebVerse('WEB', 6, 1, 9,
        'Haven’t I commanded you? Be strong and courageous. Don’t be afraid. Don’t be dismayed, for Yahweh your God is with you wherever you go.');
    _addWebVerse('TAOBVSI', 6, 1, 9,
        'நான் உனக்குக் கட்டளையிடவில்லையா? பலங்கொண்டு திடமனதாயிரு; திகையாதே, கலங்காதே, நீ போகும் இடமெல்லாம் உன் தேவனாகிய கர்த்தர் உன்னோடே இருக்கிறார் என்றார்.');

    _addWebVerse('WEB', 45, 8, 28,
        'We know that all things work together for good for those who love God, to those who are called according to his purpose.');
    _addWebVerse('TAOBVSI', 45, 8, 28,
        'அன்றியும், அவருடைய தீர்மானத்தின்படி அழைக்கப்பட்டவர்களாய் தேவனிடத்தில் அன்புகூருகிறவர்களுக்குச் சகலமும் நன்மைக்கு ஏதுவாக நடக்கிறது என்று அறிந்திருக்கிறோம்.');

    _addWebVerse('WEB', 23, 40, 31,
        'But those who wait for Yahweh will renew their strength. They will mount up with wings like eagles. They will run, and not be weary. They will walk, and not faint.');
    _addWebVerse('TAOBVSI', 23, 40, 31,
        'கர்த்தருக்குக் காத்திருக்கிறவர்களோ புதுப்பெலன் அடைந்து, கழுகுகளைப்போலச் செட்டைகளை அடித்து எழும்புவார்கள்; அவர்கள் ஓடினாலும் இளைப்படையார்கள், நடந்தாலும் சோர்ந்துபோகார்கள்.');

    _addWebVerse('WEB', 20, 3, 5,
        'Trust in Yahweh with all your heart, and don’t lean on your own understanding.');
    _addWebVerse('WEB', 20, 3, 6,
        'In all your ways acknowledge him, and he will make your paths straight.');
    _addWebVerse('TAOBVSI', 20, 3, 5,
        'உன் சுயபுத்தியின்மேல் சாயாமல், உன் முழு இருதயத்தோடும் கர்த்தரில் நம்பிக்கையாயிருந்து;');
    _addWebVerse('TAOBVSI', 20, 3, 6,
        'உன் வழிகளிலெல்லாம் அவரை நினைத்துக்கொள்; அப்பொழுது அவர் உன் பாதைகளைச் செவ்வைப்படுத்துவார்.');
  }

  void _addWebVerse(
      String versionId, int book, int chapter, int verse, String text) {
    _webVerses['${versionId}_${book}_${chapter}_$verse'] = text;
  }

  Future<void> _seedDefaultBibles(Database db) async {
    final now = DateTime.now().toIso8601String();

    await db.insert('installed_versions', {
      'id': 'WEB',
      'name': 'World English Bible',
      'language': 'English',
      'language_code': 'en',
      'size_display': '1.4 MB',
      'installed_at': now,
    });

    await db.insert('installed_versions', {
      'id': 'KJV',
      'name': 'King James Version',
      'language': 'English',
      'language_code': 'en',
      'size_display': '1.3 MB',
      'installed_at': now,
    });

    await db.insert('installed_versions', {
      'id': 'TAOBVSI',
      'name': 'Tamil Old Version (பரிசுத்த வேதாகமம்)',
      'language': 'Tamil',
      'language_code': 'tam',
      'size_display': '1.5 MB',
      'installed_at': now,
    });

    final batch = db.batch();

    // John 14:27
    batch.insert('verses', {
      'version_id': 'WEB',
      'book_number': 43,
      'book_name': 'John',
      'chapter': 14,
      'verse': 27,
      'text':
          'Peace I leave with you. My peace I give to you; not as the world gives, give I to you. Don’t let your heart be troubled, neither let it be fearful.',
    });
    batch.insert('verses', {
      'version_id': 'KJV',
      'book_number': 43,
      'book_name': 'John',
      'chapter': 14,
      'verse': 27,
      'text':
          'Peace I leave with you, my peace I give unto you: not as the world giveth, give I unto you. Let not your heart be troubled, neither let it be afraid.',
    });
    batch.insert('verses', {
      'version_id': 'TAOBVSI',
      'book_number': 43,
      'book_name': 'John',
      'chapter': 14,
      'verse': 27,
      'text':
          'சமாதானத்தை உங்களுக்கு வைத்துப்போகிறேன், என்னுடைய சமாதானத்தையே உங்களுக்குக் கொடுக்கிறேன்; உலகம் கொடுக்கிறபிரகாரம் நான் உங்களுக்குக் கொடுக்கிறதில்லை. உங்கள் இருதயம் கலங்காமலும் பயப்படாமலும் இருப்பதாக.',
    });

    // John 3:16
    batch.insert('verses', {
      'version_id': 'WEB',
      'book_number': 43,
      'book_name': 'John',
      'chapter': 3,
      'verse': 16,
      'text':
          'For God so loved the world, that he gave his one and only Son, that whoever believes in him should not perish, but have eternal life.',
    });
    batch.insert('verses', {
      'version_id': 'KJV',
      'book_number': 43,
      'book_name': 'John',
      'chapter': 3,
      'verse': 16,
      'text':
          'For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.',
    });
    batch.insert('verses', {
      'version_id': 'TAOBVSI',
      'book_number': 43,
      'book_name': 'John',
      'chapter': 3,
      'verse': 16,
      'text':
          'தேவன், தம்முடைய ஒரேபேறான குமாரனை விசுவாசிக்கிற எவனும் கெட்டுப்போகாமல் நித்தியஜீவனை அடையும்படிக்கு, அவரைத் தந்தருளி, இவ்வளவாய் உலகத்தில் அன்புகூர்ந்தார்.',
    });

    // Jeremiah 29:11
    batch.insert('verses', {
      'version_id': 'WEB',
      'book_number': 24,
      'book_name': 'Jeremiah',
      'chapter': 29,
      'verse': 11,
      'text':
          '“For I know the thoughts that I think toward you,” says Yahweh, “thoughts of peace, and not of evil, to give you hope and a future.”',
    });
    batch.insert('verses', {
      'version_id': 'KJV',
      'book_number': 24,
      'book_name': 'Jeremiah',
      'chapter': 29,
      'verse': 11,
      'text':
          'For I know the thoughts that I think toward you, saith the LORD, thoughts of peace, and not of evil, to give you an expected end.',
    });
    batch.insert('verses', {
      'version_id': 'TAOBVSI',
      'book_number': 24,
      'book_name': 'Jeremiah',
      'chapter': 29,
      'verse': 11,
      'text':
          'நீங்கள் எதிர்பார்த்திருக்கும் முடிவை உங்களுக்குக் கொடுக்கும்படிக்கு நான் உங்கள்பேரில் நினைத்திருக்கிற நினைவுகளை அறிவேன் என்று கர்த்தர் சொல்லுகிறார்; அவைகள் தீமைக்கல்ல, சமாதானத்துக்கேதுவான நினைவுகளே.',
    });

    // Philippians 4:6-7
    batch.insert('verses', {
      'version_id': 'WEB',
      'book_number': 50,
      'book_name': 'Philippians',
      'chapter': 4,
      'verse': 6,
      'text':
          'In nothing be anxious, but in everything, by prayer and petition with thanksgiving, let your requests be made known to God.',
    });
    batch.insert('verses', {
      'version_id': 'WEB',
      'book_number': 50,
      'book_name': 'Philippians',
      'chapter': 4,
      'verse': 7,
      'text':
          'And the peace of God, which surpasses all understanding, will guard your hearts and your thoughts in Christ Jesus.',
    });
    batch.insert('verses', {
      'version_id': 'TAOBVSI',
      'book_number': 50,
      'book_name': 'Philippians',
      'chapter': 4,
      'verse': 6,
      'text':
          'நீங்கள் ஒன்றுக்குங் கவலைப்படாமல், எல்லாவற்றையுங்குறித்து உங்கள் விண்ணப்பங்களை ஸ்தோத்திரத்தோடே கூடிய ஜெபத்தினாலும் வேண்டுதலினாலும் தேவனுக்குத் தெரியப்படுத்துங்கள்.',
    });
    batch.insert('verses', {
      'version_id': 'TAOBVSI',
      'book_number': 50,
      'book_name': 'Philippians',
      'chapter': 4,
      'verse': 7,
      'text':
          'அப்பொழுது, எல்லாப் புத்திக்கும் மேலான தேவ சமாதானம் உங்கள் இருதயங்களையும் உங்கள் சிந்தைகளையும் கிறிஸ்து இயேசுவுக்குள்ளாகக் காத்துக்கொள்ளும்.',
    });

    // Psalm 23:1-3
    batch.insert('verses', {
      'version_id': 'WEB',
      'book_number': 19,
      'book_name': 'Psalms',
      'chapter': 23,
      'verse': 1,
      'text': 'Yahweh is my shepherd: I shall lack nothing.',
    });
    batch.insert('verses', {
      'version_id': 'WEB',
      'book_number': 19,
      'book_name': 'Psalms',
      'chapter': 23,
      'verse': 2,
      'text':
          'He makes me lie down in green pastures. He leads me beside still waters.',
    });
    batch.insert('verses', {
      'version_id': 'WEB',
      'book_number': 19,
      'book_name': 'Psalms',
      'chapter': 23,
      'verse': 3,
      'text':
          'He restores my soul. He guides me in the paths of righteousness for his name’s sake.',
    });

    batch.insert('verses', {
      'version_id': 'TAOBVSI',
      'book_number': 19,
      'book_name': 'Psalms',
      'chapter': 23,
      'verse': 1,
      'text': 'கர்த்தர் என் மேய்ப்பராயிருக்கிறார்; நான் தாழ்ச்சியடையேன்.',
    });
    batch.insert('verses', {
      'version_id': 'TAOBVSI',
      'book_number': 19,
      'book_name': 'Psalms',
      'chapter': 23,
      'verse': 2,
      'text':
          'அவர் என்னைப் புல்லுள்ள இடங்களில் படுக்கப்பண்ணி, அமர்ந்த தண்ணீர்கள் அண்டையில் என்னைக் கொண்டுபோய் விடுகிறார்.',
    });
    batch.insert('verses', {
      'version_id': 'TAOBVSI',
      'book_number': 19,
      'book_name': 'Psalms',
      'chapter': 23,
      'verse': 3,
      'text':
          'அவர் என் ஆத்துமாவைத் தேற்றி, தம்முடைய நாமத்தினிமித்தம் என்னை நீதியின் பாதைகளில் நடத்துகிறார்.',
    });

    // Joshua 1:9
    batch.insert('verses', {
      'version_id': 'WEB',
      'book_number': 6,
      'book_name': 'Joshua',
      'chapter': 1,
      'verse': 9,
      'text':
          'Haven’t I commanded you? Be strong and courageous. Don’t be afraid. Don’t be dismayed, for Yahweh your God is with you wherever you go.',
    });
    batch.insert('verses', {
      'version_id': 'TAOBVSI',
      'book_number': 6,
      'book_name': 'Joshua',
      'chapter': 1,
      'verse': 9,
      'text':
          'நான் உனக்குக் கட்டளையிடவில்லையா? பலங்கொண்டு திடமனதாயிரு; திகையாதே, கலங்காதே, நீ போகும் இடமெல்லாம் உன் தேவனாகிய கர்த்தர் உன்னோடே இருக்கிறார் என்றார்.',
    });

    // Romans 8:28
    batch.insert('verses', {
      'version_id': 'WEB',
      'book_number': 45,
      'book_name': 'Romans',
      'chapter': 8,
      'verse': 28,
      'text':
          'We know that all things work together for good for those who love God, to those who are called according to his purpose.',
    });
    batch.insert('verses', {
      'version_id': 'TAOBVSI',
      'book_number': 45,
      'book_name': 'Romans',
      'chapter': 8,
      'verse': 28,
      'text':
          'அன்றியும், அவருடைய தீர்மானத்தின்படி அழைக்கப்பட்டவர்களாய் தேவனிடத்தில் அன்புகூருகிறவர்களுக்குச் சகலமும் நன்மைக்கு ஏதுவாக நடக்கிறது என்று அறிந்திருக்கிறோம்.',
    });

    // Isaiah 40:31
    batch.insert('verses', {
      'version_id': 'WEB',
      'book_number': 23,
      'book_name': 'Isaiah',
      'chapter': 40,
      'verse': 31,
      'text':
          'But those who wait for Yahweh will renew their strength. They will mount up with wings like eagles. They will run, and not be weary. They will walk, and not faint.',
    });
    batch.insert('verses', {
      'version_id': 'TAOBVSI',
      'book_number': 23,
      'book_name': 'Isaiah',
      'chapter': 40,
      'verse': 31,
      'text':
          'கர்த்தருக்குக் காத்திருக்கிறவர்களோ புதுப்பெலன் அடைந்து, கழுகுகளைப்போலச் செட்டைகளை அடித்து எழும்புவார்கள்; அவர்கள் ஓடினாலும் இளைப்படையார்கள், நடந்தாலும் சோர்ந்துபோகார்கள்.',
    });

    // Proverbs 3:5-6
    batch.insert('verses', {
      'version_id': 'WEB',
      'book_number': 20,
      'book_name': 'Proverbs',
      'chapter': 3,
      'verse': 5,
      'text':
          'Trust in Yahweh with all your heart, and don’t lean on your own understanding.',
    });
    batch.insert('verses', {
      'version_id': 'WEB',
      'book_number': 20,
      'book_name': 'Proverbs',
      'chapter': 3,
      'verse': 6,
      'text':
          'In all your ways acknowledge him, and he will make your paths straight.',
    });
    batch.insert('verses', {
      'version_id': 'TAOBVSI',
      'book_number': 20,
      'book_name': 'Proverbs',
      'chapter': 3,
      'verse': 5,
      'text':
          'உன் சுயபுத்தியின்மேல் சாயாமல், உன் முழு இருதயத்தோடும் கர்த்தரில் நம்பிக்கையாயிருந்து;',
    });
    batch.insert('verses', {
      'version_id': 'TAOBVSI',
      'book_number': 20,
      'book_name': 'Proverbs',
      'chapter': 3,
      'verse': 6,
      'text':
          'உன் வழிகளிலெல்லாம் அவரை நினைத்துக்கொள்; அப்பொழுது அவர் உன் பாதைகளைச் செவ்வைப்படுத்துவார்.',
    });

    await batch.commit(noResult: true);
  }

  Future<String?> resolvePassage({
    required String versionId,
    required int bookNumber,
    required int chapter,
    required int startVerse,
    int? endVerse,
  }) async {
    final end = endVerse ?? startVerse;

    if (kIsWeb) {
      final List<String> parts = [];
      for (int v = startVerse; v <= end; v++) {
        final key = '${versionId}_${bookNumber}_${chapter}_$v';
        if (_webVerses.containsKey(key)) {
          parts.add(_webVerses[key]!);
        }
      }
      if (parts.isNotEmpty) return parts.join(' ');
      return null;
    }

    final db = _db;
    if (db == null) return null;

    final results = await db.query(
      'verses',
      columns: ['text'],
      where:
          'version_id = ? AND book_number = ? AND chapter = ? AND verse >= ? AND verse <= ?',
      whereArgs: [versionId, bookNumber, chapter, startVerse, end],
      orderBy: 'verse ASC',
    );

    if (results.isEmpty) return null;
    return results.map((r) => r['text'] as String).join(' ');
  }

  Future<List<String>> getInstalledVersionIds() async {
    if (kIsWeb) {
      return _webInstalledVersions.toList();
    }

    final db = _db;
    if (db == null) return ['WEB'];

    final results = await db.query('installed_versions', columns: ['id']);
    return results.map((r) => r['id'] as String).toList();
  }

  Future<void> registerInstalledVersion({
    required String id,
    required String name,
    required String language,
    required String languageCode,
    required String sizeDisplay,
  }) async {
    if (kIsWeb) {
      _webInstalledVersions.add(id);
      return;
    }

    final db = _db;
    if (db == null) return;

    await db.insert(
      'installed_versions',
      {
        'id': id,
        'name': name,
        'language': language,
        'language_code': languageCode,
        'size_display': sizeDisplay,
        'installed_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertVerses(
      String versionId, List<Map<String, dynamic>> verses) async {
    if (kIsWeb) {
      for (final v in verses) {
        final book = v['bookNumber'] ?? v['book_number'];
        final chapter = v['chapter'];
        final verse = v['verse'];
        final text = v['text'];
        _webVerses['${versionId}_${book}_${chapter}_$verse'] = text;
      }
      return;
    }

    final db = _db;
    if (db == null) return;

    final batch = db.batch();
    for (final v in verses) {
      batch.insert('verses', {
        'version_id': versionId,
        'book_number': v['bookNumber'] ?? v['book_number'],
        'book_name': v['bookName'] ?? v['book_name'] ?? '',
        'chapter': v['chapter'],
        'verse': v['verse'],
        'text': v['text'],
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteVersion(String versionId) async {
    if (kIsWeb) {
      _webInstalledVersions.remove(versionId);
      return;
    }

    final db = _db;
    if (db == null) return;

    await db.delete('installed_versions',
        where: 'id = ?', whereArgs: [versionId]);
    await db.delete('verses', where: 'version_id = ?', whereArgs: [versionId]);
  }
}
