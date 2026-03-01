// lib/apps/notes/notes_screen.dart
//
// Full-featured sermon & note manager with:
//   • Folder tree: Topical (with holiday sub-folders) / Expositional / General / Prayer / Meeting / Archive
//   • Rich note model: date, message type, book of Bible, series, tags
//   • Master search across all folders + archive
//   • Scripture verse import (bolls.life via BibleService)
//   • Upload .docx / .txt / .md files into a note
//   • Export to .docx (Node.js) or .pdf (Python reportlab)

import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../models/app_state.dart';
import '../../screens/dashboard_screen.dart';
import '../../services/bible_service.dart';
import '../../theme.dart';
import '../../widgets/scripture_field.dart';

// ══════════════════════════════════════════════════════════════════════════════
// DATA MODEL
// ══════════════════════════════════════════════════════════════════════════════

enum MessageType {
  sermon, teaching, devotional, bibleStudy, smallGroup, prayer, meeting, other
}

const messageTypeLabels = <MessageType, String>{
  MessageType.sermon:     'Sermon',
  MessageType.teaching:   'Teaching',
  MessageType.devotional: 'Devotional',
  MessageType.bibleStudy: 'Bible Study',
  MessageType.smallGroup: 'Small Group',
  MessageType.prayer:     'Prayer',
  MessageType.meeting:    'Meeting',
  MessageType.other:      'Other',
};

// Top-level folder IDs
const kFolderTopical     = 'Topical';
const kFolderExpositional= 'Expositional';
const kFolderGeneral     = 'General';
const kFolderPrayer      = 'Prayer';
const kFolderMeeting     = 'Meeting';
const kFolderArchive     = 'Archive';

// Topical sub-folders (holidays + main topics)
const topicalSubfolders = <String>[
  'Christmas',
  'Easter / Resurrection',
  'Good Friday',
  'Palm Sunday',
  'Pentecost',
  'Thanksgiving',
  'New Year',
  "Mother's Day",
  "Father's Day",
  'Independence Day',
  'Baptism',
  'Communion / Lord\'s Supper',
  'Missions',
  'Marriage & Family',
  'Evangelism',
  'Discipleship',
  'Worship',
  'Stewardship',
  'Grief & Comfort',
  'Salvation',
  'Holy Spirit',
  'Prayer & Fasting',
  'Other Topical',
];

// Books of the Bible for Expositional series picker
const booksOT = <String>[
  'Genesis','Exodus','Leviticus','Numbers','Deuteronomy','Joshua','Judges',
  'Ruth','1 Samuel','2 Samuel','1 Kings','2 Kings','1 Chronicles','2 Chronicles',
  'Ezra','Nehemiah','Esther','Job','Psalms','Proverbs','Ecclesiastes',
  'Song of Solomon','Isaiah','Jeremiah','Lamentations','Ezekiel','Daniel',
  'Hosea','Joel','Amos','Obadiah','Jonah','Micah','Nahum','Habakkuk',
  'Zephaniah','Haggai','Zechariah','Malachi',
];
const booksNT = <String>[
  'Matthew','Mark','Luke','John','Acts','Romans','1 Corinthians','2 Corinthians',
  'Galatians','Ephesians','Philippians','Colossians','1 Thessalonians',
  '2 Thessalonians','1 Timothy','2 Timothy','Titus','Philemon','Hebrews',
  'James','1 Peter','2 Peter','1 John','2 John','3 John','Jude','Revelation',
];

class NoteModel {
  final String id;
  String title;
  String content;
  String folder;        // kFolderTopical / kFolderExpositional / etc.
  String subfolder;     // topic name or book of bible for expositional
  String seriesName;    // Expositional series / title
  MessageType messageType;
  DateTime?   date;
  bool        isPinned;
  bool        isArchived;
  List<String> tags;
  String?     sourceFilePath;  // if imported from a file
  String?     translation;     // Bible translation used
  final DateTime createdAt;
  DateTime       updatedAt;

