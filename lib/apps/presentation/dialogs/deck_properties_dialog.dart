// lib/apps/presentation/dialogs/deck_properties_dialog.dart
//
// Full deck metadata editor:
//   • Title, Description, Author
//   • Service date picker
//   • Tags (add / remove chips)
//   • Private notes
//   • File info (path, size, created/modified dates)
//   • Pin / Template toggle

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/presentation_models.dart';

Future<Deck?> showDeckPropertiesDialog(
  BuildContext context, {
  required Deck  deck,
  required Color primary,
}) {
  return showDialog<Deck>(
    context: context,
    builder: (_) => _DeckPropertiesDialog(deck: deck, primary: primary),
  );
}

class _DeckPropertiesDialog extends StatefulWidget {
  final Deck  deck;
  final Color primary;
  const _DeckPropertiesDialog({required this.deck, required this.primary});

  @override
  State<_DeckPropertiesDialog> createState() => _DeckPropertiesDialogState();
}

class _DeckPropertiesDialogState extends State<_DeckPropertiesDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // ── controllers ────────────────────────────────────────────────────────────
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _authorCtrl;
  late TextEditingController _notesCtrl;
  late TextEditingController _tagCtrl;

  // ── mutable state ──────────────────────────────────────────────────────────
  late List<String> _tags;
  late bool         _isPinned;
  late bool         _isTemplate;
  DateTime?         _serviceDate;

  // ── file info ──────────────────────────────────────────────────────────────
  int?   _fileSizeBytes;

  @override
  void initState() {
    super.initState();
    _tabs        = TabController(length: 3, vsync: this);
    final d      = widget.deck;
    _nameCtrl    = TextEditingController(text: d.name);
    _descCtrl    = TextEditingController(text: d.description);
    _authorCtrl  = TextEditingController(text: d.author);
    _notesCtrl   = TextEditingController(text: d.notes);
    _tagCtrl     = TextEditingController();
    _tags        = List.of(d.tags);
    _isPinned    = d.isPinned;
    _isTemplate  = d.isTemplate;
    _serviceDate = d.serviceDate;
    _loadFileSize();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _authorCtrl.dispose();
    _notesCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFileSize() async {
    if (widget.deck.filePath == null) return;
    try {
      final f    = File(widget.deck.filePath!);
      final stat = await f.stat();
      if (mounted) setState(() => _fileSizeBytes = stat.size);
    } catch (_) {}
  }

  void _addTag() {
    final t = _tagCtrl.text.trim();
    if (t.isNotEmpty && !_tags.contains(t)) {
      setState(() { _tags.add(t); _tagCtrl.clear(); });
    }
  }

  Future<void> _pickDate() async {
    final now  = DateTime.now();
    final date = await showDatePicker(
      context:       context,
      initialDate:   _serviceDate ?? now,
      firstDate:     DateTime(2000),
      lastDate:      DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(primary: widget.primary),
        ),
        child: child!,
      ),
    );
    if (date != null) setState(() => _serviceDate = date);
  }

  Deck _buildResult() {
    final d = widget.deck;
    return Deck(
      id:             d.id,
      name:           _nameCtrl.text.trim().isEmpty
                        ? d.name : _nameCtrl.text.trim(),
      description:    _descCtrl.text.trim(),
      author:         _authorCtrl.text.trim(),
      notes:          _notesCtrl.text.trim(),
      serviceDate:    _serviceDate,
      tags:           List.of(_tags),
      isTemplate:     _isTemplate,
      isPinned:       _isPinned,
      sortOrder:      d.sortOrder,
      slides:         d.slides,
      groups:         d.groups,
      createdAt:      d.createdAt,
      lastUsedAt:     d.lastUsedAt,
      lastModifiedAt: DateTime.now(),
      filePath:       d.filePath,
    );
  }

  Color get p => widget.primary;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: SizedBox(
        width:  560,
        height: 600,
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              decoration: BoxDecoration(
                color:        p.withValues(alpha: 0.07),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16)),
                border: Border(
                    bottom: BorderSide(
                        color: p.withValues(alpha: 0.14))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color:        p.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.folder_open_rounded,
                        color: p, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Presentation Properties',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize:   16,
                                color:      p)),
                        Text(widget.deck.name,
                            style: TextStyle(
                                fontSize: 11,
                                color:    Colors.grey.shade500),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    icon:  const Icon(Icons.close_rounded),
                    color: Colors.grey,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // ── Tab bar ──────────────────────────────────────────────────
            TabBar(
              controller:           _tabs,
              labelColor:           p,
              unselectedLabelColor: Colors.grey,
              indicatorColor:       p,
              indicatorWeight:      2.5,
              tabs: const [
                Tab(icon: Icon(Icons.info_outline_rounded,  size: 16),
                    text: 'Details'),
                Tab(icon: Icon(Icons.label_outline_rounded, size: 16),
                    text: 'Tags & Notes'),
                Tab(icon: Icon(Icons.insert_drive_file_outlined, size: 16),
                    text: 'File'),
              ],
            ),

            // ── Tab bodies ───────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _DetailsTab(
                    nameCtrl:    _nameCtrl,
                    descCtrl:    _descCtrl,
                    authorCtrl:  _authorCtrl,
                    serviceDate: _serviceDate,
                    isPinned:    _isPinned,
                    isTemplate:  _isTemplate,
                    primary:     p,
                    onPickDate:  _pickDate,
                    onClearDate: () => setState(() => _serviceDate = null),
                    onPinChanged:      (v) => setState(() => _isPinned   = v),
                    onTemplateChanged: (v) => setState(() => _isTemplate = v),
                  ),
                  _TagsNotesTab(
                    tags:      _tags,
                    tagCtrl:   _tagCtrl,
                    notesCtrl: _notesCtrl,
                    primary:   p,
                    onAddTag:  _addTag,
                    onRemove:  (t) => setState(() => _tags.remove(t)),
                  ),
                  _FileTab(
                    deck:          widget.deck,
                    fileSizeBytes: _fileSizeBytes,
                    primary:       p,
                  ),
                ],
              ),
            ),

            // ── Actions ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () =>
                        Navigator.pop(context, _buildResult()),
                    icon:  const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Save Properties',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p,
                      foregroundColor: _contrast(p),
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
        ),
      ),
    );
  }
}

