// lib/apps/notes/widgets/folder_tree.dart
//
// Left-hand folder/category navigation panel.
// To add a new top-level folder: add a constant in note_constants.dart and
// add an entry in _FolderTreeState.build().
//
// CHANGES (this revision)
// ───────────────────────
// • Added "Textual" folder between Expositional and General.
//   Textual notes use a two-level subfolder encoding: "OT:Genesis" / "NT:Romans".
//   The tree shows two static sub-headers (Old Testament / New Testament) that
//   each expand to show only the books that already have notes, plus an
//   "Add book…" button identical to the Expositional one.

import 'package:flutter/material.dart';
import '../../../theme.dart';
import '../note_constants.dart';
import '../note_model.dart';

// ── PUBLIC WIDGET ─────────────────────────────────────────────────────────────

class FolderTree extends StatefulWidget {
  final String          activeFolder;
  final String          activeSubfolder;
  final List<NoteModel> notes;
  final Color           primary;
  final void Function(String folder, String sub) onSelectFolder;

  const FolderTree({
    super.key,
    required this.activeFolder,
    required this.activeSubfolder,
    required this.notes,
    required this.primary,
    required this.onSelectFolder,
  });

  @override
  State<FolderTree> createState() => _FolderTreeState();
}

class _FolderTreeState extends State<FolderTree> {
  final Set<String> _expanded = {
    kFolderTopical,
    kFolderExpositional,
    kFolderTextual,
  };

  // Track which Textual testament sub-sections are expanded
  final Set<String> _textualExpanded = {kTextualOT, kTextualNT};

  // ── Helpers ────────────────────────────────────────────────────────────────

  int _count(String folder, [String sub = '']) =>
      widget.notes.where((n) {
        if (folder == kFolderArchive) return n.isArchived;
        if (n.isArchived) return false;
        if (n.folder != folder) return false;
        if (sub.isNotEmpty) return n.subfolder == sub;
        return true;
      }).length;

  // For Expositional: subfolder is just the book name.
  List<String> get _expositionalBooks => widget.notes
      .where((n) => n.folder == kFolderExpositional && !n.isArchived)
      .map((n) => n.subfolder)
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  // For Textual: subfolder is "OT:BookName" or "NT:BookName".
  // Returns sorted book names for a given testament.
  List<String> _textualBooks(String testament) => widget.notes
      .where((n) =>
          n.folder == kFolderTextual &&
          !n.isArchived &&
          n.subfolder.startsWith('$testament:'))
      .map((n) => parseTextualSubfolder(n.subfolder)[1])
      .toSet()
      .toList()
    ..sort();

  void _toggle(String key) => setState(() {
    if (_expanded.contains(key)) {
      _expanded.remove(key);
    } else {
      _expanded.add(key);
    }
  });

