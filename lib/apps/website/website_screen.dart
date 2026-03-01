// lib/apps/website/website_screen.dart
// Wix/WordPress-style website builder with:
// - Left panel: pages + block library
// - Center: live HTML preview (opens in browser) / block canvas
// - Right panel: selected block property editor
// - Template picker on first launch
// - Export to static HTML + GitHub Pages / Cloudflare deploy config

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/app_state.dart';
import '../../screens/dashboard_screen.dart';
import '../../services/bible_service.dart';
import '../../theme.dart';
import '../../widgets/scripture_field.dart';
import 'website_models.dart';
import 'website_templates.dart';
import 'website_exporter.dart';

const _uuid = Uuid();
String _id() => _uuid.v4();

// ══════════════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class WebsiteScreen extends StatefulWidget {
  const WebsiteScreen({super.key});
  @override
  State<WebsiteScreen> createState() => _WebsiteScreenState();
}

class _WebsiteScreenState extends State<WebsiteScreen> {
  ChurchWebsite? _site;
  WebPage?       _activePage;
  WebBlock?      _selectedBlock;
  bool           _loading       = true;
  bool           _previewMode   = false;
  bool           _exportBusy    = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── PERSISTENCE ─────────────────────────────────────────────────────────────

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('website_v2');
    if (raw != null) {
      try {
        _site = ChurchWebsite.fromJson(jsonDecode(raw));
        _activePage = _site!.homePage ?? _site!.pages.firstOrNull;
      } catch (_) {}
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_site == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('website_v2', jsonEncode(_site!.toJson()));
  }

  void _update(VoidCallback fn) {
    setState(fn);
    _save();
  }

  // ── TEMPLATE PICKER ──────────────────────────────────────────────────────────

  Future<void> _showTemplatePicker() async {
    final state = context.read<AppState>();
    final p     = state.churchProfile;

    final template = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TemplatePickerDialog(primary: state.brandPrimary),
    );
    if (template == null || !mounted) return;

