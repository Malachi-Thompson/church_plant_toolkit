// lib/apps/notes/dialogs/verse_import_dialog.dart
//
// Dialog for searching and importing a Bible verse into a note.
// Supports direct reference lookups ("John 3:16") and keyword search.

import 'package:flutter/material.dart';
import '../../../services/bible_service.dart';
import '../../../theme.dart';

// Matches references like "John 3:16", "1 Cor 13:4-7", "Ps 23", "Gen 1:1–3"
final _refPattern = RegExp(
  r'^(\d?\s?[A-Za-z]+(?:\s[A-Za-z]+)?)\s+(\d+)(?:[:\.](\d+)(?:[–\-](\d+))?)?$',
  caseSensitive: false,
);

class VerseImportDialog extends StatefulWidget {
  final BibleService bibleService;
  final Color        primary;
  final String       translationId; // the note's own translation

  const VerseImportDialog({
    super.key,
    required this.bibleService,
    required this.primary,
    required this.translationId,
  });

  @override
  State<VerseImportDialog> createState() => _VerseImportDialogState();
}

class _VerseImportDialogState extends State<VerseImportDialog> {
  final _searchCtrl = TextEditingController();
  List<VerseSearchResult> _results  = [];
  bool   _loading  = false;
  bool   _searched = false;
  String _error    = '';

  BibleService get _svc => widget.bibleService;

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  // Temporarily swap the service translation, run action, restore
  Future<T> _withTranslation<T>(Future<T> Function() action) async {
    final original = _svc.translationId;
    final needSwap = widget.translationId != original;
    if (needSwap) await _svc.setTranslation(widget.translationId);
    try {
      return await action();
    } finally {
      if (needSwap) await _svc.setTranslation(original);
    }
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true; _error = ''; _results = []; _searched = true;
    });

    try {
      // 1. Try to parse as a scripture reference first
      final match = _refPattern.firstMatch(q);
      if (match != null) {
        final bookQuery = match.group(1)!.trim();
        final chapter   = int.parse(match.group(2)!);
        final vStart    = int.tryParse(match.group(3) ?? '') ?? 1;
        final vEnd      = int.tryParse(match.group(4) ?? '') ?? vStart;

        final book = _svc.books.where((b) =>
            b.name.toLowerCase().startsWith(bookQuery.toLowerCase()) ||
            bookQuery.toLowerCase().startsWith(
                b.name.toLowerCase().split(' ').last.toLowerCase())
        ).firstOrNull;

        if (book != null) {
          final ch = await _withTranslation(
              () => _svc.getChapter(book.bookId, chapter));
          if (ch != null) {
            final verses = ch.verses
                .where((v) => v.number >= vStart && v.number <= vEnd)
                .toList();
            if (verses.isNotEmpty) {
              setState(() {
                _results = verses.map((v) => VerseSearchResult(
                  bookId:    book.bookId,
                  bookName:  book.name,
                  chapter:   chapter,
                  verse:     v.number,
                  text:      v.text,
                  reference: '${book.name} $chapter:${v.number}',
                )).toList();
                _loading = false;
              });
              return;
            }
          }
        }
      }

      // 2. Fall back to keyword search
      final res = await _withTranslation(
          () => _svc.searchVerses(q, limit: 25));
      setState(() { _results = res; _loading = false; });

    } catch (e) {
      setState(() { _loading = false; _error = 'Search failed: $e'; });
    }
  }

  void _selectResult(VerseSearchResult r) {
    final ref = r.verse == 0
        ? '${r.bookName} ${r.chapter}'
        : '${r.bookName} ${r.chapter}:${r.verse}';
    final output = '"${r.text}"\n— $ref (${widget.translationId})';
    Navigator.pop(context, output);
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              Icon(Icons.menu_book_outlined, color: primary),
              const SizedBox(width: 8),
              Text('Import Verse',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: primary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(widget.translationId,
                    style: TextStyle(
                        fontSize: 11,
                        color: primary,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ]),
          ),
          // ── Search bar ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              Expanded(child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: 'e.g. "John 3:16" or "love"',
                  prefixIcon: Icon(Icons.search, color: primary, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: primary)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: primary, width: 2)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              )),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _loading ? null : _search,
                style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: contrastOn(primary),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12)),
                child: const Text('Search'),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          // ── Body ──────────────────────────────────────────────────────────
          Flexible(child: _buildBody(primary)),
        ]),
      ),
    );
  }

  Widget _buildBody(Color primary) {
    if (_loading) {
      return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()));
    }
    if (_error.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off_outlined, size: 32, color: Colors.red),
          const SizedBox(height: 8),
          Text(_error,
              style: const TextStyle(color: Colors.red, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton(onPressed: _search, child: const Text('Try again')),
        ]),
      );
    }
    if (!_searched) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.menu_book_outlined,
              size: 40, color: primary.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          Text(
            'Type a reference like "John 3:16"\nor search by keyword like "faith"',
            style: TextStyle(
                fontSize: 13, color: primary.withValues(alpha: 0.5)),
            textAlign: TextAlign.center,
          ),
        ]),
      );
    }
    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off_outlined,
              size: 36, color: primary.withValues(alpha: 0.2)),
          const SizedBox(height: 10),
          Text(
            'No results found.\nTry a different reference or keyword.',
            style: TextStyle(
                fontSize: 13, color: primary.withValues(alpha: 0.5)),
            textAlign: TextAlign.center,
          ),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      shrinkWrap: true,
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final r = _results[i];
        return ListTile(
          dense: true,
          title: Text(r.reference,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: primary)),
          subtitle: Text(r.text,
              style: const TextStyle(fontSize: 12),
              maxLines: 4,
              overflow: TextOverflow.ellipsis),
          trailing:
              Icon(Icons.add_circle_outline, size: 18, color: primary),
          onTap: () => _selectResult(r),
        );
      },
    );
  }
}