  NoteModel({
    required this.id,
    required this.title,
    required this.content,
    required this.folder,
    this.subfolder   = '',
    this.seriesName  = '',
    this.messageType = MessageType.sermon,
    this.date,
    this.isPinned    = false,
    this.isArchived  = false,
    this.tags        = const [],
    this.sourceFilePath,
    this.translation,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'content': content,
    'folder': folder, 'subfolder': subfolder, 'seriesName': seriesName,
    'messageType': messageType.name,
    'date': date?.toIso8601String(),
    'isPinned': isPinned, 'isArchived': isArchived, 'tags': tags,
    'sourceFilePath': sourceFilePath, 'translation': translation,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory NoteModel.fromJson(Map<String, dynamic> j) => NoteModel(
    id:          j['id'] ?? const Uuid().v4(),
    title:       j['title']   ?? 'Untitled',
    content:     j['content'] ?? '',
    folder:      j['folder']  ?? kFolderGeneral,
    subfolder:   j['subfolder']  ?? '',
    seriesName:  j['seriesName'] ?? '',
    messageType: MessageType.values.firstWhere(
        (t) => t.name == j['messageType'],
        orElse: () => MessageType.sermon),
    date:        j['date'] != null ? DateTime.tryParse(j['date']) : null,
    isPinned:    j['isPinned']    ?? false,
    isArchived:  j['isArchived']  ?? false,
    tags:        List<String>.from(j['tags'] ?? []),
    sourceFilePath: j['sourceFilePath'],
    translation: j['translation'],
    createdAt:   DateTime.parse(j['createdAt']),
    updatedAt:   DateTime.parse(j['updatedAt']),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<NoteModel> _notes         = [];
  String          _searchQuery   = '';
  String          _activeFolder  = kFolderTopical;
  String          _activeSubfolder = '';
  NoteModel?      _selectedNote;
  bool            _showSearch    = false;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  // ── PERSISTENCE ─────────────────────────────────────────────────────────────

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('notes_v2');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        setState(() => _notes = list.map((e) => NoteModel.fromJson(e)).toList());
      } catch (_) {}
    }
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'notes_v2', jsonEncode(_notes.map((n) => n.toJson()).toList()));
  }

  void _update(VoidCallback fn) { setState(fn); _saveNotes(); }

  // ── FILTERED LIST ────────────────────────────────────────────────────────────

  List<NoteModel> get _visibleNotes {
    final q = _searchQuery.toLowerCase();

    // Global search mode
    if (_showSearch && q.isNotEmpty) {
      return _notes.where((n) =>
        n.title.toLowerCase().contains(q) ||
        n.content.toLowerCase().contains(q) ||
        n.subfolder.toLowerCase().contains(q) ||
        n.seriesName.toLowerCase().contains(q) ||
        n.tags.any((t) => t.toLowerCase().contains(q))
      ).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }

    // Archive folder
    if (_activeFolder == kFolderArchive) {
      return _notes.where((n) => n.isArchived).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }

    return _notes.where((n) {
      if (n.isArchived) return false;
      if (n.folder != _activeFolder) return false;
      if (_activeSubfolder.isNotEmpty && n.subfolder != _activeSubfolder) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
  }

  // ── CREATE ───────────────────────────────────────────────────────────────────

  void _createNote() {
    final now  = DateTime.now();
    final note = NoteModel(
      id:          const Uuid().v4(),
      title:       'Untitled Note',
      content:     '',
      folder:      _activeFolder == kFolderArchive ? kFolderGeneral : _activeFolder,
      subfolder:   _activeSubfolder,
      messageType: _activeFolder == kFolderMeeting
          ? MessageType.meeting
          : _activeFolder == kFolderPrayer
              ? MessageType.prayer
              : MessageType.sermon,
      date:       now,
      translation: context.read<AppState>().bibleService.translationId,
      createdAt:  now,
      updatedAt:  now,
    );
    _update(() {
      _notes.insert(0, note);
      _selectedNote = note;
    });
  }

  // ── ARCHIVE / DELETE ─────────────────────────────────────────────────────────

  void _archiveNote(NoteModel note) {
    _update(() {
      note.isArchived = true;
      note.updatedAt  = DateTime.now();
      if (_selectedNote?.id == note.id) _selectedNote = null;
    });
  }

  void _unarchiveNote(NoteModel note) {
    _update(() {
      note.isArchived = false;
      note.updatedAt  = DateTime.now();
    });
  }

  void _deleteNote(NoteModel note) {
    _update(() {
      _notes.removeWhere((n) => n.id == note.id);
      if (_selectedNote?.id == note.id) _selectedNote = null;
    });
  }

  // ── IMPORT FROM FILE ─────────────────────────────────────────────────────────

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'docx'],
      dialogTitle: 'Import Note File',
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final path = file.path;
    if (path == null) return;

    String content = '';
    String title   = file.name.replaceAll(RegExp(r'\.[^.]+$'), '');

    if (file.extension == 'txt' || file.extension == 'md') {
      content = await File(path).readAsString();
    } else if (file.extension == 'docx') {
      // Extract text from docx using python/pandoc if available
      final tmpOut = '${(await getTemporaryDirectory()).path}/note_import.txt';
      try {
        final res = await Process.run('pandoc',
            [path, '-t', 'plain', '-o', tmpOut]);
        if (res.exitCode == 0) {
          content = await File(tmpOut).readAsString();
        } else {
          content = '[Could not extract text from .docx automatically.\n'
              'Paste your content here and delete this line.]';
        }
      } catch (_) {
        content = '[pandoc not found — paste your content here.]';
      }
    }

    final now  = DateTime.now();
    final note = NoteModel(
      id:          const Uuid().v4(),
      title:       title,
      content:     content,
      folder:      _activeFolder == kFolderArchive ? kFolderGeneral : _activeFolder,
      subfolder:   _activeSubfolder,
      messageType: MessageType.other,
      date:        now,
      sourceFilePath: path,
      createdAt:   now,
      updatedAt:   now,
    );
    _update(() {
      _notes.insert(0, note);
      _selectedNote = note;
    });
  }

  // ── EXPORT ───────────────────────────────────────────────────────────────────

  Future<void> _exportNote(NoteModel note, {required bool pdf}) async {
    final tmpDir    = await getTemporaryDirectory();
    final jsonPath  = '${tmpDir.path}/note_export_input.json';
    final ext       = pdf ? 'pdf' : 'docx';

    // Ask where to save
    final outPath = await FilePicker.platform.saveFile(
      dialogTitle:       'Save ${pdf ? 'PDF' : 'Word'} File',
      fileName:          '${note.title.replaceAll(RegExp(r'[^\w\s]'), '')}_note.$ext',
      allowedExtensions: [ext],
      type: FileType.custom,
    );
    if (outPath == null) return;

    // Write JSON payload
    final payload = {
      ...note.toJson(),
      'translation': note.translation ??
          context.read<AppState>().bibleService.translationId,
    };
    await File(jsonPath).writeAsString(jsonEncode(payload));

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
        content: Text('Exporting…'), behavior: SnackBarBehavior.floating));

    try {
      ProcessResult res;
      if (pdf) {
        // Try Python with reportlab
        final scriptPath = await _extractScript('note_export.py');
        res = await Process.run('python', [scriptPath, jsonPath, outPath]);
        if (res.exitCode != 0) {
          res = await Process.run('python3', [scriptPath, jsonPath, outPath]);
        }
      } else {
        // Node.js docx
        final scriptPath = await _extractScript('note_export.js');
        res = await Process.run('node', [scriptPath, jsonPath, outPath]);
      }

      if (!mounted) return;
      if (res.exitCode == 0 || (res.stdout as String).startsWith('OK:')) {
        messenger.showSnackBar(SnackBar(
          content: Text('Saved to $outPath'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Open',
            onPressed: () async {
              if (Platform.isWindows) {
                await Process.run('explorer', ['/select,', outPath]);
              }
            },
          ),
        ));
      } else {
        throw Exception(res.stderr ?? res.stdout);
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Export failed: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// Copy a bundled asset script to a temp dir so we can run it
  Future<String> _extractScript(String filename) async {
    final tmpDir = await getTemporaryDirectory();
    final dest   = File('${tmpDir.path}/$filename');
    if (!await dest.exists()) {
      // Copy from our app's assets/scripts/ bundle
      // (files are also in the repo root for direct use in dev)
      final srcPath = '${Directory.current.path}/assets/scripts/$filename';
      final src = File(srcPath);
      if (await src.exists()) {
        await src.copy(dest.path);
      }
    }
    return dest.path;
  }

  // ── BUILD ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state     = context.watch<AppState>();
    final primary   = state.brandPrimary;
    final secondary = state.brandSecondary;
    final profile   = state.churchProfile;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: contrastOn(primary),
        title: Row(children: [
          if (profile != null)
            ChurchLogo(logoPath: profile.logoPath,
                primary: primary, secondary: secondary,
                size: 30, borderRadius: 7),
          if (profile != null) const SizedBox(width: 10),
          const Text('Notes & Messages',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        actions: [
          // Global search toggle
          IconButton(
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) _searchQuery = '';
            }),
            icon: Icon(_showSearch ? Icons.search_off : Icons.search,
                color: contrastOn(primary)),
            tooltip: 'Search all notes',
          ),
          IconButton(
            onPressed: _importFile,
            icon: Icon(Icons.upload_file, color: contrastOn(primary)),
            tooltip: 'Import file',
          ),
          IconButton(
            onPressed: _createNote,
            icon: Icon(Icons.add, color: contrastOn(primary)),
            tooltip: 'New note',
          ),
        ],
      ),
      body: Column(children: [
        // Search bar (shown when active)
        if (_showSearch)
          Container(
            color: primary.withValues(alpha: 0.06),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search all notes, folders, and archive…',
                prefixIcon: Icon(Icons.search, color: primary),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        Expanded(
          child: Row(children: [
            // LEFT: Folder tree
            SizedBox(
              width: 220,
              child: _FolderTree(
                activeFolder:    _activeFolder,
                activeSubfolder: _activeSubfolder,
                notes:           _notes,
                primary:         primary,
                onSelectFolder: (folder, sub) => setState(() {
                  _activeFolder    = folder;
                  _activeSubfolder = sub;
                  _selectedNote    = null;
                  _showSearch      = false;
                  _searchQuery     = '';
                }),
              ),
            ),
            const VerticalDivider(width: 1),
            // CENTER: Note list
            SizedBox(
              width: 280,
              child: _NoteList(
                notes:        _visibleNotes,
                selectedNote: _selectedNote,
                primary:      primary,
                secondary:    secondary,
                showingSearch: _showSearch && _searchQuery.isNotEmpty,
                onSelect:     (n) => setState(() => _selectedNote = n),
                onArchive:    _archiveNote,
                onUnarchive:  _unarchiveNote,
                onDelete:     _deleteNote,
                onExport:     (n, pdf) => _exportNote(n, pdf: pdf),
                onNew:        _createNote,
                activeFolder: _activeFolder,
              ),
            ),
            const VerticalDivider(width: 1),
            // RIGHT: Editor
            Expanded(
              child: _selectedNote != null
                  ? _NoteEditor(
                      key:         ValueKey(_selectedNote!.id),
                      note:        _selectedNote!,
                      primary:     primary,
                      secondary:   secondary,
                      bibleService: state.bibleService,
                      onChanged:   () => _update(() =>
                          _selectedNote!.updatedAt = DateTime.now()),
                      onArchive:   () => _archiveNote(_selectedNote!),
                      onExport:    (pdf) =>
                          _exportNote(_selectedNote!, pdf: pdf),
                    )
                  : _EmptyEditor(primary: primary),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FOLDER TREE
// ══════════════════════════════════════════════════════════════════════════════

class _FolderTree extends StatefulWidget {
  final String              activeFolder;
  final String              activeSubfolder;
  final List<NoteModel>     notes;
  final Color               primary;
  final void Function(String folder, String sub) onSelectFolder;

  const _FolderTree({
    required this.activeFolder, required this.activeSubfolder,
    required this.notes, required this.primary, required this.onSelectFolder,
  });
  @override State<_FolderTree> createState() => _FolderTreeState();
}

class _FolderTreeState extends State<_FolderTree> {
  final Set<String> _expanded = {kFolderTopical, kFolderExpositional};

  int _count(String folder, [String sub = '']) => widget.notes.where((n) {
    if (folder == kFolderArchive) return n.isArchived;
    if (n.isArchived) return false;
    if (n.folder != folder) return false;
    if (sub.isNotEmpty) return n.subfolder == sub;
    return true;
  }).length;

  // Collect unique expositional books actually used
  List<String> get _expositionalBooks {
    final books = widget.notes
        .where((n) => n.folder == kFolderExpositional && !n.isArchived)
        .map((n) => n.subfolder)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()..sort();
    return books;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F9FA),
      child: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // ── Topical ──────────────────────────────────────────────────
              _FolderHeader(
                label:    'Topical',
                icon:     Icons.book_outlined,
                count:    _count(kFolderTopical),
                expanded: _expanded.contains(kFolderTopical),
                selected: widget.activeFolder == kFolderTopical &&
                    widget.activeSubfolder.isEmpty,
                primary:  widget.primary,
                onTap: () {
                  setState(() {
                    if (_expanded.contains(kFolderTopical)) {
                      _expanded.remove(kFolderTopical);
                    } else {
                      _expanded.add(kFolderTopical);
                    }
                  });
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

              // ── Expositional ─────────────────────────────────────────────
              _FolderHeader(
                label:    'Expositional',
                icon:     Icons.menu_book_outlined,
                count:    _count(kFolderExpositional),
                expanded: _expanded.contains(kFolderExpositional),
                selected: widget.activeFolder == kFolderExpositional &&
                    widget.activeSubfolder.isEmpty,
                primary:  widget.primary,
                onTap: () {
                  setState(() {
                    if (_expanded.contains(kFolderExpositional)) {
                      _expanded.remove(kFolderExpositional);
                    } else {
                      _expanded.add(kFolderExpositional);
                    }
                  });
                  widget.onSelectFolder(kFolderExpositional, '');
                },
              ),
              if (_expanded.contains(kFolderExpositional)) ...[
                // Show books that have notes
                ..._expositionalBooks.map((book) => _SubfolderTile(
                  label:    book,
                  count:    _count(kFolderExpositional, book),
                  selected: widget.activeFolder == kFolderExpositional &&
                      widget.activeSubfolder == book,
                  primary:  widget.primary,
                  onTap:    () =>
                      widget.onSelectFolder(kFolderExpositional, book),
                )),
                // Add new book button
                _AddBookButton(
                  primary: widget.primary,
                  onAdd:   (book) =>
                      widget.onSelectFolder(kFolderExpositional, book),
                ),
              ],

              const SizedBox(height: 4),
              const Divider(height: 1, indent: 12, endIndent: 12),
              const SizedBox(height: 4),

              // ── Simple folders ────────────────────────────────────────────
              ...[kFolderGeneral, kFolderPrayer, kFolderMeeting].map((f) =>
                _SimpleFolderTile(
                  label: f,
                  icon: f == kFolderGeneral
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

              // ── Archive ───────────────────────────────────────────────────
              _SimpleFolderTile(
                label: 'Archive',
                icon:  Icons.archive_outlined,
                count: _count(kFolderArchive),
                selected: widget.activeFolder == kFolderArchive,
                primary:  widget.primary,
                onTap: () => widget.onSelectFolder(kFolderArchive, ''),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _FolderHeader extends StatelessWidget {
  final String     label;
  final IconData   icon;
  final int        count;
  final bool       expanded;
  final bool       selected;
  final Color      primary;
  final VoidCallback onTap;

  const _FolderHeader({
    required this.label, required this.icon, required this.count,
    required this.expanded, required this.selected, required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: selected
                      ? primary.withValues(alpha: 0.15)
                      : const Color(0xFFE8E8EC),
                  borderRadius: BorderRadius.circular(10)),
              child: Text('$count',
                  style: TextStyle(
                      fontSize: 10, color: selected ? primary : textMid,
                      fontWeight: FontWeight.bold)),
            ),
        ]),
      ),
    );
  }
}

class _SubfolderTile extends StatelessWidget {
  final String label;
  final int    count;
  final bool   selected;
  final Color  primary;
  final VoidCallback onTap;

  const _SubfolderTile({
    required this.label, required this.count,
    required this.selected, required this.primary, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? primary.withValues(alpha: 0.07) : null,
        padding: const EdgeInsets.fromLTRB(40, 7, 12, 7),
        child: Row(children: [
          Expanded(child: Text(label,
              style: TextStyle(fontSize: 12,
                  color: selected ? primary : textDark,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (count > 0)
            Text('$count',
                style: TextStyle(fontSize: 10,
                    color: selected ? primary : textMid)),
        ]),
      ),
    );
  }
}

class _SimpleFolderTile extends StatelessWidget {
  final String   label;
  final IconData icon;
  final int      count;
  final bool     selected;
  final Color    primary;
  final VoidCallback onTap;

  const _SimpleFolderTile({
    required this.label, required this.icon, required this.count,
    required this.selected, required this.primary, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? primary.withValues(alpha: 0.08) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(children: [
          Icon(icon, size: 17, color: selected ? primary : textMid),
          const SizedBox(width: 10),
          Expanded(child: Text(label,
              style: TextStyle(fontSize: 13,
                  color: selected ? primary : textDark,
                  fontWeight: selected
                      ? FontWeight.bold : FontWeight.normal))),
          if (count > 0)
            Container(
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
            ),
        ]),
      ),
    );
  }
}

class _AddBookButton extends StatelessWidget {
  final Color primary;
  final ValueChanged<String> onAdd;

  const _AddBookButton({required this.primary, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showBookPicker(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 6, 12, 6),
        child: Row(children: [
          Icon(Icons.add, size: 14, color: primary.withValues(alpha: 0.6)),
          const SizedBox(width: 6),
          Text('Add book…',
              style: TextStyle(fontSize: 11,
                  color: primary.withValues(alpha: 0.7))),
        ]),
      ),
    );
  }

  void _showBookPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _BookPickerDialog(
        primary: primary,
        onSelect: onAdd,
      ),
    );
  }
}

class _BookPickerDialog extends StatefulWidget {
  final Color primary;
  final ValueChanged<String> onSelect;
  const _BookPickerDialog({required this.primary, required this.onSelect});
  @override State<_BookPickerDialog> createState() => _BookPickerDialogState();
}

class _BookPickerDialogState extends State<_BookPickerDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  @override void initState() { super.initState(); _tabs = TabController(length: 2, vsync: this); }
  @override void dispose()  { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
            tabs: const [Tab(text: 'Old Testament'),
                         Tab(text: 'New Testament')],
          ),
          Expanded(child: TabBarView(controller: _tabs, children: [
            _bookList(booksOT),
            _bookList(booksNT),
          ])),
        ]),
      ),
    );
  }

  Widget _bookList(List<String> books) => ListView(
    children: books.map((b) => ListTile(
      dense: true,
      title: Text(b, style: const TextStyle(fontSize: 13)),
      onTap: () { Navigator.pop(context); widget.onSelect(b); },
    )).toList(),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// NOTE LIST
// ══════════════════════════════════════════════════════════════════════════════

class _NoteList extends StatelessWidget {
  final List<NoteModel> notes;
  final NoteModel?      selectedNote;
  final Color           primary;
  final Color           secondary;
  final bool            showingSearch;
  final String          activeFolder;
  final ValueChanged<NoteModel> onSelect;
  final ValueChanged<NoteModel> onArchive;
  final ValueChanged<NoteModel> onUnarchive;
  final ValueChanged<NoteModel> onDelete;
  final void Function(NoteModel, bool) onExport;
  final VoidCallback    onNew;

  const _NoteList({
    required this.notes, required this.selectedNote,
    required this.primary, required this.secondary,
    required this.showingSearch, required this.activeFolder,
    required this.onSelect, required this.onArchive,
    required this.onUnarchive, required this.onDelete,
    required this.onExport, required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFAFAFB),
      child: Column(children: [
        // List header
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
          child: Row(children: [
            Text(showingSearch ? 'Search Results' : activeFolder,
                style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.bold, color: textMid)),
            const Spacer(),
            Text('${notes.length}',
                style: const TextStyle(fontSize: 11, color: textMid)),
            const SizedBox(width: 4),
            if (!showingSearch)
              IconButton(
                icon: Icon(Icons.add, size: 18, color: primary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: onNew,
                tooltip: 'New note',
              ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: notes.isEmpty
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.note_add_outlined, size: 40,
                        color: primary.withValues(alpha: 0.2)),
                    const SizedBox(height: 10),
                    Text(showingSearch ? 'No results' : 'No notes yet',
                        style: TextStyle(
                            color: primary.withValues(alpha: 0.4))),
                  ],
                ))
              : ListView.separated(
                  itemCount: notes.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 14),
                  itemBuilder: (_, i) => _NoteListTile(
                    note:     notes[i],
                    selected: selectedNote?.id == notes[i].id,
                    primary:  primary,
                    secondary: secondary,
                    onTap:    () => onSelect(notes[i]),
                    onArchive: () => onArchive(notes[i]),
                    onUnarchive: () => onUnarchive(notes[i]),
                    onDelete: () => onDelete(notes[i]),
                    onExportDocx: () => onExport(notes[i], false),
                    onExportPdf:  () => onExport(notes[i], true),
                  ),
                ),
        ),
      ]),
    );
  }
}