// ── Tab 1: Details ────────────────────────────────────────────────────────────
class _DetailsTab extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final TextEditingController authorCtrl;
  final DateTime?             serviceDate;
  final bool                  isPinned;
  final bool                  isTemplate;
  final Color                 primary;
  final VoidCallback          onPickDate;
  final VoidCallback          onClearDate;
  final ValueChanged<bool>    onPinChanged;
  final ValueChanged<bool>    onTemplateChanged;

  const _DetailsTab({
    required this.nameCtrl,
    required this.descCtrl,
    required this.authorCtrl,
    required this.serviceDate,
    required this.isPinned,
    required this.isTemplate,
    required this.primary,
    required this.onPickDate,
    required this.onClearDate,
    required this.onPinChanged,
    required this.onTemplateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEEE, MMMM d, y');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field('Title', nameCtrl,
              hint: 'Presentation title',
              icon: Icons.slideshow_rounded),
          const SizedBox(height: 14),
          _field('Description', descCtrl,
              hint: 'Short description (shown on card)',
              icon: Icons.notes_rounded,
              maxLines: 3),
          const SizedBox(height: 14),
          _field('Author / Presenter', authorCtrl,
              hint: 'Who created or is presenting this',
              icon: Icons.person_outline_rounded),
          const SizedBox(height: 18),

          // Service date
          _Label('Service Date'),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onPickDate,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            size: 18,
                            color: serviceDate != null
                                ? primary : Colors.grey),
                        const SizedBox(width: 10),
                        Text(
                          serviceDate != null
                              ? fmt.format(serviceDate!)
                              : 'Tap to set service date',
                          style: TextStyle(
                            fontSize: 13,
                            color: serviceDate != null
                                ? null : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (serviceDate != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.clear_rounded,
                      color: Colors.grey, size: 20),
                  tooltip:   'Clear date',
                  onPressed: onClearDate,
                ),
              ],
            ],
          ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),

          // Toggles
          _Toggle(
            icon:     Icons.push_pin_rounded,
            label:    'Pinned',
            subtitle: 'Always show at the top of your list',
            value:    isPinned,
            color:    primary,
            onChanged: onPinChanged,
          ),
          const SizedBox(height: 8),
          _Toggle(
            icon:     Icons.content_copy_rounded,
            label:    'Save as Template',
            subtitle: 'Use this deck as a starting point for new ones',
            value:    isTemplate,
            color:    primary,
            onChanged: onTemplateChanged,
          ),
        ],
      ),
    );
  }
}

// ── Tab 2: Tags & Notes ───────────────────────────────────────────────────────
class _TagsNotesTab extends StatelessWidget {
  final List<String>          tags;
  final TextEditingController tagCtrl;
  final TextEditingController notesCtrl;
  final Color                 primary;
  final VoidCallback          onAddTag;
  final ValueChanged<String>  onRemove;

