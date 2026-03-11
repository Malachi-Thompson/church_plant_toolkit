// lib/apps/website/website_screen.dart
// Wix/WordPress-style website builder with:
// - Left panel: pages + block library
// - Center: live HTML preview (opens in browser) / block canvas
// - Right panel: selected block property editor
// - Template picker on first launch
// - One-click deploy to GitHub Pages or Cloudflare Pages
// - Auto DNS config for Cloudflare domains; DNS copy-paste card for Namecheap

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
import 'website_deploy_service.dart';
import 'website_preview_panel.dart';

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
  bool           _loading     = true;
  bool           _previewMode = false;
  bool           _exportBusy  = false;

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
      p?.name              ?? 'My Church',
      p?.tagline           ?? 'Welcome to our community',
      p?.primaryColorHex   ?? '#1A3A5C',
      p?.secondaryColorHex ?? '#D4A843',
    );
    _update(() {
      _site       = site;
      _activePage = site.homePage;
      _selectedBlock = null;
    });
  }

  // ── PAGE MANAGEMENT ──────────────────────────────────────────────────────────

  void _addPage() {
    if (_site == null) return;
    final idx  = _site!.pages.length + 1;
    final page = WebPage(
      id: _id(), title: 'New Page $idx',
      slug: 'page-$idx', isHomePage: false,
    );
    _update(() {
      _site!.pages.add(page);
      _activePage    = page;
      _selectedBlock = null;
    });
  }

  void _deletePage(WebPage page) {
    if (_site == null || _site!.pages.length <= 1) return;
    _update(() {
      _site!.pages.remove(page);
      if (_activePage?.id == page.id) {
        _activePage    = _site!.homePage ?? _site!.pages.first;
        _selectedBlock = null;
      }
    });
  }

  // ── BLOCK MANAGEMENT ─────────────────────────────────────────────────────────

  void _addBlock(BlockType type) {
    if (_activePage == null) return;
    _update(() => _activePage!.blocks.add(_defaultBlock(type)));
  }

  WebBlock _defaultBlock(BlockType type) {
    switch (type) {
      case BlockType.hero:
        return WebBlock(id: _id(), type: type,
            heading:    'Welcome to Our Church',
            subheading: 'A community of faith, hope, and love.',
            buttonText: 'Join Us Sunday', buttonUrl: '#services');
      case BlockType.about:
        return WebBlock(id: _id(), type: type,
            heading: 'About Us',
            body:    'We are a growing church family committed to following Jesus together.');
      case BlockType.services:
        return WebBlock(id: _id(), type: type,
            heading:      'Service Times',
            serviceTimes: [ServiceTime(day: 'Sunday', time: '10:00 AM')]);
      case BlockType.events:
        return WebBlock(id: _id(), type: type,
            heading: 'Upcoming Events',
            events:  [WebEvent(title: 'Sunday Service', date: 'Sun 15', time: '10:00 AM')]);
      case BlockType.team:
        return WebBlock(id: _id(), type: type,
            heading: 'Meet Our Team',
            team:    [WebTeamMember(name: 'Pastor Name', role: 'Lead Pastor')]);
      case BlockType.sermon:
        return WebBlock(id: _id(), type: type,
            heading:    'This Week\'s Message',
            subheading: 'John 3:16',
            body:       'For God so loved the world...');
      case BlockType.contact:
        return WebBlock(id: _id(), type: type,
            heading:    'Get in Touch',
            subheading: 'We\'d love to connect with you.',
            buttonText: 'Contact Us', buttonUrl: '#contact');
      case BlockType.announcement:
        return WebBlock(id: _id(), type: type,
            heading:           '📢 Announcement',
            body:              'Add your announcement here.',
            announcementColor: '#D4A843');
      case BlockType.divider:
        return WebBlock(id: _id(), type: type, dividerStyle: 'line');
      default:
        return WebBlock(id: _id(), type: type,
            heading: blockTypeLabels[type] ?? '',
            body:    'Add your content here.');
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

  void _openPreview() {
    if (_site == null || _activePage == null) return;
    setState(() {
      _previewMode   = true;
      _selectedBlock = null; // close the property panel while previewing
    });
  }

  void _closePreview() => setState(() => _previewMode = false);

  // ── EXPORT (manual download) ─────────────────────────────────────────────────

  Future<void> _exportSite() async {
    if (_site == null) return;
    setState(() => _exportBusy = true);
    final result = await exportWebsite(_site!);
    setState(() => _exportBusy = false);
    if (!mounted) return;

    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export failed: ${result.error}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
      return;
    }

    showDialog(
      context: context,
      builder: (_) => _ExportResultDialog(result: result, site: _site!),
    );
  }

  // ── SITE SETTINGS ────────────────────────────────────────────────────────────

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

    if (_site == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.web, size: 64, color: primary.withValues(alpha: 0.3)),
              const SizedBox(height: 20),
              const Text('No website yet',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textDark)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
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
          // ── LEFT PANEL ──────────────────────────────────────────────────
          SizedBox(
            width: 220,
            child: _LeftPanel(
              site:         _site!,
              activePage:   _activePage,
              primary:      primary,
              secondary:    secondary,
              onSelectPage: (p) => _update(() {
                _activePage    = p;
                _selectedBlock = null;
              }),
              onAddPage:    _addPage,
              onDeletePage: _deletePage,
              onAddBlock:   _addBlock,
              onReset:      _showTemplatePicker,
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),

          // ── CENTER: block canvas OR in-app preview ──────────────────────
          Expanded(
            child: _previewMode && _activePage != null
                ? WebsitePreviewPanel(
                    site:        _site!,
                    initialPage: _activePage!,
                    primary:     primary,
                  )
                : _activePage != null
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
                    : Center(child: Text('Select or create a page',
                        style: TextStyle(color: primary.withValues(alpha: 0.4)))),
          ),

          // ── RIGHT PANEL: property editor ────────────────────────────────
          if (!_previewMode && _selectedBlock != null) ...[
            const VerticalDivider(width: 1, thickness: 1),
            SizedBox(
              width: 320,
              child: _BlockPropertyPanel(
                block:        _selectedBlock!,
                site:         _site!,
                primary:      primary,
                secondary:    secondary,
                bibleService: state.bibleService,
                onChanged:    () => _update(() {}),
              ),
            ),
          ],
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(Color primary, Color secondary, profile) {
    return AppBar(
      backgroundColor: primary,
      foregroundColor: contrastOn(primary),
      title: Row(children: [
        if (profile != null)
          ChurchLogo(logoPath: profile.logoPath,
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
              _site!.pages.length == 1
                  ? 'Single Page' : '${_site!.pages.length} Pages',
              style: TextStyle(fontSize: 11,
                  color: contrastOn(primary).withValues(alpha: 0.8)),
            ),
          ),
        ],
      ]),
      actions: [
        if (_previewMode)
          TextButton.icon(
            onPressed: _closePreview,
            icon: Icon(Icons.edit_outlined, color: contrastOn(primary), size: 18),
            label: Text('Edit', style: TextStyle(color: contrastOn(primary))),
          )
        else
          TextButton.icon(
            onPressed: _openPreview,
            icon: Icon(Icons.preview_outlined, color: contrastOn(primary), size: 18),
            label: Text('Preview', style: TextStyle(color: contrastOn(primary))),
          ),
        _exportBusy
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: contrastOn(primary))))
            : TextButton.icon(
                onPressed: _exportSite,
                icon: Icon(Icons.download, color: secondary, size: 18),
                label: Text('Export',
                    style: TextStyle(color: secondary, fontWeight: FontWeight.bold)),
              ),
        IconButton(
          onPressed: _showSiteSettings,
          icon: Icon(Icons.settings_outlined, color: contrastOn(primary)),
          tooltip: 'Site Settings & Deploy',
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// LEFT PANEL
// ══════════════════════════════════════════════════════════════════════════════

class _LeftPanel extends StatefulWidget {
  final ChurchWebsite   site;
  final WebPage?        activePage;
  final Color           primary;
  final Color           secondary;
  final ValueChanged<WebPage>   onSelectPage;
  final VoidCallback            onAddPage;
  final ValueChanged<WebPage>   onDeletePage;
  final ValueChanged<BlockType> onAddBlock;
  final VoidCallback            onReset;

  const _LeftPanel({
    required this.site,       required this.activePage,
    required this.primary,    required this.secondary,
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
    return Column(children: [
      TabBar(
        controller: _tabs,
        labelColor:           widget.primary,
        unselectedLabelColor: textMid,
        indicatorColor:       widget.primary,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        tabs: const [Tab(text: 'Pages'), Tab(text: 'Blocks')],
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [
            _PagesPanel(
              site:       widget.site,
              activePage: widget.activePage,
              primary:    widget.primary,
              onSelect:   widget.onSelectPage,
              onAdd:      widget.onAddPage,
              onDelete:   widget.onDeletePage,
              onReset:    widget.onReset,
            ),
            _BlockLibraryPanel(
              primary:    widget.primary,
              onAddBlock: widget.onAddBlock,
            ),
          ],
        ),
      ),
    ]);
  }
}

// ── PAGES PANEL ───────────────────────────────────────────────────────────────

class _PagesPanel extends StatelessWidget {
  final ChurchWebsite       site;
  final WebPage?            activePage;
  final Color               primary;
  final ValueChanged<WebPage> onSelect;
  final VoidCallback          onAdd;
  final ValueChanged<WebPage> onDelete;
  final VoidCallback          onReset;

  const _PagesPanel({
    required this.site, required this.activePage, required this.primary,
    required this.onSelect, required this.onAdd,
    required this.onDelete, required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          Expanded(child: ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Page', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: contrastOn(primary),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          )),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: site.pages.length,
          itemBuilder: (ctx, i) {
            final page   = site.pages[i];
            final active = activePage?.id == page.id;
            return ListTile(
              dense: true,
              selected:          active,
              selectedTileColor: primary.withValues(alpha: 0.08),
              leading: Icon(
                page.isHomePage
                    ? Icons.home_outlined : Icons.article_outlined,
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
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
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
        leading: const Icon(Icons.refresh, size: 16, color: textMid),
        title: const Text('Change Template',
            style: TextStyle(fontSize: 12, color: textMid)),
        onTap: onReset,
      ),
    ]);
  }
}

// ── BLOCK LIBRARY PANEL ───────────────────────────────────────────────────────

class _BlockLibraryPanel extends StatelessWidget {
  final Color               primary;
  final ValueChanged<BlockType> onAddBlock;
  const _BlockLibraryPanel({required this.primary, required this.onAddBlock});

  static const _groups = [
    ('Layout',  [BlockType.hero, BlockType.cta, BlockType.divider]),
    ('Content', [BlockType.about, BlockType.richText, BlockType.announcement]),
    ('Church',  [BlockType.services, BlockType.events, BlockType.sermon,
                 BlockType.team, BlockType.contact, BlockType.map, BlockType.gallery]),
  ];

  static const _icons = <BlockType, IconData>{
    BlockType.hero:         Icons.view_agenda_outlined,
    BlockType.about:        Icons.info_outline,
    BlockType.services:     Icons.access_time,
    BlockType.events:       Icons.event_outlined,
    BlockType.team:         Icons.people_outline,
    BlockType.sermon:       Icons.menu_book_outlined,
    BlockType.contact:      Icons.mail_outline,
    BlockType.map:          Icons.map_outlined,
    BlockType.gallery:      Icons.photo_library_outlined,
    BlockType.announcement: Icons.campaign_outlined,
    BlockType.divider:      Icons.horizontal_rule,
    BlockType.richText:     Icons.article_outlined,
    BlockType.cta:          Icons.ads_click,
  };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: _groups.map((group) {
        final (label, types) = group;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: textMid, letterSpacing: 0.8)),
            ),
            ...types.map((type) => _BlockLibraryTile(
              type:    type,
              icon:    _icons[type] ?? Icons.widgets,
              label:   blockTypeLabels[type] ?? '',
              primary: primary,
              onAdd:   () => onAddBlock(type),
            )),
            const SizedBox(height: 4),
          ],
        );
      }).toList(),
    );
  }
}