class _NoteListTile extends StatelessWidget {
  final NoteModel  note;
  final bool       selected;
  final Color      primary;
  final Color      secondary;
  final VoidCallback onTap, onArchive, onUnarchive, onDelete;
  final VoidCallback onExportDocx, onExportPdf;

  const _NoteListTile({
    required this.note, required this.selected,
    required this.primary, required this.secondary,
    required this.onTap, required this.onArchive, required this.onUnarchive,
    required this.onDelete, required this.onExportDocx, required this.onExportPdf,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = note.date != null
        ? DateFormat('MMM d, y').format(note.date!)
        : DateFormat('MMM d').format(note.updatedAt);

    return GestureDetector(
      onTap: onTap,
      onSecondaryTapUp: (d) => _showContextMenu(context, d.globalPosition),
      child: Container(
        color: selected ? primary.withValues(alpha: 0.07) : null,
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Pin indicator
          if (note.isPinned)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: Icon(Icons.push_pin, size: 12, color: secondary),
            ),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(note.title,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: selected ? primary : textDark),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              if (note.subfolder.isNotEmpty)
                Text(note.subfolder,
                    style: TextStyle(fontSize: 10,
                        color: secondary, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(note.content.isEmpty
                  ? 'No content'
                  : note.content.replaceAll('\n', ' '),
                  style: const TextStyle(fontSize: 11, color: textMid),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(
                      messageTypeLabels[note.messageType] ?? '',
                      style: TextStyle(
                          fontSize: 9, color: primary,
                          fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                Text(dateStr,
                    style: const TextStyle(fontSize: 10, color: textMid)),
              ]),
            ],
          )),
        ]),
      ),
    );
  }

  void _showContextMenu(BuildContext ctx, Offset pos) async {
    final result = await showMenu<String>(
      context: ctx,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        const PopupMenuItem(value: 'docx',
            child: Row(children: [
              Icon(Icons.description_outlined, size: 16),
              SizedBox(width: 8), Text('Export as Word')])),
        const PopupMenuItem(value: 'pdf',
            child: Row(children: [
              Icon(Icons.picture_as_pdf_outlined, size: 16),
              SizedBox(width: 8), Text('Export as PDF')])),
        const PopupMenuItem(value: 'archive',
            child: Row(children: [
              Icon(Icons.archive_outlined, size: 16),
              SizedBox(width: 8), Text('Archive')])),
        const PopupMenuItem(value: 'delete',
            child: Row(children: [
              Icon(Icons.delete_outline, size: 16, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Colors.red))])),
      ],
    );
    switch (result) {
      case 'docx':    onExportDocx(); break;
      case 'pdf':     onExportPdf();  break;
      case 'archive': note.isArchived ? onUnarchive() : onArchive(); break;
      case 'delete':  onDelete(); break;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// NOTE EDITOR
// ══════════════════════════════════════════════════════════════════════════════

class _NoteEditor extends StatefulWidget {
  final NoteModel    note;
  final Color        primary;
  final Color        secondary;
  final BibleService bibleService;
  final VoidCallback onChanged;
  final VoidCallback onArchive;
  final ValueChanged<bool> onExport;  // true=pdf

  const _NoteEditor({
    super.key,
    required this.note, required this.primary, required this.secondary,
    required this.bibleService, required this.onChanged,
    required this.onArchive, required this.onExport,
  });

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;
  late TextEditingController _seriesCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl   = TextEditingController(text: widget.note.title);
    _contentCtrl = TextEditingController(text: widget.note.content);
    _seriesCtrl  = TextEditingController(text: widget.note.seriesName);
    for (final c in [_titleCtrl, _contentCtrl, _seriesCtrl]) {
      c.addListener(_sync);
    }
  }

  void _sync() {
    widget.note.title      = _titleCtrl.text;
    widget.note.content    = _contentCtrl.text;
    widget.note.seriesName = _seriesCtrl.text;
    widget.onChanged();
  }

  @override
  void dispose() {
    for (final c in [_titleCtrl, _contentCtrl, _seriesCtrl]) {
      c.removeListener(_sync);
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note      = widget.note;
    final primary   = widget.primary;
    final secondary = widget.secondary;

    return Column(children: [
      // ── Toolbar ───────────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFEAEDF3))),
        ),
        child: Row(children: [
          // Message type chip
          _MetaChip(
            label: messageTypeLabels[note.messageType] ?? '',
            icon: Icons.label_outline,
            color: primary,
            onTap: () => _pickMessageType(),
          ),
          const SizedBox(width: 8),
          // Date chip
          _MetaChip(
            label: note.date != null
                ? DateFormat('MMM d, y').format(note.date!)
                : 'Set date',
            icon: Icons.calendar_today_outlined,
            color: primary,
            onTap: () => _pickDate(),
          ),
          const SizedBox(width: 8),
          // Translation chip
          _MetaChip(
            label: note.translation ?? widget.bibleService.translationId,
            icon: Icons.menu_book_outlined,
            color: secondary,
            onTap: () => _pickTranslation(),
          ),
          const Spacer(),
          // Pin
          IconButton(
            icon: Icon(
                note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: 18,
                color: note.isPinned ? secondary : textMid),
            onPressed: () {
              note.isPinned = !note.isPinned;
              widget.onChanged();
              setState(() {});
            },
            tooltip: note.isPinned ? 'Unpin' : 'Pin',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
          // Import verse button
          IconButton(
            icon: Icon(Icons.format_quote_outlined, size: 18, color: primary),
            onPressed: _showVerseImport,
            tooltip: 'Import verse',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
          // Export menu
          PopupMenuButton<String>(
            icon: Icon(Icons.ios_share_outlined, size: 18, color: primary),
            tooltip: 'Export',
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'docx',
                  child: Row(children: [
                    Icon(Icons.description_outlined, size: 16),
                    SizedBox(width: 8), Text('Export as Word (.docx)')])),
              const PopupMenuItem(value: 'pdf',
                  child: Row(children: [
                    Icon(Icons.picture_as_pdf_outlined, size: 16),
                    SizedBox(width: 8), Text('Export as PDF')])),
            ],
            onSelected: (v) => widget.onExport(v == 'pdf'),
          ),
          // Archive
          IconButton(
            icon: Icon(Icons.archive_outlined, size: 18, color: textMid),
            onPressed: widget.onArchive,
            tooltip: 'Archive note',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
        ]),
      ),

      // ── Expositional/Topical meta bar ─────────────────────────────────────
      if (note.folder == kFolderExpositional || note.subfolder.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: const Color(0xFFF0F4FF),
          child: Row(children: [
            if (note.folder == kFolderExpositional) ...[
              Icon(Icons.menu_book_outlined, size: 14, color: primary),
              const SizedBox(width: 6),
              Text(note.subfolder.isNotEmpty ? note.subfolder : 'No book set',
                  style: TextStyle(fontSize: 12,
                      color: primary, fontWeight: FontWeight.w600)),
              const SizedBox(width: 16),
              Expanded(child: TextFormField(
                controller: _seriesCtrl,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  hintText: 'Series or message title…',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              )),
            ] else ...[
              Icon(Icons.label_outline, size: 14, color: secondary),
              const SizedBox(width: 6),
              Text(note.subfolder,
                  style: TextStyle(fontSize: 12,
                      color: secondary, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),

      // ── Title ─────────────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        color: Colors.white,
        child: TextField(
          controller: _titleCtrl,
          style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.bold, color: primary),
          decoration: const InputDecoration(
            hintText: 'Note title…',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),

      // ── Content ───────────────────────────────────────────────────────────
      Expanded(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: ScriptureField(
            controller:   _contentCtrl,
            bibleService: widget.bibleService,
            primary:      primary,
            maxLines:     20,
            expands:      true,
            style: const TextStyle(
                fontSize: 15, height: 1.75, color: textDark),
            decoration: const InputDecoration(
              hintText: 'Start writing… Type a verse like "John 3:16" to auto-import it.',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (_) => _sync(),
          ),
        ),
      ),

      // ── Status bar ────────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        color: const Color(0xFFF8F9FA),
        child: Row(children: [
          Text(note.folder,
              style: const TextStyle(fontSize: 10, color: textMid)),
          if (note.subfolder.isNotEmpty) ...[
            const Text(' › ',
                style: TextStyle(fontSize: 10, color: textMid)),
            Text(note.subfolder,
                style: const TextStyle(fontSize: 10, color: textMid)),
          ],
          const Spacer(),
          Text(
            '${_contentCtrl.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length} words',
            style: const TextStyle(fontSize: 10, color: textMid),
          ),
          const SizedBox(width: 12),
          Text(
            'Saved ${DateFormat('h:mm a').format(note.updatedAt)}',
            style: const TextStyle(fontSize: 10, color: textMid),
          ),
        ]),
      ),
    ]);
  }

  // ── DIALOGS ───────────────────────────────────────────────────────────────

  Future<void> _pickMessageType() async {
    final result = await showDialog<MessageType>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text('Message Type',
            style: TextStyle(color: widget.primary)),
        children: MessageType.values.map((t) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, t),
          child: Row(children: [
            if (widget.note.messageType == t)
              Icon(Icons.check, size: 16, color: widget.primary)
            else
              const SizedBox(width: 16),
            const SizedBox(width: 8),
            Text(messageTypeLabels[t] ?? ''),
          ]),
        )).toList(),
      ),
    );
    if (result != null) {
      widget.note.messageType = result;
      widget.onChanged();
      setState(() {});
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.note.date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.light(primary: widget.primary)),
        child: child!,
      ),
    );
    if (picked != null) {
      widget.note.date = picked;
      widget.onChanged();
      setState(() {});
    }
  }

  Future<void> _pickTranslation() async {
    final svc  = widget.bibleService;
    final list = await svc.fetchTranslations();
    if (!mounted) return;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TranslationPickerDialog(
        translations: list,
        current:      widget.note.translation ?? svc.translationId,
        primary:      widget.primary,
      ),
    );
    if (result != null) {
      widget.note.translation = result;
      widget.onChanged();
      setState(() {});
    }
  }

  Future<void> _showVerseImport() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _VerseImportDialog(
        bibleService: widget.bibleService,
        primary:      widget.primary,
      ),
    );
    if (result != null && result.isNotEmpty) {
      final pos = _contentCtrl.selection.baseOffset;
      final text = _contentCtrl.text;
      final newText = pos < 0 || pos > text.length
          ? '$text\n$result\n'
          : '${text.substring(0, pos)}\n$result\n${text.substring(pos)}';
      _contentCtrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
            offset: (pos < 0 ? text.length : pos) + result.length + 2),
      );
      _sync();
    }
  }
}

