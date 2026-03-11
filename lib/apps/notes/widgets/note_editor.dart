// lib/apps/notes/widgets/note_editor.dart
//
// Full-screen note editor with:
//   • Toolbar: message type, date, translation, export-format chips + action icons
//   • Expositional / topical meta bar
//   • Title field
//   • Rich content area — ALL notes use the embedded Quill WebView editor.
//     Formatting (bold, italic, headings, lists, blockquote, align) is fully
//     preserved. Content is stored as HTML in note.content.
//   • Status bar: folder path, word count, last-saved time
//   • PDF inline viewer (syncfusion_flutter_pdfviewer)
//     with page-jump toolbar; "Open externally" kept as a secondary option
//   • DOCX / ODT imported files show a "Save to file" banner above the editor
//   • TXT / MD imported files fall back to the plain ScriptureField editor
//
// pubspec.yaml dependencies required:
//   syncfusion_flutter_pdfviewer: ^26.1.35
//   webview_windows: ^0.4.0          ← Windows (already in project)

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
// Platform-conditional WebView imports
import 'package:webview_windows/webview_windows.dart'
    if (dart.library.html) 'package:webview_flutter/webview_flutter.dart';
import '../../../services/bible_service.dart';
import '../../../theme.dart';
import '../../../widgets/scripture_field.dart';
import '../note_constants.dart';
import '../note_model.dart';
import '../dialogs/translation_picker_dialog.dart';
import '../dialogs/verse_import_dialog.dart';
import 'rich_editor_asset.dart';
import 'shared_widgets.dart';

class NoteEditor extends StatefulWidget {
  final NoteModel          note;
  final Color              primary;
  final Color              secondary;
  final BibleService       bibleService;
  final VoidCallback       onChanged;
  final VoidCallback       onArchive;
  /// Called when the user triggers an export.
  /// The value is the format key: 'docx', 'odt', or 'pdf'.
  final ValueChanged<String> onExport;
  /// Called when the user taps "Save to file" on an imported note.
  /// Implementors should write note.content back to note.sourceFilePath.
  final Future<void> Function(NoteModel)? onSaveBack;

  const NoteEditor({
    super.key,
    required this.note,
    required this.primary,
    required this.secondary,
    required this.bibleService,
    required this.onChanged,
    required this.onArchive,
    required this.onExport,
    this.onSaveBack,
  });

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;
  late TextEditingController _seriesCtrl;
  final ScrollController     _scrollCtrl = ScrollController();

  // ── PDF viewer state ──────────────────────────────────────────────────────
  // We keep a PdfViewerController so we can jump to pages from our toolbar.
  final PdfViewerController _pdfViewerCtrl = PdfViewerController();
  // For file-path sources we need to copy bytes to a temp file first.
  // _pdfSource is set once and drives which SfPdfViewer constructor is used.
  _PdfSource? _pdfSource;
  bool        _pdfError  = false;
  int         _pdfPage   = 1;   // 1-based, matching Syncfusion's API
  int         _pdfTotal  = 1;

  // ── Save-back state ───────────────────────────────────────────────────────
  bool _savingBack = false;
  bool _savedBack  = false;

  // ── Rich WebView editor state (docx / odt) ────────────────────────────────
  // webview_windows loads content via a file:// URL, so we write the editor
  // HTML to a temp file once and reuse it.  Communication is one-way from
  // Flutter→JS (executeScript) and JS→Flutter via postMessage intercepted
  // through the WebviewController's webMessage stream.
  WebviewController? _webCtrl;
  String?  _editorTempPath;         // path of the written HTML temp file
  bool  _richReady       = false;   // editor JS finished initialising
  bool  _richLoading     = true;    // WebView page still loading
  bool  _richInitialised = false;   // _initWebview() has been called
  int   _richWordCount   = 0;

  @override
  void initState() {
    super.initState();
    _titleCtrl   = TextEditingController(text: widget.note.title);
    _contentCtrl = TextEditingController(text: widget.note.content);
    _seriesCtrl  = TextEditingController(text: widget.note.seriesName);
    // Title and series still use text controllers for sync.
    // Content is synced via the WebView 'change' message — no listener needed.
    _titleCtrl.addListener(_syncMeta);
    _seriesCtrl.addListener(_syncMeta);
    if (widget.note.sourceFileType == 'pdf') {
      _preparePdfSource();
    } else {
      _initWebview();
    }
  }

