// lib/apps/presentation/views/presentations_home.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/presentation_models.dart';
import '../models/slide_defaults.dart';
import '../../../theme.dart';

class PresentationsHome extends StatefulWidget {
  final List<Deck>           decks;
  final Color                primary;
  final Color                secondary;
  final ValueChanged<Deck>   onOpenDeck;
  final VoidCallback         onNewDeck;
  final ValueChanged<Deck>   onDeleteDeck;
  final ValueChanged<Deck>   onRenameDeck;
  final ValueChanged<Deck>   onDuplicateDeck;
  final ValueChanged<Deck>   onProperties;   // open Properties dialog
  final ValueChanged<Deck>   onExportDeck;   // export .cpres file
  final VoidCallback         onImportDeck;   // import .cpres file

  const PresentationsHome({
    super.key,
    required this.decks,
    required this.primary,
    required this.secondary,
    required this.onOpenDeck,
    required this.onNewDeck,
    required this.onDeleteDeck,
    required this.onRenameDeck,
    required this.onDuplicateDeck,
    required this.onProperties,
    required this.onExportDeck,
    required this.onImportDeck,
  });

  @override
  State<PresentationsHome> createState() => _PresentationsHomeState();
}

class _PresentationsHomeState extends State<PresentationsHome> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  List<Deck> get _filtered {
    if (_query.trim().isEmpty) return widget.decks;
    final q = _query.toLowerCase();
    return widget.decks.where((d) =>
        d.name.toLowerCase().contains(q) ||
        d.description.toLowerCase().contains(q) ||
        d.author.toLowerCase().contains(q) ||
        d.tags.any((t) => t.toLowerCase().contains(q))).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      children: [
        // ── Search + Import toolbar ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText:  'Search presentations…',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled:    true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            })
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: 'Import .cpres file',
                child: OutlinedButton.icon(
                  onPressed: widget.onImportDeck,
                  icon:  Icon(Icons.file_upload_outlined,
                      color: widget.primary, size: 18),
                  label: Text('Import',
                      style: TextStyle(color: widget.primary)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: widget.primary.withValues(alpha: 0.40)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: widget.decks.isEmpty
              ? _EmptyHome(
                  primary:   widget.primary,
                  secondary: widget.secondary,
                  onNew:     widget.onNewDeck,
                  onImport:  widget.onImportDeck,
                )
              : filtered.isEmpty
                  ? Center(
                      child: Text('No presentations match "$_query"',
                          style: TextStyle(color: Colors.grey.shade500)))
                  : _DeckGrid(
                      decks:        filtered,
                      primary:      widget.primary,
                      secondary:    widget.secondary,
                      onOpen:       widget.onOpenDeck,
                      onNew:        widget.onNewDeck,
                      onDelete:     widget.onDeleteDeck,
                      onRename:     widget.onRenameDeck,
                      onDuplicate:  widget.onDuplicateDeck,
                      onProperties: widget.onProperties,
                      onExport:     widget.onExportDeck,
                    ),
        ),
      ],
    );
  }
}

// ── DECK GRID ─────────────────────────────────────────────────────────────────
class _DeckGrid extends StatelessWidget {
  final List<Deck>         decks;
  final Color              primary;
  final Color              secondary;
  final ValueChanged<Deck> onOpen;
  final VoidCallback       onNew;
  final ValueChanged<Deck> onDelete;
  final ValueChanged<Deck> onRename;
  final ValueChanged<Deck> onDuplicate;
  final ValueChanged<Deck> onProperties;
  final ValueChanged<Deck> onExport;