class _BlockLibraryTile extends StatelessWidget {
  final BlockType   type;
  final IconData    icon;
  final String      label;
  final Color       primary;
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
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
  final Function(int, int)      onReorder;
  final ValueChanged<WebBlock>  onToggleVisibility;

  const _BlockCanvas({
    required this.page,           required this.site,
    required this.selectedBlock,  required this.primary,
    required this.secondary,      required this.onSelect,
    required this.onDelete,       required this.onReorder,
    required this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    if (page.blocks.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_box_outlined, size: 48,
              color: primary.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text('No blocks yet',
              style: TextStyle(
                  fontSize: 16, color: primary.withValues(alpha: 0.5))),
          const SizedBox(height: 6),
          const Text('Add blocks from the panel on the left',
              style: TextStyle(fontSize: 12, color: textMid)),
        ]),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: page.blocks.length,
      onReorder: onReorder,
      itemBuilder: (ctx, i) {
        final block  = page.blocks[i];
        final active = selectedBlock?.id == block.id;
        return _BlockCard(
          key:        ValueKey(block.id),
          block:      block,
          isSelected: active,
          primary:    primary,
          secondary:  secondary,
          onTap:      () => onSelect(block),
          onDelete:   () => onDelete(block),
          onToggle:   () => onToggleVisibility(block),
        );
      },
    );
  }
}