  @override
  void didUpdateWidget(NoteEditor old) {
    super.didUpdateWidget(old);
    if (old.note.id != widget.note.id) {
      _titleCtrl.text   = widget.note.title;
      _contentCtrl.text = widget.note.content;
      _seriesCtrl.text  = widget.note.seriesName;
      if (widget.note.sourceFileType == 'pdf') {
        setState(() { _pdfSource = null; _pdfError = false; _pdfPage = 1; });
        _preparePdfSource();
      } else {
        // Reload the editor page so the ready handler fires and injects
        // the new note's content.
        setState(() { _richReady = false; _richLoading = true; _richWordCount = 0; });
        _webCtrl?.loadUrl(_editorTempPath != null
            ? 'file:///$_editorTempPath'
            : 'about:blank');
      }
    }
  }

  // ── PDF source resolution ─────────────────────────────────────────────────
  //
  // SfPdfViewer has three constructors:
  //   .memory(Uint8List)   — best for in-memory bytes (all platforms)
  //   .file(File)          — native platforms only; fast for large files
  //   .asset / .network    — not applicable here
  //
  // Strategy:
  //   1. If bytes are available in RAM → use .memory (works everywhere, incl. web)
  //   2. Else if a file path exists and we're on a native platform → use .file
  //   3. Otherwise write bytes to a temp file and use .file
  //   4. On web with no bytes → show error (the bytes should always be present
  //      because _importFile reads `withData: true`).

  Future<void> _preparePdfSource() async {
    try {
      final note = widget.note;

      // Prefer in-memory bytes — available immediately and cross-platform.
      if (note.sourceFileBytes != null) {
        if (mounted) {
          setState(() => _pdfSource =
              _PdfSource.memory(note.sourceFileBytes!));
        }
        return;
      }

      // Native platforms: use the file path directly if it exists.
      if (!kIsWeb && note.sourceFilePath != null) {
        final f = File(note.sourceFilePath!);
        if (f.existsSync()) {
          if (mounted) setState(() => _pdfSource = _PdfSource.file(f));
          return;
        }
      }

      if (mounted) setState(() => _pdfError = true);
    } catch (_) {
      if (mounted) setState(() => _pdfError = true);
    }
  }

  // ── Rich WebView editor helpers ───────────────────────────────────────────

  /// Kept for the file-banner routing logic (docx/odt save-back banner).
  static bool _isRichFile(String? ext) => ext == 'docx' || ext == 'odt';

  /// Writes the Quill HTML to a temp file, creates a WebviewController,
  /// subscribes to its message stream, and loads the file URL.
  Future<void> _initWebview() async {
    if (_richInitialised) return;
    _richInitialised = true;

    try {
      // Write the bundled editor HTML to a temp file so webview_windows
      // can load it via file:// (it doesn't support loadHtmlString directly).
      final tmp  = await getTemporaryDirectory();
      final file = File('${tmp.path}/quill_editor_${widget.note.id}.html');
      await file.writeAsString(kRichEditorHtml, flush: true);
      _editorTempPath = file.path.replaceAll('\\', '/');

      final ctrl = WebviewController();
      await ctrl.initialize();

      // Subscribe to JS→Flutter postMessage events.
      // The Quill HTML calls window.chrome.webview.postMessage(jsonString).
      ctrl.webMessage.listen((dynamic raw) {
        _onEditorMessage(raw is String ? raw : raw.toString());
      });

      // Track navigation state
      ctrl.loadingState.listen((state) {
        if (!mounted) return;
        if (state == LoadingState.navigationCompleted) {
          setState(() => _richLoading = false);
        }
      });

      await ctrl.loadUrl('file:///$_editorTempPath');

      if (mounted) setState(() => _webCtrl = ctrl);
    } catch (e) {
      if (mounted) setState(() => _richLoading = false);
    }
  }