// ── META CHIP ─────────────────────────────────────────────────────────────────

class _MetaChip extends StatelessWidget {
  final String     label;
  final IconData   icon;
  final Color      color;
  final VoidCallback onTap;

  const _MetaChip({
    required this.label, required this.icon,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 11, color: color,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ── VERSE IMPORT DIALOG ───────────────────────────────────────────────────────

class _VerseImportDialog extends StatefulWidget {
  final BibleService bibleService;
  final Color        primary;
  const _VerseImportDialog({required this.bibleService, required this.primary});
  @override State<_VerseImportDialog> createState() =>
      _VerseImportDialogState();
}

class _VerseImportDialogState extends State<_VerseImportDialog> {
  final _searchCtrl = TextEditingController();
  List<VerseSearchResult> _results = [];
  bool   _loading = false;
  String _error   = '';

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _loading = true; _error = ''; _results = []; });
    try {
      final res = await widget.bibleService.searchVerses(q, limit: 20);
      setState(() { _results = res; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = 'Search failed: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(width: 460, height: 520,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.menu_book_outlined, color: primary),
              const SizedBox(width: 8),
              Text('Import Verse',
                  style: TextStyle(fontSize: 16,
                      fontWeight: FontWeight.bold, color: primary)),
              const Spacer(),
              Text(widget.bibleService.translationId,
                  style: TextStyle(fontSize: 11,
                      color: primary.withValues(alpha: 0.6),
                      fontWeight: FontWeight.bold)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: TextField(
                controller: _searchCtrl,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: 'Search words or type "John 3:16"…',
                  prefixIcon: Icon(Icons.search, color: primary),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: primary)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              )),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _search,
                style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: contrastOn(primary)),
                child: const Text('Search'),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(padding: EdgeInsets.all(24),
                child: CircularProgressIndicator()),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final r = _results[i];
                return ListTile(
                  dense: true,
                  title: Text(r.reference,
                      style: TextStyle(fontSize: 12,
                          fontWeight: FontWeight.bold, color: primary)),
                  subtitle: Text(r.text,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                  onTap: () async {
                    // Fetch full verse text formatted for insertion
                    final text = await widget.bibleService.fetchVerseText(
                      bookId:     r.bookId,
                      chapter:    r.chapter,
                      verseStart: r.verse,
                      verseEnd:   r.verse,
                      bookName:   r.bookName,
                    );
                    if (context.mounted) {
                      Navigator.pop(context, text ?? r.text);
                    }
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ── TRANSLATION PICKER ────────────────────────────────────────────────────────

class _TranslationPickerDialog extends StatefulWidget {
  final List<BibleTranslation> translations;
  final String current;
  final Color  primary;
  const _TranslationPickerDialog({
    required this.translations, required this.current, required this.primary});
  @override State<_TranslationPickerDialog> createState() =>
      _TranslationPickerDialogState();
}

class _TranslationPickerDialogState extends State<_TranslationPickerDialog> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final filtered = widget.translations
        .where((t) =>
            t.id.toLowerCase().contains(_q.toLowerCase()) ||
            t.name.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    final popular = filtered
        .where((t) => popularTranslationIds.contains(t.id))
        .toList();
    final others = filtered
        .where((t) => !popularTranslationIds.contains(t.id))
        .toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(width: 420, height: 540,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16,16,16,8),
            child: Text('Choose Translation',
                style: TextStyle(fontSize: 16,
                    fontWeight: FontWeight.bold, color: widget.primary)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'Search translations…',
                prefixIcon: Icon(Icons.search, color: widget.primary),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                filled: true, fillColor: const Color(0xFFF5F5F5),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: ListView(children: [
            if (popular.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('POPULAR', style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.bold,
                    color: textMid, letterSpacing: 1.2)),
              ),
              ...popular.map((t) => _TransTile(
                  t: t, current: widget.current,
                  primary: widget.primary)),
            ],
            if (others.isNotEmpty && _q.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('ALL', style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.bold,
                    color: textMid, letterSpacing: 1.2)),
              ),
              ...others.map((t) => _TransTile(
                  t: t, current: widget.current,
                  primary: widget.primary)),
            ],
          ])),
        ]),
      ),
    );
  }
}

