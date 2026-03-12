// lib/apps/directory/directory_screen.dart
//
// Member Directory — add, edit, search, and manage church members.
// Data is persisted locally via SharedPreferences (JSON).
//
// Features:
//   • Member cards with photo placeholder, contact info, family unit
//   • Membership status (visitor / regular / member / leadership)
//   • Baptism date, join date, birthday
//   • Free-text notes field per member
//   • Search / filter by name, status, or family
//   • Export full directory as a printable PDF-ready HTML file

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

enum MemberStatus { visitor, regular, member, leadership }

const _statusLabels = <MemberStatus, String>{
  MemberStatus.visitor:    'Visitor',
  MemberStatus.regular:    'Regular Attendee',
  MemberStatus.member:     'Member',
  MemberStatus.leadership: 'Leadership',
};

const _statusColors = <MemberStatus, Color>{
  MemberStatus.visitor:    Color(0xFF9E9E9E),
  MemberStatus.regular:    Color(0xFF1565C0),
  MemberStatus.member:     Color(0xFF2E7D32),
  MemberStatus.leadership: Color(0xFFE65100),
};

class Member {
  final String id;
  String firstName;
  String lastName;
  String email;
  String phone;
  String address;
  MemberStatus status;
  String familyUnit;     // free-text family/household name
  DateTime? birthday;
  DateTime? joinDate;
  DateTime? baptismDate;
  String notes;
  String photoPath;      // local file path to photo

  Member({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.email       = '',
    this.phone       = '',
    this.address     = '',
    this.status      = MemberStatus.visitor,
    this.familyUnit  = '',
    this.birthday,
    this.joinDate,
    this.baptismDate,
    this.notes       = '',
    this.photoPath   = '',
  });

  String get fullName => '$firstName $lastName'.trim();
  String get initials {
    final f = firstName.isNotEmpty ? firstName[0] : '';
    final l = lastName.isNotEmpty  ? lastName[0]  : '';
    return '$f$l'.toUpperCase();
  }

  Map<String, dynamic> toJson() => {
    'id':          id,
    'firstName':   firstName,
    'lastName':    lastName,
    'email':       email,
    'phone':       phone,
    'address':     address,
    'status':      status.name,
    'familyUnit':  familyUnit,
    'birthday':    birthday?.toIso8601String(),
    'joinDate':    joinDate?.toIso8601String(),
    'baptismDate': baptismDate?.toIso8601String(),
    'notes':       notes,
    'photoPath':   photoPath,
  };

  factory Member.fromJson(Map<String, dynamic> j) => Member(
    id:          j['id']        ?? const Uuid().v4(),
    firstName:   j['firstName'] ?? '',
    lastName:    j['lastName']  ?? '',
    email:       j['email']     ?? '',
    phone:       j['phone']     ?? '',
    address:     j['address']   ?? '',
    status:      MemberStatus.values.firstWhere(
                   (s) => s.name == j['status'],
                   orElse: () => MemberStatus.visitor),
    familyUnit:  j['familyUnit']  ?? '',
    birthday:    j['birthday']    != null ? DateTime.tryParse(j['birthday']) : null,
    joinDate:    j['joinDate']    != null ? DateTime.tryParse(j['joinDate']) : null,
    baptismDate: j['baptismDate'] != null ? DateTime.tryParse(j['baptismDate']) : null,
    notes:       j['notes']       ?? '',
    photoPath:   j['photoPath']   ?? '',
  );

  Member copyWith({
    String? firstName, String? lastName, String? email, String? phone,
    String? address, MemberStatus? status, String? familyUnit,
    DateTime? birthday, DateTime? joinDate, DateTime? baptismDate,
    String? notes, String? photoPath,
  }) => Member(
    id:          id,
    firstName:   firstName   ?? this.firstName,
    lastName:    lastName    ?? this.lastName,
    email:       email       ?? this.email,
    phone:       phone       ?? this.phone,
    address:     address     ?? this.address,
    status:      status      ?? this.status,
    familyUnit:  familyUnit  ?? this.familyUnit,
    birthday:    birthday    ?? this.birthday,
    joinDate:    joinDate    ?? this.joinDate,
    baptismDate: baptismDate ?? this.baptismDate,
    notes:       notes       ?? this.notes,
    photoPath:   photoPath   ?? this.photoPath,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// PERSISTENCE
// ══════════════════════════════════════════════════════════════════════════════

const _kMemberPrefKey = 'member_directory_v1';

Future<List<Member>> _loadMembers() async {
  final prefs = await SharedPreferences.getInstance();
  final raw   = prefs.getString(_kMemberPrefKey);
  if (raw == null) return [];
  final list  = jsonDecode(raw) as List;
  return list.map((j) => Member.fromJson(j)).toList();
}

Future<void> _saveMembers(List<Member> members) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
      _kMemberPrefKey, jsonEncode(members.map((m) => m.toJson()).toList()));
}