  void _toggleTextual(String testament) => setState(() {
    if (_textualExpanded.contains(testament)) {
      _textualExpanded.remove(testament);
    } else {
      _textualExpanded.add(testament);
    }
  });

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F9FA),
      child: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [

              // ── Topical ────────────────────────────────────────────────────
              _FolderHeader(
                label:    'Topical',
                icon:     Icons.book_outlined,
                count:    _count(kFolderTopical),
                expanded: _expanded.contains(kFolderTopical),
                selected: widget.activeFolder == kFolderTopical &&
                    widget.activeSubfolder.isEmpty,
                primary:  widget.primary,
                onTap: () {
                  _toggle(kFolderTopical);
                  widget.onSelectFolder(kFolderTopical, '');
                },
              ),
              if (_expanded.contains(kFolderTopical))
                ...topicalSubfolders.map((sub) => _SubfolderTile(
                  label:    sub,
                  count:    _count(kFolderTopical, sub),
                  selected: widget.activeFolder == kFolderTopical &&
                      widget.activeSubfolder == sub,
                  primary:  widget.primary,
                  onTap:    () =>
                      widget.onSelectFolder(kFolderTopical, sub),
                )),

              // ── Expositional ───────────────────────────────────────────────
              _FolderHeader(
                label:    'Expositional',
                icon:     Icons.menu_book_outlined,
                count:    _count(kFolderExpositional),
                expanded: _expanded.contains(kFolderExpositional),
                selected: widget.activeFolder == kFolderExpositional &&
                    widget.activeSubfolder.isEmpty,
                primary:  widget.primary,
                onTap: () {
                  _toggle(kFolderExpositional);
                  widget.onSelectFolder(kFolderExpositional, '');
                },
              ),
              if (_expanded.contains(kFolderExpositional)) ...[
                ..._expositionalBooks.map((book) => _SubfolderTile(
                  label:    book,
                  count:    _count(kFolderExpositional, book),
                  selected: widget.activeFolder == kFolderExpositional &&
                      widget.activeSubfolder == book,
                  primary:  widget.primary,
                  onTap:    () =>
                      widget.onSelectFolder(kFolderExpositional, book),
                )),
                _AddBookButton(
                  primary: widget.primary,
                  onAdd:   (book) =>
                      widget.onSelectFolder(kFolderExpositional, book),
                ),
              ],

              // ── Textual ────────────────────────────────────────────────────
              _FolderHeader(
                label:    'Textual',
                icon:     Icons.format_quote_outlined,
                count:    _count(kFolderTextual),
                expanded: _expanded.contains(kFolderTextual),
                selected: widget.activeFolder == kFolderTextual &&
                    widget.activeSubfolder.isEmpty,
                primary:  widget.primary,
                onTap: () {
                  _toggle(kFolderTextual);
                  widget.onSelectFolder(kFolderTextual, '');
                },
              ),
              if (_expanded.contains(kFolderTextual)) ...[
                // ── Old Testament sub-section ──────────────────────────────
                _TestamentHeader(
                  label:    'Old Testament',
                  expanded: _textualExpanded.contains(kTextualOT),
                  primary:  widget.primary,
                  onTap:    () => _toggleTextual(kTextualOT),
                ),
                if (_textualExpanded.contains(kTextualOT)) ...[
                  ..._textualBooks(kTextualOT).map((book) {
                    final sub = textualSubfolder(kTextualOT, book);
                    return _SubfolderTile(
                      label:    book,
                      count:    _count(kFolderTextual, sub),
                      selected: widget.activeFolder == kFolderTextual &&
                          widget.activeSubfolder == sub,
                      primary:  widget.primary,
                      indent:   56, // deeper indent under testament header
                      onTap:    () =>
                          widget.onSelectFolder(kFolderTextual, sub),
                    );
                  }),
                  _AddBookButton(
                    primary:  widget.primary,
                    indent:   56,
                    testament: kTextualOT,
                    bookList: booksOT,
                    onAdd:    (book) => widget.onSelectFolder(
                        kFolderTextual, textualSubfolder(kTextualOT, book)),
                  ),
                ],

                // ── New Testament sub-section ──────────────────────────────
                _TestamentHeader(
                  label:    'New Testament',
                  expanded: _textualExpanded.contains(kTextualNT),
                  primary:  widget.primary,
                  onTap:    () => _toggleTextual(kTextualNT),
                ),
                if (_textualExpanded.contains(kTextualNT)) ...[
                  ..._textualBooks(kTextualNT).map((book) {
                    final sub = textualSubfolder(kTextualNT, book);
                    return _SubfolderTile(
                      label:    book,
                      count:    _count(kFolderTextual, sub),
                      selected: widget.activeFolder == kFolderTextual &&
                          widget.activeSubfolder == sub,
                      primary:  widget.primary,
                      indent:   56,
                      onTap:    () =>
                          widget.onSelectFolder(kFolderTextual, sub),
                    );
                  }),
                  _AddBookButton(
                    primary:  widget.primary,
                    indent:   56,
                    testament: kTextualNT,
                    bookList: booksNT,
                    onAdd:    (book) => widget.onSelectFolder(
                        kFolderTextual, textualSubfolder(kTextualNT, book)),
                  ),
                ],
              ],

              const SizedBox(height: 4),
              const Divider(height: 1, indent: 12, endIndent: 12),
              const SizedBox(height: 4),

              // ── Simple folders ─────────────────────────────────────────────
              ...[kFolderGeneral, kFolderPrayer, kFolderMeeting].map((f) =>
                _SimpleFolderTile(
                  label:    f,
                  icon:     f == kFolderGeneral
                      ? Icons.note_outlined
                      : f == kFolderPrayer
                          ? Icons.volunteer_activism_outlined
                          : Icons.people_outline,
                  count:    _count(f),
                  selected: widget.activeFolder == f,
                  primary:  widget.primary,
                  onTap:    () => widget.onSelectFolder(f, ''),
                )),

              const SizedBox(height: 4),
              const Divider(height: 1, indent: 12, endIndent: 12),
              const SizedBox(height: 4),

              // ── Archive ────────────────────────────────────────────────────
              _SimpleFolderTile(
                label:    'Archive',
                icon:     Icons.archive_outlined,
                count:    _count(kFolderArchive),
                selected: widget.activeFolder == kFolderArchive,
                primary:  widget.primary,
                onTap:    () => widget.onSelectFolder(kFolderArchive, ''),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── TESTAMENT SECTION HEADER ──────────────────────────────────────────────────
// Second-level collapsible row: "Old Testament" / "New Testament"

class _TestamentHeader extends StatelessWidget {
  final String       label;
  final bool         expanded;
  final Color        primary;
  final VoidCallback onTap;

  const _TestamentHeader({
    required this.label,
    required this.expanded,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(28, 6, 12, 6),
      child: Row(children: [
        Icon(
          expanded ? Icons.expand_more : Icons.chevron_right,
          size: 14,
          color: primary.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 4),
        Icon(Icons.auto_stories_outlined, size: 14,
            color: primary.withValues(alpha: 0.6)),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: primary.withValues(alpha: 0.75),
                letterSpacing: 0.3)),
      ]),
    ),
  );
}