class _TransTile extends StatelessWidget {
  final BibleTranslation t;
  final String current;
  final Color  primary;
  const _TransTile({required this.t, required this.current, required this.primary});
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    selected: t.id == current,
    selectedTileColor: primary.withValues(alpha: 0.07),
    leading: Container(
      width: 44, height: 28,
      decoration: BoxDecoration(
          color: t.id == current ? primary : const Color(0xFFEEEEEE),
          borderRadius: BorderRadius.circular(4)),
      alignment: Alignment.center,
      child: Text(t.shortName,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
              color: t.id == current ? contrastOn(primary) : textMid)),
    ),
    title: Text(t.name,
        style: const TextStyle(fontSize: 12), maxLines: 1,
        overflow: TextOverflow.ellipsis),
    trailing: t.id == current
        ? Icon(Icons.check, color: primary, size: 16) : null,
    onTap: () => Navigator.pop(context, t.id),
  );
}

// ── EMPTY EDITOR ──────────────────────────────────────────────────────────────

class _EmptyEditor extends StatelessWidget {
  final Color primary;
  const _EmptyEditor({required this.primary});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.edit_note_outlined, size: 56,
          color: primary.withValues(alpha: 0.15)),
      const SizedBox(height: 16),
      Text('Select a note or create a new one',
          style: TextStyle(color: primary.withValues(alpha: 0.35),
              fontSize: 14)),
    ]),
  );
}