    final site = buildTemplate(
      template,
      p?.name  ?? 'My Church',
      p?.tagline ?? '',
      '#${state.brandPrimary.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
      '#${state.brandSecondary.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
    );
    _update(() {
      _site        = site;
      _activePage  = site.homePage ?? site.pages.firstOrNull;
      _selectedBlock = null;
    });
  }

  // ── PAGE MANAGEMENT ──────────────────────────────────────────────────────────

  void _addPage() {
    final page = WebPage(
      id: _id(), title: 'New Page',
      slug: 'page-${_site!.pages.length + 1}',
    );
    _update(() {
      _site!.pages.add(page);
      _activePage    = page;
      _selectedBlock = null;
    });
  }

  void _deletePage(WebPage page) {
    if (_site!.pages.length <= 1) return;
    _update(() {
      _site!.pages.remove(page);
      if (_activePage?.id == page.id) {
        _activePage = _site!.pages.first;
      }
      _selectedBlock = null;
    });
  }

  // ── BLOCK MANAGEMENT ─────────────────────────────────────────────────────────

  void _addBlock(BlockType type) {
    if (_activePage == null) return;
    final block = _defaultBlock(type);
    _update(() {
      _activePage!.blocks.add(block);
      _selectedBlock = block;
    });
  }

  WebBlock _defaultBlock(BlockType type) {
    final state = context.read<AppState>();
    final p     = state.churchProfile;
    switch (type) {
      case BlockType.hero:
        return WebBlock(id: _id(), type: type,
            heading: 'Welcome to ${p?.name ?? "Our Church"}',
            subheading: p?.tagline ?? 'Come as you are.',
            buttonText: 'Plan Your Visit', buttonUrl: '#contact');
      case BlockType.services:
        return WebBlock(id: _id(), type: type,
            heading: 'Join Us',
            serviceTimes: [ServiceTime(day: 'Sunday', time: '10:00 AM')]);
      case BlockType.events:
        return WebBlock(id: _id(), type: type, heading: 'Upcoming Events',
            events: [WebEvent(title: 'New Event', date: 'March 15', time: '6:00 PM')]);
      case BlockType.team:
        return WebBlock(id: _id(), type: type, heading: 'Meet the Team',
            team: [WebTeamMember(name: 'Pastor Name', role: 'Lead Pastor')]);
      case BlockType.map:
        return WebBlock(id: _id(), type: type, heading: 'Find Us',
            mapProvider: MapProvider.openStreetMap);
      case BlockType.cta:
        return WebBlock(id: _id(), type: type,
            heading: 'Ready to Take Your Next Step?',
            subheading: 'We\'d love to connect with you.',
            buttonText: 'Contact Us', buttonUrl: '#contact');
      case BlockType.announcement:
        return WebBlock(id: _id(), type: type,
            heading: '📢 Announcement',
            body: 'Add your announcement here.',
            announcementColor: '#D4A843');
      case BlockType.divider:
        return WebBlock(id: _id(), type: type, dividerStyle: 'line');
      default:
        return WebBlock(id: _id(), type: type,
            heading: blockTypeLabels[type] ?? '',
            body: 'Add your content here.');
    }
  }

  void _moveBlock(int oldIdx, int newIdx) {
    if (_activePage == null) return;
    _update(() {
      if (newIdx > oldIdx) newIdx--;
      final b = _activePage!.blocks.removeAt(oldIdx);
      _activePage!.blocks.insert(newIdx, b);
    });
  }

  void _deleteBlock(WebBlock block) {
    if (_activePage == null) return;
    _update(() {
      _activePage!.blocks.remove(block);
      if (_selectedBlock?.id == block.id) _selectedBlock = null;
    });
  }

  // ── PREVIEW ──────────────────────────────────────────────────────────────────

  Future<void> _openPreview() async {
    if (_site == null || _activePage == null) return;
    try {
      final dir      = await getApplicationDocumentsDirectory();
      final previewDir = Directory('${dir.path}/website_preview');
      await previewDir.create(recursive: true);

      // Write all pages + CSS so nav links work
      final cssFile = File('${previewDir.path}/style.css');
      await cssFile.writeAsString(generateCSS(_site!.settings));
      for (final page in _site!.pages) {
        final fname = page.isHomePage ? 'index.html' : '${page.slug}.html';
        await File('${previewDir.path}/$fname')
            .writeAsString(generatePageHtml(_site!, page));
      }

      final activeName = _activePage!.isHomePage
          ? 'index.html' : '${_activePage!.slug}.html';
      final uri = Uri.file('${previewDir.path}/$activeName');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open browser preview'),
                behavior: SnackBarBehavior.floating),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preview error: $e'),
              behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  // ── EXPORT ───────────────────────────────────────────────────────────────────

  Future<void> _exportSite() async {
    if (_site == null) return;
    setState(() => _exportBusy = true);
    final result = await exportWebsite(_site!);
    setState(() => _exportBusy = false);
    if (!mounted) return;

    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: ${result.error}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => _ExportResultDialog(result: result, site: _site!),
    );
  }

  // ── BUILD ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state     = context.watch<AppState>();
    final primary   = state.brandPrimary;
    final secondary = state.brandSecondary;
    final profile   = state.churchProfile;

    if (_loading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: primary)));
    }

    // First launch — show template picker
    if (_site == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.web, size: 64,
                  color: primary.withValues(alpha: 0.3)),
              const SizedBox(height: 20),
              const Text('No website yet',
                  style: TextStyle(fontSize: 20,
                      fontWeight: FontWeight.bold, color: textDark)),
              const SizedBox(height: 8),
              const Text('Choose a template to get started',
                  style: TextStyle(color: textMid)),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: _showTemplatePicker,
                icon: const Icon(Icons.dashboard_customize),
                label: const Text('Choose Template'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: contrastOn(primary),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(primary, secondary, profile),
      body: Row(
        children: [
          // ── LEFT PANEL: pages + block library ──────────────────────────
          SizedBox(
            width: 220,
            child: _LeftPanel(
              site:          _site!,
              activePage:    _activePage,
              primary:       primary,
              secondary:     secondary,
              onSelectPage:  (p) => _update(() {
                _activePage    = p;
                _selectedBlock = null;
              }),
              onAddPage:     _addPage,
              onDeletePage:  _deletePage,
              onAddBlock:    _addBlock,
              onReset:       _showTemplatePicker,
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),

          // ── CENTER: block canvas ────────────────────────────────────────
          Expanded(
            child: _activePage != null
                ? _BlockCanvas(
                    page:          _activePage!,
                    site:          _site!,
                    selectedBlock: _selectedBlock,
                    primary:       primary,
                    secondary:     secondary,
                    onSelect:      (b) => setState(() => _selectedBlock = b),
                    onDelete:      _deleteBlock,
                    onReorder:     _moveBlock,
                    onToggleVisibility: (b) => _update(() =>
                        b.isVisible = !b.isVisible),
                  )
                : Center(
                    child: Text('Select or create a page',
                        style: TextStyle(color: primary.withValues(alpha: 0.4)))),
          ),

          // ── RIGHT PANEL: property editor ────────────────────────────────
          if (_selectedBlock != null) ...[
            const VerticalDivider(width: 1, thickness: 1),
            SizedBox(
              width: 320,
              child: _BlockPropertyPanel(
                block:       _selectedBlock!,
                site:        _site!,
                primary:     primary,
                secondary:   secondary,
                bibleService: state.bibleService,
                onChanged:   () => _update(() {}),
              ),
            ),
          ],
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
      Color primary, Color secondary, profile) {
    return AppBar(
      backgroundColor: primary,
      foregroundColor: contrastOn(primary),
      title: Row(
        children: [
          if (profile != null)
            ChurchLogo(
              logoPath: profile.logoPath,
              primary: primary, secondary: secondary,
              size: 30, borderRadius: 7),
          if (profile != null) const SizedBox(width: 10),
          const Text('Website Builder',
              style: TextStyle(fontWeight: FontWeight.bold)),
          if (_site != null) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: contrastOn(primary).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6)),
              child: Text(
                _site!.pages.length == 1 ? 'Single Page' : '${_site!.pages.length} Pages',
                style: TextStyle(fontSize: 11,
                    color: contrastOn(primary).withValues(alpha: 0.8)),
              ),
            ),
          ],
        ],
      ),
      actions: [
        // Preview in browser
        TextButton.icon(
          onPressed: _openPreview,
          icon: Icon(Icons.open_in_browser,
              color: contrastOn(primary), size: 18),
          label: Text('Preview',
              style: TextStyle(color: contrastOn(primary))),
        ),
        // Export / Deploy
        _exportBusy
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: contrastOn(primary))))
            : TextButton.icon(
                onPressed: _exportSite,
                icon: Icon(Icons.rocket_launch,
                    color: secondary, size: 18),
                label: Text('Export & Deploy',
                    style: TextStyle(
                        color: secondary, fontWeight: FontWeight.bold)),
              ),
        // Site settings
        IconButton(
          onPressed: () => _showSiteSettings(),
          icon: Icon(Icons.settings_outlined, color: contrastOn(primary)),
          tooltip: 'Site Settings',
        ),
      ],
    );
  }

  void _showSiteSettings() {
    if (_site == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SiteSettingsSheet(
        site:      _site!,
        primary:   context.read<AppState>().brandPrimary,
        secondary: context.read<AppState>().brandSecondary,
        onChanged: () => _update(() {}),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// LEFT PANEL
// ══════════════════════════════════════════════════════════════════════════════

class _LeftPanel extends StatefulWidget {
  final ChurchWebsite  site;
  final WebPage?       activePage;
  final Color          primary;
  final Color          secondary;
  final ValueChanged<WebPage>  onSelectPage;
  final VoidCallback           onAddPage;
  final ValueChanged<WebPage>  onDeletePage;
  final ValueChanged<BlockType> onAddBlock;
  final VoidCallback           onReset;

  const _LeftPanel({
    required this.site, required this.activePage,
    required this.primary, required this.secondary,
    required this.onSelectPage, required this.onAddPage,
    required this.onDeletePage, required this.onAddBlock,
    required this.onReset,
  });

  @override
  State<_LeftPanel> createState() => _LeftPanelState();
}

class _LeftPanelState extends State<_LeftPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          labelColor:          widget.primary,
          unselectedLabelColor: textMid,
          indicatorColor:      widget.primary,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: const [Tab(text: 'Pages'), Tab(text: 'Blocks')],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _PagesPanel(
                site:         widget.site,
                activePage:   widget.activePage,
                primary:      widget.primary,
                onSelect:     widget.onSelectPage,
                onAdd:        widget.onAddPage,
                onDelete:     widget.onDeletePage,
                onReset:      widget.onReset,
              ),
              _BlockLibraryPanel(
                primary:  widget.primary,
                onAddBlock: widget.onAddBlock,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── PAGES PANEL ───────────────────────────────────────────────────────────────

class _PagesPanel extends StatelessWidget {
  final ChurchWebsite site;
  final WebPage? activePage;
  final Color primary;
  final ValueChanged<WebPage> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<WebPage> onDelete;
  final VoidCallback onReset;

  const _PagesPanel({
    required this.site, required this.activePage, required this.primary,
    required this.onSelect, required this.onAdd,
    required this.onDelete, required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Page', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: contrastOn(primary),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: site.pages.length,
            itemBuilder: (ctx, i) {
              final page    = site.pages[i];
              final active  = activePage?.id == page.id;
              return ListTile(
                dense: true,
                selected: active,
                selectedTileColor: primary.withValues(alpha: 0.08),
                leading: Icon(
                  page.isHomePage ? Icons.home_outlined : Icons.article_outlined,
                  size: 18,
                  color: active ? primary : textMid,
                ),
                title: Text(page.title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.bold : FontWeight.normal,
                        color: active ? primary : textDark)),
                subtitle: Text('/${page.slug}  ·  ${page.blocks.length} blocks',
                    style: const TextStyle(fontSize: 10, color: textMid)),
                trailing: site.pages.length > 1
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 16, color: Colors.red),
                        onPressed: () => onDelete(page),
                      )
                    : null,
                onTap: () => onSelect(page),
              );
            },
          ),
        ),
        const Divider(height: 1),
        ListTile(
          dense: true,
          leading: Icon(Icons.dashboard_customize,
              size: 16, color: primary.withValues(alpha: 0.6)),
          title: Text('Change Template',
              style: TextStyle(fontSize: 12,
                  color: primary.withValues(alpha: 0.8))),
          onTap: onReset,
        ),
      ],
    );
  }
}

