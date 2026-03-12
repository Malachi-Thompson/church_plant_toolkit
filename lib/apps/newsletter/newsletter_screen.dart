// lib/apps/newsletter/newsletter_screen.dart
//
// Newsletter Builder — compose a church newsletter, preview it,
// export as a styled PDF, and generate an email-ready HTML version.
//
// Layout: Left = issue list  |  Centre = editor  |  Right = preview panel
//
// PDF export: builds a print-ready HTML file and opens it in the browser
//   (File → Print → Save as PDF) — same pattern as note_exporter.dart.
// Email export: saves a self-contained HTML file the user can paste into
//   Mailchimp, Constant Contact, or any email client.

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_state.dart';
import '../../theme.dart';

// ══════════════════════════════════════════════════════════════════════════════
// DATA MODEL
// ══════════════════════════════════════════════════════════════════════════════

enum NewsletterSection { announcement, sermon, event, prayer, scripture, custom }

const _sectionLabels = <NewsletterSection, String>{
  NewsletterSection.announcement: 'Announcement',
  NewsletterSection.sermon:       'Sermon Recap',
  NewsletterSection.event:        'Upcoming Event',
  NewsletterSection.prayer:       'Prayer Request',
  NewsletterSection.scripture:    'Scripture',
  NewsletterSection.custom:       'Custom Section',
};

const _sectionIcons = <NewsletterSection, IconData>{
  NewsletterSection.announcement: Icons.campaign_outlined,
  NewsletterSection.sermon:       Icons.menu_book_outlined,
  NewsletterSection.event:        Icons.event_outlined,
  NewsletterSection.prayer:       Icons.volunteer_activism_outlined,
  NewsletterSection.scripture:    Icons.format_quote_outlined,
  NewsletterSection.custom:       Icons.edit_note_outlined,
};

class NewsletterBlock {
  final String id;
  NewsletterSection type;
  String heading;
  String body;
  String date;   // optional — used by event blocks

  NewsletterBlock({
    required this.id,
    required this.type,
    this.heading = '',
    this.body    = '',
    this.date    = '',
  });

  Map<String, dynamic> toJson() => {
    'id':      id,
    'type':    type.name,
    'heading': heading,
    'body':    body,
    'date':    date,
  };

  factory NewsletterBlock.fromJson(Map<String, dynamic> j) => NewsletterBlock(
    id:      j['id']      ?? const Uuid().v4(),
    type:    NewsletterSection.values.firstWhere(
                 (s) => s.name == j['type'],
                 orElse: () => NewsletterSection.custom),
    heading: j['heading'] ?? '',
    body:    j['body']    ?? '',
    date:    j['date']    ?? '',
  );
}

class NewsletterIssue {
  final String id;
  String title;
  String subtitle;
  DateTime issueDate;
  List<NewsletterBlock> blocks;
  String logoPath;

  NewsletterIssue({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.issueDate,
    required this.blocks,
    this.logoPath = '',
  });

  Map<String, dynamic> toJson() => {
    'id':        id,
    'title':     title,
    'subtitle':  subtitle,
    'issueDate': issueDate.toIso8601String(),
    'blocks':    blocks.map((b) => b.toJson()).toList(),
    'logoPath':  logoPath,
  };

  factory NewsletterIssue.fromJson(Map<String, dynamic> j) => NewsletterIssue(
    id:        j['id']       ?? const Uuid().v4(),
    title:     j['title']    ?? 'Newsletter',
    subtitle:  j['subtitle'] ?? '',
    issueDate: DateTime.tryParse(j['issueDate'] ?? '') ?? DateTime.now(),
    blocks:    (j['blocks'] as List? ?? [])
                   .map((b) => NewsletterBlock.fromJson(b)).toList(),
    logoPath:  j['logoPath'] ?? '',
  );

