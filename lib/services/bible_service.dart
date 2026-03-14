// lib/services/bible_service.dart
//
// Powered by bolls.life (free, no API key required).
// KJV, NKJV, ESV, NASB1995, NIV, NLT, CSB, BSB, ASV, WEB, YLT + 100 more.
//
// OFFLINE-FIRST: all 66 books + 15 popular translations are hardcoded and
// available immediately — no network needed just to browse. Network is only
// required to load verse text.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ══════════════════════════════════════════════════════════════════════════════
// MODELS
// ══════════════════════════════════════════════════════════════════════════════

class BibleTranslation {
  final String id;
  final String name;
  final String shortName;
  final String language;
  final String languageEnglishName;
  const BibleTranslation({
    required this.id, required this.name, required this.shortName,
    required this.language, required this.languageEnglishName,
  });
  factory BibleTranslation.fromJson(Map<String, dynamic> j) =>
      BibleTranslation(
        id:                  ((j['short_name'] ?? '') as String).trim(),
        shortName:           ((j['short_name'] ?? '') as String).trim(),
        name:                ((j['full_name']  ?? j['short_name'] ?? '') as String).trim(),
        language:            ((j['language']   ?? 'en') as String).trim(),
        languageEnglishName: ((j['language']   ?? 'English') as String).trim(),
      );
  @override String toString() => '$shortName – $name';
}

class BibleBook {
  final int    bookId;
  final String name;
  final int    chapters;
  final bool   isOT;
  const BibleBook({required this.bookId, required this.name, required this.chapters, required this.isOT});
  String get id => bookId.toString();
  factory BibleBook.fromJson(Map<String, dynamic> j) {
    final id = (j['bookid'] as num?)?.toInt() ?? 0;
    return BibleBook(bookId: id, name: ((j['name'] ?? '') as String).trim(),
        chapters: (j['chapters'] as num?)?.toInt() ?? 1, isOT: id <= 39);
  }
}

class BibleVerse {
  final int number; final String text;
  const BibleVerse({required this.number, required this.text});
}

class BibleChapter {
  final String translationId; final int bookId; final String bookName;
  final int chapterNumber; final List<BibleVerse> verses;
  const BibleChapter({required this.translationId, required this.bookId,
      required this.bookName, required this.chapterNumber, required this.verses});
}

class VerseSearchResult {
  final String bookName; final int bookId, chapter, verse;
  final String text, reference;
  const VerseSearchResult({required this.bookName, required this.bookId,
      required this.chapter, required this.verse, required this.text, required this.reference});
}

// ══════════════════════════════════════════════════════════════════════════════
// HARDCODED FALLBACKS — always visible, no network needed
// ══════════════════════════════════════════════════════════════════════════════

const _builtinTranslations = <BibleTranslation>[
  BibleTranslation(id:'KJV',     shortName:'KJV',     name:'King James Version (1769)',            language:'en', languageEnglishName:'English'),
  BibleTranslation(id:'NKJV',    shortName:'NKJV',    name:'New King James Version (1982)',         language:'en', languageEnglishName:'English'),
  BibleTranslation(id:'ESV',     shortName:'ESV',     name:'English Standard Version (2001/2016)', language:'en', languageEnglishName:'English'),
  BibleTranslation(id:'NASB',    shortName:'NASB',    name:'New American Standard Bible (1995)',   language:'en', languageEnglishName:'English'),
  BibleTranslation(id:'NIV',     shortName:'NIV',     name:'New International Version (1984)',     language:'en', languageEnglishName:'English'),
  BibleTranslation(id:'NIV2011', shortName:'NIV2011', name:'New International Version (2011)',     language:'en', languageEnglishName:'English'),
  BibleTranslation(id:'NLT',     shortName:'NLT',     name:'New Living Translation (2015)',        language:'en', languageEnglishName:'English'),
  BibleTranslation(id:'CSB17',   shortName:'CSB',     name:'Christian Standard Bible (2017)',      language:'en', languageEnglishName:'English'),
  BibleTranslation(id:'BSB',     shortName:'BSB',     name:'Berean Standard Bible',                language:'en', languageEnglishName:'English'),
  BibleTranslation(id:'LSB',     shortName:'LSB',     name:'Legacy Standard Bible',                language:'en', languageEnglishName:'English'),
  BibleTranslation(id:'ASV',     shortName:'ASV',     name:'American Standard Version (1901)',     language:'en', languageEnglishName:'English'),
  BibleTranslation(id:'WEB',     shortName:'WEB',     name:'World English Bible',                  language:'en', languageEnglishName:'English'),
  BibleTranslation(id:'YLT',     shortName:'YLT',     name:"Young's Literal Translation (1898)",   language:'en', languageEnglishName:'English'),
  BibleTranslation(id:'AMP',     shortName:'AMP',     name:'Amplified Bible (2015)',               language:'en', languageEnglishName:'English'),
  BibleTranslation(id:'MSG',     shortName:'MSG',     name:'The Message (2002)',                   language:'en', languageEnglishName:'English'),
];

