// lib/apps/bible/bible_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../screens/dashboard_screen.dart';
import '../../services/bible_service.dart';
import '../../theme.dart';

class BibleScreen extends StatefulWidget {
  /// If set, the screen opens directly to this book + chapter
  final int? initialBookId;
  final int initialChapter;

  const BibleScreen({
    super.key,
    this.initialBookId,
    this.initialChapter = 1,
  });

  @override
  State<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends State<BibleScreen> {
  BibleBook? _selectedBook;
  int _selectedChapter = 1;
  BibleChapter? _chapterData;
  bool _loadingChapter = false;
  String? _error;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final svc   = context.read<BibleService>();
    final books = await svc.getBooks();
    if (books.isEmpty) return;

    BibleBook book;
    if (widget.initialBookId != null) {
      book = books.firstWhere(
        (b) => b.bookId == widget.initialBookId,
        orElse: () => books.first,
      );
    } else {
      book = books.first;
    }
    setState(() {
      _selectedBook    = book;
      _selectedChapter = widget.initialChapter;
    });
    await _loadChapter();
  }

  Future<void> _loadChapter() async {
    if (_selectedBook == null) return;
    setState(() { _loadingChapter = true; _error = null; });
    try {
      final svc  = context.read<BibleService>();
      final data = await svc.getChapter(_selectedBook!.bookId, _selectedChapter);
      setState(() {
        _chapterData   = data;
        _loadingChapter = false;
      });
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
            0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loadingChapter = false; });
    }
  }

  void _prevChapter() {
    if (_selectedChapter > 1) {
      setState(() => _selectedChapter--);
      _loadChapter();
    }
  }

  void _nextChapter() {
    if (_selectedBook != null &&
        _selectedChapter < _selectedBook!.chapters) {
      setState(() => _selectedChapter++);
      _loadChapter();
    }
  }

  void _showBookPicker(Color primary) async {
    final svc   = context.read<BibleService>();
    final books = await svc.getBooks();
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _BookPickerSheet(
        books:    books,
        selected: _selectedBook,
        primary:  primary,
        onPick: (book) {
          setState(() {
            _selectedBook    = book;
            _selectedChapter = 1;
          });
          _loadChapter();
        },
      ),
    );
  }

  void _showChapterPicker(Color primary) async {
    if (_selectedBook == null) return;
    final total = _selectedBook!.chapters;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ChapterPickerSheet(
        totalChapters:   total,
        selectedChapter: _selectedChapter,
        primary:         primary,
        onPick: (ch) {
          setState(() => _selectedChapter = ch);
          _loadChapter();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state     = context.watch<AppState>();
    final svc       = context.watch<BibleService>();
    final primary   = state.brandPrimary;
    final secondary = state.brandSecondary;
    final profile   = state.churchProfile;

    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F5),
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: contrastOn(primary),
        title: Row(
          children: [
            if (profile != null)
              ChurchLogo(
                logoPath:     profile.logoPath,
                primary:      primary,
                secondary:    secondary,
                size:         30,
                borderRadius: 7,
              ),
            if (profile != null) const SizedBox(width: 10),
            const Text('Bible',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          // Verse search
          IconButton(
            tooltip: 'Search verses',
            icon: Icon(Icons.search, color: contrastOn(primary)),
            onPressed: () => _showVerseSearch(context, primary),
          ),
          // Translation badge
          GestureDetector(
            onTap: () => _showTranslationPicker(context, primary),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: contrastOn(primary).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: contrastOn(primary).withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Text(svc.translationName,
                      style: TextStyle(
                          color: contrastOn(primary),
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  const SizedBox(width: 4),
                  Icon(Icons.swap_horiz,
                      size: 14, color: contrastOn(primary)),
                ],
              ),
            ),
          ),
        ],
        bottom: _selectedBook != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Container(
                  color: primary,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    children: [
                      // Book selector
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showBookPicker(primary),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: contrastOn(primary).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _selectedBook!.name,
                                    style: TextStyle(
                                        color: contrastOn(primary),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Icon(Icons.arrow_drop_down,
                                    color: contrastOn(primary), size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Chapter selector
                      GestureDetector(
                        onTap: () => _showChapterPicker(primary),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: contrastOn(primary).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Text(
                                'Ch. $_selectedChapter',
                                style: TextStyle(
                                    color: contrastOn(primary),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14),
                              ),
                              Icon(Icons.arrow_drop_down,
                                  color: contrastOn(primary), size: 18),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: _buildBody(primary, secondary),
      bottomNavigationBar: _buildNavBar(primary, secondary),
    );
  }

  Widget _buildBody(Color primary, Color secondary) {
    if (context.watch<BibleService>().loadingBooks) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: primary),
            const SizedBox(height: 16),
            const Text('Loading Bible…', style: TextStyle(color: textMid)),
          ],
        ),
      );
    }

    if (_loadingChapter) {
      return Center(child: CircularProgressIndicator(color: primary));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off, size: 48, color: primary.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              const Text('Could not load chapter.',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold,
                      color: textDark)),
              const SizedBox(height: 8),
              const Text('Check your internet connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textMid)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadChapter,
                style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: contrastOn(primary)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_chapterData == null) {
      return const Center(
        child: Text('Select a book to start reading.',
            style: TextStyle(color: textMid)),
      );
    }

    final verses = _chapterData!.verses;

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      itemCount: verses.length + 1, // +1 for chapter header
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _chapterData!.bookName,
                  style: TextStyle(
                      fontSize: 14,
                      color: primary.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.2),
                ),
                Text(
                  'Chapter $_selectedChapter',
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: primary),
                ),
                const SizedBox(height: 8),
                Divider(color: primary.withValues(alpha: 0.2), thickness: 2),
              ],
            ),
          );
        }

        final verse = verses[i - 1];
        return _VerseRow(
          verse:     verse,
          primary:   primary,
          secondary: secondary,
        );
      },
    );
  }

  Widget _buildNavBar(Color primary, Color secondary) {
    final canPrev = _selectedChapter > 1;
    final canNext = _selectedBook != null &&
        _selectedChapter < _selectedBook!.chapters;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEAEDF3))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: canPrev ? _prevChapter : null,
            icon: Icon(Icons.chevron_left,
                color: canPrev ? primary : Colors.grey.shade300, size: 30),
          ),
          Expanded(
            child: Text(
              _selectedBook != null
                  ? '${_selectedBook!.name} $_selectedChapter'
                      ' / ${_selectedBook!.chapters}'
                  : '',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14),
            ),
          ),
          IconButton(
            onPressed: canNext ? _nextChapter : null,
            icon: Icon(Icons.chevron_right,
                color: canNext ? primary : Colors.grey.shade300, size: 30),
          ),
        ],
      ),
    );
  }

  Future<void> _showVerseSearch(BuildContext context, Color primary) async {
    final svc = context.read<BibleService>();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _VerseSearchSheet(
        service: svc,
        primary: primary,
        onNavigate: (bookId, chapter) {
          final books = svc.books;
          final book = books.firstWhere(
            (b) => b.bookId == bookId,
            orElse: () => books.first,
          );
          setState(() {
            _selectedBook    = book;
            _selectedChapter = chapter;
          });
          _loadChapter();
        },
      ),
    );
  }

  Future<void> _showTranslationPicker(
      BuildContext context, Color primary) async {
    final svc = context.read<BibleService>();
    await svc.fetchTranslations();
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => TranslationPickerSheet(
        service:  svc,
        primary:  primary,
        onPicked: (id) async {
          await svc.setTranslation(id);
          if (mounted) await _loadChapter();
        },
      ),
    );
  }
}