  NewsletterIssue copyWith({
    String? title, String? subtitle, DateTime? issueDate,
    List<NewsletterBlock>? blocks, String? logoPath,
  }) => NewsletterIssue(
    id:        id,
    title:     title     ?? this.title,
    subtitle:  subtitle  ?? this.subtitle,
    issueDate: issueDate ?? this.issueDate,
    blocks:    blocks    ?? this.blocks,
    logoPath:  logoPath  ?? this.logoPath,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// PERSISTENCE
// ══════════════════════════════════════════════════════════════════════════════

const _kPrefKey = 'newsletter_issues_v1';

Future<List<NewsletterIssue>> _loadIssues() async {
  final prefs = await SharedPreferences.getInstance();
  final raw   = prefs.getString(_kPrefKey);
  if (raw == null) return [];
  final list  = jsonDecode(raw) as List;
  return list.map((j) => NewsletterIssue.fromJson(j)).toList();
}

Future<void> _saveIssues(List<NewsletterIssue> issues) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kPrefKey, jsonEncode(issues.map((i) => i.toJson()).toList()));
}

// ══════════════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class NewsletterScreen extends StatefulWidget {
  const NewsletterScreen({super.key});

  @override
  State<NewsletterScreen> createState() => _NewsletterScreenState();
}

class _NewsletterScreenState extends State<NewsletterScreen> {
  List<NewsletterIssue> _issues     = [];
  NewsletterIssue?      _selected;
  bool                  _loading    = true;
  bool                  _showPreview = false;