  const _DeckGrid({
    required this.decks,
    required this.primary,
    required this.secondary,
    required this.onOpen,
    required this.onNew,
    required this.onDelete,
    required this.onRename,
    required this.onDuplicate,
    required this.onProperties,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('My Presentations',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text('${decks.length} deck${decks.length == 1 ? '' : 's'}',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 13)),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: onNew,
                  icon:  const Icon(Icons.add),
                  label: const Text('New Deck'),
                  style: FilledButton.styleFrom(backgroundColor: primary),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              mainAxisExtent:     220,
              crossAxisSpacing:   16,
              mainAxisSpacing:    16,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _DeckCard(
                key:          ValueKey(decks[i].id),
                deck:         decks[i],
                primary:      primary,
                secondary:    secondary,
                onOpen:       () => onOpen(decks[i]),
                onDelete:     () => onDelete(decks[i]),
                onRename:     () => onRename(decks[i]),
                onDuplicate:  () => onDuplicate(decks[i]),
                onProperties: () => onProperties(decks[i]),
                onExport:     () => onExport(decks[i]),
              ),
              childCount: decks.length,
            ),
          ),
        ),
      ],
    );
  }
}

// ── DECK CARD ─────────────────────────────────────────────────────────────────
class _DeckCard extends StatelessWidget {
  final Deck         deck;
  final Color        primary;
  final Color        secondary;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onProperties;
  final VoidCallback onExport;

  const _DeckCard({
    super.key,
    required this.deck,
    required this.primary,
    required this.secondary,
    required this.onOpen,
    required this.onDelete,
    required this.onRename,
    required this.onDuplicate,
    required this.onProperties,
    required this.onExport,
  });

  DateTime get lastUsed => deck.lastUsedAt ?? deck.createdAt;

  String _formatDate(DateTime dt) {
    final now  = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays <  7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(dt);
  }

