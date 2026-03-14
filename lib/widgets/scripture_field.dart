// lib/widgets/scripture_field.dart
//
// Drop-in replacement for TextFormField that detects Bible verse references
// as the user types and offers a one-tap button to fetch + insert verse text.
// Works in Notes, Website Builder, and Presentation Studio.
//
// Now powered by bolls.life API (integer book IDs 1–66).
//
// SPELL CHECK: wraps the input in SpellCheckField so red squiggly underlines
// appear under misspelled words on all platforms.  Requires:
//   • lib/services/spell_check_service.dart  (already present)
//   • lib/widgets/spell_check_field.dart     (already present)
//   • assets/dictionary/en_US.txt            (download once — see spell_check_service.dart)
//   • pubspec.yaml assets section must include:  - assets/dictionary/

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/bible_service.dart';
import '../theme.dart';
import 'spell_check_field.dart';   // ← NEW

// ── REFERENCE PARSER ──────────────────────────────────────────────────────────

class VerseRef {
  final String raw;         // original matched text, e.g. "John 3:16-18"
  final int    bookId;      // bolls.life integer book ID (1–66)
  final String bookName;    // human readable
  final int    chapter;
  final int    verseStart;
  final int    verseEnd;

  const VerseRef({
    required this.raw,
    required this.bookId,
    required this.bookName,
    required this.chapter,
    required this.verseStart,
    required this.verseEnd,
  });
}

// Maps common names + abbreviations → bolls.life integer book ID (1–66)
const _bookAliases = <String, int>{
  // Old Testament
  'genesis': 1,   'gen': 1,
  'exodus': 2,    'exo': 2,   'ex': 2,
  'leviticus': 3, 'lev': 3,
  'numbers': 4,   'num': 4,
  'deuteronomy': 5,'deut': 5, 'deu': 5,
  'joshua': 6,    'josh': 6,  'jos': 6,
  'judges': 7,    'judg': 7,
  'ruth': 8,
  '1 samuel': 9,  '1sam': 9,  '1sa': 9,
  '2 samuel': 10, '2sam': 10, '2sa': 10,
  '1 kings': 11,  '1ki': 11,
  '2 kings': 12,  '2ki': 12,
  '1 chronicles': 13, '1chr': 13, '1ch': 13,
  '2 chronicles': 14, '2chr': 14, '2ch': 14,
  'ezra': 15,
  'nehemiah': 16, 'neh': 16,
  'esther': 17,   'est': 17,
  'job': 18,
  'psalm': 19,    'psalms': 19,'ps': 19, 'psa': 19,
  'proverbs': 20, 'prov': 20, 'pro': 20,
  'ecclesiastes': 21, 'eccl': 21, 'ecc': 21,
  'song of solomon': 22, 'song': 22, 'sos': 22, 'sng': 22,
  'isaiah': 23,   'isa': 23,
  'jeremiah': 24, 'jer': 24,
  'lamentations': 25, 'lam': 25,
  'ezekiel': 26,  'ezek': 26, 'ezk': 26,
  'daniel': 27,   'dan': 27,
  'hosea': 28,    'hos': 28,
  'joel': 29,
  'amos': 30,
  'obadiah': 31,  'oba': 31,
  'jonah': 32,    'jon': 32,
  'micah': 33,    'mic': 33,
  'nahum': 34,    'nah': 34,
  'habakkuk': 35, 'hab': 35,
  'zephaniah': 36,'zep': 36,
  'haggai': 37,   'hag': 37,
  'zechariah': 38,'zech': 38, 'zec': 38,
  'malachi': 39,  'mal': 39,
  // New Testament
  'matthew': 40,  'matt': 40, 'mat': 40,
  'mark': 41,     'mrk': 41,
  'luke': 42,     'luk': 42,
  'john': 43,     'jhn': 43,
  'acts': 44,     'act': 44,
  'romans': 45,   'rom': 45,
  '1 corinthians': 46, '1cor': 46, '1co': 46,
  '2 corinthians': 47, '2cor': 47, '2co': 47,
  'galatians': 48,'gal': 48,
  'ephesians': 49,'eph': 49,
  'philippians': 50,'phil': 50,'php': 50,
  'colossians': 51,'col': 51,
  '1 thessalonians': 52,'1thess': 52,'1th': 52,
  '2 thessalonians': 53,'2thess': 53,'2th': 53,
  '1 timothy': 54,'1tim': 54, '1ti': 54,
  '2 timothy': 55,'2tim': 55, '2ti': 55,
  'titus': 56,    'tit': 56,
  'philemon': 57, 'phlm': 57, 'phm': 57,
  'hebrews': 58,  'heb': 58,
  'james': 59,    'jas': 59,
  '1 peter': 60,  '1pet': 60, '1pe': 60,
  '2 peter': 61,  '2pet': 61, '2pe': 61,
  '1 john': 62,   '1jn': 62,
  '2 john': 63,   '2jn': 63,
  '3 john': 64,   '3jn': 64,
  'jude': 65,
  'revelation': 66,'rev': 66,
};