const popularTranslationIds = <String>[
  'KJV','NKJV','ESV','NASB','NIV','NIV2011','NLT','CSB17','BSB','LSB','ASV','WEB','YLT','AMP','MSG',
];

const _builtinBooks = <BibleBook>[
  BibleBook(bookId: 1,  name:'Genesis',         chapters:50,  isOT:true),
  BibleBook(bookId: 2,  name:'Exodus',           chapters:40,  isOT:true),
  BibleBook(bookId: 3,  name:'Leviticus',        chapters:27,  isOT:true),
  BibleBook(bookId: 4,  name:'Numbers',          chapters:36,  isOT:true),
  BibleBook(bookId: 5,  name:'Deuteronomy',      chapters:34,  isOT:true),
  BibleBook(bookId: 6,  name:'Joshua',           chapters:24,  isOT:true),
  BibleBook(bookId: 7,  name:'Judges',           chapters:21,  isOT:true),
  BibleBook(bookId: 8,  name:'Ruth',             chapters:4,   isOT:true),
  BibleBook(bookId: 9,  name:'1 Samuel',         chapters:31,  isOT:true),
  BibleBook(bookId: 10, name:'2 Samuel',         chapters:24,  isOT:true),
  BibleBook(bookId: 11, name:'1 Kings',          chapters:22,  isOT:true),
  BibleBook(bookId: 12, name:'2 Kings',          chapters:25,  isOT:true),
  BibleBook(bookId: 13, name:'1 Chronicles',     chapters:29,  isOT:true),
  BibleBook(bookId: 14, name:'2 Chronicles',     chapters:36,  isOT:true),
  BibleBook(bookId: 15, name:'Ezra',             chapters:10,  isOT:true),
  BibleBook(bookId: 16, name:'Nehemiah',         chapters:13,  isOT:true),
  BibleBook(bookId: 17, name:'Esther',           chapters:10,  isOT:true),
  BibleBook(bookId: 18, name:'Job',              chapters:42,  isOT:true),
  BibleBook(bookId: 19, name:'Psalms',           chapters:150, isOT:true),
  BibleBook(bookId: 20, name:'Proverbs',         chapters:31,  isOT:true),
  BibleBook(bookId: 21, name:'Ecclesiastes',     chapters:12,  isOT:true),
  BibleBook(bookId: 22, name:'Song of Solomon',  chapters:8,   isOT:true),
  BibleBook(bookId: 23, name:'Isaiah',           chapters:66,  isOT:true),
  BibleBook(bookId: 24, name:'Jeremiah',         chapters:52,  isOT:true),
  BibleBook(bookId: 25, name:'Lamentations',     chapters:5,   isOT:true),
  BibleBook(bookId: 26, name:'Ezekiel',          chapters:48,  isOT:true),
  BibleBook(bookId: 27, name:'Daniel',           chapters:12,  isOT:true),
  BibleBook(bookId: 28, name:'Hosea',            chapters:14,  isOT:true),
  BibleBook(bookId: 29, name:'Joel',             chapters:3,   isOT:true),
  BibleBook(bookId: 30, name:'Amos',             chapters:9,   isOT:true),
  BibleBook(bookId: 31, name:'Obadiah',          chapters:1,   isOT:true),
  BibleBook(bookId: 32, name:'Jonah',            chapters:4,   isOT:true),
  BibleBook(bookId: 33, name:'Micah',            chapters:7,   isOT:true),
  BibleBook(bookId: 34, name:'Nahum',            chapters:3,   isOT:true),
  BibleBook(bookId: 35, name:'Habakkuk',         chapters:3,   isOT:true),
  BibleBook(bookId: 36, name:'Zephaniah',        chapters:3,   isOT:true),
  BibleBook(bookId: 37, name:'Haggai',           chapters:2,   isOT:true),
  BibleBook(bookId: 38, name:'Zechariah',        chapters:14,  isOT:true),
  BibleBook(bookId: 39, name:'Malachi',          chapters:4,   isOT:true),
  BibleBook(bookId: 40, name:'Matthew',          chapters:28,  isOT:false),
  BibleBook(bookId: 41, name:'Mark',             chapters:16,  isOT:false),
  BibleBook(bookId: 42, name:'Luke',             chapters:24,  isOT:false),
  BibleBook(bookId: 43, name:'John',             chapters:21,  isOT:false),
  BibleBook(bookId: 44, name:'Acts',             chapters:28,  isOT:false),
  BibleBook(bookId: 45, name:'Romans',           chapters:16,  isOT:false),
  BibleBook(bookId: 46, name:'1 Corinthians',    chapters:16,  isOT:false),
  BibleBook(bookId: 47, name:'2 Corinthians',    chapters:13,  isOT:false),
  BibleBook(bookId: 48, name:'Galatians',        chapters:6,   isOT:false),
  BibleBook(bookId: 49, name:'Ephesians',        chapters:6,   isOT:false),
  BibleBook(bookId: 50, name:'Philippians',      chapters:4,   isOT:false),
  BibleBook(bookId: 51, name:'Colossians',       chapters:4,   isOT:false),
  BibleBook(bookId: 52, name:'1 Thessalonians',  chapters:5,   isOT:false),
  BibleBook(bookId: 53, name:'2 Thessalonians',  chapters:3,   isOT:false),
  BibleBook(bookId: 54, name:'1 Timothy',        chapters:6,   isOT:false),
  BibleBook(bookId: 55, name:'2 Timothy',        chapters:4,   isOT:false),
  BibleBook(bookId: 56, name:'Titus',            chapters:3,   isOT:false),
  BibleBook(bookId: 57, name:'Philemon',         chapters:1,   isOT:false),
  BibleBook(bookId: 58, name:'Hebrews',          chapters:13,  isOT:false),
  BibleBook(bookId: 59, name:'James',            chapters:5,   isOT:false),
  BibleBook(bookId: 60, name:'1 Peter',          chapters:5,   isOT:false),
  BibleBook(bookId: 61, name:'2 Peter',          chapters:3,   isOT:false),
  BibleBook(bookId: 62, name:'1 John',           chapters:5,   isOT:false),
  BibleBook(bookId: 63, name:'2 John',           chapters:1,   isOT:false),
  BibleBook(bookId: 64, name:'3 John',           chapters:1,   isOT:false),
  BibleBook(bookId: 65, name:'Jude',             chapters:1,   isOT:false),
  BibleBook(bookId: 66, name:'Revelation',       chapters:22,  isOT:false),
];

