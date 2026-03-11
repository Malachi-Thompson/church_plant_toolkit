// lib/apps/bulletin/widgets/bulletin_editor.dart
//
// Tabbed editor for a single bulletin.
// Tabs: Church Info | Service | Announcements | Prayer | Options

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../theme.dart';
import '../bulletin_model.dart';

class BulletinEditor extends StatefulWidget {
  final BulletinModel      bulletin;
  final Color              primary;
  final Color              secondary;
  final VoidCallback       onChanged;
  final VoidCallback       onExport;

  const BulletinEditor({
    super.key,
    required this.bulletin,
    required this.primary,
    required this.secondary,
    required this.onChanged,
    required this.onExport,
  });

  @override
  State<BulletinEditor> createState() => _BulletinEditorState();
}

class _BulletinEditorState extends State<BulletinEditor>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  BulletinModel get b => widget.bulletin;
  Color get primary    => widget.primary;
  Color get secondary  => widget.secondary;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  void _changed() {
    b.updatedAt = DateTime.now();
    widget.onChanged();
    setState(() {});
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Top bar ────────────────────────────────────────────────────────────
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(b.title,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: primary),
                  overflow: TextOverflow.ellipsis),
            ),
            // Layout badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(bulletinLayoutLabels[b.layout] ?? '',
                  style: TextStyle(
                      fontSize: 10, color: primary,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: widget.onExport,
              icon: const Icon(Icons.print_outlined, size: 16),
              label: const Text('Print / PDF'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: contrastOn(primary),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10)),
            ),
          ]),
          const SizedBox(height: 10),
          TabBar(
            controller: _tabs,
            labelColor: primary,
            unselectedLabelColor: textMid,
            indicatorColor: primary,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Church Info'),
              Tab(text: 'Service'),
              Tab(text: 'Announcements'),
              Tab(text: 'Prayer & Notes'),
              Tab(text: 'Options'),
            ],
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [
            _ChurchInfoTab(b: b, primary: primary, onChanged: _changed),
            _ServiceTab(b: b, primary: primary, secondary: secondary, onChanged: _changed),
            _AnnouncementsTab(b: b, primary: primary, onChanged: _changed),
            _PrayerNotesTab(b: b, primary: primary, onChanged: _changed),
            _OptionsTab(b: b, primary: primary, secondary: secondary, onChanged: _changed),
          ],
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 1 — CHURCH INFO
// ══════════════════════════════════════════════════════════════════════════════

class _ChurchInfoTab extends StatefulWidget {
  final BulletinModel b; final Color primary; final VoidCallback onChanged;
  const _ChurchInfoTab({required this.b, required this.primary, required this.onChanged});
  @override State<_ChurchInfoTab> createState() => _ChurchInfoTabState();
}

class _ChurchInfoTabState extends State<_ChurchInfoTab> {
  late TextEditingController _nameCtrl, _addrCtrl, _phoneCtrl,
      _webCtrl, _emailCtrl, _titleCtrl, _speakerCtrl, _scriptureCtrl, _seriesCtrl;

  @override
  void initState() {
    super.initState();
    final b = widget.b;
    _nameCtrl     = TextEditingController(text: b.churchName);
    _addrCtrl     = TextEditingController(text: b.churchAddress);
    _phoneCtrl    = TextEditingController(text: b.churchPhone);
    _webCtrl      = TextEditingController(text: b.churchWebsite);
    _emailCtrl    = TextEditingController(text: b.churchEmail);
    _titleCtrl    = TextEditingController(text: b.sermonTitle);
    _speakerCtrl  = TextEditingController(text: b.speakerName);
    _scriptureCtrl= TextEditingController(text: b.sermonScripture);
    _seriesCtrl   = TextEditingController(text: b.sermonSeriesName);
    for (final c in [_nameCtrl,_addrCtrl,_phoneCtrl,_webCtrl,_emailCtrl,
        _titleCtrl,_speakerCtrl,_scriptureCtrl,_seriesCtrl]) {
      c.addListener(_sync);
    }
  }