  /// Called whenever JS posts a message to the Flutter host.
  void _onEditorMessage(String rawJson) {
    try {
      final map  = jsonDecode(rawJson) as Map<String, dynamic>;
      final type = map['type'] as String? ?? '';
      switch (type) {
        case 'ready':
          setState(() { _richReady = true; _richLoading = false; });
          final html = widget.note.content.trimLeft().startsWith('<')
              ? widget.note.content
              : _plainTextToHtml(widget.note.content);
          _webCtrl?.executeScript('setContent(${_jsStringLiteral(html)})');
          break;
        case 'change':
          final html = map['html'] as String? ?? '';
          widget.note.content = html;
          if (_savedBack) setState(() => _savedBack = false);
          widget.onChanged();
          break;
        case 'wordCount':
          final n     = map['count'];
          final count = n is int ? n : int.tryParse('$n') ?? 0;
          if (_richWordCount != count) setState(() => _richWordCount = count);
          break;
      }
    } catch (_) {}
  }

  /// Wraps a Dart string in a JS string literal with proper escaping.
  static String _jsStringLiteral(String s) {
    final escaped = s
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', '');
    return "'$escaped'";
  }

  /// Converts plain text (newline-delimited) to minimal HTML for Quill.
  static String _plainTextToHtml(String text) {
    if (text.isEmpty) return '<p></p>';
    return text.split('\n').map((line) {
      final t = line.trim();
      if (t.isEmpty) return '<p><br></p>';
      final esc = t
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;');
      return '<p>$esc</p>';
    }).join();
  }

  // ── Sync & save-back ──────────────────────────────────────────────────────

  /// Syncs only title and series from their text controllers.
  /// Content is synced via _onEditorMessage 'change' — do not write
  /// _contentCtrl.text back to note.content here (it would overwrite HTML).
  void _syncMeta() {
    widget.note.title      = _titleCtrl.text;
    widget.note.seriesName = _seriesCtrl.text;
    widget.onChanged();
  }

  /// Legacy sync used only by the plain ScriptureField fallback (txt/md).
  void _sync() {
    widget.note.title      = _titleCtrl.text;
    widget.note.content    = _contentCtrl.text;
    widget.note.seriesName = _seriesCtrl.text;
    if (_savedBack) setState(() => _savedBack = false);
    widget.onChanged();
  }