// ── BLOCK LIBRARY ─────────────────────────────────────────────────────────────

class _BlockLibraryPanel extends StatelessWidget {
  final Color primary;
  final ValueChanged<BlockType> onAddBlock;

  const _BlockLibraryPanel(
      {required this.primary, required this.onAddBlock});

  static const _groups = <String, List<BlockType>>{
    'Layout': [BlockType.hero, BlockType.cta, BlockType.divider],
    'Content': [BlockType.about, BlockType.richText, BlockType.sermon, BlockType.announcement],
    'Info': [BlockType.services, BlockType.events, BlockType.team],
    'Media': [BlockType.gallery, BlockType.map],
    'Connect': [BlockType.contact],
  };

  static const _icons = <BlockType, IconData>{
    BlockType.hero:         Icons.web_asset,
    BlockType.about:        Icons.info_outline,
    BlockType.services:     Icons.access_time,
    BlockType.events:       Icons.event,
    BlockType.team:         Icons.people_outline,
    BlockType.sermon:       Icons.menu_book_outlined,
    BlockType.contact:      Icons.mail_outline,
    BlockType.map:          Icons.map_outlined,
    BlockType.gallery:      Icons.photo_library_outlined,
    BlockType.announcement: Icons.campaign_outlined,
    BlockType.divider:      Icons.horizontal_rule,
    BlockType.richText:     Icons.text_fields,
    BlockType.cta:          Icons.ads_click,
  };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: _groups.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Text(entry.key,
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: textMid,
                      letterSpacing: 1.2)),
            ),
            ...entry.value.map((type) => _BlockLibraryTile(
                  type: type,
                  icon: _icons[type] ?? Icons.widgets,
                  label: blockTypeLabels[type] ?? '',
                  primary: primary,
                  onAdd: () => onAddBlock(type),
                )),
            const SizedBox(height: 4),
          ],
        );
      }).toList(),
    );
  }
}

class _BlockLibraryTile extends StatelessWidget {
  final BlockType type;
  final IconData icon;
  final String label;
  final Color primary;
  final VoidCallback onAdd;

  const _BlockLibraryTile({
    required this.type, required this.icon, required this.label,
    required this.primary, required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEAEDF3)),
      ),
      child: ListTile(
        dense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        leading: Icon(icon, size: 18, color: primary),
        title: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        trailing: GestureDetector(
          onTap: onAdd,
          child: Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
                color: primary, borderRadius: BorderRadius.circular(6)),
            child: Icon(Icons.add, size: 14, color: contrastOn(primary)),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BLOCK CANVAS (center panel)
// ══════════════════════════════════════════════════════════════════════════════

class _BlockCanvas extends StatelessWidget {
  final WebPage        page;
  final ChurchWebsite  site;
  final WebBlock?      selectedBlock;
  final Color          primary;
  final Color          secondary;
  final ValueChanged<WebBlock>  onSelect;
  final ValueChanged<WebBlock>  onDelete;
  final void Function(int, int) onReorder;
  final ValueChanged<WebBlock>  onToggleVisibility;

  const _BlockCanvas({
    required this.page, required this.site,
    required this.selectedBlock, required this.primary, required this.secondary,
    required this.onSelect, required this.onDelete,
    required this.onReorder, required this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    if (page.blocks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_box_outlined,
                size: 56, color: primary.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text('This page is empty',
                style: TextStyle(
                    color: primary.withValues(alpha: 0.5), fontSize: 16)),
            const SizedBox(height: 6),
            const Text('Add blocks from the "Blocks" tab on the left',
                style: TextStyle(color: textMid, fontSize: 13)),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: page.blocks.length,
      onReorder: onReorder,
      itemBuilder: (ctx, i) {
        final block    = page.blocks[i];
        final selected = selectedBlock?.id == block.id;
        return _BlockCanvasTile(
          key:        ValueKey(block.id),
          block:      block,
          site:       site,
          index:      i,
          selected:   selected,
          primary:    primary,
          secondary:  secondary,
          onSelect:   () => onSelect(block),
          onDelete:   () => onDelete(block),
          onToggleVisible: () => onToggleVisibility(block),
        );
      },
    );
  }
}

class _BlockCanvasTile extends StatelessWidget {
  final WebBlock      block;
  final ChurchWebsite site;
  final int           index;
  final bool          selected;
  final Color         primary;
  final Color         secondary;
  final VoidCallback  onSelect;
  final VoidCallback  onDelete;
  final VoidCallback  onToggleVisible;

  const _BlockCanvasTile({
    super.key,
    required this.block, required this.site, required this.index,
    required this.selected, required this.primary, required this.secondary,
    required this.onSelect, required this.onDelete,
    required this.onToggleVisible,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.04)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? primary : const Color(0xFFE0E0E0),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Block header bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? primary.withValues(alpha: 0.08)
                    : const Color(0xFFF8F9FA),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10)),
              ),
              child: Row(
                children: [
                  // Drag handle
                  Icon(Icons.drag_handle, size: 18,
                      color: selected ? primary : Colors.grey.shade400),
                  const SizedBox(width: 8),
                  Text(blockTypeLabels[block.type] ?? '',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: selected ? primary : textMid)),
                  const Spacer(),
                  // Visibility toggle
                  IconButton(
                    icon: Icon(
                      block.isVisible
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 16,
                      color: block.isVisible ? textMid : Colors.grey.shade300,
                    ),
                    onPressed: onToggleVisible,
                    tooltip: block.isVisible ? 'Hide' : 'Show',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 28, minHeight: 28),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 16, color: Colors.red),
                    onPressed: onDelete,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
            ),
            // Block mini-preview
            Opacity(
              opacity: block.isVisible ? 1.0 : 0.35,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: _BlockMiniPreview(
                    block: block, primary: primary, secondary: secondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── BLOCK MINI PREVIEW ────────────────────────────────────────────────────────

class _BlockMiniPreview extends StatelessWidget {
  final WebBlock block;
  final Color primary;
  final Color secondary;

  const _BlockMiniPreview(
      {required this.block, required this.primary, required this.secondary});

  @override
  Widget build(BuildContext context) {
    switch (block.type) {
      case BlockType.hero:
        return Container(
          width: double.infinity, height: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primary, Color.lerp(primary, Colors.black, 0.4)!]),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(block.heading,
                  style: TextStyle(
                      color: contrastOn(primary),
                      fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (block.subheading.isNotEmpty)
                Text(block.subheading,
                    style: TextStyle(
                        color: contrastOn(primary).withValues(alpha: 0.7),
                        fontSize: 11),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        );

      case BlockType.services:
        return Row(
          children: block.serviceTimes.take(3).map((st) =>
            Expanded(child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: primary.withValues(alpha: 0.2))),
              child: Column(
                children: [
                  Text(st.day, style: TextStyle(
                      color: primary, fontSize: 10, fontWeight: FontWeight.bold)),
                  Text(st.time, style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ))).toList(),
        );

      case BlockType.map:
        return Container(
          height: 60,
          decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFA5D6A7))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.map_outlined, color: Color(0xFF2E7D32)),
              const SizedBox(width: 8),
              Text(mapProviderLabels[block.mapProvider] ?? 'Map',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF2E7D32))),
            ],
          ),
        );

      case BlockType.cta:
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
              color: secondary,
              borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              Expanded(child: Text(block.heading,
                  style: TextStyle(
                      color: contrastOn(secondary),
                      fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (block.buttonText.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(block.buttonText,
                      style: TextStyle(
                          color: contrastOn(secondary),
                          fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        );

      case BlockType.divider:
        return Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                block.dividerStyle == 'cross'
                    ? '✝'
                    : block.dividerStyle == 'wave' ? '〰' : '—',
                style: TextStyle(color: primary, fontSize: 18),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        );

      case BlockType.announcement:
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Color(int.parse(
                    'FF${block.announcementColor.replaceAll('#', '')}',
                    radix: 16))
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(
                color: Color(int.parse(
                    'FF${block.announcementColor.replaceAll('#', '')}',
                    radix: 16)),
                width: 4)),
          ),
          child: Text(block.heading,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13)),
        );

      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (block.heading.isNotEmpty)
              Text(block.heading,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13, color: primary),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            if (block.body.isNotEmpty)
              Text(block.body,
                  style: const TextStyle(fontSize: 12, color: textMid),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        );
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// RIGHT PANEL — PROPERTY EDITOR
// ══════════════════════════════════════════════════════════════════════════════