// ══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ══════════════════════════════════════════════════════════════════════════════

class BibleService extends ChangeNotifier {
  static const _apiBase = 'https://bolls.life';
  static const _prefKey = 'bible_translation_id_v3';
  static const _timeout = Duration(seconds: 20);

  String _translationId = 'KJV';
  String get translationId => _translationId;

  // Pre-loaded — always non-empty
  List<BibleTranslation> _translations = List.of(_builtinTranslations);
  List<BibleTranslation> get availableTranslations => _translations;

  List<BibleBook> _books = List.of(_builtinBooks);
  List<BibleBook> get books => _books;

  bool _loadingBooks = false;
  bool get loadingBooks => _loadingBooks;

  final Map<String, BibleChapter> _chapterCache = {};

  BibleService() { _init(); }

  // ── INIT ───────────────────────────────────────────────────────────────────

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    String saved = prefs.getString(_prefKey) ?? 'KJV';
    // Migrate stale IDs that were renamed in bolls.life
    const _idMigrations = <String, String>{
      'NASB1995': 'NASB',
      'CSB':      'CSB17',
      'HCSB':     'CSB17',
      'DARBY':    'YLT',   // no Darby on bolls.life — fall back to YLT
    };
    if (_idMigrations.containsKey(saved)) {
      saved = _idMigrations[saved]!;
      await prefs.setString(_prefKey, saved);
    }
    _translationId = saved;
    notifyListeners(); // show built-in data immediately