  Future<void> _doSaveBack() async {
    if (widget.onSaveBack == null) return;
    setState(() => _savingBack = true);
    try {
      await widget.onSaveBack!(widget.note);
      if (mounted) setState(() { _savingBack = false; _savedBack = true; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingBack = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Save failed: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _pdfViewerCtrl.dispose();
    _webCtrl?.dispose();
    _titleCtrl.removeListener(_syncMeta);
    _seriesCtrl.removeListener(_syncMeta);
    for (final c in [_titleCtrl, _contentCtrl, _seriesCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final note      = widget.note;
    final primary   = widget.primary;
    final secondary = widget.secondary;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(children: [
        _buildToolbar(note, primary, secondary),
        if (note.folder == kFolderExpositional || note.subfolder.isNotEmpty)
          _buildMetaBar(note, primary, secondary),
        // Title is always shown — even for PDFs so users can rename
        _buildTitleField(note, primary),
        Flexible(
          child: ColoredBox(
            color: Colors.white,
            child: _buildContentArea(note, primary),
          ),
        ),
        _buildStatusBar(note),
      ]),
    );
  }

  // ── TOOLBAR ───────────────────────────────────────────────────────────────

  Widget _buildToolbar(NoteModel note, Color primary, Color secondary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEAEDF3))),
      ),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 4, children: [
          MetaChip(
            label: messageTypeLabels[note.messageType] ?? '',
            icon:  Icons.label_outline,
            color: primary,
            onTap: _pickMessageType,
          ),
          MetaChip(
            label: note.date != null
                ? DateFormat('MMM d, y').format(note.date!)
                : 'Set date',
            icon:  Icons.calendar_today_outlined,
            color: primary,
            onTap: _pickDate,
          ),
          MetaChip(
            label: note.translation ?? widget.bibleService.translationId,
            icon:  Icons.menu_book_outlined,
            color: secondary,
            onTap: _pickTranslation,
          ),
          MetaChip(
            label: (note.exportFormat == 'odt' ? 'ODT' : 'DOCX'),
            icon:  Icons.description_outlined,
            color: primary.withValues(alpha: 0.75),
            onTap: _pickExportFormat,
          ),
        ]),
        const SizedBox(height: 2),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
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
          IconButton(
            icon: Icon(Icons.format_quote_outlined, size: 18, color: primary),
            onPressed: _showVerseImport,
            tooltip: 'Import verse',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.ios_share_outlined, size: 18, color: primary),
            tooltip: 'Export',
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'docx', child: Row(children: [
                Icon(Icons.description_outlined, size: 16),
                SizedBox(width: 8), Text('Export as Word (.docx)')])),
              const PopupMenuItem(value: 'odt', child: Row(children: [
                Icon(Icons.description_outlined, size: 16),
                SizedBox(width: 8), Text('Export as ODT (.odt)')])),
              const PopupMenuItem(value: 'pdf', child: Row(children: [
                Icon(Icons.picture_as_pdf_outlined, size: 16),
                SizedBox(width: 8), Text('Export as PDF')])),
            ],
            onSelected: (v) => widget.onExport(v),
          ),
          IconButton(
            icon: Icon(Icons.archive_outlined, size: 18, color: textMid),
            onPressed: widget.onArchive,
            tooltip: 'Archive note',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
        ]),
      ]),
    );
  }

  // ── META BAR ──────────────────────────────────────────────────────────────

  Widget _buildMetaBar(NoteModel note, Color primary, Color secondary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFFF0F4FF),
      child: Row(children: [
        if (note.folder == kFolderExpositional) ...[
          Icon(Icons.menu_book_outlined, size: 14, color: primary),
          const SizedBox(width: 6),
          Text(
            note.subfolder.isNotEmpty ? note.subfolder : 'No book set',
            style: TextStyle(
                fontSize: 12, color: primary, fontWeight: FontWeight.w600),
          ),
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
              style: TextStyle(
                  fontSize: 12, color: secondary, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }

  // ── TITLE ─────────────────────────────────────────────────────────────────

  Widget _buildTitleField(NoteModel note, Color primary) {
    return Container(
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
    );
  }

  // ── CONTENT AREA ──────────────────────────────────────────────────────────

  Widget _buildContentArea(NoteModel note, Color primary) {
    final isPdf      = note.sourceFileType == 'pdf';
    final isPlainFile = note.sourceFileType == 'txt' || note.sourceFileType == 'md';

    if (isPdf) return _buildPdfPane(note, primary);

    // Plain txt/md imported files: keep the simple ScriptureField editor
    // with a save-back banner.
    if (isPlainFile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _fileBanner(
          icon:          _fileIcon(note.sourceFileType!),
          message:       'Imported .${note.sourceFileType} — plain text mode.',
          primary:       primary,
          actionLabel:   _savingBack ? 'Saving…' : _savedBack ? '✓ Saved' : 'Save to file',
          actionIcon:    _savedBack ? Icons.check_circle_outline : Icons.save_outlined,
          onAction:      _savingBack ? null : _doSaveBack,
          actionEnabled: widget.onSaveBack != null && !_savingBack,
        ),
        Expanded(child: _editableScrollArea(primary)),
      ]);
    }

    // All other notes (new notes, docx, odt) — use the Quill WebView editor.
    // For docx/odt add the "Save to file" banner on top.
    final isRichImport = _isRichFile(note.sourceFileType);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (isRichImport)
        _fileBanner(
          icon:          Icons.description_outlined,
          message:       'Rich document (.${note.sourceFileType}) '
              '— formatting preserved. '
              '${_richLoading ? 'Loading editor…' : 'Edits auto-save.'}',
          primary:       primary,
          actionLabel:   _savingBack ? 'Saving…' : _savedBack ? '✓ Saved' : 'Save to file',
          actionIcon:    _savedBack ? Icons.check_circle_outline : Icons.save_outlined,
          onAction:      _savingBack || !_richReady ? null : _doSaveBack,
          actionEnabled: widget.onSaveBack != null && _richReady && !_savingBack,
        ),
      Expanded(child: _buildWebViewEditor(primary)),
    ]);
  }
  //
  // Layout:
  // ── WEBVIEW EDITOR (all standard + rich-import notes) ────────────────────

  Widget _buildWebViewEditor(Color primary) {
    return Stack(children: [
      if (_webCtrl != null)
        Webview(
          _webCtrl!,
          permissionRequested: (_url, _kind, _isUser) =>
              WebviewPermissionDecision.allow,
        )
      else
        const SizedBox.shrink(),
      // Loading overlay — hidden once editor reports 'ready'
      if (_richLoading)
        Container(
          color: Colors.white,
          child: Center(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center, children: [
              CircularProgressIndicator(color: primary),
              const SizedBox(height: 12),
              Text('Loading editor…',
                  style: TextStyle(
                      fontSize: 12,
                      color: primary.withValues(alpha: 0.5))),
            ]),
          ),
        ),
    ]);
  }

  // ── PDF PANE ──────────────────────────────────────────────────────────────
  //
  // Layout:
  //   ┌─────────────────────────────────────────────────────────┐
  //   │  [PDF icon] PDF document  [← page 3/12 →] [Open ext.]  │  ← banner
  //   ├─────────────────────────────────────────────────────────┤
  //   │                                                         │
  //   │            SfPdfViewer (fills remaining space)          │
  //   │                                                         │
  //   └─────────────────────────────────────────────────────────┘

  Widget _buildPdfPane(NoteModel note, Color primary) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Banner with integrated page controls
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        color: const Color(0xFFF0F4FF),
        child: Row(children: [
          Icon(Icons.picture_as_pdf_outlined, size: 15, color: primary),
          const SizedBox(width: 8),
          Text('PDF document',
              style: const TextStyle(fontSize: 12, color: textDark)),
          const Spacer(),
          // Page navigation — only shown once PDF is loaded
          if (_pdfSource != null && !_pdfError) ...[
            _pdfNavIconBtn(
              icon:    Icons.first_page,
              enabled: _pdfPage > 1,
              color:   primary,
              onTap:   () {
                _pdfViewerCtrl.firstPage();
                setState(() => _pdfPage = 1);
              },
            ),
            _pdfNavIconBtn(
              icon:    Icons.chevron_left,
              enabled: _pdfPage > 1,
              color:   primary,
              onTap:   () {
                _pdfViewerCtrl.previousPage();
                setState(() => _pdfPage = (_pdfPage - 1).clamp(1, _pdfTotal));
              },
            ),
            const SizedBox(width: 2),
            // Tappable page indicator → jump-to-page dialog
            GestureDetector(
              onTap: _showJumpToPageDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$_pdfPage / $_pdfTotal',
                  style: TextStyle(
                      fontSize: 11,
                      color: primary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 2),
            _pdfNavIconBtn(
              icon:    Icons.chevron_right,
              enabled: _pdfPage < _pdfTotal,
              color:   primary,
              onTap:   () {
                _pdfViewerCtrl.nextPage();
                setState(() =>
                    _pdfPage = (_pdfPage + 1).clamp(1, _pdfTotal));
              },
            ),
            _pdfNavIconBtn(
              icon:    Icons.last_page,
              enabled: _pdfPage < _pdfTotal,
              color:   primary,
              onTap:   () {
                _pdfViewerCtrl.lastPage();
                setState(() => _pdfPage = _pdfTotal);
              },
            ),
            const SizedBox(width: 4),
          ],
          // Open-externally kept as a secondary escape hatch
          TextButton.icon(
            icon:  const Icon(Icons.open_in_new, size: 13),
            label: const Text('Open externally',
                style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
                foregroundColor: primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onPressed: () => _openPdfExternal(note),
          ),
        ]),
      ),

      // Viewer body
      Expanded(child: _buildSfPdfViewer(primary)),
    ]);
  }

  Widget _buildSfPdfViewer(Color primary) {
    if (_pdfError) {
      return _pdfFallback(primary,
          'Could not load the PDF.\nTry "Open externally" above.');
    }

    if (_pdfSource == null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(color: primary),
          const SizedBox(height: 12),
          Text('Loading PDF…',
              style: TextStyle(
                  fontSize: 12, color: primary.withValues(alpha: 0.5))),
        ]),
      );
    }

    // SfPdfViewer is available on Android, iOS, macOS, Windows, Linux, web.
    // We pick the right constructor based on whether we have bytes or a file.
    Widget viewer;
    if (_pdfSource!.bytes != null) {
      viewer = SfPdfViewer.memory(
        _pdfSource!.bytes!,
        controller: _pdfViewerCtrl,
        canShowScrollHead:          true,
        canShowScrollStatus:        true,
        canShowPageLoadingIndicator: true,
        onPageChanged: (details) {
          if (mounted) {
            setState(() {
              _pdfPage = details.newPageNumber;
            });
          }
        },
        onDocumentLoaded: (details) {
          if (mounted) {
            setState(() => _pdfTotal = details.document.pages.count);
          }
        },
        onDocumentLoadFailed: (_) {
          if (mounted) setState(() => _pdfError = true);
        },
      );
    } else {
      viewer = SfPdfViewer.file(
        _pdfSource!.file!,
        controller: _pdfViewerCtrl,
        canShowScrollHead:          true,
        canShowScrollStatus:        true,
        canShowPageLoadingIndicator: true,
        onPageChanged: (details) {
          if (mounted) {
            setState(() {
              _pdfPage = details.newPageNumber;
            });
          }
        },
        onDocumentLoaded: (details) {
          if (mounted) {
            setState(() => _pdfTotal = details.document.pages.count);
          }
        },
        onDocumentLoadFailed: (_) {
          if (mounted) setState(() => _pdfError = true);
        },
      );
    }

    return viewer;
  }

  // ── PDF HELPERS ───────────────────────────────────────────────────────────

  Widget _pdfNavIconBtn({
    required IconData     icon,
    required bool         enabled,
    required Color        color,
    required VoidCallback onTap,
  }) =>
      IconButton(
        icon: Icon(icon, size: 18,
            color: enabled ? color : color.withValues(alpha: 0.28)),
        onPressed: enabled ? onTap : null,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      );

  Widget _pdfFallback(Color primary, String message) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.picture_as_pdf_outlined,
          size: 44, color: primary.withValues(alpha: 0.22)),
      const SizedBox(height: 14),
      Text(message,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13,
              color: primary.withValues(alpha: 0.45),
              height: 1.5)),
    ]),
  );

  Future<void> _showJumpToPageDialog() async {
    final ctrl = TextEditingController(text: '$_pdfPage');
    final result = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Go to page',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: widget.primary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '1 – $_pdfTotal',
            suffixText: '/ $_pdfTotal',
          ),
          onSubmitted: (v) {
            final n = int.tryParse(v);
            if (n != null) Navigator.pop(context, n);
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                final n = int.tryParse(ctrl.text);
                if (n != null) Navigator.pop(context, n);
              },
              child: Text('Go',
                  style: TextStyle(color: widget.primary))),
        ],
      ),
    );
    if (result != null) {
      final page = result.clamp(1, _pdfTotal);
      _pdfViewerCtrl.jumpToPage(page);
      setState(() => _pdfPage = page);
    }
  }

  Future<void> _openPdfExternal(NoteModel note) async {
    try {
      // Try to resolve a usable file path
      String? path = note.sourceFilePath;

      // If no path (e.g. web import, or path no longer valid), write bytes
      // to a temp file so we can open it.
      if ((path == null || (!kIsWeb && !File(path).existsSync())) &&
          note.sourceFileBytes != null) {
        final tmp  = await getTemporaryDirectory();
        final safe = note.title.replaceAll(RegExp(r'[^\w\s]'), '').trim();
        path = '${tmp.path}/${safe}_${note.id}.pdf';
        await File(path).writeAsBytes(note.sourceFileBytes!);
      }

      if (path != null && !kIsWeb) {
        final uri = Uri.file(path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No external PDF viewer found on this device.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not open PDF: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── FILE BANNER (non-PDF imported files) ─────────────────────────────────

  Widget _fileBanner({
    required IconData     icon,
    required String       message,
    required Color        primary,
    required String       actionLabel,
    required IconData     actionIcon,
    VoidCallback?         onAction,
    bool                  actionEnabled = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: const Color(0xFFF0F4FF),
      child: Row(children: [
        Icon(icon, size: 16, color: primary),
        const SizedBox(width: 8),
        Expanded(child: Text(message,
            style: const TextStyle(fontSize: 12, color: textDark))),
        TextButton.icon(
          icon:  Icon(actionIcon, size: 14),
          label: Text(actionLabel, style: const TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(foregroundColor: primary),
          onPressed: actionEnabled ? onAction : null,
        ),
      ]),
    );
  }

  IconData _fileIcon(String ext) {
    switch (ext) {
      case 'docx':
      case 'odt':  return Icons.description_outlined;
      case 'md':   return Icons.code_outlined;
      default:     return Icons.text_snippet_outlined;
    }
  }

  Widget _editableScrollArea(Color primary) => Scrollbar(
    controller: _scrollCtrl,
    thumbVisibility: false,
    interactive: true,
    child: SingleChildScrollView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 320),
        child: ScriptureField(
          controller:   _contentCtrl,
          bibleService: widget.bibleService,
          primary:      primary,
          maxLines:     9999,
          expands:      false,
          style: const TextStyle(fontSize: 15, height: 1.75, color: textDark),
          decoration: const InputDecoration(
            hintText:
                'Start writing… Type a verse like "John 3:16" to auto-import it.',
            border:        InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (_) => _sync(),
        ),
      ),
    ),
  );

  // ── STATUS BAR ────────────────────────────────────────────────────────────

  Widget _buildStatusBar(NoteModel note) {
    final isPdf = note.sourceFileType == 'pdf';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FA),
        border: Border(top: BorderSide(color: Color(0xFFEAEDF3))),
      ),
      child: Row(children: [
        Flexible(
          child: Text(
            note.subfolder.isNotEmpty
                ? '${note.folder} › ${note.subfolder}'
                : note.folder,
            style: const TextStyle(fontSize: 10, color: textMid),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Spacer(),
        if (isPdf && _pdfTotal > 1)
          Text(
            'Page $_pdfPage of $_pdfTotal',
            style: const TextStyle(fontSize: 10, color: textMid),
          )
        else if (note.sourceFileType != 'txt' && note.sourceFileType != 'md')
          // WebView editor tracks word count via JS message
          Text(
            '$_richWordCount words',
            style: const TextStyle(fontSize: 10, color: textMid),
          )
        else
          // Plain ScriptureField fallback for txt/md
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
    );
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
      firstDate:   DateTime(2000),
      lastDate:    DateTime(2100),
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
      builder: (_) => TranslationPickerDialog(
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
    final translationId =
        widget.note.translation ?? widget.bibleService.translationId;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => VerseImportDialog(
        bibleService:  widget.bibleService,
        primary:       widget.primary,
        translationId: translationId,
      ),
    );
    if (result == null || result.isEmpty) return;

    final note = widget.note;
    final isPlain = note.sourceFileType == 'txt' || note.sourceFileType == 'md';

    if (isPlain) {
      // Plain ScriptureField path
      final pos    = _contentCtrl.selection.baseOffset;
      final text   = _contentCtrl.text;
      final insert = '\n$result\n';
      final newText = pos < 0 || pos > text.length
          ? '$text$insert'
          : '${text.substring(0, pos)}$insert${text.substring(pos)}';
      _contentCtrl.value = TextEditingValue(
        text:      newText,
        selection: TextSelection.collapsed(
            offset: (pos < 0 ? text.length : pos) + insert.length),
      );
      _sync();
    } else {
      // WebView Quill path — insert as a blockquote paragraph at cursor.
      // We pass the verse text as HTML and let JS handle insertion.
      final esc = result
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll("'", r"\'")
          .replaceAll('\n', '<br>');
      _webCtrl?.executeScript(
          "insertVerseHtml('<blockquote>$esc</blockquote>')");
    }
  }

  Future<void> _pickExportFormat() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text('Default Export Format',
            style: TextStyle(color: widget.primary, fontSize: 15)),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'docx'),
            child: Row(children: [
              if (widget.note.exportFormat == 'docx')
                Icon(Icons.check, size: 16, color: widget.primary)
              else
                const SizedBox(width: 16),
              const SizedBox(width: 8),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Word Document (.docx)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Text('Best for Microsoft Word, Google Docs',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            ]),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'odt'),
            child: Row(children: [
              if (widget.note.exportFormat == 'odt')
                Icon(Icons.check, size: 16, color: widget.primary)
              else
                const SizedBox(width: 16),
              const SizedBox(width: 8),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('OpenDocument (.odt)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Text('Best for LibreOffice, OpenOffice',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            ]),
          ),
        ],
      ),
    );
    if (result != null) {
      widget.note.exportFormat = result;
      widget.onChanged();
      setState(() {});
    }
  }
}

// ── PDF SOURCE DISCRIMINATED UNION ────────────────────────────────────────────
// Avoids storing both bytes and file redundantly.

class _PdfSource {
  final Uint8List? bytes;
  final File?      file;

  const _PdfSource._({this.bytes, this.file});

  factory _PdfSource.memory(Uint8List b) => _PdfSource._(bytes: b);
  factory _PdfSource.file(File f)        => _PdfSource._(file: f);
}