class _BlockPropertyPanel extends StatefulWidget {
  final WebBlock      block;
  final ChurchWebsite site;
  final Color         primary;
  final Color         secondary;
  final BibleService  bibleService;
  final VoidCallback  onChanged;

  const _BlockPropertyPanel({
    required this.block, required this.site,
    required this.primary, required this.secondary,
    required this.bibleService, required this.onChanged,
  });

  @override
  State<_BlockPropertyPanel> createState() => _BlockPropertyPanelState();
}

class _BlockPropertyPanelState extends State<_BlockPropertyPanel> {
  late TextEditingController _headingCtrl;
  late TextEditingController _subCtrl;
  late TextEditingController _bodyCtrl;
  late TextEditingController _btnTextCtrl;
  late TextEditingController _btnUrlCtrl;

  String get _blockId => widget.block.id;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  @override
  void didUpdateWidget(_BlockPropertyPanel old) {
    super.didUpdateWidget(old);
    if (old.block.id != widget.block.id) {
      _disposeControllers();
      _initControllers();
    }
  }

  void _initControllers() {
    _headingCtrl = TextEditingController(text: widget.block.heading);
    _subCtrl     = TextEditingController(text: widget.block.subheading);
    _bodyCtrl    = TextEditingController(text: widget.block.body);
    _btnTextCtrl = TextEditingController(text: widget.block.buttonText);
    _btnUrlCtrl  = TextEditingController(text: widget.block.buttonUrl);
    for (final c in [_headingCtrl, _subCtrl, _bodyCtrl, _btnTextCtrl, _btnUrlCtrl]) {
      c.addListener(_onTextChanged);
    }
  }

  void _onTextChanged() {
    widget.block.heading    = _headingCtrl.text;
    widget.block.subheading = _subCtrl.text;
    widget.block.body       = _bodyCtrl.text;
    widget.block.buttonText = _btnTextCtrl.text;
    widget.block.buttonUrl  = _btnUrlCtrl.text;
    widget.onChanged();
  }

  void _disposeControllers() {
    for (final c in [_headingCtrl, _subCtrl, _bodyCtrl, _btnTextCtrl, _btnUrlCtrl]) {
      c.removeListener(_onTextChanged);
      c.dispose();
    }
  }