// ── VERSE ROW ─────────────────────────────────────────────────────────────────
class _VerseRow extends StatelessWidget {
  final BibleVerse verse;
  final Color primary;
  final Color secondary;

  const _VerseRow({
    required this.verse,
    required this.primary,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: verse.text));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Verse ${verse.number} copied'),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '${verse.number}  ',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: secondary,
                      height: 1.8),
                ),
                TextSpan(
                  text: verse.text,
                  style: const TextStyle(
                      fontSize: 17,
                      height:   1.8,
                      color:    textDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── BOOK PICKER ───────────────────────────────────────────────────────────────
class _BookPickerSheet extends StatefulWidget {
  final List<BibleBook> books;
  final BibleBook? selected;
  final Color primary;
  final ValueChanged<BibleBook> onPick;

  const _BookPickerSheet({
    required this.books,
    required this.selected,
    required this.primary,
    required this.onPick,
  });

  @override
  State<_BookPickerSheet> createState() => _BookPickerSheetState();
}

class _BookPickerSheetState extends State<_BookPickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.books
        .where((b) =>
            _search.isEmpty ||
            b.name.toLowerCase().contains(_search.toLowerCase()))
        .toList();
    final ot = all.where((b) => b.isOT).toList();
    final nt = all.where((b) => !b.isOT).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize:     0.95,
      minChildSize:     0.4,
      expand: false,
      builder: (ctx, scroll) => Column(
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Choose a Book',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: widget.primary)),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: false,
              decoration: const InputDecoration(
                hintText: 'Search books…',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabs,
            labelColor:   widget.primary,
            unselectedLabelColor: textMid,
            indicatorColor: widget.primary,
            tabs: const [Tab(text: 'Old Testament'), Tab(text: 'New Testament')],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _bookGrid(ot, scroll),
                _bookGrid(nt, scroll),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bookGrid(List<BibleBook> books, ScrollController scroll) {
    return GridView.builder(
      controller: scroll,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        crossAxisSpacing:   10,
        mainAxisSpacing:    10,
        childAspectRatio:   2.2,
      ),
      itemCount: books.length,
      itemBuilder: (ctx, i) {
        final book     = books[i];
        final selected = widget.selected?.id == book.id;
        return GestureDetector(
          onTap: () {
            widget.onPick(book);
            Navigator.pop(ctx);
          },
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? widget.primary
                  : widget.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? widget.primary
                    : widget.primary.withValues(alpha: 0.2),
              ),
            ),
            padding: const EdgeInsets.all(6),
            child: Text(
              book.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? contrastOn(widget.primary)
                      : widget.primary),
            ),
          ),
        );
      },
    );
  }
}