  const _TagsNotesTab({
    required this.tags,
    required this.tagCtrl,
    required this.notesCtrl,
    required this.primary,
    required this.onAddTag,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label('Tags'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller:      tagCtrl,
                  textInputAction: TextInputAction.done,
                  onSubmitted:     (_) => onAddTag(),
                  decoration: InputDecoration(
                    hintText:     'Add a tag…',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    prefixIcon: Icon(Icons.label_outline_rounded,
                        color: primary, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: onAddTag,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: _contrast(primary),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (tags.isEmpty)
            Text('No tags yet',
                style: TextStyle(
                    color: Colors.grey.shade400, fontSize: 12))
          else
            Wrap(
              spacing: 6, runSpacing: 6,
              children: tags.map((t) => Chip(
                label: Text(t),
                deleteIcon: const Icon(Icons.close_rounded, size: 14),
                onDeleted:  () => onRemove(t),
                backgroundColor: primary.withValues(alpha: 0.10),
                labelStyle: TextStyle(color: primary, fontSize: 12),
                side: BorderSide(color: primary.withValues(alpha: 0.30)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              )).toList(),
            ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 14),

          _Label('Private Notes'),
          const SizedBox(height: 6),
          Text('These notes are only visible to you — not shown during presentation.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          TextField(
            controller: notesCtrl,
            maxLines:   7,
            decoration: InputDecoration(
              hintText:    'Planning notes, order of service, reminders…',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab 3: File Info ──────────────────────────────────────────────────────────
class _FileTab extends StatelessWidget {
  final Deck   deck;
  final int?   fileSizeBytes;
  final Color  primary;

  const _FileTab({
    required this.deck,
    required this.fileSizeBytes,
    required this.primary,
  });

  String _fmtSize(int bytes) {
    if (bytes < 1024)        return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, y  h:mm a');
    final path = deck.filePath;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoCard(
            icon:    Icons.insert_drive_file_rounded,
            primary: primary,
            rows: [
              _InfoRow('ID',       deck.id),
              _InfoRow('Slides',   '${deck.slideCount}'),
              _InfoRow('Groups',   '${deck.groups.length}'),
              if (fileSizeBytes != null)
                _InfoRow('File size', _fmtSize(fileSizeBytes!)),
            ],
          ),
          const SizedBox(height: 14),
          _InfoCard(
            icon:    Icons.schedule_rounded,
            primary: primary,
            rows: [
              _InfoRow('Created',       fmt.format(deck.createdAt)),
              if (deck.lastModifiedAt != null)
                _InfoRow('Last modified', fmt.format(deck.lastModifiedAt!)),
              if (deck.lastUsedAt != null)
                _InfoRow('Last opened',  fmt.format(deck.lastUsedAt!)),
              if (deck.serviceDate != null)
                _InfoRow('Service date',
                    DateFormat('EEEE, MMM d, y').format(deck.serviceDate!)),
            ],
          ),

          if (path != null) ...[
            const SizedBox(height: 14),
            _Label('File Location'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:        Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border:       Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(path,
                        style: const TextStyle(
                            fontSize:   11,
                            fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                    icon:    const Icon(Icons.copy_rounded, size: 16),
                    tooltip: 'Copy path',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: path));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Path copied to clipboard'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2)),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('.cpres files are standard JSON — you can back them up, '
                 'share them, or open them in any text editor.',
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}

// ── Small shared widgets ──────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13));
}

Widget _field(
  String label,
  TextEditingController ctrl, {
  String?  hint,
  IconData? icon,
  int      maxLines = 1,
}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(label),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          maxLines:   maxLines,
          decoration: InputDecoration(
            hintText:       hint,
            prefixIcon:     icon != null ? Icon(icon, size: 18) : null,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );

class _Toggle extends StatelessWidget {
  final IconData           icon;
  final String             label;
  final String             subtitle;
  final bool               value;
  final Color              color;
  final ValueChanged<bool> onChanged;

  const _Toggle({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:        value
              ? color.withValues(alpha: 0.06) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(
              color: value
                  ? color.withValues(alpha: 0.25) : Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, color: value ? color : Colors.grey, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color:      value ? color : null)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
            Switch(
              value:       value,
              activeColor: color,
              onChanged:   onChanged,
            ),
          ],
        ),
      );
}

class _InfoCard extends StatelessWidget {
  final IconData       icon;
  final Color          primary;
  final List<_InfoRow> rows;

  const _InfoCard({
    required this.icon,
    required this.primary,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(
              color: primary.withValues(alpha: 0.14)),
        ),
        child: Column(
          children: rows.map((r) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(r.label,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500)),
                ),
                Expanded(
                  child: Text(r.value,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          )).toList(),
        ),
      );
}

class _InfoRow {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
}

Color _contrast(Color bg) =>
    bg.computeLuminance() > 0.35 ? Colors.black87 : Colors.white;