  @override
  void dispose() { _disposeControllers(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final block   = widget.block;
    final primary = widget.primary;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.06),
            border: const Border(
                bottom: BorderSide(color: Color(0xFFEAEDF3))),
          ),
          child: Row(
            children: [
              Icon(Icons.tune, size: 16, color: primary),
              const SizedBox(width: 8),
              Text(blockTypeLabels[block.type] ?? 'Block',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14, color: primary)),
              const Spacer(),
              Switch(
                value: block.isVisible,
                onChanged: (v) {
                  block.isVisible = v;
                  widget.onChanged();
                },
                activeTrackColor: primary,
                activeThumbColor: Colors.white,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
        // Fields
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              ..._commonFields(block, primary),
              ..._specificFields(block, primary),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _commonFields(WebBlock block, Color primary) {
    final hasHeading = block.type != BlockType.divider;
    final hasBody    = [BlockType.about, BlockType.richText, BlockType.sermon,
                        BlockType.contact, BlockType.announcement,
                        BlockType.cta].contains(block.type);
    final hasButton  = [BlockType.hero, BlockType.about, BlockType.cta,
                        BlockType.announcement].contains(block.type);

    return [
      if (hasHeading) ...[
        _propField('Heading', _headingCtrl),
        _propField('Subheading', _subCtrl),
      ],
      if (hasBody) ...[
        ScriptureField(
          controller:   _bodyCtrl,
          bibleService: widget.bibleService,
          primary:      primary,
          label:        'Body Text',
          maxLines:     4,
        ),
        const SizedBox(height: 10),
      ],
      if (hasButton) ...[
        _propField('Button Text', _btnTextCtrl),
        _propField('Button URL', _btnUrlCtrl),
      ],
    ];
  }

  List<Widget> _specificFields(WebBlock block, Color primary) {
    switch (block.type) {
      case BlockType.services:
        return [
          _sectionLabel('Service Times'),
          ..._buildServiceTimeEditor(block, primary),
        ];

      case BlockType.events:
        return [
          _sectionLabel('Events'),
          ..._buildEventEditor(block, primary),
        ];

      case BlockType.team:
        return [
          _sectionLabel('Team Members'),
          ..._buildTeamEditor(block, primary),
        ];

      case BlockType.map:
        return [
          _sectionLabel('Map Settings'),
          _MapProviderPicker(
            block: block, primary: primary,
            onChanged: widget.onChanged),
        ];

      case BlockType.announcement:
        return [
          _sectionLabel('Accent Color'),
          _ColorHexField(
            label: 'Hex Color',
            value: block.announcementColor,
            onChanged: (v) {
              block.announcementColor = v;
              widget.onChanged();
            },
          ),
        ];

      case BlockType.divider:
        return [
          _sectionLabel('Style'),
          _DividerStylePicker(
            block: block, primary: primary,
            onChanged: widget.onChanged),
        ];

      default:
        return [];
    }
  }

  Widget _propField(String label, TextEditingController ctrl,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          isDense:   true,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 6),
    child: Text(label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold,
            color: widget.primary, letterSpacing: 0.8)),
  );

  List<Widget> _buildServiceTimeEditor(WebBlock block, Color primary) {
    return [
      ...block.serviceTimes.asMap().entries.map((entry) {
        final i  = entry.key;
        final st = entry.value;
        return _ServiceTimeRow(
          st: st, primary: primary,
          onDelete: () {
            block.serviceTimes.removeAt(i);
            widget.onChanged();
            setState(() {});
          },
          onChanged: widget.onChanged,
        );
      }),
      TextButton.icon(
        onPressed: () {
          block.serviceTimes.add(
              ServiceTime(day: 'Sunday', time: '10:00 AM'));
          widget.onChanged();
          setState(() {});
        },
        icon: Icon(Icons.add, size: 14, color: primary),
        label: Text('Add Time', style: TextStyle(color: primary, fontSize: 12)),
      ),
    ];
  }

  List<Widget> _buildEventEditor(WebBlock block, Color primary) {
    return [
      ...block.events.asMap().entries.map((entry) {
        final i = entry.key;
        final e = entry.value;
        return _EventRow(
          event: e, primary: primary,
          onDelete: () {
            block.events.removeAt(i);
            widget.onChanged();
            setState(() {});
          },
          onChanged: widget.onChanged,
        );
      }),
      TextButton.icon(
        onPressed: () {
          block.events.add(WebEvent(title: 'New Event', date: 'March 15'));
          widget.onChanged();
          setState(() {});
        },
        icon: Icon(Icons.add, size: 14, color: primary),
        label: Text('Add Event', style: TextStyle(color: primary, fontSize: 12)),
      ),
    ];
  }

  List<Widget> _buildTeamEditor(WebBlock block, Color primary) {
    return [
      ...block.team.asMap().entries.map((entry) {
        final i = entry.key;
        final m = entry.value;
        return _TeamMemberRow(
          member: m, primary: primary,
          onDelete: () {
            block.team.removeAt(i);
            widget.onChanged();
            setState(() {});
          },
          onChanged: widget.onChanged,
        );
      }),
      TextButton.icon(
        onPressed: () {
          block.team.add(WebTeamMember(name: 'New Member', role: 'Role'));
          widget.onChanged();
          setState(() {});
        },
        icon: Icon(Icons.add, size: 14, color: primary),
        label: Text('Add Member', style: TextStyle(color: primary, fontSize: 12)),
      ),
    ];
  }
}

// ── INLINE ROW EDITORS ────────────────────────────────────────────────────────

class _ServiceTimeRow extends StatefulWidget {
  final ServiceTime st;
  final Color primary;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  const _ServiceTimeRow({required this.st, required this.primary,
      required this.onDelete, required this.onChanged});
  @override State<_ServiceTimeRow> createState() => _ServiceTimeRowState();
}
class _ServiceTimeRowState extends State<_ServiceTimeRow> {
  late TextEditingController _day, _time, _loc;
  @override void initState() {
    super.initState();
    _day  = TextEditingController(text: widget.st.day);
    _time = TextEditingController(text: widget.st.time);
    _loc  = TextEditingController(text: widget.st.location);
    for (final c in [_day, _time, _loc]) c.addListener(_update);
  }
  void _update() {
    widget.st.day      = _day.text;
    widget.st.time     = _time.text;
    widget.st.location = _loc.text;
    widget.onChanged();
  }
  @override void dispose() { _day.dispose(); _time.dispose(); _loc.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Card(margin: const EdgeInsets.only(bottom: 8),
      child: Padding(padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(children: [
            Expanded(child: _mini('Day', _day)),
            const SizedBox(width: 8),
            Expanded(child: _mini('Time', _time)),
            IconButton(icon: const Icon(Icons.close, size: 14, color: Colors.red),
                onPressed: widget.onDelete, padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24)),
          ]),
          const SizedBox(height: 6),
          _mini('Location (optional)', _loc),
        ]),
      ),
    );
  }
  Widget _mini(String l, TextEditingController c) => TextFormField(
      controller: c,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(labelText: l, isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)));
}

