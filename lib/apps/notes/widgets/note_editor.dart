// lib/apps/notes/widgets/note_editor.dart
//
// Full-screen note editor with:
//   • Toolbar: message type, date, translation chips + action icons
//   • Expositional / topical meta bar
//   • Title field
//   • Scrollable content area (grows with text, scrollbar on demand)
//   • Status bar: folder path, word count, last-saved time
//   • PDF view-only mode with open-in-system-viewer button
//   • DOCX editable mode with re-export button

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/bible_service.dart';
import '../../../theme.dart';
import '../../../widgets/scripture_field.dart';
import '../note_constants.dart';
import '../note_model.dart';
import '../dialogs/translation_picker_dialog.dart';
import '../dialogs/verse_import_dialog.dart';
import 'shared_widgets.dart';

class NoteEditor extends StatefulWidget {
  final NoteModel          note;
  final Color              primary;
  final Color              secondary;
  final BibleService       bibleService;
  final VoidCallback       onChanged;
  final VoidCallback       onArchive;
  final ValueChanged<bool> onExport; // true = pdf

  const NoteEditor({
    super.key,
    required this.note,
    required this.primary,
    required this.secondary,
    required this.bibleService,
    required this.onChanged,
    required this.onArchive,
    required this.onExport,
  });

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;
  late TextEditingController _seriesCtrl;
  final ScrollController     _scrollCtrl = ScrollController();

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
    _scrollCtrl.dispose();
    for (final c in [_titleCtrl, _contentCtrl, _seriesCtrl]) {
      c.removeListener(_sync);
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        // Row 1: meta chips (wrap so they never overflow)
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
        ]),
        const SizedBox(height: 2),
        // Row 2: action icons — always fits, right-aligned
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
              const PopupMenuItem(value: 'pdf', child: Row(children: [
                Icon(Icons.picture_as_pdf_outlined, size: 16),
                SizedBox(width: 8), Text('Export as PDF')])),
            ],
            onSelected: (v) => widget.onExport(v == 'pdf'),
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

  // ── EXPOSITIONAL / TOPICAL META BAR ───────────────────────────────────────

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

  // ── TITLE FIELD ───────────────────────────────────────────────────────────

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

  // ── CONTENT AREA ─────────────────────────────────────────────────────────

  Widget _buildContentArea(NoteModel note, Color primary) {
    final isPdf  = note.sourceFileType == 'pdf';
    final isDocx = note.sourceFileType == 'docx';

    if (isPdf) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _fileTypeBanner(
          icon:    Icons.picture_as_pdf_outlined,
          message: 'PDF — view-only in app.',
          primary: primary,
          actionLabel: 'Open PDF',
          actionIcon:  Icons.open_in_browser,
          onAction: () => _openPdfInBrowser(note),
        ),
        Expanded(child: _scrollableText(note.content.isEmpty
            ? '(PDF content not extracted — use Open PDF to view)'
            : note.content)),
      ]);
    }

    if (isDocx) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _fileTypeBanner(
          icon:    Icons.description_outlined,
          message: 'Imported from .docx — editing plain text.',
          primary: primary,
          actionLabel: 'Re-export .docx',
          actionIcon:  Icons.download_outlined,
          onAction: () => widget.onExport(false),
        ),
        Expanded(child: _editableScrollArea(primary)),
      ]);
    }

    return _editableScrollArea(primary);
  }

  Widget _fileTypeBanner({
    required IconData  icon,
    required String    message,
    required Color     primary,
    required String    actionLabel,
    required IconData  actionIcon,
    required VoidCallback onAction,
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
          onPressed: onAction,
        ),
      ]),
    );
  }

  Widget _scrollableText(String text) => Scrollbar(
    controller: _scrollCtrl,
    thumbVisibility: false,
    child: SingleChildScrollView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Text(text,
          style: const TextStyle(fontSize: 14, height: 1.7, color: textDark)),
    ),
  );

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
    if (result != null && result.isNotEmpty) {
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
    }
  }

  Future<void> _openPdfInBrowser(NoteModel note) async {
    try {
      if (note.sourceFileBytes != null) {
        final tmp  = await getTemporaryDirectory();
        final safe = note.title.replaceAll(RegExp(r'[^\w\s]'), '').trim();
        final file = File('${tmp.path}/$safe.pdf');
        await file.writeAsBytes(note.sourceFileBytes!);
        final uri = Uri.file(file.path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else if (note.sourceFilePath != null) {
        final uri = Uri.file(note.sourceFilePath!);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
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
}