// ── PRIVATE TILE WIDGETS ──────────────────────────────────────────────────────

class _FolderHeader extends StatelessWidget {
  final String label; final IconData icon; final int count;
  final bool expanded, selected; final Color primary;
  final VoidCallback onTap;

  const _FolderHeader({
    required this.label, required this.icon, required this.count,
    required this.expanded, required this.selected,
    required this.primary, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      color: selected ? primary.withValues(alpha: 0.08) : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(children: [
        Icon(expanded ? Icons.expand_more : Icons.chevron_right,
            size: 16, color: selected ? primary : textMid),
        const SizedBox(width: 4),
        Icon(icon, size: 17, color: selected ? primary : textMid),
        const SizedBox(width: 8),
        Expanded(child: Text(label,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold,
                color: selected ? primary : textDark))),
        if (count > 0)
          _Badge(count: count, selected: selected, primary: primary),
      ]),
    ),
  );
}

class _SubfolderTile extends StatelessWidget {
  final String label; final int count;
  final bool selected; final Color primary;
  final VoidCallback onTap;
  /// Left padding; defaults to 40 for first-level, pass 56 for textual books.
  final double indent;

  const _SubfolderTile({
    required this.label, required this.count,
    required this.selected, required this.primary, required this.onTap,
    this.indent = 40,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      color: selected ? primary.withValues(alpha: 0.07) : null,
      padding: EdgeInsets.fromLTRB(indent, 7, 12, 7),
      child: Row(children: [
        Expanded(child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: selected ? primary : textDark,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (count > 0)
          Text('$count',
              style: TextStyle(
                  fontSize: 10,
                  color: selected ? primary : textMid)),
      ]),
    ),
  );
}

class _SimpleFolderTile extends StatelessWidget {
  final String label; final IconData icon; final int count;
  final bool selected; final Color primary;
  final VoidCallback onTap;

  const _SimpleFolderTile({
    required this.label, required this.icon, required this.count,
    required this.selected, required this.primary, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      color: selected ? primary.withValues(alpha: 0.08) : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(children: [
        Icon(icon, size: 17, color: selected ? primary : textMid),
        const SizedBox(width: 10),
        Expanded(child: Text(label,
            style: TextStyle(
                fontSize: 13,
                color: selected ? primary : textDark,
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal))),
        if (count > 0)
          _Badge(count: count, selected: selected, primary: primary),
      ]),
    ),
  );
}

class _Badge extends StatelessWidget {
  final int count; final bool selected; final Color primary;
  const _Badge({required this.count, required this.selected, required this.primary});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
        color: selected
            ? primary.withValues(alpha: 0.15)
            : const Color(0xFFE8E8EC),
        borderRadius: BorderRadius.circular(10)),
    child: Text('$count',
        style: TextStyle(
            fontSize: 10,
            color: selected ? primary : textMid,
            fontWeight: FontWeight.bold)),
  );
}