class _BlockCard extends StatelessWidget {
  final WebBlock     block;
  final bool         isSelected;
  final Color        primary;
  final Color        secondary;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _BlockCard({
    super.key,
    required this.block,    required this.isSelected,
    required this.primary,  required this.secondary,
    required this.onTap,    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? primary.withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? primary : const Color(0xFFEAEDF3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(Icons.drag_handle, size: 16, color: Colors.grey.shade400),
              const SizedBox(width: 8),
              Text(blockTypeLabels[block.type] ?? '',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: isSelected ? primary : textDark)),
              if (!block.isVisible) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4)),
                  child: const Text('Hidden',
                      style: TextStyle(fontSize: 9, color: Colors.grey)),
                ),
              ],
              const Spacer(),
              IconButton(
                icon: Icon(
                  block.isVisible
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 16, color: textMid),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onToggle,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 16, color: Colors.red),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onDelete,
              ),
            ]),
          ),
          if (block.heading.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 10),
              child: Text(block.heading,
                  style: const TextStyle(fontSize: 13, color: textMid),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ]),
      ),
    );
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
    required this.block,       required this.site,
    required this.primary,     required this.secondary,
    required this.bibleService,required this.onChanged,
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

    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.06),
          border: const Border(bottom: BorderSide(color: Color(0xFFEAEDF3))),
        ),
        child: Row(children: [
          Icon(Icons.tune, size: 16, color: primary),
          const SizedBox(width: 8),
          Text(blockTypeLabels[block.type] ?? 'Block',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                  color: primary)),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (block.type != BlockType.divider) ...[
              _field('Heading',    _headingCtrl),
              _field('Subheading', _subCtrl),
            ],
            if (block.type == BlockType.richText ||
                block.type == BlockType.about    ||
                block.type == BlockType.sermon   ||
                block.type == BlockType.contact  ||
                block.type == BlockType.announcement)
              _field('Body Text', _bodyCtrl, maxLines: 4),
            if (block.type == BlockType.hero  ||
                block.type == BlockType.about ||
                block.type == BlockType.cta   ||
                block.type == BlockType.announcement ||
                block.type == BlockType.contact) ...[
              _field('Button Text', _btnTextCtrl),
              _field('Button URL',  _btnUrlCtrl),
            ],
            if (block.type == BlockType.services)
              _ServiceTimesEditor(block: block, primary: primary,
                  onChanged: widget.onChanged),
            if (block.type == BlockType.events)
              _EventsEditor(block: block, primary: primary,
                  onChanged: widget.onChanged),
            if (block.type == BlockType.team)
              _TeamEditor(block: block, primary: primary,
                  onChanged: widget.onChanged),
            if (block.type == BlockType.map)
              _MapProviderPicker(block: block, primary: primary,
                  onChanged: widget.onChanged),
            if (block.type == BlockType.gallery)
              _GalleryEditor(block: block, primary: primary,
                  onChanged: widget.onChanged),
            if (block.type == BlockType.divider)
              _DividerStylePicker(block: block, primary: primary,
                  onChanged: widget.onChanged),
            if (block.type == BlockType.announcement) ...[
              const SizedBox(height: 8),
              _ColorHexField(
                label: 'Accent Color',
                value: block.announcementColor,
                onChanged: (v) { block.announcementColor = v; widget.onChanged(); },
              ),
            ],
            if (block.type == BlockType.sermon)
              Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ScriptureField(
                controller:   _bodyCtrl,
                bibleService: widget.bibleService,
                primary:      widget.primary,
                label:        'Body / Scripture',
                maxLines:     4,
                onChanged:    (_) => widget.onChanged(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl, {int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: ctrl,
          maxLines:   maxLines,
          decoration: InputDecoration(
            labelText: label, isDense: true,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
          ),
          style: const TextStyle(fontSize: 13),
        ),
      );
}

// ── Service Times Editor ──────────────────────────────────────────────────────

class _ServiceTimesEditor extends StatefulWidget {
  final WebBlock block; final Color primary; final VoidCallback onChanged;
  const _ServiceTimesEditor({required this.block, required this.primary,
      required this.onChanged});
  @override State<_ServiceTimesEditor> createState() => _ServiceTimesEditorState();
}
class _ServiceTimesEditorState extends State<_ServiceTimesEditor> {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Service Times',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: textMid)),
      const SizedBox(height: 8),
      ...widget.block.serviceTimes.map((st) => _ServiceTimeRow(
        st: st, primary: widget.primary,
        onDelete: () { widget.block.serviceTimes.remove(st); widget.onChanged(); setState(() {}); },
        onChanged: widget.onChanged,
      )),
      TextButton.icon(
        onPressed: () {
          widget.block.serviceTimes.add(ServiceTime(day: 'Sunday', time: '10:00 AM'));
          widget.onChanged(); setState(() {});
        },
        icon: const Icon(Icons.add, size: 14),
        label: const Text('Add Time', style: TextStyle(fontSize: 12)),
      ),
    ]);
  }
}