// Human-readable book names indexed by bolls.life ID
const _bookNames = <int, String>{
  1:'Genesis',2:'Exodus',3:'Leviticus',4:'Numbers',5:'Deuteronomy',
  6:'Joshua',7:'Judges',8:'Ruth',9:'1 Samuel',10:'2 Samuel',
  11:'1 Kings',12:'2 Kings',13:'1 Chronicles',14:'2 Chronicles',
  15:'Ezra',16:'Nehemiah',17:'Esther',18:'Job',19:'Psalms',
  20:'Proverbs',21:'Ecclesiastes',22:'Song of Solomon',23:'Isaiah',
  24:'Jeremiah',25:'Lamentations',26:'Ezekiel',27:'Daniel',
  28:'Hosea',29:'Joel',30:'Amos',31:'Obadiah',32:'Jonah',
  33:'Micah',34:'Nahum',35:'Habakkuk',36:'Zephaniah',37:'Haggai',
  38:'Zechariah',39:'Malachi',
  40:'Matthew',41:'Mark',42:'Luke',43:'John',44:'Acts',
  45:'Romans',46:'1 Corinthians',47:'2 Corinthians',48:'Galatians',
  49:'Ephesians',50:'Philippians',51:'Colossians',52:'1 Thessalonians',
  53:'2 Thessalonians',54:'1 Timothy',55:'2 Timothy',56:'Titus',
  57:'Philemon',58:'Hebrews',59:'James',60:'1 Peter',61:'2 Peter',
  62:'1 John',63:'2 John',64:'3 John',65:'Jude',66:'Revelation',
};

/// Finds the last verse reference in [text]. Returns null if none found.
VerseRef? detectVerseRef(String text) {
  final re = RegExp(
    r'((?:[123]\s)?[A-Za-z]+(?:\s[A-Za-z]+)*)\s+(\d+)(?::(\d+)(?:-(\d+))?)?',
    caseSensitive: false,
  );

  VerseRef? last;
  for (final m in re.allMatches(text)) {
    final rawBook = m.group(1)!.trim().toLowerCase();
    final bookId  = _bookAliases[rawBook];
    if (bookId == null) continue;

    final chapter    = int.parse(m.group(2)!);
    final verseStart = int.tryParse(m.group(3) ?? '') ?? 1;
    final verseEnd   = int.tryParse(m.group(4) ?? '') ?? verseStart;

    last = VerseRef(
      raw:        m.group(0)!,
      bookId:     bookId,
      bookName:   _bookNames[bookId] ?? rawBook,
      chapter:    chapter,
      verseStart: verseStart,
      verseEnd:   verseEnd,
    );
  }
  return last;
}

// ── SCRIPTURE FIELD ───────────────────────────────────────────────────────────

class ScriptureField extends StatefulWidget {
  final TextEditingController      controller;
  final BibleService               bibleService;
  final Color                      primary;
  final Color?                     secondary;
  final String?                    label;
  final String?                    hint;
  final int                        maxLines;
  final bool                       expands;
  final TextStyle?                 style;
  final InputDecoration?           decoration;
  final ValueChanged<String>?      onChanged;
  final TextInputType?             keyboardType;
  final String? Function(String?)? validator;

  const ScriptureField({
    super.key,
    required this.controller,
    required this.bibleService,
    required this.primary,
    this.secondary,
    this.label,
    this.hint,
    this.maxLines  = 1,
    this.expands   = false,
    this.style,
    this.decoration,
    this.onChanged,
    this.keyboardType,
    this.validator,
  });

  @override
  State<ScriptureField> createState() => _ScriptureFieldState();
}

