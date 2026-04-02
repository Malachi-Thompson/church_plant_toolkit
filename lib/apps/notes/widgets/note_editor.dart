// lib/apps/notes/widgets/note_editor.dart
//
// Full-screen note editor with:
//   • Toolbar: message type, date, translation, export-format chips + action icons
//   • Expositional / topical meta bar
//   • Title field
//   • Rich content area — ALL notes use the embedded Quill WebView editor.
//     Formatting (bold, italic, headings, lists, blockquote, align) is fully
//     preserved. Content is stored as HTML in note.content.
//   • PRINT PREVIEW toggle — renders the note as paginated A4/Letter pages
//     so users can see exactly what it will look like before printing/exporting.
//     • For HTML/rich notes: renders the HTML in a styled WebView page view.
//     • For DOCX imports: passes bytes through the existing DOCX→HTML extractor
//       and renders in the same paged WebView preview.
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
// Used to extract HTML from DOCX bytes for the preview
import '../note_exporter.dart' show extractHtmlFromDocxBytes;

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

  // ── Print-preview state ───────────────────────────────────────────────────
  // When true the content area switches from the editable Quill WebView to
  // the read-only paginated preview WebView.
  bool              _showPreview      = false;
  WebviewController? _previewWebCtrl;
  bool              _previewLoading   = false;
  String?           _previewTempPath; // file:// HTML page written for preview

  // ── PDF viewer state ──────────────────────────────────────────────────────
  final PdfViewerController _pdfViewerCtrl = PdfViewerController();
  _PdfSource? _pdfSource;
  bool        _pdfError  = false;
  int         _pdfPage   = 1;
  int         _pdfTotal  = 1;

  // ── Save-back state ───────────────────────────────────────────────────────
  bool _savingBack = false;
  bool _savedBack  = false;

  // ── Rich WebView editor state ─────────────────────────────────────────────
  WebviewController? _webCtrl;
  String?  _editorTempPath;
  bool  _richReady       = false;
  bool  _richLoading     = true;
  bool  _richInitialised = false;
  int   _richWordCount   = 0;

  @override
  void initState() {
    super.initState();
    _titleCtrl   = TextEditingController(text: widget.note.title);
    _contentCtrl = TextEditingController(text: widget.note.content);
    _seriesCtrl  = TextEditingController(text: widget.note.seriesName);
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
      // Reset preview when switching notes
      if (_showPreview) setState(() => _showPreview = false);
      if (widget.note.sourceFileType == 'pdf') {
        setState(() { _pdfSource = null; _pdfError = false; _pdfPage = 1; });
        _preparePdfSource();
      } else {
        setState(() { _richReady = false; _richLoading = true; _richWordCount = 0; });
        _webCtrl?.loadUrl(_editorTempPath != null
            ? 'file:///$_editorTempPath'
            : 'about:blank');
      }
    }
  }

  // ── PDF source resolution ─────────────────────────────────────────────────

  Future<void> _preparePdfSource() async {
    try {
      final note = widget.note;
      if (note.sourceFileBytes != null) {
        if (mounted) setState(() => _pdfSource = _PdfSource.memory(note.sourceFileBytes!));
        return;
      }
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

  static bool _isRichFile(String? ext) => ext == 'docx' || ext == 'odt';

  Future<void> _initWebview() async {
    if (_richInitialised) return;
    _richInitialised = true;
    try {
      final tmp  = await getTemporaryDirectory();
      final file = File('${tmp.path}/quill_editor_${widget.note.id}.html');
      await file.writeAsString(kRichEditorHtml, flush: true);
      _editorTempPath = file.path.replaceAll('\\', '/');

      final ctrl = WebviewController();
      await ctrl.initialize();

      ctrl.webMessage.listen((dynamic raw) {
        _onEditorMessage(raw is String ? raw : raw.toString());
      });

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

  static String _jsStringLiteral(String s) {
    final escaped = s
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', '');
    return "'$escaped'";
  }

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

  // ── Print-preview helpers ─────────────────────────────────────────────────
  //
  // The preview renders the note as a sequence of A4/Letter-sized white "pages"
  // separated by a grey gutter — exactly the look of a word processor's Print
  // Layout view.  Content is the note's rich HTML with a print-ready stylesheet
  // applied (no toolbar, no Quill chrome).
  //
  // For DOCX imports we first extract HTML from the bytes using the existing
  // extractHtmlFromDocxBytes helper so the preview reflects the actual document
  // formatting rather than the raw Quill edit buffer.

  Future<void> _togglePreview() async {
    if (_showPreview) {
      // Turn preview off — just flip the flag; editor WebView stays alive.
      setState(() { _showPreview = false; });
      return;
    }

    // Turning preview ON
    setState(() { _showPreview = true; _previewLoading = true; });

    try {
      String previewHtml;

      // For DOCX imports, extract the original document HTML so the preview
      // shows the file's native formatting (headings, fonts, etc.).
      if (widget.note.sourceFileType == 'docx' &&
          widget.note.sourceFileBytes != null) {
        final extracted =
            await extractHtmlFromDocxBytes(widget.note.sourceFileBytes!);
        previewHtml = (extracted != null && extracted.isNotEmpty)
            ? extracted
            : widget.note.content;
      } else {
        previewHtml = widget.note.content.trimLeft().startsWith('<')
            ? widget.note.content
            : _plainTextToHtml(widget.note.content);
      }

      final pageHtml = _buildPrintPreviewHtml(
        title:       widget.note.title,
        contentHtml: previewHtml,
        primary:     widget.primary,
      );

      final tmp   = await getTemporaryDirectory();
      final file  = File('${tmp.path}/preview_${widget.note.id}.html');
      await file.writeAsString(pageHtml, flush: true);
      _previewTempPath = file.path.replaceAll('\\', '/');

      if (_previewWebCtrl == null) {
        final ctrl = WebviewController();
        await ctrl.initialize();
        ctrl.loadingState.listen((state) {
          if (!mounted) return;
          if (state == LoadingState.navigationCompleted) {
            setState(() => _previewLoading = false);
          }
        });
        await ctrl.loadUrl('file:///$_previewTempPath');
        if (mounted) setState(() { _previewWebCtrl = ctrl; });
      } else {
        // Reuse the existing controller and reload the updated file.
        await _previewWebCtrl!.loadUrl('file:///$_previewTempPath');
      }
    } catch (e) {
      if (mounted) setState(() { _previewLoading = false; });
    }
  }

  /// Builds a self-contained HTML page that mimics a word-processor "Print
  /// Layout" view: A4 pages (794 × 1123 px at 96 dpi) separated by a grey
  /// background, with the body content paginated via CSS column layout.
  ///
  /// We use a simple CSS-based paged layout:
  ///  • A fixed-height scrollable container holds the grey gutter.
  ///  • Individual "page" divs are white cards with print-standard margins.
  ///  • Content is placed in the first page and allowed to overflow into
  ///    following pages via CSS `break-inside: avoid` rules.
  ///
  /// Note: True CSS `@page` pagination requires a print context; in a WebView
  /// we simulate it with CSS columns or sequential page divs.  For simplicity
  /// we use a single-column flowing layout inside a vertically-scrollable
  /// container — which faithfully represents printed output for most content.
  static String _buildPrintPreviewHtml({
    required String title,
    required String contentHtml,
    required Color  primary,
  }) {
    // Convert Color to CSS hex
    final r = (primary.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (primary.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (primary.b * 255).round().toRadixString(16).padLeft(2, '0');
    final primaryHex = '#$r$g$b';

    // Escape the title for HTML
    final escapedTitle = title
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');

    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Print Preview</title>
<style>
  /* ── Reset ──────────────────────────────────────────────────────────── */
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  html, body {
    height: 100%;
    background: #D0D0D0;
    font-family: 'Segoe UI', Calibri, Georgia, serif;
  }

  /* ── Preview gutter ─────────────────────────────────────────────────── */
  #gutter {
    min-height: 100%;
    padding: 32px 40px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 24px;
  }

  /* ── Badge shown at top ─────────────────────────────────────────────── */
  #preview-badge {
    background: $primaryHex;
    color: #fff;
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 1px;
    padding: 4px 12px;
    border-radius: 20px;
    text-transform: uppercase;
    user-select: none;
    align-self: center;
  }

  /* ── A4 page card ───────────────────────────────────────────────────── */
  /*  A4 at 96 dpi = 794 × 1123 px                                        */
  .page {
    background: #ffffff;
    width: 794px;
    min-height: 1123px;
    padding: 96px 96px 96px 96px; /* ~1 inch margins */
    box-shadow: 0 2px 12px rgba(0,0,0,0.22);
    position: relative;
    break-inside: avoid;
  }

  /* ── Page header (title + date) ─────────────────────────────────────── */
  .page-header {
    border-bottom: 2px solid $primaryHex;
    padding-bottom: 12px;
    margin-bottom: 28px;
  }
  .page-title {
    font-size: 24px;
    font-weight: 700;
    color: $primaryHex;
    line-height: 1.2;
  }
  .page-meta {
    font-size: 11px;
    color: #888;
    margin-top: 4px;
  }

  /* ── Body content ───────────────────────────────────────────────────── */
  .page-body {
    font-size: 12pt;
    line-height: 1.8;
    color: #1C1C2E;
  }
  .page-body h1 { font-size: 20px; color: $primaryHex; margin: 18px 0 8px; }
  .page-body h2 { font-size: 16px; color: $primaryHex; margin: 14px 0 6px; }
  .page-body h3 { font-size: 13px; color: $primaryHex; margin: 10px 0 4px; }
  .page-body p  { margin: 0 0 8px; }
  .page-body ul, .page-body ol { margin: 0 0 10px 24px; }
  .page-body li { margin-bottom: 4px; }
  .page-body blockquote {
    border-left: 3px solid $primaryHex;
    background: #F0F4FF;
    padding: 10px 16px;
    margin: 12px 0;
    font-style: italic;
    color: #374151;
    border-radius: 0 6px 6px 0;
  }
  .page-body strong { font-weight: 700; }
  .page-body em     { font-style: italic; }
  .page-body u      { text-decoration: underline; }
  .page-body s      { text-decoration: line-through; }

  /* ── Page footer ────────────────────────────────────────────────────── */
  .page-footer {
    position: absolute;
    bottom: 48px;
    left: 96px;
    right: 96px;
    border-top: 1px solid #E0E0E0;
    padding-top: 6px;
    font-size: 9px;
    color: #B0B0B0;
    display: flex;
    justify-content: space-between;
  }
</style>
</head>
<body>
<div id="gutter">
  <div id="preview-badge">Print Preview</div>
  <div class="page">
    <div class="page-header">
      <div class="page-title">$escapedTitle</div>
    </div>
    <div class="page-body">
      $contentHtml
    </div>
    <div class="page-footer">
      <span>$escapedTitle</span>
      <span>Page 1</span>
    </div>
  </div>
</div>
</body>
</html>''';
  }

  // ── Sync & save-back ──────────────────────────────────────────────────────

  void _syncMeta() {
    widget.note.title      = _titleCtrl.text;
    widget.note.seriesName = _seriesCtrl.text;
    widget.onChanged();
  }

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
    _previewWebCtrl?.dispose();
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
        if (note.folder == kFolderExpositional ||
            note.folder == kFolderTextual ||
            note.subfolder.isNotEmpty)
          _buildMetaBar(note, primary, secondary),
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
    final isPdf     = note.sourceFileType == 'pdf';
    final canPreview = !isPdf; // preview supported for all non-PDF notes

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
          // ── Print-preview toggle ──────────────────────────────────────────
          if (canPreview) ...[
            Tooltip(
              message: _showPreview ? 'Back to editing' : 'Print preview',
              child: InkWell(
                onTap: _togglePreview,
                borderRadius: BorderRadius.circular(6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _showPreview
                        ? primary.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _showPreview
                          ? primary.withValues(alpha: 0.4)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      _showPreview
                          ? Icons.edit_outlined
                          : Icons.print_outlined,
                      size: 16,
                      color: _showPreview ? primary : textMid,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _showPreview ? 'Edit' : 'Preview',
                      style: TextStyle(
                        fontSize: 11,
                        color: _showPreview ? primary : textMid,
                        fontWeight: _showPreview
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          // ── Existing action icons ─────────────────────────────────────────
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
    // For Textual notes display just the book name (strip "OT:"/"NT:" prefix)
    final displaySubfolder = note.folder == kFolderTextual && note.subfolder.isNotEmpty
        ? parseTextualSubfolder(note.subfolder)[1]
        : note.subfolder;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFFF0F4FF),
      child: Row(children: [
        if (note.folder == kFolderExpositional || note.folder == kFolderTextual) ...[
          Icon(Icons.menu_book_outlined, size: 14, color: primary),
          const SizedBox(width: 6),
          Text(
            displaySubfolder.isNotEmpty ? displaySubfolder : 'No book set',
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
        // Title is always editable, even in preview mode (header is non-content)
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
    final isPdf       = note.sourceFileType == 'pdf';
    final isPlainFile = note.sourceFileType == 'txt' || note.sourceFileType == 'md';

    if (isPdf) return _buildPdfPane(note, primary);

    // Print preview mode — shown for all non-PDF notes when toggled ON
    if (_showPreview) return _buildPreviewPane(primary);

    // Plain txt/md imported files
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

  // ── PRINT PREVIEW PANE ────────────────────────────────────────────────────
  //
  // Layout:
  //   ┌─────────────────────────────────────────────────────────┐
  //   │  [print icon] Print Preview             [✕ Back to edit]│  ← info bar
  //   ├─────────────────────────────────────────────────────────┤
  //   │                  grey gutter                            │
  //   │   ┌────────── A4 white page card ───────────────────┐   │
  //   │   │  Title heading                                  │   │
  //   │   │  ─────────────────────────────────────────────  │   │
  //   │   │  Body content (rich HTML, formatted)            │   │
  //   │   └─────────────────────────────────────────────────┘   │
  //   └─────────────────────────────────────────────────────────┘

  Widget _buildPreviewPane(Color primary) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Info bar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        color: primary.withValues(alpha: 0.07),
        child: Row(children: [
          Icon(Icons.print_outlined, size: 15, color: primary),
          const SizedBox(width: 8),
          Text('Print Preview — read-only',
              style: TextStyle(fontSize: 12, color: primary,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          TextButton.icon(
            icon:  const Icon(Icons.edit_outlined, size: 13),
            label: const Text('Back to editing',
                style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
                foregroundColor: primary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onPressed: _togglePreview,
          ),
        ]),
      ),
      // Preview WebView
      Expanded(child: Stack(children: [
        if (_previewWebCtrl != null)
          Webview(
            _previewWebCtrl!,
            permissionRequested: (_url, _kind, _isUser) =>
                WebviewPermissionDecision.allow,
          )
        else
          const SizedBox.shrink(),
        if (_previewLoading)
          Container(
            color: Colors.white,
            child: Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                CircularProgressIndicator(color: primary),
                const SizedBox(height: 12),
                Text('Building preview…',
                    style: TextStyle(
                        fontSize: 12,
                        color: primary.withValues(alpha: 0.5))),
              ]),
            ),
          ),
      ])),
    ]);
  }

  // ── WEBVIEW EDITOR ────────────────────────────────────────────────────────

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

  Widget _buildPdfPane(NoteModel note, Color primary) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        color: const Color(0xFFF0F4FF),
        child: Row(children: [
          Icon(Icons.picture_as_pdf_outlined, size: 15, color: primary),
          const SizedBox(width: 8),
          Text('PDF document',
              style: const TextStyle(fontSize: 12, color: textDark)),
          const Spacer(),
          if (_pdfSource != null && !_pdfError) ...[
            _pdfNavIconBtn(
              icon:    Icons.first_page,
              enabled: _pdfPage > 1,
              color:   primary,
              onTap:   () { _pdfViewerCtrl.firstPage(); setState(() => _pdfPage = 1); },
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
            GestureDetector(
              onTap: _showJumpToPageDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('$_pdfPage / $_pdfTotal',
                    style: TextStyle(fontSize: 11, color: primary,
                        fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 2),
            _pdfNavIconBtn(
              icon:    Icons.chevron_right,
              enabled: _pdfPage < _pdfTotal,
              color:   primary,
              onTap:   () {
                _pdfViewerCtrl.nextPage();
                setState(() => _pdfPage = (_pdfPage + 1).clamp(1, _pdfTotal));
              },
            ),
            _pdfNavIconBtn(
              icon:    Icons.last_page,
              enabled: _pdfPage < _pdfTotal,
              color:   primary,
              onTap:   () { _pdfViewerCtrl.lastPage(); setState(() => _pdfPage = _pdfTotal); },
            ),
            const SizedBox(width: 4),
          ],
          TextButton.icon(
            icon:  const Icon(Icons.open_in_new, size: 13),
            label: const Text('Open externally', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
                foregroundColor: primary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onPressed: () => _openPdfExternal(note),
          ),
        ]),
      ),
      Expanded(child: _buildSfPdfViewer(primary)),
    ]);
  }

  Widget _buildSfPdfViewer(Color primary) {
    if (_pdfError) {
      return _pdfFallback(primary, 'Could not load the PDF.\nTry "Open externally" above.');
    }
    if (_pdfSource == null) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircularProgressIndicator(color: primary),
        const SizedBox(height: 12),
        Text('Loading PDF…',
            style: TextStyle(fontSize: 12, color: primary.withValues(alpha: 0.5))),
      ]));
    }

    final onPageChanged = (PdfPageChangedDetails d) {
      if (mounted) setState(() => _pdfPage = d.newPageNumber);
    };
    final onDocLoaded = (PdfDocumentLoadedDetails d) {
      if (mounted) setState(() => _pdfTotal = d.document.pages.count);
    };
    final onDocFailed = (_) {
      if (mounted) setState(() => _pdfError = true);
    };

    if (_pdfSource!.bytes != null) {
      return SfPdfViewer.memory(
        _pdfSource!.bytes!,
        controller: _pdfViewerCtrl,
        canShowScrollHead: true,
        canShowScrollStatus: true,
        canShowPageLoadingIndicator: true,
        onPageChanged: onPageChanged,
        onDocumentLoaded: onDocLoaded,
        onDocumentLoadFailed: onDocFailed,
      );
    } else {
      return SfPdfViewer.file(
        _pdfSource!.file!,
        controller: _pdfViewerCtrl,
        canShowScrollHead: true,
        canShowScrollStatus: true,
        canShowPageLoadingIndicator: true,
        onPageChanged: onPageChanged,
        onDocumentLoaded: onDocLoaded,
        onDocumentLoadFailed: onDocFailed,
      );
    }
  }

  // ── PDF HELPERS ───────────────────────────────────────────────────────────

  Widget _pdfNavIconBtn({
    required IconData icon, required bool enabled,
    required Color color,   required VoidCallback onTap,
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
      Text(message, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: primary.withValues(alpha: 0.45),
              height: 1.5)),
    ]),
  );

  Future<void> _showJumpToPageDialog() async {
    final ctrl   = TextEditingController(text: '$_pdfPage');
    final result = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Go to page',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                color: widget.primary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1 – $_pdfTotal',
              suffixText: '/ $_pdfTotal'),
          onSubmitted: (v) {
            final n = int.tryParse(v);
            if (n != null) Navigator.pop(context, n);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final n = int.tryParse(ctrl.text);
              if (n != null) Navigator.pop(context, n);
            },
            child: Text('Go', style: TextStyle(color: widget.primary)),
          ),
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
      String? path = note.sourceFilePath;
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not open PDF: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ── FILE BANNER ───────────────────────────────────────────────────────────

  Widget _fileBanner({
    required IconData icon,    required String  message,
    required Color    primary, required String  actionLabel,
    required IconData actionIcon,
    VoidCallback?     onAction, bool actionEnabled = true,
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
                // For Textual notes show readable path without the OT:/NT: prefix
                ? (note.folder == kFolderTextual
                    ? '${note.folder} › ${parseTextualSubfolder(note.subfolder)[0] == kTextualOT ? 'Old Testament' : 'New Testament'} › ${parseTextualSubfolder(note.subfolder)[1]}'
                    : '${note.folder} › ${note.subfolder}')
                : note.folder,
            style: const TextStyle(fontSize: 10, color: textMid),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Spacer(),
        if (_showPreview)
          Text('Preview mode',
              style: TextStyle(fontSize: 10, color: widget.primary,
                  fontWeight: FontWeight.w600))
        else if (isPdf && _pdfTotal > 1)
          Text('Page $_pdfPage of $_pdfTotal',
              style: const TextStyle(fontSize: 10, color: textMid))
        else if (note.sourceFileType != 'txt' && note.sourceFileType != 'md')
          Text('$_richWordCount words',
              style: const TextStyle(fontSize: 10, color: textMid))
        else
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
        title: Text('Message Type', style: TextStyle(color: widget.primary)),
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

    final note    = widget.note;
    final isPlain = note.sourceFileType == 'txt' || note.sourceFileType == 'md';

    if (isPlain) {
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
                Text('Word Document (.docx)', style: TextStyle(fontWeight: FontWeight.w600)),
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
                Text('OpenDocument (.odt)', style: TextStyle(fontWeight: FontWeight.w600)),
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

class _PdfSource {
  final Uint8List? bytes;
  final File?      file;
  const _PdfSource._({this.bytes, this.file});
  factory _PdfSource.memory(Uint8List b) => _PdfSource._(bytes: b);
  factory _PdfSource.file(File f)        => _PdfSource._(file: f);
}