class _ServiceTimeRow extends StatefulWidget {
  final ServiceTime st; final Color primary;
  final VoidCallback onDelete, onChanged;
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
      controller: c, style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(labelText: l, isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)));
}

// ── Events Editor ─────────────────────────────────────────────────────────────

class _EventsEditor extends StatefulWidget {
  final WebBlock block; final Color primary; final VoidCallback onChanged;
  const _EventsEditor({required this.block, required this.primary, required this.onChanged});
  @override State<_EventsEditor> createState() => _EventsEditorState();
}
class _EventsEditorState extends State<_EventsEditor> {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Events', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textMid)),
      const SizedBox(height: 8),
      ...widget.block.events.map((e) => _EventRow(
        event: e, primary: widget.primary,
        onDelete: () { widget.block.events.remove(e); widget.onChanged(); setState(() {}); },
        onChanged: widget.onChanged,
      )),
      TextButton.icon(
        onPressed: () {
          widget.block.events.add(WebEvent(title: 'New Event'));
          widget.onChanged(); setState(() {});
        },
        icon: const Icon(Icons.add, size: 14),
        label: const Text('Add Event', style: TextStyle(fontSize: 12)),
      ),
    ]);
  }
}

class _EventRow extends StatefulWidget {
  final WebEvent event; final Color primary;
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
      controller: c, style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(labelText: l, isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)));
}

// ── Team Editor ───────────────────────────────────────────────────────────────

class _TeamEditor extends StatefulWidget {
  final WebBlock block; final Color primary; final VoidCallback onChanged;
  const _TeamEditor({required this.block, required this.primary, required this.onChanged});
  @override State<_TeamEditor> createState() => _TeamEditorState();
}
class _TeamEditorState extends State<_TeamEditor> {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Team Members', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textMid)),
      const SizedBox(height: 8),
      ...widget.block.team.map((m) => _TeamMemberRow(
        member: m, primary: widget.primary,
        onDelete: () { widget.block.team.remove(m); widget.onChanged(); setState(() {}); },
        onChanged: widget.onChanged,
      )),
      TextButton.icon(
        onPressed: () {
          widget.block.team.add(WebTeamMember(name: 'New Member'));
          widget.onChanged(); setState(() {});
        },
        icon: const Icon(Icons.add, size: 14),
        label: const Text('Add Member', style: TextStyle(fontSize: 12)),
      ),
    ]);
  }
}

class _TeamMemberRow extends StatefulWidget {
  final WebTeamMember member; final Color primary;
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
      controller: c, style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(labelText: l, isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)));
}

// ── Map Provider Picker ───────────────────────────────────────────────────────

class _MapProviderPicker extends StatefulWidget {
  final WebBlock block; final Color primary; final VoidCallback onChanged;
  const _MapProviderPicker({required this.block, required this.primary, required this.onChanged});
  @override State<_MapProviderPicker> createState() => _MapProviderPickerState();
}
class _MapProviderPickerState extends State<_MapProviderPicker> {
  late TextEditingController _addrCtrl, _latCtrl, _lngCtrl;
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Map Provider', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textMid)),
      const SizedBox(height: 8),
      ...MapProvider.values.map((p) => RadioListTile<MapProvider>(
        dense: true, contentPadding: EdgeInsets.zero,
        value: p, groupValue: widget.block.mapProvider,
        activeColor: widget.primary,
        title: Text(mapProviderLabels[p] ?? p.name,
            style: const TextStyle(fontSize: 12)),
        onChanged: (v) { if (v != null) { widget.block.mapProvider = v; widget.onChanged(); setState(() {}); } },
      )),
      const SizedBox(height: 8),
      TextFormField(controller: _addrCtrl,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(labelText: 'Address', isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8))),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextFormField(controller: _latCtrl,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(labelText: 'Lat', isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)))),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(controller: _lngCtrl,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(labelText: 'Lng', isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)))),
      ]),
    ]);
  }
}

// ── Gallery Editor ────────────────────────────────────────────────────────────

class _GalleryEditor extends StatefulWidget {
  final WebBlock block; final Color primary; final VoidCallback onChanged;
  const _GalleryEditor({required this.block, required this.primary, required this.onChanged});
  @override State<_GalleryEditor> createState() => _GalleryEditorState();
}
class _GalleryEditorState extends State<_GalleryEditor> {
  late TextEditingController _urlCtrl;
  @override void initState() { super.initState(); _urlCtrl = TextEditingController(); }
  @override void dispose() { _urlCtrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Gallery Images', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textMid)),
      const SizedBox(height: 8),
      ...widget.block.galleryImages.asMap().entries.map((e) => ListTile(
        dense: true,
        leading: const Icon(Icons.image_outlined, size: 16, color: textMid),
        title: Text(e.value, style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          icon: const Icon(Icons.close, size: 14, color: Colors.red),
          padding: EdgeInsets.zero, constraints: const BoxConstraints(),
          onPressed: () {
            widget.block.galleryImages.removeAt(e.key);
            widget.onChanged(); setState(() {});
          },
        ),
      )),
      Row(children: [
        Expanded(child: TextFormField(
          controller: _urlCtrl,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'Image URL or path',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
        )),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () {
            if (_urlCtrl.text.isNotEmpty) {
              widget.block.galleryImages.add(_urlCtrl.text.trim());
              _urlCtrl.clear();
              widget.onChanged(); setState(() {});
            }
          },
          child: const Text('Add'),
        ),
      ]),
    ]);
  }
}

// ── Divider Style Picker ──────────────────────────────────────────────────────