  // Editor controllers for the selected issue header fields
  final _titleCtrl    = TextEditingController();
  final _subtitleCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadIssues().then((list) {
      setState(() { _issues = list; _loading = false; });
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color get _primary   => context.read<AppState>().brandPrimary;
  Color get _secondary => context.read<AppState>().brandSecondary;

  String get _churchName =>
      context.read<AppState>().churchProfile?.name ?? 'Church Newsletter';
  String get _churchLogoPath =>
      context.read<AppState>().churchProfile?.logoPath ?? '';

  void _selectIssue(NewsletterIssue issue) {
    setState(() {
      _selected = issue;
      _titleCtrl.text    = issue.title;
      _subtitleCtrl.text = issue.subtitle;
      _showPreview = false;
    });
  }

  void _newIssue() {
    final issue = NewsletterIssue(
      id:        const Uuid().v4(),
      title:     _churchName,
      subtitle:  'Weekly Newsletter',
      issueDate: DateTime.now(),
      blocks: [
        NewsletterBlock(
          id:      const Uuid().v4(),
          type:    NewsletterSection.announcement,
          heading: 'Welcome',
          body:    'Thank you for joining us this week!',
        ),
      ],
      logoPath: _churchLogoPath,
    );
    setState(() {
      _issues.insert(0, issue);
      _selectIssue(issue);
    });
    _persist();
  }

  void _deleteIssue(NewsletterIssue issue) {
    setState(() {
      _issues.removeWhere((i) => i.id == issue.id);
      if (_selected?.id == issue.id) _selected = null;
    });
    _persist();
  }

  void _persist() => _saveIssues(_issues);

  void _updateSelected(NewsletterIssue updated) {
    setState(() {
      final idx = _issues.indexWhere((i) => i.id == updated.id);
      if (idx != -1) _issues[idx] = updated;
      _selected = updated;
    });
    _persist();
  }

  // ── Export ────────────────────────────────────────────────────────────────

  Future<void> _exportPdf() async {
    final issue = _selected;
    if (issue == null) return;
    final html  = _buildHtml(issue, forEmail: false);
    final tmp   = await getTemporaryDirectory();
    final safe  = issue.title.replaceAll(RegExp(r'[^\w\s\-]'), '').trim()
                             .replaceAll(' ', '_');
    final file  = File('${tmp.path}/${safe}_newsletter.html');
    await file.writeAsString(html);
    final uri   = Uri.file(file.path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'Opened in browser — use File › Print › Save as PDF')));
    }
  }

  Future<void> _exportEmail() async {
    final issue = _selected;
    if (issue == null) return;
    final html  = _buildHtml(issue, forEmail: true);
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Email HTML',
      fileName:    '${issue.title.replaceAll(' ', '_')}_email.html',
      type: FileType.custom,
      allowedExtensions: ['html'],
    );
    if (result != null) {
      await File(result).writeAsString(html);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Email HTML saved to $result')));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary   = _primary;
    final secondary = _secondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Newsletter Builder'),
        backgroundColor: primary,
        foregroundColor: contrastOn(primary),
        actions: [
          if (_selected != null) ...[
            IconButton(
              icon: Icon(_showPreview
                  ? Icons.edit_outlined
                  : Icons.preview_outlined),
              tooltip: _showPreview ? 'Back to Editor' : 'Preview',
              onPressed: () => setState(() => _showPreview = !_showPreview),
            ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Export PDF',
              onPressed: _exportPdf,
            ),
            IconButton(
              icon: const Icon(Icons.email_outlined),
              tooltip: 'Export Email HTML',
              onPressed: _exportEmail,
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(children: [
              // ── Issue list sidebar ─────────────────────────────────────────
              SizedBox(
                width: 240,
                child: _IssueList(
                  issues:     _issues,
                  selected:   _selected,
                  primary:    primary,
                  secondary:  secondary,
                  onSelect:   _selectIssue,
                  onDelete:   _deleteIssue,
                  onNew:      _newIssue,
                ),
              ),
              const VerticalDivider(width: 1),
              // ── Editor / Preview ───────────────────────────────────────────
              Expanded(
                child: _selected == null
                    ? _EmptyState(primary: primary, onNew: _newIssue)
                    : _showPreview
                        ? _PreviewPanel(
                            issue:   _selected!,
                            primary: primary,
                            html:    _buildHtml(_selected!, forEmail: false))
                        : _IssueEditor(
                            key:          ValueKey(_selected!.id),
                            issue:        _selected!,
                            primary:      primary,
                            secondary:    secondary,
                            titleCtrl:    _titleCtrl,
                            subtitleCtrl: _subtitleCtrl,
                            onChanged:    _updateSelected,
                          ),
              ),
            ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HTML GENERATION
  // ══════════════════════════════════════════════════════════════════════════

  String _buildHtml(NewsletterIssue issue, {required bool forEmail}) {
    final primary   = _primary;
    final secondary = _secondary;
    final pHex      = '#${primary.value.toRadixString(16).substring(2).toUpperCase()}';
    final sHex      = '#${secondary.value.toRadixString(16).substring(2).toUpperCase()}';
    final dateStr   = DateFormat('MMMM d, y').format(issue.issueDate);
    final church    = _churchName;

    final logoHtml = (issue.logoPath.isNotEmpty &&
            File(issue.logoPath).existsSync())
        ? '<img src="file://${issue.logoPath}" style="height:60px;object-fit:contain;margin-bottom:8px;" alt="Logo">'
        : '';

    final blocksHtml = issue.blocks.map((b) => _blockHtml(b, pHex, sHex)).join('\n');

    final width = forEmail ? '600px' : '800px';

    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${_esc(issue.title)}</title>
<style>
  @media print {
    body { margin: 0; }
    .no-print { display: none !important; }
  }
  body {
    margin: 0; padding: 20px;
    font-family: Georgia, 'Times New Roman', serif;
    background: #f4f4f4;
    color: #222;
  }
  .wrapper {
    max-width: $width; margin: 0 auto;
    background: #fff;
    border-radius: 8px;
    overflow: hidden;
    box-shadow: 0 2px 12px rgba(0,0,0,0.10);
  }
  .header {
    background: $pHex;
    color: #fff;
    text-align: center;
    padding: 36px 32px 28px;
  }
  .header h1 { margin:0 0 6px; font-size: 28px; letter-spacing:.5px; }
  .header p  { margin:0; font-size: 14px; opacity:.80; }
  .date-bar {
    background: $sHex;
    color: #fff;
    text-align: center;
    padding: 8px;
    font-size: 13px;
    font-family: Arial, sans-serif;
    letter-spacing: .5px;
  }
  .content { padding: 28px 36px; }
  .block { margin-bottom: 28px; }
  .block-label {
    font-family: Arial, sans-serif;
    font-size: 10px;
    font-weight: bold;
    letter-spacing: 1.4px;
    text-transform: uppercase;
    color: $pHex;
    margin-bottom: 4px;
  }
  .block h2 {
    font-size: 20px;
    margin: 0 0 8px;
    color: #1a1a1a;
    border-bottom: 2px solid $sHex;
    padding-bottom: 4px;
  }
  .block p { font-size: 15px; line-height: 1.75; margin: 0; color: #333; }
  .block.scripture {
    background: #f7f3ee;
    border-left: 4px solid $sHex;
    padding: 14px 18px;
    border-radius: 0 6px 6px 0;
    font-style: italic;
  }
  .block.scripture h2 { border-bottom: none; color: $pHex; font-size: 15px; }
  .block.event .event-date {
    font-family: Arial, sans-serif;
    font-size: 12px;
    color: $sHex;
    font-weight: bold;
    margin-bottom: 4px;
  }
  .footer {
    background: #f0f0f0;
    text-align: center;
    padding: 18px;
    font-family: Arial, sans-serif;
    font-size: 12px;
    color: #777;
    border-top: 1px solid #ddd;
  }
  .footer a { color: $pHex; text-decoration: none; }
</style>
</head>
<body>
<div class="wrapper">
  <div class="header">
    $logoHtml
    <h1>${_esc(issue.title)}</h1>
    <p>${_esc(issue.subtitle.isNotEmpty ? issue.subtitle : church)}</p>
  </div>
  <div class="date-bar">$dateStr</div>
  <div class="content">
    $blocksHtml
  </div>
  <div class="footer">
    &copy; ${DateTime.now().year} ${_esc(church)} &nbsp;|&nbsp;
    Sent with Church Plant Toolkit
  </div>
</div>
</body>
</html>''';
  }

  String _blockHtml(NewsletterBlock b, String pHex, String sHex) {
    final cssClass = b.type.name;
    final label    = _sectionLabels[b.type] ?? '';
    final dateRow  = (b.type == NewsletterSection.event && b.date.isNotEmpty)
        ? '<div class="event-date">📅 ${_esc(b.date)}</div>'
        : '';
    return '''
<div class="block $cssClass">
  <div class="block-label">$label</div>
  ${b.heading.isNotEmpty ? '<h2>${_esc(b.heading)}</h2>' : ''}
  $dateRow
  ${b.body.isNotEmpty ? '<p>${_esc(b.body).replaceAll('\n', '<br>')}</p>' : ''}
</div>''';
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

// ══════════════════════════════════════════════════════════════════════════════
// ISSUE LIST SIDEBAR
// ══════════════════════════════════════════════════════════════════════════════

class _IssueList extends StatelessWidget {
  final List<NewsletterIssue> issues;
  final NewsletterIssue?      selected;
  final Color                 primary;
  final Color                 secondary;
  final ValueChanged<NewsletterIssue> onSelect;
  final ValueChanged<NewsletterIssue> onDelete;
  final VoidCallback          onNew;

  const _IssueList({
    required this.issues, required this.selected,
    required this.primary, required this.secondary,
    required this.onSelect, required this.onDelete, required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F9FA),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
          child: Row(children: [
            const Text('Issues',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                    color: textMid)),
            const Spacer(),
            Text('${issues.length}',
                style: const TextStyle(fontSize: 11, color: textMid)),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.add, size: 18, color: primary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: onNew,
              tooltip: 'New issue',
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: issues.isEmpty
              ? Center(child: Text('No issues yet',
                    style: TextStyle(color: primary.withValues(alpha: 0.4),
                        fontSize: 13)))
              : ListView.separated(
                  itemCount: issues.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 14),
                  itemBuilder: (ctx, i) {
                    final issue = issues[i];
                    final sel   = selected?.id == issue.id;
                    return GestureDetector(
                      onTap: () => onSelect(issue),
                      onSecondaryTapUp: (d) async {
                        final result = await showMenu<String>(
                          context: ctx,
                          position: RelativeRect.fromLTRB(
                              d.globalPosition.dx, d.globalPosition.dy,
                              d.globalPosition.dx, d.globalPosition.dy),
                          items: [
                            const PopupMenuItem(value: 'delete',
                                child: Row(children: [
                                  Icon(Icons.delete_outline,
                                      size: 16, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete',
                                      style: TextStyle(color: Colors.red)),
                                ])),
                          ],
                        );
                        if (result == 'delete') onDelete(issue);
                      },
                      child: Container(
                        color: sel ? primary.withValues(alpha: 0.07) : null,
                        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(issue.title,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: sel ? primary : textDark),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(
                              DateFormat('MMM d, y').format(issue.issueDate),
                              style: const TextStyle(
                                  fontSize: 11, color: textMid),
                            ),
                            Text('${issue.blocks.length} section(s)',
                                style: const TextStyle(
                                    fontSize: 10, color: textMid)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ISSUE EDITOR
// ══════════════════════════════════════════════════════════════════════════════

class _IssueEditor extends StatefulWidget {
  final NewsletterIssue issue;
  final Color           primary;
  final Color           secondary;
  final TextEditingController titleCtrl;
  final TextEditingController subtitleCtrl;
  final ValueChanged<NewsletterIssue> onChanged;

  const _IssueEditor({
    super.key,
    required this.issue,
    required this.primary,
    required this.secondary,
    required this.titleCtrl,
    required this.subtitleCtrl,
    required this.onChanged,
  });

  @override
  State<_IssueEditor> createState() => _IssueEditorState();
}

class _IssueEditorState extends State<_IssueEditor> {
  late NewsletterIssue _issue;

  @override
  void initState() {
    super.initState();
    _issue = widget.issue;
  }

  void _update(NewsletterIssue updated) {
    setState(() => _issue = updated);
    widget.onChanged(updated);
  }

  void _updateBlock(NewsletterBlock updated) {
    final blocks = _issue.blocks.map(
        (b) => b.id == updated.id ? updated : b).toList();
    _update(_issue.copyWith(blocks: blocks));
  }

  void _deleteBlock(String id) {
    final blocks = _issue.blocks.where((b) => b.id != id).toList();
    _update(_issue.copyWith(blocks: blocks));
  }

  void _addBlock(NewsletterSection type) {
    final block = NewsletterBlock(
      id:      const Uuid().v4(),
      type:    type,
      heading: _sectionLabels[type] ?? '',
    );
    _update(_issue.copyWith(blocks: [..._issue.blocks, block]));
  }

  void _moveBlock(int oldIdx, int newIdx) {
    final blocks = List<NewsletterBlock>.from(_issue.blocks);
    final item   = blocks.removeAt(oldIdx);
    blocks.insert(newIdx, item);
    _update(_issue.copyWith(blocks: blocks));
  }

  @override
  Widget build(BuildContext context) {
    final primary   = widget.primary;
    final secondary = widget.secondary;

    return Column(children: [
      // ── Header fields ──────────────────────────────────────────────────────
      Container(
        color: const Color(0xFFFAFAFB),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(children: [
          Row(children: [
            Expanded(child: TextField(
              controller: widget.titleCtrl,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                  labelText: 'Newsletter Title',
                  border: OutlineInputBorder(), isDense: true),
              onChanged: (v) => _update(_issue.copyWith(title: v)),
            )),
            const SizedBox(width: 12),
            // Issue date picker
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(DateFormat('MMM d, y').format(_issue.issueDate)),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _issue.issueDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) _update(_issue.copyWith(issueDate: d));
              },
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: widget.subtitleCtrl,
            decoration: const InputDecoration(
                labelText: 'Subtitle / Edition',
                border: OutlineInputBorder(), isDense: true),
            onChanged: (v) => _update(_issue.copyWith(subtitle: v)),
          ),
        ]),
      ),
      const Divider(height: 1),
      // ── Blocks list ────────────────────────────────────────────────────────
      Expanded(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
          itemCount: _issue.blocks.length,
          onReorder: _moveBlock,
          itemBuilder: (ctx, i) {
            final block = _issue.blocks[i];
            return _BlockCard(
              key:       ValueKey(block.id),
              block:     block,
              primary:   primary,
              secondary: secondary,
              onChanged: _updateBlock,
              onDelete:  () => _deleteBlock(block.id),
            );
          },
        ),
      ),
      // ── Add section bar ────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: borderColor)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            const Text('Add section:',
                style: TextStyle(fontSize: 12, color: textMid)),
            const SizedBox(width: 10),
            ...NewsletterSection.values.map((s) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: Icon(_sectionIcons[s], size: 14, color: primary),
                label: Text(_sectionLabels[s]!,
                    style: TextStyle(fontSize: 12, color: primary)),
                backgroundColor: primary.withValues(alpha: 0.07),
                side: BorderSide(color: primary.withValues(alpha: 0.2)),
                onPressed: () => _addBlock(s),
              ),
            )),
          ]),
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BLOCK CARD
// ══════════════════════════════════════════════════════════════════════════════

class _BlockCard extends StatefulWidget {
  final NewsletterBlock block;
  final Color           primary;
  final Color           secondary;
  final ValueChanged<NewsletterBlock> onChanged;
  final VoidCallback    onDelete;

  const _BlockCard({
    super.key,
    required this.block,
    required this.primary,
    required this.secondary,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_BlockCard> createState() => _BlockCardState();
}

class _BlockCardState extends State<_BlockCard> {
  late TextEditingController _headCtrl;
  late TextEditingController _bodyCtrl;
  late TextEditingController _dateCtrl;

  @override
  void initState() {
    super.initState();
    _headCtrl = TextEditingController(text: widget.block.heading);
    _bodyCtrl = TextEditingController(text: widget.block.body);
    _dateCtrl = TextEditingController(text: widget.block.date);
  }

  @override
  void dispose() {
    _headCtrl.dispose();
    _bodyCtrl.dispose();
    _dateCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged(NewsletterBlock(
      id:      widget.block.id,
      type:    widget.block.type,
      heading: _headCtrl.text,
      body:    _bodyCtrl.text,
      date:    _dateCtrl.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final primary   = widget.primary;
    final isScripture = widget.block.type == NewsletterSection.scripture;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header row
          Row(children: [
            Icon(_sectionIcons[widget.block.type] ?? Icons.edit_note,
                size: 16, color: primary),
            const SizedBox(width: 6),
            Text(_sectionLabels[widget.block.type] ?? '',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold,
                    color: primary, letterSpacing: 0.8)),
            const Spacer(),
            // Drag handle hint
            Icon(Icons.drag_handle, size: 18, color: Colors.grey.shade400),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: Colors.red),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: widget.onDelete,
            ),
          ]),
          const SizedBox(height: 8),
          // Heading
          if (!isScripture)
            TextField(
              controller: _headCtrl,
              decoration: const InputDecoration(
                  labelText: 'Heading',
                  border: OutlineInputBorder(), isDense: true),
              onChanged: (_) => _notify(),
            ),
          if (!isScripture) const SizedBox(height: 8),
          // Event date
          if (widget.block.type == NewsletterSection.event) ...[
            TextField(
              controller: _dateCtrl,
              decoration: const InputDecoration(
                  labelText: 'Event Date / Time',
                  border: OutlineInputBorder(), isDense: true),
              onChanged: (_) => _notify(),
            ),
            const SizedBox(height: 8),
          ],
          // Scripture heading (ref)
          if (isScripture)
            TextField(
              controller: _headCtrl,
              decoration: const InputDecoration(
                  labelText: 'Reference (e.g. John 3:16)',
                  border: OutlineInputBorder(), isDense: true),
              onChanged: (_) => _notify(),
            ),
          if (isScripture) const SizedBox(height: 8),
          // Body
          TextField(
            controller: _bodyCtrl,
            maxLines: null,
            minLines: 3,
            decoration: InputDecoration(
                labelText: isScripture ? 'Verse text' : 'Body text',
                border: const OutlineInputBorder(), isDense: true,
                alignLabelWithHint: true),
            onChanged: (_) => _notify(),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PREVIEW PANEL
// ══════════════════════════════════════════════════════════════════════════════

class _PreviewPanel extends StatelessWidget {
  final NewsletterIssue issue;
  final Color           primary;
  final String          html;

  const _PreviewPanel({
    required this.issue, required this.primary, required this.html});

  @override
  Widget build(BuildContext context) {
    // Since webview is Windows-only in this project, show a styled text preview
    final dateStr = DateFormat('MMMM d, y').format(issue.issueDate);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Header
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10)),
              ),
              child: Column(children: [
                Text(issue.title,
                    style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold,
                        color: contrastOn(primary)),
                    textAlign: TextAlign.center),
                if (issue.subtitle.isNotEmpty)
                  Text(issue.subtitle,
                      style: TextStyle(
                          color: contrastOn(primary).withValues(alpha: 0.7),
                          fontSize: 14),
                      textAlign: TextAlign.center),
              ]),
            ),
            Container(
              color: context.read<AppState>().brandSecondary,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(dateStr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ),
            // Blocks
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(10)),
              ),
              child: Column(children: issue.blocks.map((b) =>
                  _PreviewBlock(block: b, primary: primary)).toList()),
            ),
            const SizedBox(height: 8),
            const Text('Preview — export as PDF or Email HTML to share',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: textMid)),
          ]),
        ),
      ),
    );
  }
}

class _PreviewBlock extends StatelessWidget {
  final NewsletterBlock block;
  final Color           primary;
  const _PreviewBlock({required this.block, required this.primary});

  @override
  Widget build(BuildContext context) {
    final secondary = context.read<AppState>().brandSecondary;
    final isScripture = block.type == NewsletterSection.scripture;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: isScripture
          ? const EdgeInsets.all(14)
          : EdgeInsets.zero,
      decoration: isScripture
          ? BoxDecoration(
              color: const Color(0xFFF7F3EE),
              border: Border(
                  left: BorderSide(color: secondary, width: 4)),
              borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(6)),
            )
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_sectionLabels[block.type]!.toUpperCase(),
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold,
                color: primary, letterSpacing: 1.4)),
        const SizedBox(height: 4),
        if (block.heading.isNotEmpty)
          Text(block.heading,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold,
                  color: isScripture ? primary : textDark)),
        if (block.date.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text('📅 ${block.date}',
                style: TextStyle(
                    fontSize: 12, color: secondary,
                    fontWeight: FontWeight.bold)),
          ),
        if (block.body.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(block.body,
              style: TextStyle(
                  fontSize: 14, height: 1.7,
                  color: textDark,
                  fontStyle: isScripture
                      ? FontStyle.italic
                      : FontStyle.normal)),
        ],
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ══════════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final Color primary;
  final VoidCallback onNew;
  const _EmptyState({required this.primary, required this.onNew});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.newspaper_outlined,
          size: 56, color: primary.withValues(alpha: 0.15)),
      const SizedBox(height: 16),
      Text('No issue selected',
          style: TextStyle(
              color: primary.withValues(alpha: 0.35), fontSize: 15)),
      const SizedBox(height: 12),
      ElevatedButton.icon(
        onPressed: onNew,
        icon: const Icon(Icons.add),
        label: const Text('Create First Issue'),
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: contrastOn(primary),
        ),
      ),
    ]),
  );
}