  void _sync() {
    final b = widget.b;
    b.churchName       = _nameCtrl.text;
    b.churchAddress    = _addrCtrl.text;
    b.churchPhone      = _phoneCtrl.text;
    b.churchWebsite    = _webCtrl.text;
    b.churchEmail      = _emailCtrl.text;
    b.sermonTitle      = _titleCtrl.text;
    b.speakerName      = _speakerCtrl.text;
    b.sermonScripture  = _scriptureCtrl.text;
    b.sermonSeriesName = _seriesCtrl.text;
    widget.onChanged();
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl,_addrCtrl,_phoneCtrl,_webCtrl,_emailCtrl,
        _titleCtrl,_speakerCtrl,_scriptureCtrl,_seriesCtrl]) {
      c.removeListener(_sync);
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionLabel('Church Information', widget.primary),
        _Field('Church Name',    _nameCtrl),
        _Field('Address',        _addrCtrl),
        _Field('Phone',          _phoneCtrl),
        _Field('Website',        _webCtrl),
        _Field('Email',          _emailCtrl),
        const SizedBox(height: 20),

        _SectionLabel("Today's Message", widget.primary),
        _serviceDate(context),
        const SizedBox(height: 12),
        _Field('Sermon Title',     _titleCtrl),
        _Field('Speaker Name',     _speakerCtrl),
        _Field('Scripture Reference', _scriptureCtrl,
            hint: 'e.g. John 3:16–17'),
        _Field('Series Name',      _seriesCtrl,
            hint: 'optional'),
      ],
    );
  }

  Widget _serviceDate(BuildContext context) {
    final primary = widget.primary;
    final b       = widget.b;
    final label = b.serviceDate != null
        ? DateFormat('MMMM d, yyyy').format(b.serviceDate!)
        : 'Set service date';
    return Row(children: [
      Expanded(child: _FieldLabel('Service Date')),
      TextButton.icon(
        icon: Icon(Icons.calendar_today_outlined, size: 14, color: primary),
        label: Text(label, style: TextStyle(color: primary, fontSize: 13)),
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: b.serviceDate ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2099),
            builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(
                  colorScheme: ColorScheme.light(primary: primary)),
              child: child!,
            ),
          );
          if (picked != null) {
            b.serviceDate = picked;
            b.title = 'Bulletin – ${DateFormat('MMMM d, y').format(picked)}';
            widget.onChanged();
            setState(() {});
          }
        },
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 2 — SERVICE (Order of Service)
// ══════════════════════════════════════════════════════════════════════════════

class _ServiceTab extends StatefulWidget {
  final BulletinModel b;
  final Color primary, secondary;
  final VoidCallback onChanged;
  const _ServiceTab({required this.b, required this.primary, required this.secondary, required this.onChanged});
  @override State<_ServiceTab> createState() => _ServiceTabState();
}

class _ServiceTabState extends State<_ServiceTab> {
  @override
  Widget build(BuildContext context) {
    final items = widget.b.orderOfService;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Row(children: [
          Text('Order of Service',
              style: TextStyle(fontWeight: FontWeight.bold, color: textDark)),
          const Spacer(),
          TextButton.icon(
            icon: Icon(Icons.add, size: 16, color: widget.primary),
            label: Text('Add item',
                style: TextStyle(color: widget.primary, fontSize: 12)),
            onPressed: () {
              setState(() => items.add(ServiceItem(label: 'New Item')));
              widget.onChanged();
            },
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          itemCount: items.length,
          onReorder: (oldIdx, newIdx) {
            setState(() {
              if (newIdx > oldIdx) newIdx--;
              final item = items.removeAt(oldIdx);
              items.insert(newIdx, item);
            });
            widget.onChanged();
          },
          itemBuilder: (_, i) => _ServiceItemRow(
            key:       ValueKey('svc_$i'),
            item:      items[i],
            primary:   widget.primary,
            onChanged: () { setState(() {}); widget.onChanged(); },
            onDelete:  () {
              setState(() => items.removeAt(i));
              widget.onChanged();
            },
          ),
        ),
      ),
    ]);
  }
}

class _ServiceItemRow extends StatefulWidget {
  final ServiceItem  item;
  final Color        primary;
  final VoidCallback onChanged, onDelete;
  const _ServiceItemRow({
    super.key, required this.item, required this.primary,
    required this.onChanged, required this.onDelete,
  });
  @override State<_ServiceItemRow> createState() => _ServiceItemRowState();
}

class _ServiceItemRowState extends State<_ServiceItemRow> {
  late TextEditingController _time, _label, _detail;

  @override
  void initState() {
    super.initState();
    _time   = TextEditingController(text: widget.item.time);
    _label  = TextEditingController(text: widget.item.label);
    _detail = TextEditingController(text: widget.item.detail);
    for (final c in [_time, _label, _detail]) c.addListener(_sync);
  }

  void _sync() {
    widget.item.time   = _time.text;
    widget.item.label  = _label.text;
    widget.item.detail = _detail.text;
    widget.onChanged();
  }