class _DividerStylePicker extends StatelessWidget {
  final WebBlock block; final Color primary; final VoidCallback onChanged;
  const _DividerStylePicker({required this.block, required this.primary, required this.onChanged});
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
              style: TextStyle(fontSize: 16,
                  color: sel ? contrastOn(primary) : textDark),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Color Hex Field ───────────────────────────────────────────────────────────

class _ColorHexField extends StatefulWidget {
  final String label; final String value; final ValueChanged<String> onChanged;
  const _ColorHexField({required this.label, required this.value, required this.onChanged});
  @override State<_ColorHexField> createState() => _ColorHexFieldState();
}
class _ColorHexFieldState extends State<_ColorHexField> {
  late TextEditingController _ctrl;
  @override void initState() { super.initState(); _ctrl = TextEditingController(text: widget.value); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    Color? preview;
    try { preview = Color(int.parse('FF${_ctrl.text.replaceAll('#', '')}', radix: 16)); } catch (_) {}
    return Row(children: [
      if (preview != null)
        Container(width: 28, height: 28, margin: const EdgeInsets.only(right: 8),
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
// SITE SETTINGS SHEET  (tabs: Design | Social | Deploy)
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

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final s = widget.site.settings;
    _titleCtrl   = TextEditingController(text: s.siteTitle);
    _taglineCtrl = TextEditingController(text: s.tagline);
    _footerCtrl  = TextEditingController(text: s.footerText);
    _fbCtrl      = TextEditingController(text: s.facebookUrl);
    _igCtrl      = TextEditingController(text: s.instagramUrl);
    _ytCtrl      = TextEditingController(text: s.youtubeUrl);
    _twCtrl      = TextEditingController(text: s.twitterUrl);
    for (final c in [_titleCtrl, _taglineCtrl, _footerCtrl,
        _fbCtrl, _igCtrl, _ytCtrl, _twCtrl]) {
      c.addListener(_sync);
    }
  }

  void _sync() {
    final s = widget.site.settings;
    s.siteTitle    = _titleCtrl.text;
    s.tagline      = _taglineCtrl.text;
    s.footerText   = _footerCtrl.text;
    s.facebookUrl  = _fbCtrl.text;
    s.instagramUrl = _igCtrl.text;
    s.youtubeUrl   = _ytCtrl.text;
    s.twitterUrl   = _twCtrl.text;
    widget.onChanged();
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [_titleCtrl, _taglineCtrl, _footerCtrl,
        _fbCtrl, _igCtrl, _ytCtrl, _twCtrl]) {
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
        // Handle
        Center(child: Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2)),
        )),
        // Title
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Text('Site Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                    color: primary)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ),
        // Tabs
        TabBar(
          controller: _tabs,
          labelColor:           primary,
          unselectedLabelColor: textMid,
          indicatorColor:       primary,
          tabs: const [
            Tab(text: 'Design'),
            Tab(text: 'Social'),
            Tab(text: 'Publish'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              // ── DESIGN TAB ───────────────────────────────────────────────
              ListView(controller: scroll, padding: const EdgeInsets.all(20),
                children: [
                  _f('Site Name',    _titleCtrl),
                  _f('Tagline',      _taglineCtrl),
                  _f('Footer Text',  _footerCtrl),
                  const SizedBox(height: 12),
                  const Text('Colors', style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13, color: textMid)),
                  const SizedBox(height: 8),
                  _ColorHexField(
                    label: 'Primary Color',
                    value: s.primaryHex,
                    onChanged: (v) { s.primaryHex = v; widget.onChanged(); setState(() {}); },
                  ),
                  const SizedBox(height: 8),
                  _ColorHexField(
                    label: 'Secondary Color',
                    value: s.secondaryHex,
                    onChanged: (v) { s.secondaryHex = v; widget.onChanged(); setState(() {}); },
                  ),
                ],
              ),
              // ── SOCIAL TAB ───────────────────────────────────────────────
              ListView(controller: scroll, padding: const EdgeInsets.all(20),
                children: [
                  SwitchListTile(
                    value: s.footerShowSocial,
                    activeColor: primary,
                    title: const Text('Show social links in footer',
                        style: TextStyle(fontSize: 14)),
                    onChanged: (v) {
                      s.footerShowSocial = v;
                      widget.onChanged(); setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  _f('Facebook URL',   _fbCtrl),
                  _f('Instagram URL',  _igCtrl),
                  _f('YouTube URL',    _ytCtrl),
                  _f('Twitter / X URL',_twCtrl),
                ],
              ),
              // ── PUBLISH TAB ──────────────────────────────────────────────
              _DeployPanel(
                site:      widget.site,
                primary:   primary,
                onChanged: () { widget.onChanged(); setState(() {}); },
              ),
            ],
          ),
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

// ══════════════════════════════════════════════════════════════════════════════
// DEPLOY PANEL  —  one-click publish to GitHub Pages or Cloudflare Pages
// ══════════════════════════════════════════════════════════════════════════════

class _DeployPanel extends StatefulWidget {
  final ChurchWebsite site;
  final Color primary;
  final VoidCallback onChanged;

  const _DeployPanel({
    required this.site,
    required this.primary,
    required this.onChanged,
  });

  @override
  State<_DeployPanel> createState() => _DeployPanelState();
}

class _DeployPanelState extends State<_DeployPanel> {
  late final TextEditingController _ghTokenCtrl;
  late final TextEditingController _ghRepoCtrl;
  late final TextEditingController _cfTokenCtrl;
  late final TextEditingController _cfAccountCtrl;
  late final TextEditingController _cfProjectCtrl;
  late final TextEditingController _domainCtrl;

  bool   _deploying   = false;
  String _deployStep  = '';
  String _deployError = '';

  DeploySettings get _d => widget.site.settings.deploy;

  @override
  void initState() {
    super.initState();
    _ghTokenCtrl   = TextEditingController(text: _d.githubToken);
    _ghRepoCtrl    = TextEditingController(text: _d.githubRepo);
    _cfTokenCtrl   = TextEditingController(text: _d.cloudflareApiToken);
    _cfAccountCtrl = TextEditingController(text: _d.cloudflareAccountId);
    _cfProjectCtrl = TextEditingController(text: _d.cloudflareProject);
    _domainCtrl    = TextEditingController(text: _d.customDomain);
  }

  @override
  void dispose() {
    _ghTokenCtrl.dispose();  _ghRepoCtrl.dispose();
    _cfTokenCtrl.dispose();  _cfAccountCtrl.dispose();
    _cfProjectCtrl.dispose();_domainCtrl.dispose();
    super.dispose();
  }

  void _saveFields() {
    _d.githubToken         = _ghTokenCtrl.text.trim();
    _d.githubRepo          = _ghRepoCtrl.text.trim();
    _d.cloudflareApiToken  = _cfTokenCtrl.text.trim();
    _d.cloudflareAccountId = _cfAccountCtrl.text.trim();
    _d.cloudflareProject   = _cfProjectCtrl.text.trim();
    _d.customDomain        = _domainCtrl.text.trim().toLowerCase();
    widget.onChanged();
  }

  Future<void> _deploy() async {
    _saveFields();
    setState(() {
      _deploying   = true;
      _deployError = '';
      _deployStep  = 'Starting…';
    });

    try {
      DeployResult result;

      if (_d.hostingPlatform == HostingPlatform.githubPages) {
        final svc = GitHubDeployService(_d.githubToken);
        result = await svc.fullDeploy(widget.site,
            (s) { if (mounted) setState(() => _deployStep = s); });
      } else {
        final svc = CloudflareDeployService(
            _d.cloudflareApiToken, _d.cloudflareAccountId);
        result = await svc.fullDeploy(widget.site,
            (s) { if (mounted) setState(() => _deployStep = s); });
      }

      if (!mounted) return;

      if (result.success) {
        // Persist live URL back into settings
        if (_d.hostingPlatform == HostingPlatform.githubPages) {
          _d.githubPagesUrl = result.liveUrl;
          if (result.cnameTarget.isNotEmpty) {
            _d.githubUsername =
                result.cnameTarget.replaceAll('.github.io', '');
          }
        } else {
          _d.cloudflarePagesUrl = result.liveUrl;
        }
        widget.onChanged();

        setState(() {
          _deploying  = false;
          _deployStep = result.message;
        });

        // Show DNS dialog if custom domain and non-Cloudflare registrar
        if (_d.customDomain.isNotEmpty &&
            _d.domainRegistrar != DomainRegistrar.cloudflare &&
            result.cnameTarget.isNotEmpty) {
          _showDnsDialog(result.cnameTarget);
        }
      } else {
        setState(() {
          _deploying   = false;
          _deployError = result.message;
        });
      }
    } catch (e) {
      setState(() {
        _deploying   = false;
        _deployError = e.toString();
      });
    }
  }

  void _showDnsDialog(String cnameTarget) {
    final records = buildDnsRecords(cnameTarget);
    showDialog(
      context: context,
      builder: (_) => _DnsDialog(
        domain:     _d.customDomain,
        registrar:  _d.domainRegistrar,
        records:    records,
        primary:    widget.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Header ────────────────────────────────────────────────────────
        const Text('Publish Your Site',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Enter your credentials once, then hit Deploy. '
          'The app handles everything automatically.',
          style: TextStyle(fontSize: 12, color: textMid),
        ),
        const SizedBox(height: 20),

        // ── Live URL badge ────────────────────────────────────────────────
        if (_d.liveUrl.isNotEmpty) ...[
          _LiveUrlBadge(url: _d.liveUrl, primary: widget.primary),
          const SizedBox(height: 16),
        ],

        // ── Platform selector ─────────────────────────────────────────────
        _SectionLabel('Hosting Platform'),
        const SizedBox(height: 8),
        _PlatformToggle(
          selected:  _d.hostingPlatform,
          primary:   widget.primary,
          onChanged: (p) {
            setState(() => _d.hostingPlatform = p);
            widget.onChanged();
          },
        ),
        const SizedBox(height: 20),

        // ── Platform credentials ──────────────────────────────────────────
        if (_d.hostingPlatform == HostingPlatform.githubPages) ...[
          _SectionLabel('GitHub Credentials'),
          const SizedBox(height: 8),
          _CredentialField(
            controller: _ghTokenCtrl,
            label:    'Personal Access Token',
            hint:     'ghp_xxxxxxxxxxxxxxxxxxxx',
            obscure:  true,
            helpText: 'Create at github.com/settings/tokens',
            helpUrl:  'https://github.com/settings/tokens/new'
                      '?scopes=repo,pages&description=Church+Plant+Toolkit',
            onChanged: (_) => _saveFields(),
          ),
          const SizedBox(height: 10),
          _CredentialField(
            controller: _ghRepoCtrl,
            label:    'Repository Name',
            hint:     'my-church-site',
            helpText: 'Created automatically if it doesn\'t exist',
            onChanged: (_) => _saveFields(),
          ),
          const SizedBox(height: 8),
          _InfoBox(
            color: const Color(0xFFF0F4FF),
            iconColor: const Color(0xFF6366F1),
            text: 'The app creates the repo, uploads all files, '
                  'and enables GitHub Pages — no browser required.',
          ),
        ] else ...[
          _SectionLabel('Cloudflare Credentials'),
          const SizedBox(height: 8),
          _CredentialField(
            controller: _cfTokenCtrl,
            label:    'API Token',
            hint:     'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
            obscure:  true,
            helpText: 'Create at dash.cloudflare.com/profile/api-tokens',
            helpUrl:  'https://dash.cloudflare.com/profile/api-tokens',
            onChanged: (_) => _saveFields(),
          ),
          const SizedBox(height: 10),
          _CredentialField(
            controller: _cfAccountCtrl,
            label:    'Account ID',
            hint:     '32-character hex ID',
            helpText: 'Found in the right sidebar at dash.cloudflare.com',
            onChanged: (_) => _saveFields(),
          ),
          const SizedBox(height: 10),
          _CredentialField(
            controller: _cfProjectCtrl,
            label:    'Project Name',
            hint:     'my-church-site',
            helpText: 'Created automatically if it doesn\'t exist',
            onChanged: (_) => _saveFields(),
          ),
          const SizedBox(height: 8),
          _InfoBox(
            color: const Color(0xFFFFF7ED),
            iconColor: const Color(0xFFF97316),
            text: 'Token needs: Cloudflare Pages → Edit'
                  '  (+ Zone → DNS:Edit if you have a Cloudflare domain)',
          ),
        ],

        const SizedBox(height: 20),

        // ── Custom Domain ─────────────────────────────────────────────────
        _SectionLabel('Custom Domain (optional)'),
        const SizedBox(height: 8),
        _CredentialField(
          controller: _domainCtrl,
          label:    'Your Domain',
          hint:     'mychurch.org',
          onChanged: (_) { _saveFields(); setState(() {}); },
        ),

        if (_domainCtrl.text.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionLabel('Where did you buy this domain?'),
          const SizedBox(height: 8),
          _RegistrarSelector(
            selected:  _d.domainRegistrar,
            primary:   widget.primary,
            onChanged: (r) {
              setState(() => _d.domainRegistrar = r);
              widget.onChanged();
            },
          ),
          const SizedBox(height: 8),
          if (_d.domainRegistrar == DomainRegistrar.cloudflare)
            _InfoBox(
              color:     Colors.green.shade50,
              iconColor: Colors.green,
              icon:      Icons.auto_awesome,
              text:      'DNS will be configured automatically during deployment!',
            ),
          if (_d.domainRegistrar == DomainRegistrar.namecheap)
            _InfoBox(
              color:     const Color(0xFFF0F4FF),
              iconColor: const Color(0xFF6366F1),
              text:      'After deploying we\'ll show you the exact DNS records '
                         'to paste into Namecheap — takes about 2 minutes.',
            ),
          if (_d.domainRegistrar == DomainRegistrar.other)
            _InfoBox(
              color:     const Color(0xFFF9FAFB),
              iconColor: textMid,
              text:      'After deploying we\'ll show you the CNAME record '
                         'to add with your registrar.',
            ),
        ],

        const SizedBox(height: 24),

        // ── Deploy button ─────────────────────────────────────────────────
        SizedBox(
          width: double.infinity, height: 48,
          child: ElevatedButton.icon(
            onPressed: _deploying ? null : _deploy,
            icon: _deploying
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.rocket_launch_rounded),
            label: Text(_deploying ? _deployStep : 'Deploy Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),

        // ── Success ───────────────────────────────────────────────────────
        if (!_deploying && _deployStep.isNotEmpty && _deployError.isEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_deployStep,
                  style: const TextStyle(color: Colors.green))),
            ]),
          ),
        ],

        // ── Error ─────────────────────────────────────────────────────────
        if (_deployError.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_deployError,
                  style: const TextStyle(color: Colors.red, fontSize: 12))),
            ]),
          ),
        ],
      ],
    );
  }
}

// ── Deploy sub-widgets ────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: Color(0xFF374151)));
}

