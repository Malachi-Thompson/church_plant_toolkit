// lib/apps/bulletin/bulletin_screen.dart
//
// Main coordinator for the Bulletin Maker feature.
// Architecture mirrors the notes screen: state + routing only, no layout widgets.
//
// To add a new section to bulletins → bulletin_model.dart + bulletin_editor.dart
// To add a new layout              → bulletin_model.dart + bulletin_exporter.dart
// To change export behaviour       → bulletin_exporter.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../models/app_state.dart';
import '../../screens/dashboard_screen.dart';
import '../../theme.dart';
import 'bulletin_exporter.dart';
import 'bulletin_model.dart';
import 'dialogs/new_bulletin_dialog.dart';
import 'widgets/bulletin_editor.dart';
import 'widgets/bulletin_list.dart';

// ── MOBILE PANE ───────────────────────────────────────────────────────────────
enum _MobilePane { list, editor }

// ══════════════════════════════════════════════════════════════════════════════
// SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class BulletinScreen extends StatefulWidget {
  const BulletinScreen({super.key});
  @override
  State<BulletinScreen> createState() => _BulletinScreenState();
}

class _BulletinScreenState extends State<BulletinScreen> {
  List<BulletinModel> _bulletins   = [];
  BulletinModel?      _selected;
  _MobilePane         _mobilePane  = _MobilePane.list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── PERSISTENCE ───────────────────────────────────────────────────────────

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('bulletins_v1');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        setState(() => _bulletins =
            list.map((e) => BulletinModel.fromJson(e)).toList());
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'bulletins_v1',
        jsonEncode(_bulletins.map((b) => b.toJson()).toList()));
  }

  void _update(VoidCallback fn) { setState(fn); _save(); }

  // ── SORTED LIST ───────────────────────────────────────────────────────────

  List<BulletinModel> get _sorted => [..._bulletins]
    ..sort((a, b) {
      // Most recent service date first; fall back to updatedAt
      final da = a.serviceDate ?? a.updatedAt;
      final db = b.serviceDate ?? b.updatedAt;
      return db.compareTo(da);
    });

  // ── CREATE ────────────────────────────────────────────────────────────────

  Future<void> _createBulletin() async {
    final layout = await showDialog<BulletinLayout>(
      context: context,
      builder: (_) => NewBulletinDialog(
          primary: context.read<AppState>().brandPrimary),
    );
    if (layout == null || !mounted) return;

    final now     = DateTime.now();
    final nextSun = _nextSunday(now);
    final appState = context.read<AppState>();
    final profile  = appState.churchProfile;

    final bulletin = BulletinModel(
      id:          const Uuid().v4(),
      title:       'Bulletin – ${DateFormat('MMMM d, y').format(nextSun)}',
      serviceDate: nextSun,
      churchName:    profile?.name         ?? '',
      churchAddress: profile != null
          ? [profile.city, profile.state, profile.country]
              .where((s) => s.isNotEmpty).join(', ')
          : '',
      churchPhone:   profile?.phone        ?? '',
      churchWebsite: profile?.website      ?? '',
      churchEmail:   profile?.email        ?? '',
      layout:       layout,
      accentColor:  _colorToHex(appState.brandPrimary),
      createdAt:    now,
      updatedAt:    now,
    );

    _update(() {
      _bulletins.insert(0, bulletin);
      _selected = bulletin;
    });

    if (mounted && MediaQuery.of(context).size.width < 700) {
      setState(() => _mobilePane = _MobilePane.editor);
    }
  }

  // ── DUPLICATE ─────────────────────────────────────────────────────────────

  void _duplicateBulletin(BulletinModel b) {
    final copy = b.copyForNewWeek();
    _update(() {
      _bulletins.insert(0, copy);
      _selected = copy;
    });
    if (mounted && MediaQuery.of(context).size.width < 700) {
      setState(() => _mobilePane = _MobilePane.editor);
    }
  }

  // ── DELETE ────────────────────────────────────────────────────────────────

  void _deleteBulletin(BulletinModel b) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Bulletin'),
        content: Text('Delete "${b.title}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      _update(() {
        _bulletins.removeWhere((x) => x.id == b.id);
        if (_selected?.id == b.id) _selected = null;
      });
    }
  }

  // ── EXPORT ────────────────────────────────────────────────────────────────

  Future<void> _export(BulletinModel b) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await exportBulletinHtml(b);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text(
            'Bulletin opened in browser — use File → Print → Save as PDF'),
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

  // ── HELPERS ───────────────────────────────────────────────────────────────

  static DateTime _nextSunday(DateTime from) {
    final daysUntilSunday = (7 - from.weekday) % 7;
    return from.add(Duration(
        days: daysUntilSunday == 0 ? 7 : daysUntilSunday));
  }

  static String _colorToHex(Color c) {
    final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
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
        ? _buildDesktop(context, primary, secondary, profile)
        : _buildMobile(context, primary, secondary, profile);
  }

  // ── DESKTOP ───────────────────────────────────────────────────────────────

  Widget _buildDesktop(BuildContext context,
      Color primary, Color secondary, dynamic profile) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: contrastOn(primary),
        title: Row(children: [
          if (profile != null)
            ChurchLogo(
                logoPath: profile.logoPath,
                primary: primary, secondary: secondary,
                size: 30, borderRadius: 7),
          if (profile != null) const SizedBox(width: 10),
          const Text('Bulletin Maker',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: contrastOn(primary)),
            tooltip: 'New bulletin',
            onPressed: _createBulletin,
          ),
        ],
      ),
      body: Row(children: [
        // Bulletin list (left panel)
        SizedBox(
          width: 280,
          child: BulletinList(
            bulletins:   _sorted,
            selected:    _selected,
            primary:     primary,
            onSelect:    (b) => setState(() => _selected = b),
            onDelete:    _deleteBulletin,
            onDuplicate: _duplicateBulletin,
            onNew:       _createBulletin,
          ),
        ),
        const VerticalDivider(width: 1),
        // Editor (right)
        Expanded(
          child: _selected != null
              ? BulletinEditor(
                  key:       ValueKey(_selected!.id),
                  bulletin:  _selected!,
                  primary:   primary,
                  secondary: secondary,
                  onChanged: () => _update(() =>
                      _selected!.updatedAt = DateTime.now()),
                  onExport:  () => _export(_selected!),
                )
              : _EmptyState(primary: primary, onNew: _createBulletin),
        ),
      ]),
    );
  }

  // ── MOBILE ────────────────────────────────────────────────────────────────

  Widget _buildMobile(BuildContext context,
      Color primary, Color secondary, dynamic profile) {
    final showBack = _mobilePane == _MobilePane.editor;
    final title    = showBack
        ? (_selected?.title ?? 'Bulletin')
        : 'Bulletin Maker';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: contrastOn(primary),
        leading: showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    setState(() => _mobilePane = _MobilePane.list),
              )
            : null,
        title: Row(children: [
          if (!showBack && profile != null) ...[
            ChurchLogo(
                logoPath: profile.logoPath,
                primary: primary, secondary: secondary,
                size: 26, borderRadius: 6),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        actions: [
          if (!showBack)
            IconButton(
              icon: Icon(Icons.add, color: contrastOn(primary)),
              onPressed: _createBulletin,
            ),
          if (showBack && _selected != null)
            IconButton(
              icon: Icon(Icons.print_outlined, color: contrastOn(primary)),
              tooltip: 'Print / PDF',
              onPressed: () => _export(_selected!),
            ),
        ],
      ),
      body: _mobilePane == _MobilePane.list
          ? BulletinList(
              bulletins:   _sorted,
              selected:    _selected,
              primary:     primary,
              onSelect: (b) => setState(() {
                _selected   = b;
                _mobilePane = _MobilePane.editor;
              }),
              onDelete:    _deleteBulletin,
              onDuplicate: _duplicateBulletin,
              onNew:       _createBulletin,
            )
          : (_selected != null
              ? BulletinEditor(
                  key:       ValueKey(_selected!.id),
                  bulletin:  _selected!,
                  primary:   primary,
                  secondary: secondary,
                  onChanged: () => _update(() =>
                      _selected!.updatedAt = DateTime.now()),
                  onExport:  () => _export(_selected!),
                )
              : _EmptyState(primary: primary, onNew: _createBulletin)),
    );
  }
}

// ── EMPTY STATE ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final Color primary; final VoidCallback onNew;
  const _EmptyState({required this.primary, required this.onNew});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.article_outlined,
          size: 60, color: primary.withValues(alpha: 0.15)),
      const SizedBox(height: 20),
      Text('No bulletin selected',
          style: TextStyle(
              fontSize: 16,
              color: primary.withValues(alpha: 0.35),
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      Text('Select a bulletin from the list or create a new one.',
          style: TextStyle(
              fontSize: 13, color: primary.withValues(alpha: 0.3))),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: onNew,
        icon: const Icon(Icons.add),
        label: const Text('New Bulletin'),
        style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: contrastOn(primary)),
      ),
    ]),
  );
}