// lib/services/bible_service.dart
//
// Bible data powered by bolls.life — free, no API key, includes:
// KJV, NKJV, ESV, NASB1995, NIV, NLT, CSB, BSB, ASV, YLT, WEB and 100+ more.
//
// API reference: https://bolls.life/api/
//   GET  https://bolls.life/static/bolls/app/views/languages.json   → translation list
//   GET  https://bolls.life/get-books/{translation}/                → books
//   GET  https://bolls.life/get-text/{translation}/{bookId}/{ch}/   → verses
//   GET  https://bolls.life/v2/find/{translation}?search=…          → search

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── MODELS ────────────────────────────────────────────────────────────────────

class BibleTranslation {
  final String id;          // e.g. "KJV", "NASB1995"
  final String name;        // full name
  final String shortName;   // abbreviation shown in UI
  final String language;
  final String languageEnglishName;
  final int    numberOfBooks;

  const BibleTranslation({
    required this.id,
    required this.name,
    required this.shortName,
    required this.language,
    required this.languageEnglishName,
    required this.numberOfBooks,
  });

  // bolls.life returns: { short_name, full_name, language, ... }
  factory BibleTranslation.fromBollsJson(Map<String, dynamic> j) =>
      BibleTranslation(
        id:                  j['short_name'] ?? '',
        shortName:           j['short_name'] ?? '',
        name:                j['full_name']  ?? j['short_name'] ?? '',
        language:            j['language']   ?? 'en',
        languageEnglishName: j['language']   ?? 'English',
        numberOfBooks:       66,
      );

  @override
  String toString() => '$shortName – $name';
}

class BibleBook {
  final int    bookId;      // bolls.life uses integer IDs 1–66 (+ apocrypha)
  final String name;
  final int    chapters;
  final bool   isOT;

  const BibleBook({
    required this.bookId,
    required this.name,
    required this.chapters,
    required this.isOT,
  });

  String get id => bookId.toString();

  // bolls.life: { bookid, name, chapters }
  factory BibleBook.fromBollsJson(Map<String, dynamic> j) {
    final id = j['bookid'] as int? ?? 0;
    return BibleBook(
      bookId:   id,
      name:     j['name'] ?? '',
      chapters: j['chapters'] as int? ?? 1,
      isOT:     id >= 1 && id <= 39,
    );
  }
}

class BibleVerse {
  final int    number;
  final String text;
  const BibleVerse({required this.number, required this.text});
}

class BibleChapter {
  final String        translationId;
  final int           bookId;
  final String        bookName;
  final int           chapterNumber;
  final List<BibleVerse> verses;

  const BibleChapter({
    required this.translationId,
    required this.bookId,
    required this.bookName,
    required this.chapterNumber,
    required this.verses,
  });
}

class VerseSearchResult {
  final String bookName;
  final int    bookId;
  final int    chapter;
  final int    verse;
  final String text;
  final String reference;

  const VerseSearchResult({
    required this.bookName,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.text,
    required this.reference,
  });
}

// ── POPULAR TRANSLATIONS (shown first in picker) ──────────────────────────────

const popularTranslationIds = <String>[
  'KJV',       // King James Version
  'NKJV',      // New King James Version
  'ESV',        // English Standard Version
  'NASB1995',  // New American Standard Bible 1995
  'NIV',        // New International Version (if available)
  'NLT',        // New Living Translation
  'CSB',        // Christian Standard Bible
  'BSB',        // Berean Standard Bible (fully free)
  'ASV',        // American Standard Version
  'WEB',        // World English Bible
  'YLT',        // Young's Literal Translation
  'DARBY',     // Darby Translation
];

// ── SERVICE ───────────────────────────────────────────────────────────────────

class BibleService extends ChangeNotifier {
  static const _base         = 'https://bolls.life';
  static const _prefKey      = 'bible_translation_id';
  static const _booksCache   = 'bible_books_cache_v2_';

  String _translationId = 'KJV';
  String get translationId => _translationId;

  List<BibleTranslation> _availableTranslations = [];
  List<BibleTranslation> get availableTranslations => _availableTranslations;

  List<BibleBook> _books = [];
  List<BibleBook> get books => _books;

  bool _loadingBooks = false;
  bool get loadingBooks => _loadingBooks;

  // In-memory chapter cache: "KJV/1/1" → BibleChapter
  final Map<String, BibleChapter> _chapterCache = {};

