// lib/services/spell_check_service.dart
//
// Offline spell-check service backed by a bundled word-list asset.
//
// SETUP (one-time):
//   1. Download the word list (~2 MB):
//      https://raw.githubusercontent.com/dwyl/english-words/master/words_alpha.txt
//   2. Save it to:  assets/dictionary/en_US.txt
//   3. pubspec.yaml already declares it (see assets section).
//
// USAGE:
//   final svc = SpellCheckService();
//   await svc.ensureLoaded();                    // call once, e.g. in initState
//   final ranges = svc.misspelledRanges(text);  // returns TextRange list

import 'package:flutter/services.dart' show rootBundle;

class SpellCheckService {
  // Singleton so the dictionary is only loaded once across the whole app.
  static final SpellCheckService _instance = SpellCheckService._internal();
  factory SpellCheckService() => _instance;
  SpellCheckService._internal();

  Set<String> _dictionary = {};
  bool _loaded = false;
  bool _loading = false;

  // ── Words that should never be flagged ───────────────────────────────────
  // Common proper nouns, abbreviations, and church-specific terms.
  static const _whitelist = <String>{
    // Church / ministry
    'amen', 'hallelujah', 'alleluia', 'scripture', 'scriptures',
    'pastor', 'deacon', 'deacons', 'sermon', 'sermons', 'liturgy',
    'baptism', 'communion', 'eucharist', 'tithe', 'tithes', 'tithing',
    'congregant', 'congregants', 'doxology', 'benediction',
    // Common abbreviations
    'jr', 'sr', 'dr', 'mr', 'mrs', 'ms', 'rev', 'st', 'ave', 'blvd',
    // Days / months (already in most dictionaries but just in case)
    'jan','feb','mar','apr','jun','jul','aug','sep','sept','oct','nov','dec',
    'mon','tue','wed','thu','fri','sat','sun',
  };

  // ── Load ─────────────────────────────────────────────────────────────────

  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final raw = await rootBundle.loadString(
          'assets/dictionary/en_US.txt');
      _dictionary = raw
          .split('\n')
          .map((w) => w.trim().toLowerCase())
          .where((w) => w.isNotEmpty)
          .toSet();
      _dictionary.addAll(_whitelist);
      _loaded = true;
    } catch (_) {
      // Asset missing — fail silently; spell check just won't underline.
      _loaded = true;
    }
    _loading = false;
  }

  bool get isReady => _loaded;

  // ── Core check ───────────────────────────────────────────────────────────

  /// Returns a [TextRange] for every misspelled word in [text].
  List<TextRange> misspelledRanges(String text) {
    if (!_loaded || _dictionary.isEmpty) return [];
    final ranges = <TextRange>[];
    // Walk through every token that looks like a word.
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
    // Direct hit
    if (_dictionary.contains(lower)) return true;
    // Strip trailing apostrophe-s  ("church's" → "church")
    if (lower.endsWith("'s") &&
        _dictionary.contains(lower.substring(0, lower.length - 2))) {
      return true;
    }
    // Strip possessive s  ("pastors" already in dict usually, but just in case)
    // Numbers and single letters are always fine
    if (word.length == 1) return true;
    if (RegExp(r'^\d').hasMatch(word)) return true;
    // ALL-CAPS words are treated as acronyms — skip
    if (word == word.toUpperCase()) return true;
    // Capitalised word — check lowercase version (handles sentence-start caps)
    final decap = lower;
    if (_dictionary.contains(decap)) return true;

    return false;
  }
}