// ── ADD BOOK BUTTON + DIALOG ──────────────────────────────────────────────────

class _AddBookButton extends StatelessWidget {
  final Color        primary;
  final double       indent;
  /// If provided the picker is restricted to this testament and [bookList].
  /// If null it shows both OT + NT tabs (original Expositional behaviour).
  final String?      testament;
  final List<String>? bookList;
  final ValueChanged<String> onAdd;

  const _AddBookButton({
    required this.primary,
    required this.onAdd,
    this.indent    = 40,
    this.testament,
    this.bookList,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => _showPicker(context),
    child: Padding(
      padding: EdgeInsets.fromLTRB(indent, 6, 12, 6),
      child: Row(children: [
        Icon(Icons.add, size: 14, color: primary.withValues(alpha: 0.6)),
        const SizedBox(width: 6),
        Text('Add book…',
            style: TextStyle(
                fontSize: 11, color: primary.withValues(alpha: 0.7))),
      ]),
    ),
  );

  void _showPicker(BuildContext context) {
    if (testament != null && bookList != null) {
      // Single-testament picker (used inside Textual OT / NT sections)
      showDialog(
        context: context,
        builder: (_) => _SingleTestamentBookPickerDialog(
          title:    '${testament == kTextualOT ? 'Old' : 'New'} Testament',
          books:    bookList!,
          primary:  primary,
          onSelect: onAdd,
        ),
      );
    } else {
      // Dual-tab picker (original Expositional behaviour)
      showDialog(
        context: context,
        builder: (_) => _BookPickerDialog(primary: primary, onSelect: onAdd),
      );
    }
  }
}

// ── SINGLE-TESTAMENT BOOK PICKER ─────────────────────────────────────────────

class _SingleTestamentBookPickerDialog extends StatelessWidget {
  final String       title;
  final List<String> books;
  final Color        primary;
  final ValueChanged<String> onSelect;

  const _SingleTestamentBookPickerDialog({
    required this.title,
    required this.books,
    required this.primary,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: SizedBox(width: 320, height: 440,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                  color: primary)),
        ),
        const Divider(height: 1),
        Expanded(child: ListView(
          children: books.map((b) => ListTile(
            dense: true,
            title: Text(b, style: const TextStyle(fontSize: 13)),
            onTap: () { Navigator.pop(context); onSelect(b); },
          )).toList(),
        )),
      ]),
    ),
  );
}

// ── DUAL-TAB BOOK PICKER (Expositional) ──────────────────────────────────────

class _BookPickerDialog extends StatefulWidget {
  final Color primary;
  final ValueChanged<String> onSelect;
  const _BookPickerDialog({required this.primary, required this.onSelect});
  @override State<_BookPickerDialog> createState() => _BookPickerDialogState();
}

class _BookPickerDialogState extends State<_BookPickerDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }
  @override void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: SizedBox(width: 360, height: 480,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Select Bible Book',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                  color: widget.primary)),
        ),
        TabBar(
          controller: _tabs,
          labelColor: widget.primary,
          unselectedLabelColor: textMid,
          indicatorColor: widget.primary,
          tabs: const [
            Tab(text: 'Old Testament'),
            Tab(text: 'New Testament'),
          ],
        ),
        Expanded(child: TabBarView(controller: _tabs, children: [
          _bookList(booksOT),
          _bookList(booksNT),
        ])),
      ]),
    ),
  );

  Widget _bookList(List<String> books) => ListView(
    children: books.map((b) => ListTile(
      dense: true,
      title: Text(b, style: const TextStyle(fontSize: 13)),
      onTap: () { Navigator.pop(context); widget.onSelect(b); },
    )).toList(),
  );
}