// ── CHAPTER PICKER ────────────────────────────────────────────────────────────
class _ChapterPickerSheet extends StatelessWidget {
  final int totalChapters;
  final int selectedChapter;
  final Color primary;
  final ValueChanged<int> onPick;

  const _ChapterPickerSheet({
    required this.totalChapters,
    required this.selectedChapter,
    required this.primary,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      maxChildSize:     0.85,
      minChildSize:     0.3,
      expand: false,
      builder: (ctx, scroll) => Column(
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text('Choose a Chapter',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primary)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 64,
                crossAxisSpacing:   8,
                mainAxisSpacing:    8,
                childAspectRatio:   1,
              ),
              itemCount: totalChapters,
              itemBuilder: (ctx, i) {
                final ch  = i + 1;
                final sel = ch == selectedChapter;
                return GestureDetector(
                  onTap: () {
                    onPick(ch);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: sel ? primary : primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: sel
                            ? primary
                            : primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      '$ch',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: sel ? contrastOn(primary) : primary),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── TRANSLATION PICKER (reusable from settings) ───────────────────────────────
class TranslationPickerSheet extends StatefulWidget {
  final BibleService service;
  final Color primary;
  final ValueChanged<String> onPicked;

  const TranslationPickerSheet({
    super.key,
    required this.service,
    required this.primary,
    required this.onPicked,
  });

  @override
  State<TranslationPickerSheet> createState() => _TranslationPickerSheetState();
}

class _TranslationPickerSheetState extends State<TranslationPickerSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final svc   = widget.service;
    final query = _search.toLowerCase();

    // English-only: match language 'en' or 'eng', or fall back to the
    // built-in list (which is all English) when the live fetch hasn't run yet.
    final allTranslations = svc.availableTranslations;
    final hasLanguageTags = allTranslations.any(
        (t) => t.language == 'eng' || t.language == 'en');

    final english = allTranslations
        .where((t) {
          final isEnglish = hasLanguageTags
              ? (t.language == 'eng' || t.language == 'en')
              : true; // built-in list is all English
          final matchesQuery = query.isEmpty ||
              t.name.toLowerCase().contains(query) ||
              t.shortName.toLowerCase().contains(query);
          return isEnglish && matchesQuery;
        })
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize:     0.95,
      minChildSize:     0.4,
      expand: false,
      builder: (ctx, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Bible Translation',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: widget.primary)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('${english.length} English translations',
                style: const TextStyle(fontSize: 12, color: textMid)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: false,
              decoration: const InputDecoration(
                hintText: 'Search translations…',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: english.isEmpty
                ? const Center(
                    child: Text('No translations found.',
                        style: TextStyle(color: textMid)))
                : ListView.separated(
                    controller: scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: english.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final t   = english[i];
                      final sel = t.id == svc.translationId;
                      return ListTile(
                        selected:          sel,
                        selectedTileColor: widget.primary.withValues(alpha: 0.08),
                        leading: Container(
                          width: 52, height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: sel
                                ? widget.primary
                                : widget.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(t.shortName,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: sel
                                      ? contrastOn(widget.primary)
                                      : widget.primary)),
                        ),
                        title: Text(t.name,
                            style: TextStyle(
                                fontWeight:
                                    sel ? FontWeight.bold : FontWeight.normal,
                                fontSize: 14,
                                color: sel ? widget.primary : textDark)),
                        trailing: sel
                            ? Icon(Icons.check_circle,
                                color: widget.primary, size: 20)
                            : null,
                        onTap: () {
                          widget.onPicked(t.id);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
// ── VERSE SEARCH SHEET ────────────────────────────────────────────────────────
/// Full-text verse search + quick Book / Chapter / Verse navigator in one sheet.
class _VerseSearchSheet extends StatefulWidget {
  final BibleService service;
  final Color primary;
  /// Called when user taps a result — navigate to that book + chapter.
  final void Function(int bookId, int chapter) onNavigate;

  const _VerseSearchSheet({
    required this.service,
    required this.primary,
    required this.onNavigate,
  });

  @override
  State<_VerseSearchSheet> createState() => _VerseSearchSheetState();
}

class _VerseSearchSheetState extends State<_VerseSearchSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // ── Search tab state
  final _searchCtrl = TextEditingController();
  List<VerseSearchResult> _results   = [];
  bool                    _searching = false;
  String?                 _searchErr;

  // ── Browse tab state
  BibleBook? _navBook;
  int        _navChapter = 1;
  int        _navVerse   = 1;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    final books = widget.service.books;
    if (books.isNotEmpty) _navBook = books.first;
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Search helpers ──────────────────────────────────────────────────────────

  Future<void> _runSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() { _results = []; _searchErr = null; });
      return;
    }
    setState(() { _searching = true; _searchErr = null; });
    try {
      final res = await widget.service.searchVerses(query.trim(), limit: 40);
      if (mounted) setState(() { _results = res; _searching = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _searching = false;
          _searchErr = 'Search failed — check connection';
        });
      }
    }
  }

  void _navigateToResult(VerseSearchResult r) {
    Navigator.pop(context);
    // Call after pop so _BibleScreenState.setState fires on a mounted widget.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onNavigate(r.bookId, r.chapter);
    });
  }

  // ── Browse helpers ──────────────────────────────────────────────────────────

  void _goToNavSelection() {
    if (_navBook == null) return;
    final bookId  = _navBook!.bookId;
    final chapter = _navChapter;
    Navigator.pop(context);
    // Call after pop so _BibleScreenState.setState fires on a mounted widget.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onNavigate(bookId, chapter);
    });
  }