class _LiveUrlBadge extends StatelessWidget {
  final String url; final Color primary;
  const _LiveUrlBadge({required this.url, required this.primary});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: primary.withOpacity(0.06),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: primary.withOpacity(0.3)),
    ),
    child: Row(children: [
      Icon(Icons.public, size: 16, color: primary),
      const SizedBox(width: 8),
      Expanded(child: Text(url,
          style: TextStyle(fontSize: 12, color: primary,
              fontWeight: FontWeight.w600))),
      GestureDetector(
        onTap: () => launchUrl(Uri.parse(url)),
        child: Icon(Icons.open_in_new, size: 15, color: primary),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () => Clipboard.setData(ClipboardData(text: url)),
        child: const Icon(Icons.copy, size: 15, color: Colors.grey),
      ),
    ]),
  );
}

class _PlatformToggle extends StatelessWidget {
  final HostingPlatform selected;
  final Color primary;
  final ValueChanged<HostingPlatform> onChanged;
  const _PlatformToggle({
    required this.selected, required this.primary, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: _PlatformChip(
      icon: '🐙', label: 'GitHub Pages', sublabel: 'Free · Easy',
      selected: selected == HostingPlatform.githubPages, primary: primary,
      onTap: () => onChanged(HostingPlatform.githubPages),
    )),
    const SizedBox(width: 8),
    Expanded(child: _PlatformChip(
      icon: '☁️', label: 'Cloudflare Pages', sublabel: 'Free · Fast CDN',
      selected: selected == HostingPlatform.cloudflarePages, primary: primary,
      onTap: () => onChanged(HostingPlatform.cloudflarePages),
    )),
  ]);
}

