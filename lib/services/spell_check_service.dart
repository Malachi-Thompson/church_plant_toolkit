// lib/services/spell_check_service.dart
//
// Offline spell-check service backed by a bundled word-list asset.
//
// SETUP (one-time):
//   1. Download the word list (~2 MB):
//      https://raw.githubusercontent.com/dwyl/english-words/master/words_alpha.txt
//   2. Save it to:  assets/dictionary/en_US.txt
//   3. pubspec.yaml must declare it under assets:
//        - assets/dictionary/
//
// USAGE:
//   final svc = SpellCheckService();
//   await svc.ensureLoaded();
//   final ranges      = svc.misspelledRanges(text);
//   final suggestions = svc.suggestions('teh');   // → ['the', 'ten', ...]

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

class SpellCheckService {
  // Singleton — dictionary loaded once for the whole app.
  static final SpellCheckService _instance = SpellCheckService._internal();
  factory SpellCheckService() => _instance;
  SpellCheckService._internal();

  Set<String>  _dictionary = {};
  final Set<String> _ignored = {};   // session-level ignore list
  bool _loaded  = false;
  bool _loading = false;

  // ── Whitelist ─────────────────────────────────────────────────────────────
  static const _whitelist = <String>{
    'amen', 'hallelujah', 'alleluia', 'scripture', 'scriptures',
    'pastor', 'deacon', 'deacons', 'sermon', 'sermons', 'liturgy',
    'baptism', 'communion', 'eucharist', 'tithe', 'tithes', 'tithing',
    'congregant', 'congregants', 'doxology', 'benediction',
    'jr', 'sr', 'dr', 'mr', 'mrs', 'ms', 'rev', 'st', 'ave', 'blvd',
    'jan','feb','mar','apr','jun','jul','aug','sep','sept','oct','nov','dec',
    'mon','tue','wed','thu','fri','sat','sun',
  };

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final raw = await rootBundle.loadString('assets/dictionary/en_US.txt');
      _dictionary = raw
          .split('\n')
          .map((w) => w.trim().toLowerCase())
          .where((w) => w.isNotEmpty)
          .toSet();
      _dictionary.addAll(_whitelist);
      _loaded = true;
    } catch (_) {
      _loaded = true;   // fail silently — squiggles just won't appear
    }
    _loading = false;
  }

  bool get isReady => _loaded;

  /// Adds [word] to a session-level ignore list so it is no longer underlined.
  /// The ignore list resets when the app restarts.
  void addIgnored(String word) => _ignored.add(word.toLowerCase());

  // ── Misspelled ranges ─────────────────────────────────────────────────────

  /// Returns a [TextRange] for every misspelled word in [text].
  List<TextRange> misspelledRanges(String text) {
    if (!_loaded || _dictionary.isEmpty) return [];
    final ranges = <TextRange>[];
    final re = RegExp(r"[A-Za-z][A-Za-z'\-]*[A-Za-z]|[A-Za-z]");
    for (final m in re.allMatches(text)) {
      final word = m.group(0)!;
      if (!_isCorrect(word)) {
        ranges.add(TextRange(start: m.start, end: m.end));
      }
    }
    return ranges;
  }

  bool _isCorrect(String word) {
    final lower = word.toLowerCase();
    if (_ignored.contains(lower)) return true;
    if (_dictionary.contains(lower)) return true;
    if (lower.endsWith("'s") &&
        _dictionary.contains(lower.substring(0, lower.length - 2))) return true;
    if (word.length == 1) return true;
    if (RegExp(r'^\d').hasMatch(word)) return true;
    if (word == word.toUpperCase()) return true;     // acronym
    return false;
  }

  // ── Suggestions ───────────────────────────────────────────────────────────

  /// Returns up to [maxResults] spelling suggestions for [word].
  ///
  /// Strategy (fast, no external package needed):
  ///   1. Collect every dictionary word within edit-distance 1 (deletes,
  ///      transposes, replaces, inserts).  These are the highest-quality hits.
  ///   2. If fewer than [maxResults] found, expand to edit-distance 2 by
  ///      applying edit-distance-1 to each edit-distance-1 result and
  ///      keeping only real words.
  ///   3. Sort by length-difference so the most similar words appear first.
  List<String> suggestions(String word, {int maxResults = 6}) {
    if (!_loaded || _dictionary.isEmpty) return [];
    final lower = word.toLowerCase();
    if (_dictionary.contains(lower)) return [];

    final seen   = <String>{lower};
    final result = <String>[];

    // Edit distance 1
    for (final candidate in _edits1(lower)) {
      if (_dictionary.contains(candidate) && seen.add(candidate)) {
        result.add(candidate);
        if (result.length >= maxResults) break;
      }
    }

    // Edit distance 2 — only if we still need more
    if (result.length < maxResults) {
      for (final e1 in _edits1(lower)) {
        for (final candidate in _edits1(e1)) {
          if (_dictionary.contains(candidate) && seen.add(candidate)) {
            result.add(candidate);
            if (result.length >= maxResults) break;
          }
        }
        if (result.length >= maxResults) break;
      }
    }

    // Sort: words closest in length to the input first
    result.sort((a, b) =>
        (a.length - lower.length).abs()
            .compareTo((b.length - lower.length).abs()));

    return result.take(maxResults).toList();
  }

  /// Generates all strings within edit-distance 1 of [word].
  Iterable<String> _edits1(String word) sync* {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz';
    final n = word.length;

    for (int i = 0; i <= n; i++) {
      final head = word.substring(0, i);
      final tail = word.substring(i);

      // Delete character at position i
      if (tail.isNotEmpty) yield '$head${tail.substring(1)}';

      // Transpose adjacent characters
      if (tail.length > 1) {
        yield '$head${tail[1]}${tail[0]}${tail.substring(2)}';
      }

      // Replace character at position i
      if (tail.isNotEmpty) {
        for (final c in alphabet.split('')) {
          if (c != tail[0]) yield '$head$c${tail.substring(1)}';
        }
      }

      // Insert character at position i
      for (final c in alphabet.split('')) {
        yield '$head$c$tail';
      }
    }
  }
}