class _ScriptureFieldState extends State<ScriptureField> {
  VerseRef? _detected;
  bool      _fetching   = false;
  String?   _fetchError;
  Timer?    _debounce;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _debounce?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      final ref = detectVerseRef(widget.controller.text);
      if (mounted) {
        setState(() { _detected = ref; _fetchError = null; });
      }
    });
    widget.onChanged?.call(widget.controller.text);
  }

  Future<void> _importVerse() async {
    final ref = _detected;
    if (ref == null) return;
    setState(() { _fetching = true; _fetchError = null; });

    try {
      final inserted = await widget.bibleService.fetchVerseText(
        bookId:     ref.bookId,
        chapter:    ref.chapter,
        verseStart: ref.verseStart,
        verseEnd:   ref.verseEnd,
        bookName:   ref.bookName,
      );

      if (inserted == null) {
        setState(() {
          _fetching   = false;
          _fetchError = 'Could not load ${ref.raw}';
        });
        return;
      }

      final current  = widget.controller.text;
      final matchIdx = current.toLowerCase()
          .lastIndexOf(ref.raw.toLowerCase());
      final String next;
      if (matchIdx == -1) {
        next = '$current\n$inserted';
      } else {
        final after = matchIdx + ref.raw.length;
        next = '${current.substring(0, after)}\n$inserted${current.substring(after)}';
      }

      widget.controller.value = TextEditingValue(
        text:      next,
        selection: TextSelection.collapsed(offset: next.length),
      );
      widget.onChanged?.call(next);
      setState(() { _fetching = false; _detected = null; });
    } catch (e) {
      setState(() {
        _fetching   = false;
        _fetchError = 'Network error — check connection';
      });
    }
  }

  void _dismiss() => setState(() { _detected = null; _fetchError = null; });

  @override
  Widget build(BuildContext context) {
    final primary        = widget.primary;
    final baseDecoration = widget.decoration ??
        InputDecoration(labelText: widget.label, hintText: widget.hint);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── CHANGED: was TextFormField, now SpellCheckField ─────────────────
        SpellCheckField(
          controller:   widget.controller,
          maxLines:     widget.expands ? null : widget.maxLines,
          expands:      widget.expands,
          style:        widget.style,
          keyboardType: widget.keyboardType,
          validator:    widget.validator,
          decoration:   baseDecoration,
          // onChanged is not forwarded here because ScriptureField owns the
          // listener via widget.controller.addListener(_onTextChanged) above.
          // SpellCheckField forwards its own internal onChanged, but since
          // both widgets share the same controller instance the listener
          // chain fires correctly without double-calling.
        ),
        if (_detected != null || _fetchError != null)
          _ScriptureBanner(
            ref:           _detected,
            error:         _fetchError,
            fetching:      _fetching,
            primary:       primary,
            translationId: widget.bibleService.translationId,
            onImport:      _importVerse,
            onDismiss:     _dismiss,
          ),
      ],
    );
  }
}

// ── BANNER ────────────────────────────────────────────────────────────────────

class _ScriptureBanner extends StatelessWidget {
  final VerseRef?    ref;
  final String?      error;
  final bool         fetching;
  final Color        primary;
  final String       translationId;
  final VoidCallback onImport;
  final VoidCallback onDismiss;

  const _ScriptureBanner({
    required this.ref, required this.error, required this.fetching,
    required this.primary, required this.translationId,
    required this.onImport, required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isError = error != null;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isError
              ? Colors.red.shade50
              : Color.lerp(primary, Colors.white, 0.91),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isError
                ? Colors.red.shade200
                : primary.withValues(alpha: 0.3),
          ),
        ),
        child: isError
            ? Row(children: [
                Icon(Icons.error_outline, size: 16, color: Colors.red.shade600),
                const SizedBox(width: 8),
                Expanded(child: Text(error!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12))),
                GestureDetector(onTap: onDismiss,
                    child: Icon(Icons.close, size: 16, color: Colors.red.shade400)),
              ])
            : Row(children: [
                Icon(Icons.menu_book_outlined, size: 16, color: primary),
                const SizedBox(width: 8),
                Expanded(child: RichText(text: TextSpan(children: [
                  TextSpan(text: ref!.raw,
                      style: TextStyle(color: primary,
                          fontWeight: FontWeight.bold, fontSize: 12)),
                  TextSpan(text: '  ·  $translationId',
                      style: TextStyle(color: primary.withValues(alpha: 0.6),
                          fontSize: 11)),
                ]))),
                const SizedBox(width: 8),
                fetching
                    ? SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: primary))
                    : GestureDetector(
                        onTap: onImport,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: primary,
                              borderRadius: BorderRadius.circular(6)),
                          child: Text('Insert verse',
                              style: TextStyle(color: contrastOn(primary),
                                  fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                const SizedBox(width: 6),
                GestureDetector(onTap: onDismiss,
                    child: Icon(Icons.close, size: 15,
                        color: primary.withValues(alpha: 0.5))),
              ]),
      ),
    );
  }
}