  Widget _firstSlidePreview() {
    if (deck.slides.isEmpty) {
      return Container(
        color: primary.withValues(alpha: 0.08),
        child: Center(
          child: Icon(Icons.slideshow_outlined,
              size: 36, color: primary.withValues(alpha: 0.25)),
        ),
      );
    }
    final s  = deck.slides.first;
    final bg = s.bgColor;
    return Container(
      color: bg,
      padding: const EdgeInsets.all(10),
      child: Center(
        child: Text(
          s.title.isNotEmpty ? s.title : s.body,
          textAlign: TextAlign.center,
          maxLines:  3,
          overflow:  TextOverflow.ellipsis,
          style: TextStyle(
            color:      s.textColor,
            fontSize:   11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _slideStrip() {
    final slides = deck.slides.take(6).toList();
    if (slides.isEmpty) return const SizedBox.shrink();
    return Row(
      children: slides.map((s) => Container(
        width:  20, height: 14,
        margin: const EdgeInsets.only(right: 3),
        decoration: BoxDecoration(
          color:        s.bgColor,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
              color: Colors.black.withValues(alpha: 0.10), width: 0.5),
        ),
      )).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation:   2,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          children: [
            // Slide preview
            Expanded(
              flex: 50,
              child: _firstSlidePreview(),
            ),

            // Info area
            Expanded(
              flex: 50,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _slideStrip(),
                    const SizedBox(height: 6),

                    // Name row
                    Row(
                      children: [
                        if (deck.isPinned) ...[
                          Icon(Icons.push_pin_rounded,
                              size: 12, color: primary),
                          const SizedBox(width: 4),
                        ],
                        if (deck.isTemplate) ...[
                          Icon(Icons.content_copy_rounded,
                              size: 12, color: Colors.deepPurple.shade300),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(deck.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize:   13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert,
                              size: 18, color: Colors.grey.shade500),
                          onSelected: (v) {
                            switch (v) {
                              case 'open':       onOpen();       break;
                              case 'properties': onProperties(); break;
                              case 'rename':     onRename();     break;
                              case 'duplicate':  onDuplicate();  break;
                              case 'export':     onExport();     break;
                              case 'delete':     onDelete();     break;
                            }
                          },
                          itemBuilder: (_) => [
                            _menuItem('open',       Icons.open_in_new,             'Open'),
                            _menuItem('properties', Icons.info_outline_rounded,    'Properties…'),
                            const PopupMenuDivider(),
                            _menuItem('rename',    Icons.drive_file_rename_outline, 'Rename'),
                            _menuItem('duplicate', Icons.copy_rounded,              'Duplicate'),
                            _menuItem('export',    Icons.file_download_outlined,    'Export .cpres'),
                            const PopupMenuDivider(),
                            _menuItem('delete',    Icons.delete_outline,            'Delete',
                                color: Colors.red),
                          ],
                        ),
                      ],
                    ),

                    // Description if present
                    if (deck.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(deck.description,
                          style: TextStyle(
                              fontSize: 10,
                              color:    Colors.grey.shade500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],

                    const Spacer(),

                    // Footer row
                    Row(
                      children: [
                        Icon(Icons.layers_outlined,
                            size: 11, color: Colors.grey.shade400),
                        const SizedBox(width: 3),
                        Text('${deck.slideCount}',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500)),
                        if (deck.author.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.person_outline_rounded,
                              size: 11, color: Colors.grey.shade400),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(deck.author,
                                style: TextStyle(
                                    fontSize: 11,
                                    color:    Colors.grey.shade500),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ] else
                          const Spacer(),
                        Icon(Icons.schedule,
                            size: 11, color: Colors.grey.shade400),
                        const SizedBox(width: 3),
                        Text(_formatDate(lastUsed),
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500)),
                      ],
                    ),

                    // Service date badge
                    if (deck.serviceDate != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:        primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_rounded,
                                size: 10, color: primary),
                            const SizedBox(width: 3),
                            Text(
                              DateFormat('MMM d, y').format(deck.serviceDate!),
                              style: TextStyle(
                                  fontSize:   10,
                                  color:      primary,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

PopupMenuItem<String> _menuItem(
  String value,
  IconData icon,
  String label, {
  Color? color,
}) =>
    PopupMenuItem(
      value: value,
      child: ListTile(
        leading: Icon(icon, size: 18, color: color),
        title:   Text(label,
            style: TextStyle(color: color, fontSize: 14)),
        dense:   true,
        contentPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );

// ── RENAME DIALOG ─────────────────────────────────────────────────────────────
Future<String?> showRenameDeckDialog(
  BuildContext context,
  String currentName,
) async {
  final ctrl   = TextEditingController(text: currentName);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Rename Presentation'),
      content: TextField(
        controller:  ctrl,
        autofocus:   true,
        decoration: const InputDecoration(
          labelText: 'Presentation name',
          border:    OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Rename')),
      ],
    ),
  );
  ctrl.dispose();
  return result?.isEmpty == true ? null : result;
}

// ── EMPTY STATE ───────────────────────────────────────────────────────────────
class _EmptyHome extends StatelessWidget {
  final Color        primary;
  final Color        secondary;
  final VoidCallback onNew;
  final VoidCallback onImport;

  const _EmptyHome({
    required this.primary,
    required this.secondary,
    required this.onNew,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.slideshow,
              size: 88, color: primary.withValues(alpha: 0.25)),
          const SizedBox(height: 24),
          Text('No presentations yet',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold,
                  color: primary.withValues(alpha: 0.60))),
          const SizedBox(height: 8),
          Text('Create a new deck or import an existing .cpres file.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: onNew,
                icon:  const Icon(Icons.add),
                label: const Text('New Deck'),
                style: FilledButton.styleFrom(
                  backgroundColor: primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onImport,
                icon:  Icon(Icons.file_upload_outlined, color: primary),
                label: Text('Import File',
                    style: TextStyle(color: primary)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: primary.withValues(alpha: 0.40)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          Text('Or start from a template:',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: SlideDefaults.slideTypes.map((type) =>
              OutlinedButton.icon(
                onPressed: onNew,
                icon:  const Icon(Icons.add, size: 16),
                label: Text(SlideDefaults.typeLabel(type)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primary,
                  side: BorderSide(
                      color: primary.withValues(alpha: 0.40)),
                ),
              ),
            ).toList(),
          ),
        ],
      ),
    );
  }
}