class _EventRow extends StatefulWidget {
  final WebEvent event;
  final Color primary;
  final VoidCallback onDelete, onChanged;
  const _EventRow({required this.event, required this.primary,
      required this.onDelete, required this.onChanged});
  @override State<_EventRow> createState() => _EventRowState();
}
class _EventRowState extends State<_EventRow> {
  late TextEditingController _title, _date, _time, _desc;
  @override void initState() {
    super.initState();
    _title = TextEditingController(text: widget.event.title);
    _date  = TextEditingController(text: widget.event.date);
    _time  = TextEditingController(text: widget.event.time);
    _desc  = TextEditingController(text: widget.event.description);
    for (final c in [_title, _date, _time, _desc]) c.addListener(_update);
  }
  void _update() {
    widget.event.title       = _title.text;
    widget.event.date        = _date.text;
    widget.event.time        = _time.text;
    widget.event.description = _desc.text;
    widget.onChanged();
  }
  @override void dispose() { for (final c in [_title, _date, _time, _desc]) c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Card(margin: const EdgeInsets.only(bottom: 8),
      child: Padding(padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(children: [
            Expanded(child: _mini('Title', _title)),
            IconButton(icon: const Icon(Icons.close, size: 14, color: Colors.red),
                onPressed: widget.onDelete, padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _mini('Date', _date)),
            const SizedBox(width: 8),
            Expanded(child: _mini('Time', _time)),
          ]),
          const SizedBox(height: 6),
          _mini('Description', _desc),
        ]),
      ),
    );
  }
  Widget _mini(String l, TextEditingController c) => TextFormField(
      controller: c,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(labelText: l, isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)));
}

class _TeamMemberRow extends StatefulWidget {
  final WebTeamMember member;
  final Color primary;
  final VoidCallback onDelete, onChanged;
  const _TeamMemberRow({required this.member, required this.primary,
      required this.onDelete, required this.onChanged});
  @override State<_TeamMemberRow> createState() => _TeamMemberRowState();
}
class _TeamMemberRowState extends State<_TeamMemberRow> {
  late TextEditingController _name, _role, _bio;
  @override void initState() {
    super.initState();
    _name = TextEditingController(text: widget.member.name);
    _role = TextEditingController(text: widget.member.role);
    _bio  = TextEditingController(text: widget.member.bio);
    for (final c in [_name, _role, _bio]) c.addListener(_update);
  }
  void _update() {
    widget.member.name = _name.text;
    widget.member.role = _role.text;
    widget.member.bio  = _bio.text;
    widget.onChanged();
  }
  @override void dispose() { _name.dispose(); _role.dispose(); _bio.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Card(margin: const EdgeInsets.only(bottom: 8),
      child: Padding(padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(children: [
            Expanded(child: _mini('Name', _name)),
            IconButton(icon: const Icon(Icons.close, size: 14, color: Colors.red),
                onPressed: widget.onDelete, padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24)),
          ]),
          const SizedBox(height: 6),
          _mini('Role / Title', _role),
          const SizedBox(height: 6),
          _mini('Bio', _bio),
        ]),
      ),
    );
  }
  Widget _mini(String l, TextEditingController c) => TextFormField(
      controller: c,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(labelText: l, isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)));
}

// ── MAP PROVIDER PICKER ───────────────────────────────────────────────────────

class _MapProviderPicker extends StatefulWidget {
  final WebBlock block;
  final Color primary;
  final VoidCallback onChanged;
  const _MapProviderPicker({required this.block, required this.primary,
      required this.onChanged});
  @override State<_MapProviderPicker> createState() => _MapProviderPickerState();
}
class _MapProviderPickerState extends State<_MapProviderPicker> {
  late TextEditingController _addrCtrl;
  late TextEditingController _latCtrl;
  late TextEditingController _lngCtrl;
  @override void initState() {
    super.initState();
    _addrCtrl = TextEditingController(text: widget.block.mapAddress);
    _latCtrl  = TextEditingController(text: widget.block.mapLat.toString());
    _lngCtrl  = TextEditingController(text: widget.block.mapLng.toString());
    for (final c in [_addrCtrl, _latCtrl, _lngCtrl]) c.addListener(_update);
  }
  void _update() {
    widget.block.mapAddress = _addrCtrl.text;
    widget.block.mapLat     = double.tryParse(_latCtrl.text) ?? 0;
    widget.block.mapLng     = double.tryParse(_lngCtrl.text) ?? 0;
    widget.onChanged();
  }
  @override void dispose() { _addrCtrl.dispose(); _latCtrl.dispose(); _lngCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Provider selector
      ...MapProvider.values.map((p) {
        final selected = widget.block.mapProvider == p;
        return RadioListTile<MapProvider>(
          dense: true,
          value: p,
          groupValue: widget.block.mapProvider,
          activeColor: primary,
          title: Text(mapProviderLabels[p] ?? '',
              style: const TextStyle(fontSize: 13)),
          subtitle: p == MapProvider.openStreetMap
              ? const Text('No API key needed',
                  style: TextStyle(fontSize: 10, color: Color(0xFF2E7D32)))
              : p == MapProvider.google
                  ? const Text('Requires Google Maps API key',
                      style: TextStyle(fontSize: 10, color: textMid))
                  : const Text('Best in Safari on Apple devices',
                      style: TextStyle(fontSize: 10, color: textMid)),
          onChanged: (v) {
            widget.block.mapProvider = v!;
            widget.onChanged();
            setState(() {});
          },
        );
      }),
      const SizedBox(height: 8),
      _mini('Address / Place Name', _addrCtrl),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _mini('Latitude', _latCtrl)),
        const SizedBox(width: 8),
        Expanded(child: _mini('Longitude', _lngCtrl)),
      ]),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 13, color: Color(0xFF2E7D32)),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'For OpenStreetMap, find lat/lng at openstreetmap.org — right-click any location.',
              style: TextStyle(fontSize: 10, color: Color(0xFF2E7D32)),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _mini(String l, TextEditingController c) => TextFormField(
      controller: c,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(labelText: l, isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)));
}

// ── DIVIDER STYLE PICKER ──────────────────────────────────────────────────────

