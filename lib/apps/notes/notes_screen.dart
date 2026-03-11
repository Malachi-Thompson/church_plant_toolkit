// lib/apps/notes/notes_screen.dart
//
// Top-level coordinator for the Notes & Messages feature.
// This file owns state and business logic only — no layout widgets live here.
//
// To add a new feature:
//   • New folder type     → note_constants.dart + widgets/folder_tree.dart
//   • New note metadata   → note_model.dart + widgets/note_editor.dart toolbar
//   • New dialog          → dialogs/ + call from note_editor.dart
//   • New export format   → note_exporter.dart + _exportNote() below

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../models/app_state.dart';
import '../../screens/dashboard_screen.dart';
import '../../theme.dart';
import 'note_constants.dart';
import 'note_exporter.dart' show exportDocx, exportOdt, exportHtmlForPdf, extractTextFromDocxBytes, extractHtmlFromDocxBytes;
import 'note_model.dart';
import 'widgets/folder_tree.dart';
import 'widgets/note_editor.dart';
import 'widgets/note_list.dart';
import 'widgets/shared_widgets.dart';

// ── MOBILE PANE ENUM ─────────────────────────────────────────────────────────

enum _MobilePane { folders, list, editor }

// ══════════════════════════════════════════════════════════════════════════════
// SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<NoteModel> _notes          = [];
  String          _searchQuery    = '';
  String          _activeFolder   = kFolderTopical;
  String          _activeSubfolder = '';
  NoteModel?      _selectedNote;
  bool            _showSearch     = false;
  _MobilePane     _mobilePane     = _MobilePane.list;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  // ── PERSISTENCE ───────────────────────────────────────────────────────────

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('notes_v2');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        setState(() =>
            _notes = list.map((e) => NoteModel.fromJson(e)).toList());
      } catch (_) {}
    }
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'notes_v2', jsonEncode(_notes.map((n) => n.toJson()).toList()));
  }

  void _update(VoidCallback fn) {
    setState(fn);
    _saveNotes();
  }

  // ── FILTERED NOTE LIST ────────────────────────────────────────────────────

  List<NoteModel> get _visibleNotes {
    final q = _searchQuery.toLowerCase();

    // Global search across all folders + archive
    if (_showSearch && q.isNotEmpty) {
      return _notes.where((n) =>
          n.title.toLowerCase().contains(q) ||
          n.content.toLowerCase().contains(q) ||
          n.subfolder.toLowerCase().contains(q) ||
          n.seriesName.toLowerCase().contains(q) ||
          n.tags.any((t) => t.toLowerCase().contains(q))).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }

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

  // ── CREATE ────────────────────────────────────────────────────────────────

  void _createNote() {
    final now  = DateTime.now();
    final note = NoteModel(
      id:          const Uuid().v4(),
      title:       'Untitled Note',
      content:     '',
      folder:      _activeFolder == kFolderArchive
          ? kFolderGeneral
          : _activeFolder,
      subfolder:   _activeSubfolder,
      messageType: _activeFolder == kFolderMeeting
          ? MessageType.meeting
          : _activeFolder == kFolderPrayer
              ? MessageType.prayer
              : MessageType.sermon,
      date:        now,
      translation: context.read<AppState>().bibleService.translationId,
      createdAt:   now,
      updatedAt:   now,
    );
    _update(() {
      _notes.insert(0, note);
      _selectedNote = note;
    });
  }

  // ── ARCHIVE / DELETE ──────────────────────────────────────────────────────

  void _archiveNote(NoteModel note) => _update(() {
    note.isArchived = true;
    note.updatedAt  = DateTime.now();
    if (_selectedNote?.id == note.id) _selectedNote = null;
  });

  void _unarchiveNote(NoteModel note) => _update(() {
    note.isArchived = false;
    note.updatedAt  = DateTime.now();
  });

  void _deleteNote(NoteModel note) => _update(() {
    _notes.removeWhere((n) => n.id == note.id);
    if (_selectedNote?.id == note.id) _selectedNote = null;
  });

  // ── IMPORT FROM FILE ──────────────────────────────────────────────────────

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'docx', 'odt', 'pdf'],
      dialogTitle: 'Import Note File',
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final ext  = (file.extension ?? '').toLowerCase();
    final title = file.name.replaceAll(RegExp(r'\.[^.]+$'), '');

    // Read bytes — works on all platforms
    Uint8List? bytes;
    if (file.bytes != null) {
      bytes = file.bytes!;
    } else if (file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) return;

    String content = '';
    if (ext == 'txt' || ext == 'md') {
      content = utf8.decode(bytes);
    } else if (ext == 'docx') {
      // Extract as rich HTML to preserve formatting in the WebView editor.
      content = extractHtmlFromDocxBytes(bytes) ??
          extractTextFromDocxBytes(bytes) ??
          '[Could not extract text from .docx — paste your content here.]';
    }
    // ODT: content stays empty initially; the WebView editor starts blank.
    // PDF: content stays empty; bytes stored for inline viewer.

    final now  = DateTime.now();
    final note = NoteModel(
      id:              const Uuid().v4(),
      title:           title,
      content:         content,
      folder:          _activeFolder == kFolderArchive
          ? kFolderGeneral
          : _activeFolder,
      subfolder:       _activeSubfolder,
      messageType:     MessageType.other,
      date:            now,
      sourceFilePath:  file.path,
      sourceFileType:  ext,
      sourceFileBytes: bytes,
      exportFormat:    ext == 'odt' ? 'odt' : 'docx',
      createdAt:       now,
      updatedAt:       now,
    );
    _update(() {
      _notes.insert(0, note);
      _selectedNote = note;
    });

    if (mounted && MediaQuery.of(context).size.width < 700) {
      setState(() => _mobilePane = _MobilePane.editor);
    }
  }

  // ── EXPORT ────────────────────────────────────────────────────────────────

  Future<void> _exportNote(NoteModel note, {required String format}) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
        content: Text('Exporting…'),
        behavior: SnackBarBehavior.floating));

    // For rich-HTML content (docx/odt imported notes) we export the stored
    // HTML directly; for plain-text notes we use the content as-is.
    final payload = {
      ...note.toJson(),
      'translation': note.translation ??
          context.read<AppState>().bibleService.translationId,
    };
    final safe = note.title.replaceAll(RegExp(r'[^\w\s]'), '').trim();
    final isPdf = format == 'pdf';
    final isOdt = format == 'odt';
    final ext   = isPdf ? 'pdf' : isOdt ? 'odt' : 'docx';

    try {
      final bool isMobile =
          !kIsWeb && (Platform.isAndroid || Platform.isIOS);

      if (isMobile) {
        final tmpDir  = await getTemporaryDirectory();
        final outPath = '${tmpDir.path}/${safe}_note.$ext';
        if (isPdf) {
          await exportHtmlForPdf(payload);
        } else if (isOdt) {
          await exportOdt(payload, outPath);
          final uri = Uri.file(outPath);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        } else {
          await exportDocx(payload, outPath);
          final uri = Uri.file(outPath);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      } else {
        final outPath = await FilePicker.platform.saveFile(
          dialogTitle:       'Save ${isPdf ? 'PDF' : isOdt ? 'ODT' : 'Word'} File',
          fileName:          '${safe}_note.$ext',
          allowedExtensions: [ext],
          type: FileType.custom,
        );
        if (outPath == null) return;

        if (isPdf) {
          await exportHtmlForPdf(payload);
        } else if (isOdt) {
          await exportOdt(payload, outPath);
        } else {
          await exportDocx(payload, outPath);
        }

        if (!mounted) return;
        messenger.showSnackBar(SnackBar(
          content: Text('Saved to $outPath'),
          behavior: SnackBarBehavior.floating,
          action: (!kIsWeb && Platform.isWindows)
              ? SnackBarAction(
                  label: 'Open',
                  onPressed: () =>
                      Process.run('explorer', ['/select,', outPath]),
                )
              : null,
        ));
        return;
      }

      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(isPdf
            ? 'Print page opened — use File → Print → Save as PDF'
            : 'File exported successfully'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Export failed: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ── SAVE BACK TO SOURCE FILE ──────────────────────────────────────────────
  //
  // Writes the note's current content back to the original imported file.
  // Supported for txt, md, and docx.  PDFs are never written back.

  Future<void> _saveBack(NoteModel note) async {
    final path = note.sourceFilePath;
    final ext  = note.sourceFileType;
    if (path == null || ext == null || ext == 'pdf') return;

    if (ext == 'txt' || ext == 'md') {
      await File(path).writeAsString(note.content, flush: true);
    } else if (ext == 'docx') {
      // Re-export note content as a fresh .docx into the original path.
      final payload = {
        ...note.toJson(),
        'translation': note.translation ??
            context.read<AppState>().bibleService.translationId,
      };
      await exportDocx(payload, path);
    } else if (ext == 'odt') {
      final payload = {
        ...note.toJson(),
        'translation': note.translation ??
            context.read<AppState>().bibleService.translationId,
      };
      await exportOdt(payload, path);
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state     = context.watch<AppState>();
    final primary   = state.brandPrimary;
    final secondary = state.brandSecondary;
    final profile   = state.churchProfile;
    final isWide    = MediaQuery.of(context).size.width >= 700;

    return isWide
        ? _buildDesktop(context, state, primary, secondary, profile)
        : _buildMobile(context, state, primary, secondary, profile);
  }

  // ── DESKTOP LAYOUT ────────────────────────────────────────────────────────

  Widget _buildDesktop(BuildContext context, dynamic state,
      Color primary, Color secondary, dynamic profile) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: contrastOn(primary),
        title: Row(children: [
          if (profile != null)
            ChurchLogo(
                logoPath: profile.logoPath,
                primary: primary,
                secondary: secondary,
                size: 30,
                borderRadius: 7),
          if (profile != null) const SizedBox(width: 10),
          const Text('Notes & Messages',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        actions: [
          IconButton(
            icon: Icon(
                _showSearch ? Icons.search_off : Icons.search,
                color: contrastOn(primary)),
            tooltip: 'Search all notes',
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) _searchQuery = '';
            }),
          ),
          IconButton(
            icon: Icon(Icons.upload_file, color: contrastOn(primary)),
            tooltip: 'Import file',
            onPressed: _importFile,
          ),
          IconButton(
            icon: Icon(Icons.add, color: contrastOn(primary)),
            tooltip: 'New note',
            onPressed: _createNote,
          ),
        ],
      ),
      body: Column(children: [
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
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        Expanded(
          child: Row(children: [
            // Folder tree
            SizedBox(
              width: 200,
              child: FolderTree(
                activeFolder:    _activeFolder,
                activeSubfolder: _activeSubfolder,
                notes:           _notes,
                primary:         primary,
                onSelectFolder:  (folder, sub) => setState(() {
                  _activeFolder    = folder;
                  _activeSubfolder = sub;
                  _selectedNote    = null;
                  _showSearch      = false;
                  _searchQuery     = '';
                }),
              ),
            ),
            const VerticalDivider(width: 1),
            // Note list
            SizedBox(
              width: 260,
              child: NoteList(
                notes:         _visibleNotes,
                selectedNote:  _selectedNote,
                primary:       primary,
                secondary:     secondary,
                showingSearch: _showSearch && _searchQuery.isNotEmpty,
                activeFolder:  _activeFolder,
                onSelect:      (n) => setState(() => _selectedNote = n),
                onArchive:     _archiveNote,
                onUnarchive:   _unarchiveNote,
                onDelete:      _deleteNote,
                onExport:      (n, fmt) => _exportNote(n, format: fmt),
                onNew:         _createNote,
              ),
            ),
            const VerticalDivider(width: 1),
            // Editor / empty state
            Expanded(
              child: _selectedNote != null
                  ? NoteEditor(
                      key:          ValueKey(_selectedNote!.id),
                      note:         _selectedNote!,
                      primary:      primary,
                      secondary:    secondary,
                      bibleService: state.bibleService,
                      onChanged:    () => _update(() =>
                          _selectedNote!.updatedAt = DateTime.now()),
                      onArchive:    () => _archiveNote(_selectedNote!),
                      onExport:     (fmt) =>
                          _exportNote(_selectedNote!, format: fmt),
                      onSaveBack:   _saveBack,
                    )
                  : EmptyEditor(primary: primary),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── MOBILE LAYOUT ─────────────────────────────────────────────────────────

  Widget _buildMobile(BuildContext context, dynamic state,
      Color primary, Color secondary, dynamic profile) {
    String title;
    bool showBack = false;
    switch (_mobilePane) {
      case _MobilePane.folders:
        title = 'Folders';
      case _MobilePane.list:
        title = _activeFolder;
        showBack = true;
      case _MobilePane.editor:
        title = _selectedNote?.title.isNotEmpty == true
            ? _selectedNote!.title
            : 'Note';
        showBack = true;
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: contrastOn(primary),
        leading: showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _mobilePane = _mobilePane == _MobilePane.editor
                      ? _MobilePane.list
                      : _MobilePane.folders;
                }),
              )
            : null,
        title: Row(children: [
          if (profile != null && _mobilePane == _MobilePane.folders) ...[
            ChurchLogo(
                logoPath: profile.logoPath,
                primary: primary,
                secondary: secondary,
                size: 26,
                borderRadius: 6),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        actions: [
          if (_mobilePane != _MobilePane.editor) ...[
            IconButton(
              icon: Icon(
                  _showSearch ? Icons.search_off : Icons.search,
                  color: contrastOn(primary)),
              onPressed: () => setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) _searchQuery = '';
              }),
            ),
            IconButton(
              icon: Icon(Icons.upload_file, color: contrastOn(primary)),
              onPressed: _importFile,
            ),
            IconButton(
              icon: Icon(Icons.add, color: contrastOn(primary)),
              onPressed: () {
                _createNote();
                setState(() => _mobilePane = _MobilePane.editor);
              },
            ),
          ],
        ],
      ),
      body: _buildMobileBody(state, primary, secondary),
    );
  }

  Widget _buildMobileBody(dynamic state, Color primary, Color secondary) {
    switch (_mobilePane) {
      case _MobilePane.folders:
        return FolderTree(
          activeFolder:    _activeFolder,
          activeSubfolder: _activeSubfolder,
          notes:           _notes,
          primary:         primary,
          onSelectFolder:  (folder, sub) => setState(() {
            _activeFolder    = folder;
            _activeSubfolder = sub;
            _selectedNote    = null;
            _showSearch      = false;
            _searchQuery     = '';
            _mobilePane      = _MobilePane.list;
          }),
        );

      case _MobilePane.list:
        return Column(children: [
          // Breadcrumb bar — tap to go back to folders
          InkWell(
            onTap: () => setState(() => _mobilePane = _MobilePane.folders),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              color: primary.withValues(alpha: 0.06),
              child: Row(children: [
                Icon(Icons.folder_open_outlined,
                    size: 15, color: primary),
                const SizedBox(width: 8),
                Text(_activeFolder,
                    style: TextStyle(
                        fontSize: 13,
                        color: primary,
                        fontWeight: FontWeight.w600)),
                if (_activeSubfolder.isNotEmpty)
                  Text(' › $_activeSubfolder',
                      style:
                          TextStyle(fontSize: 13, color: primary)),
                const Spacer(),
                Icon(Icons.chevron_right,
                    size: 16,
                    color: primary.withValues(alpha: 0.5)),
              ]),
            ),
          ),
          if (_showSearch)
            Container(
              color: primary.withValues(alpha: 0.04),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search all notes…',
                  prefixIcon: Icon(Icons.search, color: primary),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
          Expanded(
            child: NoteList(
              notes:         _visibleNotes,
              selectedNote:  _selectedNote,
              primary:       primary,
              secondary:     secondary,
              showingSearch: _showSearch && _searchQuery.isNotEmpty,
              activeFolder:  _activeFolder,
              onSelect: (n) => setState(() {
                _selectedNote = n;
                _mobilePane   = _MobilePane.editor;
              }),
              onArchive:   _archiveNote,
              onUnarchive: _unarchiveNote,
              onDelete:    _deleteNote,
              onExport:    (n, fmt) => _exportNote(n, format: fmt),
              onNew: () {
                _createNote();
                setState(() => _mobilePane = _MobilePane.editor);
              },
            ),
          ),
        ]);

      case _MobilePane.editor:
        if (_selectedNote == null) return EmptyEditor(primary: primary);
        return NoteEditor(
          key:          ValueKey(_selectedNote!.id),
          note:         _selectedNote!,
          primary:      primary,
          secondary:    secondary,
          bibleService: state.bibleService,
          onChanged:    () => _update(() =>
              _selectedNote!.updatedAt = DateTime.now()),
          onArchive: () {
            _archiveNote(_selectedNote!);
            setState(() => _mobilePane = _MobilePane.list);
          },
          onExport:   (fmt) => _exportNote(_selectedNote!, format: fmt),
          onSaveBack: _saveBack,
        );
    }
  }
}