    // Restore cached book list if available (no network)
    final cached = prefs.getString('bolls_books_$_translationId');
    if (cached != null) _applyBooksJson(cached);

    // Refresh in background — won't block UI
    _bgFetchBooks();
    _bgFetchTranslations();
  }

  // ── TRANSLATION ────────────────────────────────────────────────────────────

  Future<void> setTranslation(String id) async {
    if (id == _translationId) return;
    _translationId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, id);
    _books = List.of(_builtinBooks); // reset to built-in while fetching
    _chapterCache.clear();
    notifyListeners();

    final cached = prefs.getString('bolls_books_$id');
    if (cached != null) _applyBooksJson(cached);
    _bgFetchBooks();
  }

  String get translationName {
    try { return _translations.firstWhere((t) => t.id == _translationId).name; }
    catch (_) { return _translationId; }
  }

  Future<List<BibleTranslation>> fetchTranslations() async {
    _bgFetchTranslations();
    return _translations; // returns immediately with built-in list
  }

  // ── BOOKS ──────────────────────────────────────────────────────────────────

  Future<List<BibleBook>> getBooks() => Future.value(_books);

  void _applyBooksJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final fetched = (decoded as List)
          .whereType<Map<String, dynamic>>()
          .map(BibleBook.fromJson)
          .where((b) => b.bookId >= 1 && b.bookId <= 66)
          .toList();
      if (fetched.length >= 60) { // only replace if we got a full book list
        _books = fetched;
        notifyListeners();
      }
    } catch (_) {}
  }

  void _bgFetchBooks() async {
    if (_loadingBooks) return;
    _loadingBooks = true;
    try {
      final res = await http
          .get(Uri.parse('$_apiBase/get-books/$_translationId/'))
          .timeout(_timeout);
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        _applyBooksJson(res.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('bolls_books_$_translationId', res.body);
      }
    } catch (e) {
      debugPrint('BibleService: books fetch failed — $e (built-in list in use)');
    }
    _loadingBooks = false;
  }

  void _bgFetchTranslations() async {
    try {
      final res = await http
          .get(Uri.parse('$_apiBase/static/bolls/app/views/languages.json'))
          .timeout(_timeout);
      if (res.statusCode != 200 || res.body.isEmpty) return;

      final decoded = jsonDecode(res.body);
      if (decoded is! List) return;

      final fetched = (decoded as List)
          .whereType<Map<String, dynamic>>()
          .map(BibleTranslation.fromJson)
          .where((t) => t.id.isNotEmpty)
          .toList();
      if (fetched.isEmpty) return;

      fetched.sort((a, b) {
        final ai = popularTranslationIds.indexOf(a.id);
        final bi = popularTranslationIds.indexOf(b.id);
        if (ai >= 0 && bi >= 0) return ai.compareTo(bi);
        if (ai >= 0) return -1;
        if (bi >= 0) return 1;
        return a.id.compareTo(b.id);
      });

      _translations = fetched;
      notifyListeners();
    } catch (e) {
      debugPrint('BibleService: translations fetch failed — $e (built-in list in use)');
    }
  }

  // ── CHAPTER ────────────────────────────────────────────────────────────────

  Future<BibleChapter?> getChapter(int bookId, int chapter) async {
    final key = '$_translationId/$bookId/$chapter';
    if (_chapterCache.containsKey(key)) return _chapterCache[key];

    try {
      final res = await http
          .get(Uri.parse('$_apiBase/get-text/$_translationId/$bookId/$chapter/'))
          .timeout(_timeout);
      if (res.statusCode != 200 || res.body.isEmpty) return null;

      final decoded = jsonDecode(res.body);
      if (decoded is! List || (decoded as List).isEmpty) return null;

      final bookName = _books
          .where((b) => b.bookId == bookId)
          .map((b) => b.name)
          .firstOrNull ?? 'Book $bookId';

      final verses = (decoded as List)
          .whereType<Map<String, dynamic>>()
          .map((m) => BibleVerse(
                number: (m['verse'] as num?)?.toInt() ?? 0,
                text:   _stripHtml((m['text'] as String?) ?? ''),
              ))
          .where((v) => v.number > 0 && v.text.isNotEmpty)
          .toList();

      if (verses.isEmpty) return null;

      final result = BibleChapter(
        translationId: _translationId,
        bookId:        bookId,
        bookName:      bookName,
        chapterNumber: chapter,
        verses:        verses,
      );
      _chapterCache[key] = result;
      return result;
    } catch (e) {
      debugPrint('BibleService: chapter $bookId:$chapter failed — $e');
      return null;
    }
  }

  // ── VERSE TEXT for ScriptureField ─────────────────────────────────────────

  Future<String?> fetchVerseText({
    required int bookId, required int chapter,
    required int verseStart, required int verseEnd,
    required String bookName,
  }) async {
    final ch = await getChapter(bookId, chapter);
    if (ch == null || ch.verses.isEmpty) return null;
    final verses = ch.verses.where((v) => v.number >= verseStart && v.number <= verseEnd).toList();
    if (verses.isEmpty) return null;
    final text = verses.length == 1
        ? verses.first.text
        : verses.map((v) => '[${v.number}] ${v.text}').join(' ');
    final ref = verseStart == verseEnd
        ? '$bookName $chapter:$verseStart'
        : '$bookName $chapter:$verseStart\u2013$verseEnd';
    return '"$text"\n\u2014 $ref ($_translationId)';
  }

  // ── SEARCH ─────────────────────────────────────────────────────────────────

  Future<List<VerseSearchResult>> searchVerses(String query, {int limit = 30}) async {
    if (query.trim().isEmpty) return [];
    try {
      final uri = Uri.parse(
        '$_apiBase/v2/find/$_translationId'
        '?search=${Uri.encodeComponent(query.trim())}'
        '&match_case=false&match_whole=false&limit=$limit&page=1',
      );
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200 || res.body.isEmpty) return [];
      final body    = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (body['results'] as List?) ?? [];
      return results.whereType<Map<String, dynamic>>().map((m) {
        final bId  = (m['book']    as num?)?.toInt() ?? 0;
        final ch   = (m['chapter'] as num?)?.toInt() ?? 0;
        final v    = (m['verse']   as num?)?.toInt() ?? 0;
        final name = _books.where((b) => b.bookId == bId).map((b) => b.name).firstOrNull ?? 'Book $bId';
        return VerseSearchResult(
          bookId: bId, bookName: name, chapter: ch, verse: v,
          text: _stripHtml((m['text'] as String?) ?? ''), reference: '$name $ch:$v',
        );
      }).toList();
    } catch (e) {
      debugPrint('BibleService: search failed — $e');
      return [];
    }
  }

  // ── HTML STRIP (pure Dart, zero external packages) ────────────────────────

  static String _stripHtml(String input) => input
      .replaceAll(RegExp(r'<sup[^>]*>.*?</sup>', dotAll: true, caseSensitive: false), '')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;',  ' ')
      .replaceAll('&#160;',  ' ')
      .replaceAll('&amp;',   '&')
      .replaceAll('&lt;',    '<')
      .replaceAll('&gt;',    '>')
      .replaceAll('&quot;',  '"')
      .replaceAll('&#39;',   "'")
      .replaceAll('&apos;',  "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}