// ══════════════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key});

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  List<Member> _members  = [];
  Member?      _selected;
  bool         _loading  = true;
  String       _query    = '';
  MemberStatus? _filterStatus;

  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMembers().then((list) {
      list.sort((a, b) => a.lastName.compareTo(b.lastName));
      setState(() { _members = list; _loading = false; });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color get _primary   => context.read<AppState>().brandPrimary;
  Color get _secondary => context.read<AppState>().brandSecondary;

  List<Member> get _filtered {
    var list = _members.where((m) {
      final q = _query.toLowerCase();
      final matchesQ = q.isEmpty ||
          m.fullName.toLowerCase().contains(q) ||
          m.email.toLowerCase().contains(q) ||
          m.familyUnit.toLowerCase().contains(q);
      final matchesStatus =
          _filterStatus == null || m.status == _filterStatus;
      return matchesQ && matchesStatus;
    }).toList();
    list.sort((a, b) => a.lastName.compareTo(b.lastName));
    return list;
  }

  void _persist() => _saveMembers(_members);

  void _upsertMember(Member m) {
    setState(() {
      final idx = _members.indexWhere((x) => x.id == m.id);
      if (idx == -1) {
        _members.add(m);
      } else {
        _members[idx] = m;
      }
      _selected = m;
    });
    _persist();
  }

  void _deleteMember(Member m) {
    setState(() {
      _members.removeWhere((x) => x.id == m.id);
      if (_selected?.id == m.id) _selected = null;
    });
    _persist();
  }

  Future<void> _showMemberForm({Member? editing}) async {
    final result = await showDialog<Member>(
      context: context,
      builder: (_) => _MemberFormDialog(
        primary:  _primary,
        existing: editing,
      ),
    );
    if (result != null) _upsertMember(result);
  }

  Future<void> _exportDirectory() async {
    final html   = _buildDirectoryHtml();
    final tmp    = await getTemporaryDirectory();
    final file   = File('${tmp.path}/church_directory.html');
    await file.writeAsString(html);
    final uri    = Uri.file(file.path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
            'Opened in browser — use File › Print › Save as PDF')));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary   = _primary;
    final secondary = _secondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Member Directory'),
        backgroundColor: primary,
        foregroundColor: contrastOn(primary),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export Directory PDF',
            onPressed: _exportDirectory,
          ),
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Add Member',
            onPressed: () => _showMemberForm(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(children: [
              // ── Member list ──────────────────────────────────────────────
              SizedBox(
                width: 280,
                child: _MemberList(
                  members:      _filtered,
                  selected:     _selected,
                  primary:      primary,
                  secondary:    secondary,
                  query:        _query,
                  searchCtrl:   _searchCtrl,
                  filterStatus: _filterStatus,
                  totalCount:   _members.length,
                  onSearch: (q) => setState(() => _query = q),
                  onFilterStatus: (s) => setState(() => _filterStatus = s),
                  onSelect:  (m) => setState(() => _selected = m),
                  onAdd:     () => _showMemberForm(),
                  onDelete:  _deleteMember,
                ),
              ),
              const VerticalDivider(width: 1),
              // ── Detail panel ─────────────────────────────────────────────
              Expanded(
                child: _selected == null
                    ? _EmptyDetail(primary: primary,
                          onAdd: () => _showMemberForm())
                    : _MemberDetail(
                        member:    _selected!,
                        primary:   primary,
                        secondary: secondary,
                        onEdit:    () => _showMemberForm(editing: _selected),
                        onDelete:  () => _deleteMember(_selected!),
                      ),
              ),
            ]),
    );
  }

  // ── Directory HTML ────────────────────────────────────────────────────────

  String _buildDirectoryHtml() {
    final church  = context.read<AppState>().churchProfile?.name ?? 'Church';
    final primary = _primary;
    final pHex    = '#${primary.value.toRadixString(16).substring(2).toUpperCase()}';
    final now     = DateFormat('MMMM d, y').format(DateTime.now());

    final byFamily = <String, List<Member>>{};
    for (final m in _members) {
      final key = m.familyUnit.isNotEmpty ? m.familyUnit : m.fullName;
      byFamily.putIfAbsent(key, () => []).add(m);
    }
    final keys = byFamily.keys.toList()..sort();

    final rows = keys.map((fam) {
      final members = byFamily[fam]!;
      final cells   = members.map((m) => '''
        <tr>
          <td>${_esc(m.fullName)}</td>
          <td>${_esc(_statusLabels[m.status] ?? '')}</td>
          <td>${_esc(m.email)}</td>
          <td>${_esc(m.phone)}</td>
        </tr>''').join('');
      return '<tr class="fam-header"><td colspan="4">${_esc(fam)}</td></tr>$cells';
    }).join('');

    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>${_esc(church)} — Member Directory</title>
<style>
  @media print { body { margin: 0; } }
  body { font-family: Arial, sans-serif; padding: 24px; color: #222; background: #fff; }
  h1 { color: $pHex; margin-bottom: 4px; }
  .sub { color: #777; font-size: 13px; margin-bottom: 20px; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th { background: $pHex; color: #fff; padding: 8px 12px; text-align: left; }
  td { padding: 7px 12px; border-bottom: 1px solid #eee; }
  tr.fam-header td {
    background: #f0f0f0; font-weight: bold;
    padding: 6px 12px; color: #444; font-size: 12px; letter-spacing: .5px;
  }
  tr:hover td { background: #fafafa; }
</style>
</head>
<body>
<h1>${_esc(church)}</h1>
<div class="sub">Member Directory · Printed $now · ${_members.length} records</div>
<table>
  <thead>
    <tr><th>Name</th><th>Status</th><th>Email</th><th>Phone</th></tr>
  </thead>
  <tbody>$rows</tbody>
</table>
</body>
</html>''';
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

// ══════════════════════════════════════════════════════════════════════════════
// MEMBER LIST SIDEBAR
// ══════════════════════════════════════════════════════════════════════════════

class _MemberList extends StatelessWidget {
  final List<Member>    members;
  final Member?         selected;
  final Color           primary;
  final Color           secondary;
  final String          query;
  final TextEditingController searchCtrl;
  final MemberStatus?   filterStatus;
  final int             totalCount;
  final ValueChanged<String>   onSearch;
  final ValueChanged<MemberStatus?> onFilterStatus;
  final ValueChanged<Member>   onSelect;
  final VoidCallback    onAdd;
  final ValueChanged<Member>   onDelete;

  const _MemberList({
    required this.members, required this.selected,
    required this.primary, required this.secondary,
    required this.query, required this.searchCtrl,
    required this.filterStatus, required this.totalCount,
    required this.onSearch, required this.onFilterStatus,
    required this.onSelect, required this.onAdd, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F9FA),
      child: Column(children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: TextField(
            controller: searchCtrl,
            onChanged:  onSearch,
            decoration: InputDecoration(
              hintText: 'Search members…',
              prefixIcon: Icon(Icons.search, size: 18, color: primary),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
            ),
          ),
        ),
        // Status filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
          child: Row(children: [
            _FilterChip(
              label: 'All ($totalCount)',
              selected: filterStatus == null,
              primary: primary,
              onTap: () => onFilterStatus(null),
            ),
            ...MemberStatus.values.map((s) => _FilterChip(
              label: _statusLabels[s]!,
              selected: filterStatus == s,
              primary: _statusColors[s]!,
              onTap: () => onFilterStatus(filterStatus == s ? null : s),
            )),
          ]),
        ),
        const Divider(height: 1),
        // Count + Add button
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 8, 4),
          child: Row(children: [
            Text('${members.length} shown',
                style: const TextStyle(fontSize: 11, color: textMid)),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.person_add_outlined, size: 18, color: primary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: onAdd,
              tooltip: 'Add member',
            ),
          ]),
        ),
        const Divider(height: 1),
        // List
        Expanded(
          child: members.isEmpty
              ? Center(child: Text('No members found',
                    style: TextStyle(
                        color: primary.withValues(alpha: 0.35),
                        fontSize: 13)))
              : ListView.separated(
                  itemCount: members.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 14),
                  itemBuilder: (ctx, i) {
                    final m   = members[i];
                    final sel = selected?.id == m.id;
                    return GestureDetector(
                      onTap: () => onSelect(m),
                      onSecondaryTapUp: (d) async {
                        final r = await showMenu<String>(
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
                                  Text('Remove',
                                      style: TextStyle(color: Colors.red)),
                                ])),
                          ],
                        );
                        if (r == 'delete') onDelete(m);
                      },
                      child: Container(
                        color: sel ? primary.withValues(alpha: 0.07) : null,
                        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                        child: Row(children: [
                          _Avatar(member: m, size: 36, primary: primary),
                          const SizedBox(width: 10),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.fullName,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: sel ? primary : textDark),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              _StatusBadge(status: m.status, small: true),
                            ],
                          )),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label; final bool selected;
  final Color primary; final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected,
      required this.primary, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? primary : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected
            ? primary : Colors.grey.shade300),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              color: selected ? contrastOn(primary) : textMid,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// MEMBER DETAIL PANEL
// ══════════════════════════════════════════════════════════════════════════════

class _MemberDetail extends StatelessWidget {
  final Member       member;
  final Color        primary;
  final Color        secondary;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MemberDetail({
    required this.member, required this.primary, required this.secondary,
    required this.onEdit, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMMM d, y');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──────────────────────────────────────────────────────────
        Row(children: [
          _Avatar(member: member, size: 72, primary: primary),
          const SizedBox(width: 20),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(member.fullName,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold,
                    color: textDark)),
            const SizedBox(height: 4),
            _StatusBadge(status: member.status),
            if (member.familyUnit.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.people_outline, size: 14, color: textMid),
                const SizedBox(width: 4),
                Text(member.familyUnit,
                    style: const TextStyle(fontSize: 13, color: textMid)),
              ]),
            ],
          ])),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit'),
            onPressed: onEdit,
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline,
                size: 16, color: Colors.red),
            label: const Text('Remove',
                style: TextStyle(color: Colors.red)),
            onPressed: onDelete,
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red)),
          ),
        ]),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),

        // ── Contact info ─────────────────────────────────────────────────────
        _Section(title: 'Contact', primary: primary, children: [
          if (member.email.isNotEmpty)
            _InfoRow(icon: Icons.email_outlined, label: 'Email',
                value: member.email),
          if (member.phone.isNotEmpty)
            _InfoRow(icon: Icons.phone_outlined, label: 'Phone',
                value: member.phone),
          if (member.address.isNotEmpty)
            _InfoRow(icon: Icons.home_outlined, label: 'Address',
                value: member.address),
        ]),

        // ── Dates ────────────────────────────────────────────────────────────
        if (member.birthday != null ||
            member.joinDate != null ||
            member.baptismDate != null) ...[
          const SizedBox(height: 16),
          _Section(title: 'Important Dates', primary: primary, children: [
            if (member.birthday != null)
              _InfoRow(icon: Icons.cake_outlined, label: 'Birthday',
                  value: fmt.format(member.birthday!)),
            if (member.joinDate != null)
              _InfoRow(icon: Icons.church_outlined, label: 'Joined',
                  value: fmt.format(member.joinDate!)),
            if (member.baptismDate != null)
              _InfoRow(icon: Icons.water_drop_outlined, label: 'Baptised',
                  value: fmt.format(member.baptismDate!)),
          ]),
        ],

        // ── Notes ────────────────────────────────────────────────────────────
        if (member.notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Section(title: 'Notes', primary: primary, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
              child: Text(member.notes,
                  style: const TextStyle(fontSize: 14, height: 1.6,
                      color: textDark)),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  final String title; final Color primary;
  final List<Widget> children;
  const _Section({required this.title, required this.primary,
      required this.children});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title.toUpperCase(),
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
              color: primary, letterSpacing: 1.4)),
      const SizedBox(height: 8),
      ...children,
    ],
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon; final String label; final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 16, color: textMid),
      const SizedBox(width: 10),
      Text('$label: ',
          style: const TextStyle(fontSize: 13, color: textMid)),
      Expanded(child: Text(value,
          style: const TextStyle(fontSize: 13, color: textDark,
              fontWeight: FontWeight.w500))),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// AVATAR WIDGET
// ══════════════════════════════════════════════════════════════════════════════

class _Avatar extends StatelessWidget {
  final Member member; final double size; final Color primary;
  const _Avatar({required this.member, required this.size,
      required this.primary});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = member.photoPath.isNotEmpty &&
        File(member.photoPath).existsSync();
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: primary.withValues(alpha: 0.15),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? Image.file(File(member.photoPath), fit: BoxFit.cover)
          : Center(
              child: Text(member.initials,
                  style: TextStyle(
                      fontSize: size * 0.35,
                      fontWeight: FontWeight.bold,
                      color: primary))),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// STATUS BADGE
// ══════════════════════════════════════════════════════════════════════════════

class _StatusBadge extends StatelessWidget {
  final MemberStatus status; final bool small;
  const _StatusBadge({required this.status, this.small = false});

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[status]!;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 6 : 10, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(_statusLabels[status]!,
          style: TextStyle(
              fontSize: small ? 10 : 12,
              color: color,
              fontWeight: FontWeight.bold)),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MEMBER FORM DIALOG
// ══════════════════════════════════════════════════════════════════════════════

class _MemberFormDialog extends StatefulWidget {
  final Color   primary;
  final Member? existing;
  const _MemberFormDialog({required this.primary, this.existing});

  @override
  State<_MemberFormDialog> createState() => _MemberFormDialogState();
}

class _MemberFormDialogState extends State<_MemberFormDialog> {
  final _formKey      = GlobalKey<FormState>();
  late TextEditingController _firstCtrl, _lastCtrl, _emailCtrl,
                             _phoneCtrl, _addressCtrl, _familyCtrl,
                             _notesCtrl;
  late MemberStatus _status;
  DateTime? _birthday, _joinDate, _baptismDate;
  String    _photoPath = '';

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    _firstCtrl   = TextEditingController(text: m?.firstName   ?? '');
    _lastCtrl    = TextEditingController(text: m?.lastName    ?? '');
    _emailCtrl   = TextEditingController(text: m?.email       ?? '');
    _phoneCtrl   = TextEditingController(text: m?.phone       ?? '');
    _addressCtrl = TextEditingController(text: m?.address     ?? '');
    _familyCtrl  = TextEditingController(text: m?.familyUnit  ?? '');
    _notesCtrl   = TextEditingController(text: m?.notes       ?? '');
    _status      = m?.status ?? MemberStatus.visitor;
    _birthday    = m?.birthday;
    _joinDate    = m?.joinDate;
    _baptismDate = m?.baptismDate;
    _photoPath   = m?.photoPath ?? '';
  }

  @override
  void dispose() {
    for (final c in [_firstCtrl, _lastCtrl, _emailCtrl, _phoneCtrl,
        _addressCtrl, _familyCtrl, _notesCtrl]) c.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.image, allowMultiple: false);
    if (result != null && result.files.single.path != null) {
      // Copy to app documents dir so it persists
      final src  = File(result.files.single.path!);
      final dir  = await getApplicationDocumentsDirectory();
      final dest = '${dir.path}/member_photos/${const Uuid().v4()}'
                   '${result.files.single.extension != null ? ".${result.files.single.extension}" : ""}';
      await Directory('${dir.path}/member_photos').create(recursive: true);
      await src.copy(dest);
      setState(() => _photoPath = dest);
    }
  }

  Future<void> _pickDate(String field) async {
    final initial = (field == 'birthday'  ? _birthday  :
                     field == 'joinDate'  ? _joinDate  :
                     _baptismDate) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() {
      if (field == 'birthday')  _birthday    = d;
      if (field == 'joinDate')  _joinDate    = d;
      if (field == 'baptism')   _baptismDate = d;
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final member = Member(
      id:          widget.existing?.id ?? const Uuid().v4(),
      firstName:   _firstCtrl.text.trim(),
      lastName:    _lastCtrl.text.trim(),
      email:       _emailCtrl.text.trim(),
      phone:       _phoneCtrl.text.trim(),
      address:     _addressCtrl.text.trim(),
      status:      _status,
      familyUnit:  _familyCtrl.text.trim(),
      birthday:    _birthday,
      joinDate:    _joinDate,
      baptismDate: _baptismDate,
      notes:       _notesCtrl.text.trim(),
      photoPath:   _photoPath,
    );
    Navigator.pop(context, member);
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary;
    final fmt     = DateFormat('MMM d, y');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Title bar
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            decoration: BoxDecoration(
              color: primary,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16)),
            ),
            child: Row(children: [
              Text(
                widget.existing == null ? 'Add Member' : 'Edit Member',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                    color: contrastOn(primary)),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close, color: contrastOn(primary), size: 18),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ]),
          ),
          // Form
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(children: [
                  // Photo picker
                  GestureDetector(
                    onTap: _pickPhoto,
                    child: Stack(alignment: Alignment.bottomRight, children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: primary.withValues(alpha: 0.15),
                        backgroundImage: (_photoPath.isNotEmpty &&
                                File(_photoPath).existsSync())
                            ? FileImage(File(_photoPath))
                            : null,
                        child: (_photoPath.isEmpty ||
                                !File(_photoPath).existsSync())
                            ? Icon(Icons.person, color: primary, size: 32)
                            : null,
                      ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                            color: primary, shape: BoxShape.circle),
                        child: Icon(Icons.camera_alt,
                            size: 14, color: contrastOn(primary)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  // Name row
                  Row(children: [
                    Expanded(child: TextFormField(
                      controller: _firstCtrl,
                      decoration: const InputDecoration(
                          labelText: 'First Name *',
                          border: OutlineInputBorder(), isDense: true),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty)
                              ? 'Required' : null,
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: TextFormField(
                      controller: _lastCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Last Name *',
                          border: OutlineInputBorder(), isDense: true),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty)
                              ? 'Required' : null,
                    )),
                  ]),
                  const SizedBox(height: 12),
                  // Status
                  DropdownButtonFormField<MemberStatus>(
                    value: _status,
                    decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(), isDense: true),
                    items: MemberStatus.values.map((s) =>
                        DropdownMenuItem(value: s,
                            child: Text(_statusLabels[s]!))).toList(),
                    onChanged: (v) => setState(() => _status = v!),
                  ),
                  const SizedBox(height: 12),
                  // Contact
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(), isDense: true),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Phone',
                        border: OutlineInputBorder(), isDense: true),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Address',
                        border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _familyCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Family / Household Name',
                        hintText: 'e.g. "The Smith Family"',
                        border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 12),
                  // Dates row
                  Row(children: [
                    Expanded(child: _DateButton(
                      label: 'Birthday',
                      value: _birthday != null ? fmt.format(_birthday!) : null,
                      icon: Icons.cake_outlined,
                      primary: primary,
                      onTap: () => _pickDate('birthday'),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: _DateButton(
                      label: 'Join Date',
                      value: _joinDate != null ? fmt.format(_joinDate!) : null,
                      icon: Icons.church_outlined,
                      primary: primary,
                      onTap: () => _pickDate('joinDate'),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: _DateButton(
                      label: 'Baptism',
                      value: _baptismDate != null
                          ? fmt.format(_baptismDate!) : null,
                      icon: Icons.water_drop_outlined,
                      primary: primary,
                      onTap: () => _pickDate('baptism'),
                    )),
                  ]),
                  const SizedBox(height: 12),
                  // Notes
                  TextFormField(
                    controller: _notesCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Notes',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true),
                    maxLines: 3,
                    minLines: 2,
                  ),
                ]),
              ),
            ),
          ),
          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: contrastOn(primary),
                ),
                child: Text(widget.existing == null ? 'Add Member' : 'Save'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label; final String? value;
  final IconData icon; final Color primary;
  final VoidCallback onTap;
  const _DateButton({required this.label, required this.value,
      required this.icon, required this.primary, required this.onTap});

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      side: BorderSide(color: borderColor),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: primary),
      const SizedBox(height: 2),
      Text(value ?? label,
          style: TextStyle(
              fontSize: 10,
              color: value != null ? textDark : textMid),
          textAlign: TextAlign.center,
          maxLines: 2, overflow: TextOverflow.ellipsis),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// EMPTY DETAIL STATE
// ══════════════════════════════════════════════════════════════════════════════

class _EmptyDetail extends StatelessWidget {
  final Color primary; final VoidCallback onAdd;
  const _EmptyDetail({required this.primary, required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.people_outline,
          size: 56, color: primary.withValues(alpha: 0.15)),
      const SizedBox(height: 16),
      Text('Select a member or add a new one',
          style: TextStyle(
              color: primary.withValues(alpha: 0.35), fontSize: 15)),
      const SizedBox(height: 12),
      ElevatedButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add First Member'),
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: contrastOn(primary),
        ),
      ),
    ]),
  );
}