class _PlatformChip extends StatelessWidget {
  final String icon, label, sublabel;
  final bool selected; final Color primary; final VoidCallback onTap;
  const _PlatformChip({required this.icon, required this.label,
      required this.sublabel, required this.selected,
      required this.primary, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? primary.withOpacity(0.08) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? primary : const Color(0xFFE5E7EB),
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$icon  $label', style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? primary : const Color(0xFF374151))),
        Text(sublabel, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
    ),
  );
}

class _RegistrarSelector extends StatelessWidget {
  final DomainRegistrar selected;
  final Color primary;
  final ValueChanged<DomainRegistrar> onChanged;
  const _RegistrarSelector({
    required this.selected, required this.primary, required this.onChanged});

  static const _opts = [
    (DomainRegistrar.namecheap, '🏷️', 'Namecheap'),
    (DomainRegistrar.cloudflare,'☁️', 'Cloudflare'),
    (DomainRegistrar.other,     '🌐', 'Other'),
  ];

  @override
  Widget build(BuildContext context) => Row(
    children: _opts.map((opt) {
      final (r, icon, label) = opt;
      final sel = selected == r;
      return Expanded(child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: () => onChanged(r),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: sel ? primary.withOpacity(0.1) : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: sel ? primary : const Color(0xFFE5E7EB),
                width: sel ? 2 : 1,
              ),
            ),
            child: Column(children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: sel ? primary : const Color(0xFF6B7280))),
            ]),
          ),
        ),
      ));
    }).toList(),
  );
}

class _InfoBox extends StatelessWidget {
  final Color color, iconColor;
  final IconData icon;
  final String text;
  const _InfoBox({
    required this.color, required this.iconColor,
    this.icon = Icons.info_outline, required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color, borderRadius: BorderRadius.circular(8)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: iconColor),
      const SizedBox(width: 8),
      Expanded(child: Text(text,
          style: const TextStyle(fontSize: 11, color: Color(0xFF4B5563)))),
    ]),
  );
}