  @override
  void dispose() {
    for (final c in [_time, _label, _detail]) { c.removeListener(_sync); c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.drag_handle, size: 18, color: textMid),
        ),
        SizedBox(
          width: 52,
          child: TextField(
            controller: _time,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              hintText: 'Time',
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              TextField(
                controller: _label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  hintText: 'Item label',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                ),
              ),
              TextField(
                controller: _detail,
                style: const TextStyle(fontSize: 11, color: textMid),
                decoration: const InputDecoration(
                  hintText: 'Detail (song title, reader…)',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      EdgeInsets.only(bottom: 6),
                ),
              ),
            ]),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 16, color: textMid),
          onPressed: widget.onDelete,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 3 — ANNOUNCEMENTS
// ══════════════════════════════════════════════════════════════════════════════

class _AnnouncementsTab extends StatefulWidget {
  final BulletinModel b; final Color primary; final VoidCallback onChanged;
  const _AnnouncementsTab({required this.b, required this.primary, required this.onChanged});
  @override State<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends State<_AnnouncementsTab> {
  @override
  Widget build(BuildContext context) {
    final items = widget.b.announcements;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Row(children: [
          const Text('Announcements',
              style: TextStyle(fontWeight: FontWeight.bold, color: textDark)),
          const Spacer(),
          TextButton.icon(
            icon: Icon(Icons.add, size: 16, color: widget.primary),
            label: Text('Add',
                style: TextStyle(color: widget.primary, fontSize: 12)),
            onPressed: () {
              setState(() => items.add(
                  Announcement(title: 'New Announcement')));
              widget.onChanged();
            },
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: items.isEmpty
            ? Center(
                child: Text('No announcements yet.',
                    style: TextStyle(
                        color: widget.primary.withValues(alpha: 0.3))))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                itemBuilder: (_, i) => _AnnouncementRow(
                  key:       ValueKey('ann_$i'),
                  item:      items[i],
                  primary:   widget.primary,
                  onChanged: () { setState(() {}); widget.onChanged(); },
                  onDelete:  () {
                    setState(() => items.removeAt(i));
                    widget.onChanged();
                  },
                ),
              ),
      ),
    ]);
  }
}

class _AnnouncementRow extends StatefulWidget {
  final Announcement item; final Color primary;
  final VoidCallback onChanged, onDelete;
  const _AnnouncementRow({super.key, required this.item, required this.primary, required this.onChanged, required this.onDelete});
  @override State<_AnnouncementRow> createState() => _AnnouncementRowState();
}

class _AnnouncementRowState extends State<_AnnouncementRow> {
  late TextEditingController _title, _body;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.item.title);
    _body  = TextEditingController(text: widget.item.body);
    _title.addListener(_sync); _body.addListener(_sync);
  }

  void _sync() {
    widget.item.title = _title.text;
    widget.item.body  = _body.text;
    widget.onChanged();
  }

  @override
  void dispose() {
    _title.removeListener(_sync); _body.removeListener(_sync);
    _title.dispose(); _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: TextField(
            controller: _title,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: 'Announcement title',
              hintStyle: const TextStyle(fontWeight: FontWeight.normal),
              border: InputBorder.none, isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              prefixIcon: Icon(Icons.campaign_outlined,
                  size: 16, color: widget.primary),
            ),
          )),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: textMid),
            onPressed: widget.onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ]),
        TextField(
          controller: _body,
          minLines: 2,
          maxLines: 6,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'Details (date, time, location…)',
            border: InputBorder.none, isDense: true,
            contentPadding:
                EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 4 — PRAYER REQUESTS & SERMON NOTES
// ══════════════════════════════════════════════════════════════════════════════

class _PrayerNotesTab extends StatefulWidget {
  final BulletinModel b; final Color primary; final VoidCallback onChanged;
  const _PrayerNotesTab({required this.b, required this.primary, required this.onChanged});
  @override State<_PrayerNotesTab> createState() => _PrayerNotesTabState();
}

class _PrayerNotesTabState extends State<_PrayerNotesTab> {
  late TextEditingController _prayerCtrl, _notesLabelCtrl;

  @override
  void initState() {
    super.initState();
    _prayerCtrl    = TextEditingController(text: widget.b.prayerRequests);
    _notesLabelCtrl= TextEditingController(text: widget.b.sermonNotesPrompt);
    _prayerCtrl.addListener(_sync);
    _notesLabelCtrl.addListener(_sync);
  }

  void _sync() {
    widget.b.prayerRequests    = _prayerCtrl.text;
    widget.b.sermonNotesPrompt = _notesLabelCtrl.text;
    widget.onChanged();
  }

  @override
  void dispose() {
    _prayerCtrl.removeListener(_sync);
    _notesLabelCtrl.removeListener(_sync);
    _prayerCtrl.dispose();
    _notesLabelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionLabel('Prayer Requests', widget.primary),
        const Text(
          'One prayer request per line. These print in the bulletin.',
          style: TextStyle(fontSize: 11, color: textMid),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _prayerCtrl,
          minLines: 6,
          maxLines: 20,
          decoration: _inputDecoration('Add prayer requests, one per line…'),
        ),
        const SizedBox(height: 24),
        _SectionLabel('Sermon Notes', widget.primary),
        Row(children: [
          Expanded(child: _Field(
            'Notes section heading',
            _notesLabelCtrl,
            hint: 'e.g. "Sermon Notes" or "Message Outline"',
          )),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Include notes area',
                style: TextStyle(fontSize: 12, color: textDark)),
            Switch(
              value: widget.b.includeSermonNotes,
              activeColor: widget.primary,
              onChanged: (v) {
                widget.b.includeSermonNotes = v;
                widget.onChanged();
                setState(() {});
              },
            ),
          ]),
        ]),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 5 — OPTIONS (layout, contact card, accent color)