  // ── BUILD ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize:     0.96,
      minChildSize:     0.5,
      expand: false,
      builder: (ctx, scroll) => Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Find a Verse',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primary)),
          ),
          const SizedBox(height: 8),
          // Tabs
          TabBar(
            controller: _tabs,
            labelColor:           primary,
            unselectedLabelColor: textMid,
            indicatorColor:       primary,
            tabs: const [
              Tab(text: 'Search'),
              Tab(text: 'Browse'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildSearchTab(scroll),
                _buildBrowseTab(scroll),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── SEARCH TAB ─────────────────────────────────────────────────────────────

  Widget _buildSearchTab(ScrollController scroll) {
    final primary = widget.primary;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller:     _searchCtrl,
            autofocus:      false,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText:   'Search by keyword or phrase…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() { _results = []; _searchErr = null; });
                      })
                  : null,
              isDense: true,
            ),
            onChanged:   (v) { setState(() {}); _runSearch(v); },
            onSubmitted: _runSearch,
          ),
        ),
        if (_searching)
          Padding(
            padding: const EdgeInsets.all(24),
            child: CircularProgressIndicator(color: primary, strokeWidth: 2),
          )
        else if (_searchErr != null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_searchErr!,
                style: TextStyle(color: Colors.red.shade600, fontSize: 13)),
          )
        else if (_results.isEmpty && _searchCtrl.text.isNotEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No verses found.',
                style: TextStyle(color: textMid, fontSize: 14)),
          )
        else if (_results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              children: [
                Icon(Icons.menu_book_outlined,
                    size: 48, color: primary.withValues(alpha: 0.25)),
                const SizedBox(height: 12),
                Text(
                  'Type a word or phrase to search '
                  'the ${widget.service.translationId}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: textMid, fontSize: 13),
                ),
              ],
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final r = _results[i];
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color:        primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(r.reference,
                        style: TextStyle(
                            fontSize:   10,
                            fontWeight: FontWeight.bold,
                            color:      primary)),
                  ),
                  title: Text(r.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: textDark, height: 1.45)),
                  onTap: () => _navigateToResult(r),
                );
              },
            ),
          ),
      ],
    );
  }

  // ── BROWSE TAB ─────────────────────────────────────────────────────────────

  Widget _buildBrowseTab(ScrollController scroll) {
    final primary = widget.primary;
    final books   = widget.service.books;
    final book    = _navBook;
    final maxCh   = (book?.chapters ?? 1).clamp(1, 999);

    // Guard: keep chapter in range if book changes
    if (_navChapter > maxCh) _navChapter = maxCh;

    return SingleChildScrollView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Book dropdown
          _SectionLabel(label: 'BOOK', primary: primary),
          const SizedBox(height: 8),
          _DropdownRow<BibleBook>(
            value:     book,
            items:     books,
            labelOf:   (b) => b.name,
            hint:      'Select a book',
            primary:   primary,
            onChanged: (b) => setState(() {
              _navBook    = b;
              _navChapter = 1;
              _navVerse   = 1;
            }),
          ),
          const SizedBox(height: 20),

          // Chapter grid
          _SectionLabel(label: 'CHAPTER', primary: primary),
          const SizedBox(height: 8),
          _NumberGrid(
            count:    maxCh,
            selected: _navChapter,
            primary:  primary,
            onTap: (n) => setState(() { _navChapter = n; _navVerse = 1; }),
          ),
          const SizedBox(height: 20),

          // Verse grid (optional, cosmetic — navigates to chapter)
          _SectionLabel(label: 'STARTING VERSE (optional)', primary: primary),
          const SizedBox(height: 8),
          _NumberGrid(
            count:    176,
            selected: _navVerse,
            primary:  primary,
            onTap:    (n) => setState(() => _navVerse = n),
          ),
          const SizedBox(height: 28),

          // Go button
          if (book != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon:  const Icon(Icons.open_in_new, size: 18),
                label: Text(
                  'Go to ${book.name} $_navChapter:$_navVerse',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: contrastOn(primary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _goToNavSelection,
              ),
            ),
        ],
      ),
    );
  }
}

