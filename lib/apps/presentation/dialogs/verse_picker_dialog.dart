// lib/apps/presentation/dialogs/verse_picker_dialog.dart
//
// A three-mode dialog for importing scripture into a presentation slide:
//
//   Search mode  — type a keyword / reference and pick from results
//   Browse mode  — Book → Chapter → Verse(s) drill-down
//
// Returns a fully-populated [Slide] of type 'scripture', or null if cancelled.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../services/bible_service.dart';
import '../../../theme.dart';
import '../models/presentation_models.dart';

// ══════════════════════════════════════════════════════════════════════════════
// PUBLIC ENTRY POINT
// ══════════════════════════════════════════════════════════════════════════════

/// Opens the verse-picker. Returns a ready-to-use [Slide] or null.
Future<Slide?> showVersePickerDialog(
  BuildContext context, {
  required Color primary,
  required Color secondary,
}) {
  return showDialog<Slide>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _VersePickerDialog(
      primary:   primary,
      secondary: secondary,
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// DIALOG WIDGET
// ══════════════════════════════════════════════════════════════════════════════

enum _Mode { search, browse }

class _VersePickerDialog extends StatefulWidget {
  final Color primary;
  final Color secondary;
  const _VersePickerDialog({required this.primary, required this.secondary});

  @override
  State<_VersePickerDialog> createState() => _VersePickerDialogState();
}

class _VersePickerDialogState extends State<_VersePickerDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final BibleService  _bible;

  // ── Search state ──────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  List<VerseSearchResult> _results    = [];
  bool                    _searching  = false;
  String                  _searchErr  = '';

  // ── Browse state ──────────────────────────────────────────────────────────
  BibleBook?    _book;
  int?          _chapter;
  BibleChapter? _chapterData;
  bool          _loadingChapter = false;

  // ── Verse selection ───────────────────────────────────────────────────────
  // A single selected verse (from search) or a range (from browse)
  VerseSearchResult? _pickedSearch;
  int?               _verseStart;
  int?               _verseEnd;

  // ── Preview / slide config ────────────────────────────────────────────────
  bool   _showPreview = false;
  String _slideTitle  = '';
  String _slideBody   = '';
  String _slideRef    = '';

  @override
  void initState() {
    super.initState();
    _tabs  = TabController(length: 2, vsync: this);
    _bible = context.read<BibleService>();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Color get p => widget.primary;
  Color get s => widget.secondary;

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _runSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _searching = true; _searchErr = ''; _results = []; });
    try {
      final r = await _bible.searchVerses(q, limit: 40);
      setState(() => _results = r);
    } catch (e) {
      setState(() => _searchErr = e.toString());
    } finally {
      setState(() => _searching = false);
    }
  }

  Future<void> _loadChapter(BibleBook book, int chapter) async {
    setState(() { _loadingChapter = true; _chapterData = null; });
    final data = await _bible.getChapter(book.bookId, chapter);
    setState(() { _chapterData = data; _loadingChapter = false; });
  }

  void _pickSearchResult(VerseSearchResult r) {
    setState(() {
      _pickedSearch = r;
      _slideTitle   = r.bookName;
      _slideBody    = r.text;
      _slideRef     = '${r.reference} (${_bible.translationId})';
      _showPreview  = true;
    });
  }

  void _pickBrowseVerse(BibleVerse v) {
    if (_book == null || _chapter == null) return;
    if (_verseStart == null) {
      setState(() {
        _verseStart   = v.number;
        _verseEnd     = v.number;
      });
    } else if (v.number == _verseStart && _verseStart == _verseEnd) {
      // tap same verse again → deselect
      setState(() { _verseStart = null; _verseEnd = null; });
      return;
    } else {
      // extend range
      final lo = v.number < _verseStart! ? v.number : _verseStart!;
      final hi = v.number > _verseEnd!   ? v.number : _verseEnd!;
      setState(() { _verseStart = lo; _verseEnd = hi; });
    }
    _buildBrowsePreview();
  }

  void _buildBrowsePreview() {
    if (_chapterData == null || _verseStart == null) return;
    final verses = _chapterData!.verses
        .where((v) => v.number >= _verseStart! && v.number <= _verseEnd!)
        .toList();
    if (verses.isEmpty) return;

    final text = verses.length == 1
        ? verses.first.text
        : verses.map((v) => '[${v.number}] ${v.text}').join(' ');

    final ref = _verseStart == _verseEnd
        ? '${_book!.name} $_chapter:$_verseStart'
        : '${_book!.name} $_chapter:$_verseStart–$_verseEnd';

    setState(() {
      _slideTitle  = _book!.name;
      _slideBody   = text;
      _slideRef    = '$ref (${_bible.translationId})';
      _showPreview = true;
    });
  }

  Slide _buildSlide() {
    final bg = Color.lerp(p, Colors.black, 0.30)!;
    return Slide(
      id:        const Uuid().v4(),
      type:      'scripture',
      title:     _slideTitle,
      body:      _slideBody,
      reference: _slideRef,
      bgColor:   bg,
      textColor: contrastOn(bg),
      fontSize:  32,
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width:  600,
        height: 680,
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            _Header(
              primary:   p,
              secondary: s,
              bible:     _bible,
              onClose:   () => Navigator.pop(context),
            ),

            // ── Tab bar ──────────────────────────────────────────────────
            TabBar(
              controller:              _tabs,
              labelColor:              p,
              unselectedLabelColor:    Colors.grey,
              indicatorColor:          p,
              indicatorWeight:         2.5,
              tabs: const [
                Tab(icon: Icon(Icons.search,       size: 17), text: 'Search'),
                Tab(icon: Icon(Icons.menu_book,    size: 17), text: 'Browse'),
              ],
            ),

            // ── Body ────────────────────────────────────────────────────
            Expanded(
              child: _showPreview
                  ? _PreviewPanel(
                      primary:     p,
                      secondary:   s,
                      slideTitle:  _slideTitle,
                      slideBody:   _slideBody,
                      slideRef:    _slideRef,
                      bible:       _bible,
                      onTitleChanged: (v) => setState(() => _slideTitle = v),
                      onBodyChanged:  (v) => setState(() => _slideBody  = v),
                      onRefChanged:   (v) => setState(() => _slideRef   = v),
                      onBack: () => setState(() => _showPreview = false),
                      onInsert: () => Navigator.pop(context, _buildSlide()),
                    )
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        // ── SEARCH TAB ─────────────────────────────────
                        _SearchTab(
                          primary:    p,
                          searchCtrl: _searchCtrl,
                          results:    _results,
                          searching:  _searching,
                          error:      _searchErr,
                          onSearch:   _runSearch,
                          onPick:     _pickSearchResult,
                        ),
                        // ── BROWSE TAB ─────────────────────────────────
                        _BrowseTab(
                          primary:        p,
                          secondary:      s,
                          bible:          _bible,
                          book:           _book,
                          chapter:        _chapter,
                          chapterData:    _chapterData,
                          loadingChapter: _loadingChapter,
                          verseStart:     _verseStart,
                          verseEnd:       _verseEnd,
                          onPickBook: (b) => setState(() {
                            _book        = b;
                            _chapter     = null;
                            _chapterData = null;
                            _verseStart  = null;
                            _verseEnd    = null;
                            _showPreview = false;
                          }),
                          onPickChapter: (c) {
                            setState(() {
                              _chapter    = c;
                              _verseStart = null;
                              _verseEnd   = null;
                              _showPreview = false;
                            });
                            _loadChapter(_book!, c);
                          },
                          onPickVerse: _pickBrowseVerse,
                          onConfirmRange: () => setState(
                              () => _showPreview = _verseStart != null),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HEADER
// ══════════════════════════════════════════════════════════════════════════════
class _Header extends StatelessWidget {
  final Color        primary;
  final Color        secondary;
  final BibleService bible;
  final VoidCallback onClose;

  const _Header({
    required this.primary,
    required this.secondary,
    required this.bible,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.06),
        border: Border(
            bottom: BorderSide(color: primary.withValues(alpha: 0.12))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:        primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.menu_book_rounded, color: primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Import Scripture Slide',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize:   16,
                        color:      primary)),
                ListenableBuilder(
                  listenable: context.read<BibleService>(),
                  builder: (_, __) {
                    final b = context.read<BibleService>();
                    return Text(
                      'Translation: ${b.translationName}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500),
                    );
                  },
                ),
              ],
            ),
          ),
          IconButton(
            icon:      const Icon(Icons.close_rounded),
            color:     Colors.grey,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SEARCH TAB
// ══════════════════════════════════════════════════════════════════════════════
class _SearchTab extends StatelessWidget {
  final Color                         primary;
  final TextEditingController         searchCtrl;
  final List<VerseSearchResult>       results;
  final bool                          searching;
  final String                        error;
  final VoidCallback                  onSearch;
  final ValueChanged<VerseSearchResult> onPick;

  const _SearchTab({
    required this.primary,
    required this.searchCtrl,
    required this.results,
    required this.searching,
    required this.error,
    required this.onSearch,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller:      searchCtrl,
                  decoration:      _inputDec(
                    'Search by keyword, e.g. "grace", "John 3"',
                    prefixIcon: Icons.search,
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted:     (_) => onSearch(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48, height: 48,
                child: ElevatedButton(
                  onPressed: searching ? null : onSearch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: contrastOn(primary),
                    padding:         EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: searching
                      ? SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color:       contrastOn(primary)))
                      : const Icon(Icons.search),
                ),
              ),
            ],
          ),
        ),

        if (error.isNotEmpty)
          _ErrorBanner(message: error),

        Expanded(
          child: results.isEmpty && !searching
              ? _EmptyHint(
                  icon:    Icons.search_rounded,
                  message: 'Search for a word or reference',
                  sub:     'e.g. "love", "faith", "John 3:16"',
                  primary: primary,
                )
              : ListView.separated(
                  itemCount:        results.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 56),
                  itemBuilder: (_, i) {
                    final r = results[i];
                    return ListTile(
                      leading: CircleAvatar(
                        radius:          16,
                        backgroundColor: primary.withValues(alpha: 0.10),
                        child: Text(
                          r.bookId.toString(),
                          style: TextStyle(
                              fontSize: 10,
                              color:    primary,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(r.reference,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Text(
                        r.text,
                        maxLines:  2,
                        overflow:  TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Icon(Icons.add_circle_outline,
                          color: primary, size: 20),
                      onTap: () => onPick(r),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BROWSE TAB
// ══════════════════════════════════════════════════════════════════════════════
class _BrowseTab extends StatelessWidget {
  final Color        primary;
  final Color        secondary;
  final BibleService bible;
  final BibleBook?   book;
  final int?         chapter;
  final BibleChapter? chapterData;
  final bool         loadingChapter;
  final int?         verseStart;
  final int?         verseEnd;
  final ValueChanged<BibleBook> onPickBook;
  final ValueChanged<int>       onPickChapter;
  final ValueChanged<BibleVerse> onPickVerse;
  final VoidCallback             onConfirmRange;

  const _BrowseTab({
    required this.primary,
    required this.secondary,
    required this.bible,
    required this.book,
    required this.chapter,
    required this.chapterData,
    required this.loadingChapter,
    required this.verseStart,
    required this.verseEnd,
    required this.onPickBook,
    required this.onPickChapter,
    required this.onPickVerse,
    required this.onConfirmRange,
  });

  @override
  Widget build(BuildContext context) {
    // ── Step 1: pick a book ──────────────────────────────────────────────
    if (book == null) {
      return _BookPicker(
          primary: primary, bible: bible, onPick: onPickBook);
    }

    // ── Step 2: pick a chapter ───────────────────────────────────────────
    if (chapter == null) {
      return _ChapterPicker(
        primary:  primary,
        book:     book!,
        onBack:   () => onPickBook(book!), // triggers parent reset via null
        onPick:   onPickChapter,
      );
    }

    // ── Step 3: pick verse(s) ────────────────────────────────────────────
    return _VersePicker(
      primary:        primary,
      secondary:      secondary,
      book:           book!,
      chapter:        chapter!,
      chapterData:    chapterData,
      loading:        loadingChapter,
      verseStart:     verseStart,
      verseEnd:       verseEnd,
      onPickVerse:    onPickVerse,
      onConfirm:      onConfirmRange,
      onBack: () => onPickChapter(chapter!), // triggers parent reset
    );
  }
}

// ── Book picker ───────────────────────────────────────────────────────────────
class _BookPicker extends StatelessWidget {
  final Color                  primary;
  final BibleService           bible;
  final ValueChanged<BibleBook> onPick;

  const _BookPicker({
    required this.primary,
    required this.bible,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final books = bible.books;
    final ot    = books.where((b) => b.isOT).toList();
    final nt    = books.where((b) => !b.isOT).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        _TestamentSection(
            label: 'Old Testament', books: ot,
            primary: primary, onPick: onPick),
        const SizedBox(height: 8),
        _TestamentSection(
            label: 'New Testament', books: nt,
            primary: primary, onPick: onPick),
      ],
    );
  }
}

class _TestamentSection extends StatelessWidget {
  final String                 label;
  final List<BibleBook>        books;
  final Color                  primary;
  final ValueChanged<BibleBook> onPick;

  const _TestamentSection({
    required this.label,
    required this.books,
    required this.primary,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize:   12,
                  color:      primary,
                  letterSpacing: 0.8)),
        ),
        Wrap(
          spacing: 6, runSpacing: 6,
          children: books.map((b) => GestureDetector(
            onTap: () => onPick(b),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color:        primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(7),
                border:       Border.all(
                    color: primary.withValues(alpha: 0.20)),
              ),
              child: Text(b.name,
                  style: TextStyle(fontSize: 12, color: primary)),
            ),
          )).toList(),
        ),
      ],
    );
  }
}

// ── Chapter picker ────────────────────────────────────────────────────────────
class _ChapterPicker extends StatelessWidget {
  final Color              primary;
  final BibleBook          book;
  final VoidCallback       onBack;
  final ValueChanged<int>  onPick;

  const _ChapterPicker({
    required this.primary,
    required this.book,
    required this.onBack,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BreadcrumbBar(
          primary:  primary,
          crumbs:   [book.name],
          onBack:   onBack,
        ),
        Expanded(
          child: GridView.builder(
            padding:     const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 56,
              crossAxisSpacing:    8,
              mainAxisSpacing:     8,
              childAspectRatio:    1,
            ),
            itemCount: book.chapters,
            itemBuilder: (_, i) {
              final ch = i + 1;
              return GestureDetector(
                onTap: () => onPick(ch),
                child: Container(
                  decoration: BoxDecoration(
                    color:        primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border:       Border.all(
                        color: primary.withValues(alpha: 0.22)),
                  ),
                  child: Center(
                    child: Text('$ch',
                        style: TextStyle(
                            color:      primary,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Verse picker ──────────────────────────────────────────────────────────────
class _VersePicker extends StatelessWidget {
  final Color         primary;
  final Color         secondary;
  final BibleBook     book;
  final int           chapter;
  final BibleChapter? chapterData;
  final bool          loading;
  final int?          verseStart;
  final int?          verseEnd;
  final ValueChanged<BibleVerse> onPickVerse;
  final VoidCallback  onConfirm;
  final VoidCallback  onBack;

  const _VersePicker({
    required this.primary,
    required this.secondary,
    required this.book,
    required this.chapter,
    required this.chapterData,
    required this.loading,
    required this.verseStart,
    required this.verseEnd,
    required this.onPickVerse,
    required this.onConfirm,
    required this.onBack,
  });

  bool _inRange(int n) {
    if (verseStart == null) return false;
    return n >= verseStart! && n <= (verseEnd ?? verseStart!);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _BreadcrumbBar(
          primary: primary,
          crumbs:  ['${book.name}', 'Chapter $chapter'],
          onBack:  onBack,
        ),

        if (verseStart != null)
          Container(
            margin:  const EdgeInsets.fromLTRB(12, 0, 12, 6),
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color:        primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
              border:       Border.all(
                  color: primary.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline,
                    color: primary, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    verseStart == verseEnd
                        ? '${book.name} $chapter:$verseStart selected'
                        : '${book.name} $chapter:$verseStart–$verseEnd selected',
                    style: TextStyle(
                        fontSize:   12,
                        color:      primary,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: onConfirm,
                  style: TextButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: contrastOn(primary),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Use verse',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),

        Expanded(
          child: loading
              ? Center(
                  child: CircularProgressIndicator(color: primary))
              : chapterData == null
                  ? _EmptyHint(
                      icon:    Icons.error_outline,
                      message: 'Could not load chapter',
                      sub:     'Check your connection and try again',
                      primary: primary,
                    )
                  : ListView.builder(
                      padding:   const EdgeInsets.fromLTRB(12, 4, 12, 80),
                      itemCount: chapterData!.verses.length,
                      itemBuilder: (_, i) {
                        final v   = chapterData!.verses[i];
                        final sel = _inRange(v.number);
                        return GestureDetector(
                          onTap: () => onPickVerse(v),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            margin:   const EdgeInsets.symmetric(
                                vertical: 3),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: sel
                                  ? primary.withValues(alpha: 0.10)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: sel
                                    ? primary.withValues(alpha: 0.35)
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    '${v.number}',
                                    style: TextStyle(
                                      color:      sel
                                          ? primary
                                          : Colors.grey.shade400,
                                      fontWeight: FontWeight.bold,
                                      fontSize:   11,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    v.text,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color:    sel
                                          ? primary
                                              .withValues(alpha: 0.90)
                                          : null,
                                      height: 1.55,
                                    ),
                                  ),
                                ),
                                if (sel)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        left: 6, top: 1),
                                    child: Icon(
                                        Icons.check_circle_rounded,
                                        color: primary,
                                        size:  16),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PREVIEW / EDIT PANEL
// ══════════════════════════════════════════════════════════════════════════════
class _PreviewPanel extends StatefulWidget {
  final Color        primary;
  final Color        secondary;
  final String       slideTitle;
  final String       slideBody;
  final String       slideRef;
  final BibleService bible;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onBodyChanged;
  final ValueChanged<String> onRefChanged;
  final VoidCallback onBack;
  final VoidCallback onInsert;

  const _PreviewPanel({
    required this.primary,
    required this.secondary,
    required this.slideTitle,
    required this.slideBody,
    required this.slideRef,
    required this.bible,
    required this.onTitleChanged,
    required this.onBodyChanged,
    required this.onRefChanged,
    required this.onBack,
    required this.onInsert,
  });

  @override
  State<_PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends State<_PreviewPanel> {
  late TextEditingController _titleCtrl;
  late TextEditingController _bodyCtrl;
  late TextEditingController _refCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.slideTitle);
    _bodyCtrl  = TextEditingController(text: widget.slideBody);
    _refCtrl   = TextEditingController(text: widget.slideRef);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p  = widget.primary;
    final bg = Color.lerp(p, Colors.black, 0.30)!;
    final fg = contrastOn(bg);

    return Column(
      children: [
        // ── mini slide preview ───────────────────────────────────────
        Container(
          margin:  const EdgeInsets.fromLTRB(16, 12, 16, 10),
          height:  148,
          decoration: BoxDecoration(
            color:        bg,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12)
            ],
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: 24, vertical: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_titleCtrl.text.isNotEmpty)
                Text(_titleCtrl.text,
                    style: TextStyle(
                        color:      fg,
                        fontWeight: FontWeight.bold,
                        fontSize:   15),
                    textAlign: TextAlign.center),
              if (_bodyCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(_bodyCtrl.text,
                    style: TextStyle(
                        color:    fg.withValues(alpha: 0.90),
                        fontSize: 11,
                        height:   1.55),
                    textAlign: TextAlign.center,
                    maxLines:  4,
                    overflow:  TextOverflow.ellipsis),
              ],
              if (_refCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(_refCtrl.text,
                    style: TextStyle(
                        color:     fg.withValues(alpha: 0.60),
                        fontSize:  9,
                        fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center),
              ],
            ],
          ),
        ),

        // ── editable fields ──────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _titleCtrl,
                  decoration: _inputDec('Title'),
                  onChanged: (v) {
                    widget.onTitleChanged(v);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _bodyCtrl,
                  maxLines:   4,
                  decoration: _inputDec('Verse text'),
                  onChanged: (v) {
                    widget.onBodyChanged(v);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _refCtrl,
                  decoration: _inputDec('Reference'),
                  onChanged: (v) {
                    widget.onRefChanged(v);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),

        // ── actions ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          decoration: BoxDecoration(
            border: Border(
                top: BorderSide(
                    color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: widget.onBack,
                icon:  const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Back'),
                style: TextButton.styleFrom(foregroundColor: Colors.grey),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _bodyCtrl.text.isEmpty ? null : widget.onInsert,
                icon:  const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add to Deck',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: p,
                  foregroundColor: contrastOn(p),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SMALL SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _BreadcrumbBar extends StatelessWidget {
  final Color        primary;
  final List<String> crumbs;
  final VoidCallback onBack;

  const _BreadcrumbBar({
    required this.primary,
    required this.crumbs,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon:    Icon(Icons.arrow_back_rounded,
                size: 18, color: primary),
            onPressed: onBack,
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          ...crumbs.expand((c) => [
            Text(c,
                style: TextStyle(
                    fontSize:   12,
                    color:      primary,
                    fontWeight: FontWeight.w600)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.chevron_right,
                  size: 14, color: Colors.grey.shade400),
            ),
          ]),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        margin:     const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding:    const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:        Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(color: Colors.red.shade200),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.red, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    color: Colors.red, fontSize: 12)),
          ),
        ]),
      );
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String   message;
  final String   sub;
  final Color    primary;

  const _EmptyHint({
    required this.icon,
    required this.message,
    required this.sub,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48,
                color: primary.withValues(alpha: 0.20)),
            const SizedBox(height: 12),
            Text(message,
                style: TextStyle(
                    color:      primary.withValues(alpha: 0.55),
                    fontSize:   14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(sub,
                style: const TextStyle(
                    color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
}

InputDecoration _inputDec(String label, {IconData? prefixIcon}) =>
    InputDecoration(
      labelText:      label,
      border:         OutlineInputBorder(
          borderRadius: BorderRadius.circular(10)),
      enabledBorder:  OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:   BorderSide(color: Colors.grey.shade300)),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 12),
      prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
    );