class _DividerStylePicker extends StatelessWidget {
  final WebBlock block;
  final Color primary;
  final VoidCallback onChanged;
  const _DividerStylePicker({required this.block, required this.primary,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ['line', 'cross', 'wave'].map((style) {
        final sel = block.dividerStyle == style;
        return GestureDetector(
          onTap: () { block.dividerStyle = style; onChanged(); },
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? primary : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: sel ? primary : const Color(0xFFDDE1EC)),
            ),
            child: Text(
              style == 'line' ? '—' : style == 'cross' ? '✝' : '〰',
              style: TextStyle(
                  fontSize: 16,
                  color: sel ? contrastOn(primary) : textDark),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── COLOR HEX FIELD ───────────────────────────────────────────────────────────

class _ColorHexField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  const _ColorHexField({required this.label, required this.value,
      required this.onChanged});
  @override State<_ColorHexField> createState() => _ColorHexFieldState();
}
class _ColorHexFieldState extends State<_ColorHexField> {
  late TextEditingController _ctrl;
  @override void initState() { super.initState(); _ctrl = TextEditingController(text: widget.value); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    Color? preview;
    try {
      preview = Color(int.parse('FF${_ctrl.text.replaceAll('#', '')}', radix: 16));
    } catch (_) {}
    return Row(children: [
      if (preview != null)
        Container(width: 28, height: 28,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: preview, shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade300))),
      Expanded(child: TextFormField(
        controller: _ctrl,
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        decoration: InputDecoration(labelText: widget.label, isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
        onChanged: widget.onChanged,
      )),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SITE SETTINGS SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _SiteSettingsSheet extends StatefulWidget {
  final ChurchWebsite site;
  final Color primary, secondary;
  final VoidCallback onChanged;
  const _SiteSettingsSheet({required this.site, required this.primary,
      required this.secondary, required this.onChanged});
  @override State<_SiteSettingsSheet> createState() => _SiteSettingsSheetState();
}

class _SiteSettingsSheetState extends State<_SiteSettingsSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late TextEditingController _titleCtrl, _taglineCtrl, _footerCtrl;
  late TextEditingController _fbCtrl, _igCtrl, _ytCtrl, _twCtrl;
  late TextEditingController _ghRepoCtrl, _cfProjectCtrl, _domainCtrl;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final s = widget.site.settings;
    _titleCtrl    = TextEditingController(text: s.siteTitle);
    _taglineCtrl  = TextEditingController(text: s.tagline);
    _footerCtrl   = TextEditingController(text: s.footerText);
    _fbCtrl       = TextEditingController(text: s.facebookUrl);
    _igCtrl       = TextEditingController(text: s.instagramUrl);
    _ytCtrl       = TextEditingController(text: s.youtubeUrl);
    _twCtrl       = TextEditingController(text: s.twitterUrl);
    _ghRepoCtrl   = TextEditingController(text: s.deploy.githubRepo);
    _cfProjectCtrl= TextEditingController(text: s.deploy.cloudflareProject);
    _domainCtrl   = TextEditingController(text: s.deploy.customDomain);
    for (final c in [_titleCtrl, _taglineCtrl, _footerCtrl, _fbCtrl, _igCtrl,
        _ytCtrl, _twCtrl, _ghRepoCtrl, _cfProjectCtrl, _domainCtrl]) {
      c.addListener(_sync);
    }
  }

  void _sync() {
    final s = widget.site.settings;
    s.siteTitle       = _titleCtrl.text;
    s.tagline         = _taglineCtrl.text;
    s.footerText      = _footerCtrl.text;
    s.facebookUrl     = _fbCtrl.text;
    s.instagramUrl    = _igCtrl.text;
    s.youtubeUrl      = _ytCtrl.text;
    s.twitterUrl      = _twCtrl.text;
    s.deploy.githubRepo      = _ghRepoCtrl.text;
    s.deploy.cloudflareProject = _cfProjectCtrl.text;
    s.deploy.customDomain    = _domainCtrl.text;
    widget.onChanged();
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [_titleCtrl, _taglineCtrl, _footerCtrl, _fbCtrl, _igCtrl,
        _ytCtrl, _twCtrl, _ghRepoCtrl, _cfProjectCtrl, _domainCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s       = widget.site.settings;
    final primary = widget.primary;

    return DraggableScrollableSheet(
      initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.4,
      expand: false,
      builder: (_, scroll) => Column(children: [
        Center(child: Container(
          width: 40, height: 4,
          margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2)))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('Site Settings',
              style: TextStyle(fontSize: 18,
                  fontWeight: FontWeight.bold, color: primary))),
        const SizedBox(height: 8),
        TabBar(
          controller: _tabs,
          labelColor: primary, unselectedLabelColor: textMid,
          indicatorColor: primary,
          tabs: const [
            Tab(text: 'General'), Tab(text: 'Social'), Tab(text: 'Deploy'),
          ],
        ),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            // GENERAL
            ListView(controller: scroll, padding: const EdgeInsets.all(20),
              children: [
                _f('Site Title', _titleCtrl),
                _f('Tagline', _taglineCtrl),
                _f('Footer Text', _footerCtrl),
                const SizedBox(height: 12),
                const Text('Font', style: TextStyle(fontSize: 12, color: textMid)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: s.fontFamily,
                  decoration: const InputDecoration(isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  items: ['Inter', 'Playfair Display', 'Lato', 'Merriweather',
                          'Montserrat', 'Open Sans', 'Oswald', 'Raleway']
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (v) {
                    s.fontFamily = v!;
                    widget.onChanged();
                    setState(() {});
                  },
                ),
              ],
            ),
            // SOCIAL
            ListView(controller: scroll, padding: const EdgeInsets.all(20),
              children: [
                SwitchListTile(
                  value: s.footerShowSocial,
                  activeColor: primary,
                  title: const Text('Show social links in footer',
                      style: TextStyle(fontSize: 14)),
                  onChanged: (v) {
                    s.footerShowSocial = v;
                    widget.onChanged();
                    setState(() {});
                  },
                ),
                const SizedBox(height: 12),
                _f('Facebook URL', _fbCtrl),
                _f('Instagram URL', _igCtrl),
                _f('YouTube URL', _ytCtrl),
                _f('Twitter / X URL', _twCtrl),
              ],
            ),
            // DEPLOY
            ListView(controller: scroll, padding: const EdgeInsets.all(20),
              children: [
                _DeploySection(
                  s: s, primary: primary,
                  ghRepoCtrl: _ghRepoCtrl,
                  cfProjectCtrl: _cfProjectCtrl,
                  domainCtrl: _domainCtrl,
                  onChanged: () { widget.onChanged(); setState(() {}); },
                ),
              ],
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _f(String l, TextEditingController c) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c,
      decoration: InputDecoration(labelText: l, isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
      style: const TextStyle(fontSize: 13),
    ),
  );
}

// ── DEPLOY SECTION ────────────────────────────────────────────────────────────

class _DeploySection extends StatelessWidget {
  final WebsiteSettings s;
  final Color primary;
  final TextEditingController ghRepoCtrl, cfProjectCtrl, domainCtrl;
  final VoidCallback onChanged;

  const _DeploySection({
    required this.s, required this.primary,
    required this.ghRepoCtrl, required this.cfProjectCtrl,
    required this.domainCtrl, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // ── GitHub Pages ──────────────────────────────────────────────────────
      _platformCard(
        icon: '🐙',
        title: 'GitHub Pages',
        subtitle: 'Free · Automatic via GitHub Actions',
        enabled: s.deploy.githubPagesEnabled,
        primary: primary,
        onToggle: (v) { s.deploy.githubPagesEnabled = v; onChanged(); },
        children: [
          TextFormField(
            controller: ghRepoCtrl,
            decoration: const InputDecoration(
              labelText: 'GitHub Repo',
              hintText: 'username/repo-name',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How to deploy:', style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 12)),
                SizedBox(height: 4),
                Text(
                  '1. Export site (top-right button)\n'
                  '2. Create a GitHub repo at github.com/new\n'
                  '3. Push exported files to main branch\n'
                  '4. GitHub Actions will auto-deploy to gh-pages\n'
                  '5. Enable Pages in Repo → Settings → Pages',
                  style: TextStyle(fontSize: 11, color: textMid, height: 1.7),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),

      // ── Cloudflare Pages ─────────────────────────────────────────────────
      _platformCard(
        icon: '☁️',
        title: 'Cloudflare Pages',
        subtitle: 'Free · Fast global CDN',
        enabled: s.deploy.cloudflareEnabled,
        primary: primary,
        onToggle: (v) { s.deploy.cloudflareEnabled = v; onChanged(); },
        children: [
          TextFormField(
            controller: cfProjectCtrl,
            decoration: const InputDecoration(
              labelText: 'Cloudflare Project Name',
              hintText: 'my-church-site',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How to deploy:', style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 12)),
                SizedBox(height: 4),
                Text(
                  '1. Export site (top-right button)\n'
                  '2. Sign up at pages.cloudflare.com\n'
                  '3. Create project → Upload exported folder\n'
                  '   OR: Install Wrangler CLI:\n'
                  '   npm install -g wrangler\n'
                  '   wrangler pages deploy . --project-name=YOUR-PROJECT',
                  style: TextStyle(fontSize: 11, color: textMid, height: 1.7),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),

      // ── Custom Domain ─────────────────────────────────────────────────────
      Card(child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('🌐  Custom Domain',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          const Text('Optional — add your domain to GitHub Pages or Cloudflare',
              style: TextStyle(fontSize: 12, color: textMid)),
          const SizedBox(height: 10),
          TextFormField(
            controller: domainCtrl,
            decoration: const InputDecoration(
              labelText: 'Domain',
              hintText: 'mychurch.org',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ]),
      )),
    ]);
  }

  Widget _platformCard({
    required String icon, required String title, required String subtitle,
    required bool enabled, required Color primary,
    required ValueChanged<bool> onToggle, required List<Widget> children,
  }) {
    return Card(child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
              Text(subtitle, style: const TextStyle(
                  fontSize: 11, color: textMid)),
            ],
          )),
          Switch(value: enabled, onChanged: onToggle,
              activeTrackColor: primary, activeThumbColor: Colors.white),
        ]),
        if (enabled) ...[
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          ...children,
        ],
      ]),
    ));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TEMPLATE PICKER DIALOG
// ══════════════════════════════════════════════════════════════════════════════

class _TemplatePickerDialog extends StatefulWidget {
  final Color primary;
  const _TemplatePickerDialog({required this.primary});
  @override State<_TemplatePickerDialog> createState() =>
      _TemplatePickerDialogState();
}

class _TemplatePickerDialogState extends State<_TemplatePickerDialog> {
  String? _hovered;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 560,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose a Template',
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold,
                      color: widget.primary)),
              const SizedBox(height: 4),
              const Text(
                'Start with a template — everything can be customized.',
                style: TextStyle(color: textMid, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ...siteTemplates.map((t) => _TemplateTile(
                    template: t,
                    primary:  widget.primary,
                    onSelect: () => Navigator.pop(context, t.id),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateTile extends StatefulWidget {
  final SiteTemplate template;
  final Color primary;
  final VoidCallback onSelect;
  const _TemplateTile({required this.template, required this.primary,
      required this.onSelect});
  @override State<_TemplateTile> createState() => _TemplateTileState();
}
class _TemplateTileState extends State<_TemplateTile> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit:  (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hover
                ? widget.primary.withValues(alpha: 0.06)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hover ? widget.primary : const Color(0xFFE0E0E0),
              width: _hover ? 2 : 1,
            ),
          ),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: widget.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: Text(t.previewEmoji,
                  style: const TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(t.name, style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: t.isMultiPage
                          ? const Color(0xFFE3F2FD)
                          : const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      t.isMultiPage ? 'Multi-Page' : 'Single Page',
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.bold,
                          color: t.isMultiPage
                              ? const Color(0xFF1565C0)
                              : const Color(0xFF2E7D32)),
                    ),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(t.description,
                    style: const TextStyle(fontSize: 12, color: textMid)),
              ],
            )),
            Icon(Icons.arrow_forward_ios,
                size: 14,
                color: _hover ? widget.primary : Colors.grey.shade300),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// EXPORT RESULT DIALOG
// ══════════════════════════════════════════════════════════════════════════════

class _ExportResultDialog extends StatelessWidget {
  final ExportResult result;
  final ChurchWebsite site;
  const _ExportResultDialog({required this.result, required this.site});

  @override
  Widget build(BuildContext context) {
    final d = site.settings.deploy;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 480,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('🚀', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                const Text('Site Exported!',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 8),
              const Text('Your website files are ready to deploy.',
                  style: TextStyle(color: textMid)),
              const SizedBox(height: 16),
              // Output path
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.folder_outlined, size: 16, color: textMid),
                  const SizedBox(width: 8),
                  Expanded(child: Text(result.outputDir,
                      style: const TextStyle(
                          fontSize: 11, fontFamily: 'monospace', color: textMid))),
                  GestureDetector(
                    onTap: () =>
                        Clipboard.setData(ClipboardData(text: result.outputDir)),
                    child: const Icon(Icons.copy, size: 14, color: textMid),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              // Files list
              ...result.files.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  const Icon(Icons.insert_drive_file_outlined,
                      size: 13, color: textMid),
                  const SizedBox(width: 6),
                  Text(f, style: const TextStyle(fontSize: 12, color: textMid)),
                ]),
              )),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              // Next steps
              const Text('Next Steps',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              if (d.githubPagesEnabled)
                _Step(
                  icon: '🐙',
                  text: 'Push exported folder to GitHub repo "${d.githubRepo}" — Actions will auto-deploy.',
                ),
              if (d.cloudflareEnabled)
                _Step(
                  icon: '☁️',
                  text: 'Upload folder to Cloudflare Pages project "${d.cloudflareProject}" at pages.cloudflare.com',
                ),
              if (!d.githubPagesEnabled && !d.cloudflareEnabled)
                _Step(
                  icon: '🌐',
                  text: 'Upload the exported folder to any static host: GitHub Pages, Cloudflare Pages, Netlify, or Vercel — all free.',
                ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  onPressed: () async {
                    final uri = Uri.file(result.outputDir);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  child: const Text('Open Folder'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String icon, text;
  const _Step({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(child: Text(text,
            style: const TextStyle(fontSize: 12, color: textMid, height: 1.5))),
      ]),
    );
  }
}