  BibleService() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _translationId = prefs.getString(_prefKey) ?? 'KJV';
    await _loadBooks();
  }

  // ── TRANSLATION ────────────────────────────────────────────────────────────

  Future<void> setTranslation(String id) async {
    if (id == _translationId) return;
    _translationId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, id);
    _books = [];
    _chapterCache.clear();
    notifyListeners();
    await _loadBooks();
  }

  String get translationName {
    try {
      return _availableTranslations
          .firstWhere((t) => t.id == _translationId)
          .name;
    } catch (_) {
      return _translationId;
    }
  }

  // ── TRANSLATIONS LIST ──────────────────────────────────────────────────────

  Future<List<BibleTranslation>> fetchTranslations() async {
    if (_availableTranslations.isNotEmpty) return _availableTranslations;
    try {
      final res = await http
          .get(Uri.parse(
              '$_base/static/bolls/app/views/languages.json'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        _availableTranslations = list
            .map((j) => BibleTranslation.fromBollsJson(j as Map<String, dynamic>))
            .where((t) => t.id.isNotEmpty)
            .toList();
        // Sort: popular first, then alphabetically
        _availableTranslations.sort((a, b) {
          final aIdx = popularTranslationIds.indexOf(a.id);
          final bIdx = popularTranslationIds.indexOf(b.id);
          if (aIdx >= 0 && bIdx >= 0) return aIdx.compareTo(bIdx);
          if (aIdx >= 0) return -1;
          if (bIdx >= 0) return 1;
          return a.id.compareTo(b.id);
        });
        notifyListeners();
      }
    } catch (e) {
      debugPrint('BibleService: failed to load translations – $e');
    }
    return _availableTranslations;
  }

  // ── BOOKS ──────────────────────────────────────────────────────────────────

  Future<void> _loadBooks() async {
    // Try cache first
    final prefs   = await SharedPreferences.getInstance();
    final cacheKey = '$_booksCache$_translationId';
    final cached  = prefs.getString(cacheKey);
    if (cached != null) {
      try {
        final list = jsonDecode(cached) as List;
        _books = list
            .map((j) => BibleBook.fromBollsJson(j as Map<String, dynamic>))
            .toList();
        notifyListeners();
        return;
      } catch (_) {}
    }

    _loadingBooks = true;
    notifyListeners();

    try {
      final res = await http
          .get(Uri.parse('$_base/get-books/$_translationId/'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        _books = list
            .map((j) => BibleBook.fromBollsJson(j as Map<String, dynamic>))
            .toList();
        await prefs.setString(cacheKey, res.body);
      }
    } catch (e) {
      debugPrint('BibleService: failed to load books – $e');
    }

    _loadingBooks = false;
    notifyListeners();
  }

  Future<List<BibleBook>> getBooks() async {
    if (_books.isEmpty) await _loadBooks();
    return _books;
  }

  // ── CHAPTER ────────────────────────────────────────────────────────────────

  Future<BibleChapter?> getChapter(int bookId, int chapter) async {
    final key = '$_translationId/$bookId/$chapter';
    if (_chapterCache.containsKey(key)) return _chapterCache[key];

    try {
      final res = await http
          .get(Uri.parse('$_base/get-text/$_translationId/$bookId/$chapter/'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;

      final list = jsonDecode(res.body) as List;
      final bookName = _books.firstWhere(
        (b) => b.bookId == bookId,
        orElse: () => BibleBook(
            bookId: bookId, name: 'Book $bookId',
            chapters: 1, isOT: bookId <= 39),
      ).name;

      final verses = list.map((j) {
        // bolls.life returns HTML in `text` — strip tags for plain text
        final raw = (j['text'] as String? ?? '');
        return BibleVerse(
          number: j['verse'] as int? ?? 0,
          text:   _stripHtml(raw),
        );
      }).where((v) => v.text.isNotEmpty).toList();

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
      debugPrint('BibleService: failed to load $bookId:$chapter – $e');
      return null;
    }
  }

  // ── VERSE RANGE FETCH (for ScriptureField & note import) ──────────────────

  /// Returns formatted verse text: "[v] text ... — Ref (TRANS)"
  Future<String?> fetchVerseText({
    required int    bookId,
    required int    chapter,
    required int    verseStart,
    required int    verseEnd,
    required String bookName,
  }) async {
    final ch = await getChapter(bookId, chapter);
    if (ch == null) return null;

    final verses = ch.verses
        .where((v) => v.number >= verseStart && v.number <= verseEnd)
        .toList();
    if (verses.isEmpty) return null;

    final text = verses.length == 1
        ? verses.first.text
        : verses.map((v) => '[${v.number}] ${v.text}').join(' ');

    final ref = verseStart == verseEnd
        ? '$bookName $chapter:$verseStart'
        : '$bookName $chapter:$verseStart–$verseEnd';

    return '"$text"\n— $ref ($_translationId)';
  }

  // ── SEARCH ─────────────────────────────────────────────────────────────────

  Future<List<VerseSearchResult>> searchVerses(String query,
      {int limit = 30}) async {
    if (query.trim().isEmpty) return [];
    try {
      final uri = Uri.parse(
          '$_base/v2/find/$_translationId'
          '?search=${Uri.encodeComponent(query)}'
          '&match_case=false&match_whole=false&limit=$limit&page=1');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final results = body['results'] as List? ?? [];

      return results.map((j) {
        final bookId  = j['book'] as int? ?? 0;
        final bookName = _books.firstWhere(
          (b) => b.bookId == bookId,
          orElse: () => BibleBook(
              bookId: bookId, name: 'Book $bookId',
              chapters: 1, isOT: bookId <= 39),
        ).name;
        final ch = j['chapter'] as int? ?? 0;
        final v  = j['verse']   as int? ?? 0;
        return VerseSearchResult(
          bookId:    bookId,
          bookName:  bookName,
          chapter:   ch,
          verse:     v,
          text:      _stripHtml(j['text'] as String? ?? ''),
          reference: '$bookName $ch:$v',
        );
      }).toList();
    } catch (e) {
      debugPrint('BibleService: search failed – $e');
      return [];
    }
  }

  // ── UTIL ───────────────────────────────────────────────────────────────────

  static String _stripHtml(String html) {
    try {
      return html_parser.parse(html).documentElement?.text ?? html;
    } catch (_) {
      // Fallback: simple regex strip
      return html
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .trim();
    }
  }
}