// ══════════════════════════════════════════════════════════════════════════════

class _OptionsTab extends StatefulWidget {
  final BulletinModel b; final Color primary, secondary; final VoidCallback onChanged;
  const _OptionsTab({required this.b, required this.primary, required this.secondary, required this.onChanged});
  @override State<_OptionsTab> createState() => _OptionsTabState();
}

class _OptionsTabState extends State<_OptionsTab> {
  late TextEditingController _contactHeadCtrl;

  @override
  void initState() {
    super.initState();
    _contactHeadCtrl = TextEditingController(text: widget.b.contactCardHeading);
    _contactHeadCtrl.addListener(_sync);
  }

  void _sync() {
    widget.b.contactCardHeading = _contactHeadCtrl.text;
    widget.onChanged();
  }

  @override
  void dispose() {
    _contactHeadCtrl.removeListener(_sync);
    _contactHeadCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionLabel('Layout', widget.primary),
        ...BulletinLayout.values.map((l) => RadioListTile<BulletinLayout>(
          value:    l,
          groupValue: widget.b.layout,
          activeColor: widget.primary,
          title: Text(bulletinLayoutLabels[l] ?? '',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text(bulletinLayoutDescriptions[l] ?? '',
              style: const TextStyle(fontSize: 11, color: textMid)),
          onChanged: (v) {
            if (v != null) {
              widget.b.layout = v;
              widget.onChanged();
              setState(() {});
            }
          },
        )),
        const SizedBox(height: 20),

        _SectionLabel('Contact / Visitor Card', widget.primary),
        Row(children: [
          Expanded(child: _Field(
              'Card heading', _contactHeadCtrl,
              hint: 'e.g. "We\'d love to connect!"')),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Include card',
                style: TextStyle(fontSize: 12, color: textDark)),
            Switch(
              value: widget.b.includeContactCard,
              activeColor: widget.primary,
              onChanged: (v) {
                widget.b.includeContactCard = v;
                widget.onChanged();
                setState(() {});
              },
            ),
          ]),
        ]),
        const SizedBox(height: 20),

        _SectionLabel('Accent Color', widget.primary),
        const Text(
            'The accent color is set automatically from your church brand color. '
            'You can override it per bulletin here.',
            style: TextStyle(fontSize: 11, color: textMid)),
        const SizedBox(height: 10),
        Wrap(spacing: 10, children: [
          '#1A3A5C','#7C3AED','#B91C1C','#047857',
          '#B45309','#1D4ED8','#374151','#0E7490',
        ].map((hex) => _ColorDot(
          hex:      hex,
          selected: widget.b.accentColor == hex,
          onTap: () {
            widget.b.accentColor = hex;
            widget.onChanged();
            setState(() {});
          },
        )).toList()),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  final String hex; final bool selected; final VoidCallback onTap;
  const _ColorDot({required this.hex, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _hexToColor(hex);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: Colors.black, width: 2.5)
              : Border.all(color: Colors.transparent, width: 2.5),
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)]
              : null,
        ),
        child: selected
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : null,
      ),
    );
  }

  Color _hexToColor(String hex) {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED FIELD HELPERS
// ══════════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final String text; final Color color;
  const _SectionLabel(this.text, this.color);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text,
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: .06,
            color: color,
            decoration: TextDecoration.none)),
  );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 11, color: textMid));
}

// Simple labeled text field used throughout
class _Field extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String? hint;
  final int maxLines;

  const _Field(this.label, this.ctrl, {this.hint, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _FieldLabel(label),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 13),
          decoration: _inputDecoration(hint ?? ''),
        ),
      ]),
    );
  }
}

InputDecoration _inputDecoration(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(color: textMid, fontSize: 12),
  filled: true,
  fillColor: const Color(0xFFF9FAFB),
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
  enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
  focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.blue.shade400)),
  isDense: true,
);