class _CredentialField extends StatefulWidget {
  final TextEditingController controller;
  final String label, hint;
  final bool obscure;
  final String? helpText, helpUrl;
  final ValueChanged<String>? onChanged;
  const _CredentialField({
    required this.controller, required this.label, required this.hint,
    this.obscure = false, this.helpText, this.helpUrl, this.onChanged});
  @override State<_CredentialField> createState() => _CredentialFieldState();
}
class _CredentialFieldState extends State<_CredentialField> {
  late bool _obscure;
  @override void initState() { super.initState(); _obscure = widget.obscure; }
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.helpText != null)
        Row(children: [
          Text(widget.label, style: const TextStyle(
              fontSize: 12, color: Color(0xFF6B7280))),
          const Spacer(),
          if (widget.helpUrl != null)
            GestureDetector(
              onTap: () => launchUrl(Uri.parse(widget.helpUrl!)),
              child: Text('Get token →', style: TextStyle(
                  fontSize: 10, color: Colors.blue.shade600,
                  decoration: TextDecoration.underline)),
            ),
        ]),
      if (widget.helpText != null) const SizedBox(height: 4),
      TextFormField(
        controller: widget.controller,
        obscureText: _obscure,
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          labelText: widget.helpText == null ? widget.label : null,
          hintText: widget.hint,
          hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: widget.obscure
              ? IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_off : Icons.visibility, size: 16),
                  onPressed: () => setState(() => _obscure = !_obscure),
                )
              : null,
          helperText: widget.helpText,
          helperStyle: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
          helperMaxLines: 2,
        ),
      ),
    ],
  );
}

// ── DNS Dialog ────────────────────────────────────────────────────────────────

class _DnsDialog extends StatelessWidget {
  final String domain;
  final DomainRegistrar registrar;
  final List<DnsRecord> records;
  final Color primary;
  const _DnsDialog({required this.domain, required this.registrar,
      required this.records, required this.primary});

  @override
  Widget build(BuildContext context) {
    final registrarName = switch (registrar) {
      DomainRegistrar.namecheap => 'Namecheap',
      _                         => 'your registrar',
    };
    final namecheapUrl = registrar == DomainRegistrar.namecheap
        ? 'https://ap.www.namecheap.com/domains/domaincontrolpanel/$domain/advancedns'
        : null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.dns_rounded, color: primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Point Your Domain',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Add these records in $registrarName',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            )),
          ]),
          const SizedBox(height: 20),

          // Records table
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(children: [
              // Table header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
                ),
                child: Row(children: const [
                  Expanded(flex: 1, child: Text('Type',
                      style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w600, color: Colors.grey))),
                  Expanded(flex: 1, child: Text('Host',
                      style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w600, color: Colors.grey))),
                  Expanded(flex: 3, child: Text('Value',
                      style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w600, color: Colors.grey))),
                  SizedBox(width: 24),
                ]),
              ),
              const Divider(height: 1),
              // Rows
              ...records.map((r) => Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Row(children: [
                  Expanded(flex: 1, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(4)),
                    child: Text(r.type,
                        style: const TextStyle(fontSize: 11,
                            color: Color(0xFF3B82F6),
                            fontWeight: FontWeight.w600)),
                  )),
                  const SizedBox(width: 8),
                  Expanded(flex: 1, child: Text(r.host,
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'monospace'))),
                  Expanded(flex: 3, child: Text(r.value,
                      style: const TextStyle(fontSize: 11,
                          fontFamily: 'monospace',
                          color: Color(0xFF374151)))),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 14),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: r.value)),
                    tooltip: 'Copy',
                  ),
                ]),
              )),
            ]),
          ),
          const SizedBox(height: 16),

          // Propagation note
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: const Row(children: [
              Icon(Icons.schedule, size: 14, color: Colors.amber),
              SizedBox(width: 8),
              Expanded(child: Text(
                'DNS changes take 5–30 minutes to propagate globally.',
                style: TextStyle(fontSize: 11, color: Color(0xFF78350F)),
              )),
            ]),
          ),
          const SizedBox(height: 16),

          // Buttons
          Row(children: [
            if (namecheapUrl != null) ...[
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('Open Namecheap DNS'),
                onPressed: () => launchUrl(Uri.parse(namecheapUrl)),
              )),
              const SizedBox(width: 8),
            ],
            Expanded(child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: primary),
              child: const Text('Done'),
            )),
          ]),
        ]),
      ),
    );
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
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose a Template',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                      color: widget.primary)),
              const SizedBox(height: 4),
              const Text('Start with a template — everything can be customized.',
                  style: TextStyle(color: textMid, fontSize: 13)),
              const SizedBox(height: 20),
              ...siteTemplates.map((t) => _TemplateTile(
                template: t, primary: widget.primary,
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
            color: _hover ? widget.primary.withValues(alpha: 0.06) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hover ? widget.primary : const Color(0xFFE0E0E0),
              width: _hover ? 2 : 1,
            ),
          ),
          child: Row(children: [
            Text(t.previewEmoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(t.name, style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold,
                      color: _hover ? widget.primary : textDark)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: t.isMultiPage
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      t.isMultiPage ? 'Multi-page' : 'Single page',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                          color: t.isMultiPage
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFF1565C0)),
                    ),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(t.description,
                    style: const TextStyle(fontSize: 12, color: textMid)),
              ],
            )),
            Icon(Icons.arrow_forward_ios, size: 14,
                color: _hover ? widget.primary : Colors.grey.shade300),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// EXPORT RESULT DIALOG  (manual download flow)
// ══════════════════════════════════════════════════════════════════════════════

class _ExportResultDialog extends StatelessWidget {
  final ExportResult  result;
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
              Row(children: const [
                Text('🚀', style: TextStyle(fontSize: 28)),
                SizedBox(width: 12),
                Text('Site Exported!',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 8),
              const Text('Your website files are ready to deploy.',
                  style: TextStyle(color: textMid)),
              const SizedBox(height: 16),
              // Output folder path
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
                      style: const TextStyle(fontSize: 11,
                          fontFamily: 'monospace', color: textMid))),
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
                  Text(f, style: const TextStyle(
                      fontSize: 12, color: textMid)),
                ]),
              )),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              const Text('Next Steps',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              _Step(icon: '⚙️',
                  text: 'To deploy automatically, open Site Settings → Publish tab '
                      'and use the one-click deploy feature.'),
              _Step(icon: '🌐',
                  text: 'Or upload the folder to any static host: '
                      'GitHub Pages, Cloudflare Pages, Netlify, or Vercel.'),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(icon, style: const TextStyle(fontSize: 16)),
      const SizedBox(width: 8),
      Expanded(child: Text(text,
          style: const TextStyle(fontSize: 12, color: textMid, height: 1.5))),
    ]),
  );
}