// ── REUSABLE HELPERS ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color  primary;
  const _SectionLabel({required this.label, required this.primary});

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: TextStyle(
            fontSize:    11,
            fontWeight:  FontWeight.w700,
            color:       primary,
            letterSpacing: 1.0),
      );
}

class _DropdownRow<T> extends StatelessWidget {
  final T?               value;
  final List<T>          items;
  final String Function(T) labelOf;
  final String           hint;
  final Color            primary;
  final ValueChanged<T?> onChanged;

  const _DropdownRow({
    required this.value,
    required this.items,
    required this.labelOf,
    required this.hint,
    required this.primary,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        border:       Border.all(color: primary.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
        color:        primary.withValues(alpha: 0.04),
      ),
      child: DropdownButton<T>(
        value:         value,
        isExpanded:    true,
        underline:     const SizedBox.shrink(),
        hint:          Text(hint, style: const TextStyle(color: textMid)),
        dropdownColor: Colors.white,
        borderRadius:  BorderRadius.circular(10),
        items: items
            .map((e) => DropdownMenuItem<T>(
                  value: e,
                  child: Text(labelOf(e),
                      style: TextStyle(
                          fontSize:   14,
                          color:      textDark,
                          fontWeight: e == value
                              ? FontWeight.bold
                              : FontWeight.normal)),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

/// Compact numbered grid — used for chapter and verse pickers.
class _NumberGrid extends StatelessWidget {
  final int             count;
  final int             selected;
  final Color           primary;
  final ValueChanged<int> onTap;

  const _NumberGrid({
    required this.count,
    required this.selected,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayCount = count.clamp(1, 176);
    return GridView.builder(
      shrinkWrap: true,
      physics:    const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 56,
        crossAxisSpacing:    6,
        mainAxisSpacing:     6,
        childAspectRatio:    1,
      ),
      itemCount: displayCount,
      itemBuilder: (ctx, i) {
        final n   = i + 1;
        final sel = n == selected;
        return GestureDetector(
          onTap: () => onTap(n),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel ? primary : primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: sel ? primary : primary.withValues(alpha: 0.2),
              ),
            ),
            child: Text('$n',
                style: TextStyle(
                    fontSize:   13,
                    fontWeight: FontWeight.bold,
                    color:      sel ? contrastOn(primary) : primary)),
          ),
        );
      },
    );
  }
}