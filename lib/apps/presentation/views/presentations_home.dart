// lib/apps/presentation/views/presentations_home.dart
//
// The first screen shown when a user opens Presentation Studio.
// Displays all decks as cards with last-used date, slide count, and a
// preview of the first slide's colour.  Users can create, rename, duplicate,
// delete, and open any deck from here.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/presentation_models.dart';
import '../models/slide_defaults.dart';
import '../../../theme.dart';

class PresentationsHome extends StatelessWidget {
  final List<Deck>           decks;
  final Color                primary;
  final Color                secondary;
  final ValueChanged<Deck>   onOpenDeck;
  final VoidCallback         onNewDeck;
  final ValueChanged<Deck>   onDeleteDeck;
  final ValueChanged<Deck>   onRenameDeck;
  final ValueChanged<Deck>   onDuplicateDeck;

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
  });

  @override
  Widget build(BuildContext context) {
    return decks.isEmpty
        ? _EmptyHome(primary: primary, secondary: secondary, onNew: onNewDeck)
        : _DeckGrid(
            decks:           decks,
            primary:         primary,
            secondary:       secondary,
            onOpen:          onOpenDeck,
            onNew:           onNewDeck,
            onDelete:        onDeleteDeck,
            onRename:        onRenameDeck,
            onDuplicate:     onDuplicateDeck,
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

  const _DeckGrid({
    required this.decks,
    required this.primary,
    required this.secondary,
    required this.onOpen,
    required this.onNew,
    required this.onDelete,
    required this.onRename,
    required this.onDuplicate,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // ── HEADER ──────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Presentations',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${decks.length} deck${decks.length == 1 ? '' : 's'}',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 13),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: onNew,
                  icon:  const Icon(Icons.add),
                  label: const Text('New Deck'),
                  style: FilledButton.styleFrom(
                      backgroundColor: primary),
                ),
              ],
            ),
          ),
        ),

        // ── GRID ────────────────────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.symmetric(
              horizontal: 24, vertical: 16),
          sliver: SliverGrid(
            gridDelegate:
                const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent:  320,
              mainAxisExtent:      210,
              crossAxisSpacing:    16,
              mainAxisSpacing:     16,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _DeckCard(
                deck:        decks[i],
                primary:     primary,
                secondary:   secondary,
                onOpen:      () => onOpen(decks[i]),
                onDelete:    () => onDelete(decks[i]),
                onRename:    () => onRename(decks[i]),
                onDuplicate: () => onDuplicate(decks[i]),
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

  const _DeckCard({
    required this.deck,
    required this.primary,
    required this.secondary,
    required this.onOpen,
    required this.onDelete,
    required this.onRename,
    required this.onDuplicate,
  });

  // Build a small strip of coloured dots representing the first few slides
  Widget _slideStrip() {
    final preview = deck.slides.take(6).toList();
    if (preview.isEmpty) {
      return Container(
        height: 6,
        decoration: BoxDecoration(
          color:        Colors.grey.shade200,
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }
    return Row(
      children: preview.map((s) {
        return Expanded(
          child: Container(
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color:        s.bgColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }).toList(),
    );
  }

  // Preview of the first slide's text content
  Widget _firstSlidePreview() {
    if (deck.slides.isEmpty) {
      return Center(
        child: Icon(Icons.slideshow,
            size: 40, color: Colors.grey.shade300),
      );
    }
    final first = deck.slides.first;
    return Container(
      color: first.bgColor,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (first.title.isNotEmpty)
            Text(
              first.title,
              style: TextStyle(
                color:      first.textColor,
                fontSize:   11,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines:  2,
              overflow:  TextOverflow.ellipsis,
            ),
          if (first.body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              first.body,
              style: TextStyle(
                  color: first.textColor.withValues(alpha: 0.80),
                  fontSize: 8),
              textAlign: TextAlign.center,
              maxLines:  2,
              overflow:  TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    if (now.difference(dt).inDays == 0) return 'Today';
    if (now.difference(dt).inDays == 1) return 'Yesterday';
    return DateFormat('MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final lastUsed = deck.lastUsedAt ?? deck.createdAt;

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Slide preview (top 55%)
            Expanded(
              flex: 55,
              child: _firstSlidePreview(),
            ),

            // Bottom info area
            Expanded(
              flex: 45,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Slide colour strip
                    _slideStrip(),
                    const SizedBox(height: 8),

                    // Deck name + menu
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            deck.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize:   14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _CardMenu(
                          onOpen:      onOpen,
                          onRename:    onRename,
                          onDuplicate: onDuplicate,
                          onDelete:    onDelete,
                        ),
                      ],
                    ),

                    // Metadata row
                    const Spacer(),
                    Row(
                      children: [
                        Icon(Icons.layers_outlined,
                            size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(
                          '${deck.slideCount} slide${deck.slideCount == 1 ? '' : 's'}',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500),
                        ),
                        const Spacer(),
                        Icon(Icons.schedule,
                            size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(lastUsed),
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500),
                        ),
                      ],
                    ),
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

// ── CARD CONTEXT MENU ─────────────────────────────────────────────────────────
class _CardMenu extends StatelessWidget {
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  const _CardMenu({
    required this.onOpen,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert,
          size: 18, color: Colors.grey.shade500),
      onSelected: (v) {
        switch (v) {
          case 'open':      onOpen();      break;
          case 'rename':    onRename();    break;
          case 'duplicate': onDuplicate(); break;
          case 'delete':    onDelete();    break;
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'open',
          child: ListTile(
            leading: Icon(Icons.open_in_new, size: 18),
            title:   Text('Open'),
            dense:   true,
          ),
        ),
        PopupMenuItem(
          value: 'rename',
          child: ListTile(
            leading: Icon(Icons.drive_file_rename_outline, size: 18),
            title:   Text('Rename'),
            dense:   true,
          ),
        ),
        PopupMenuItem(
          value: 'duplicate',
          child: ListTile(
            leading: Icon(Icons.copy, size: 18),
            title:   Text('Duplicate'),
            dense:   true,
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline,
                size: 18, color: Colors.red),
            title: Text('Delete',
                style: TextStyle(color: Colors.red)),
            dense: true,
          ),
        ),
      ],
    );
  }
}

// ── RENAME DIALOG ─────────────────────────────────────────────────────────────
Future<String?> showRenameDeckDialog(
  BuildContext context,
  String currentName,
) async {
  final ctrl = TextEditingController(text: currentName);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Rename Presentation'),
      content: TextField(
        controller:   ctrl,
        autofocus:    true,
        decoration:   const InputDecoration(
          labelText: 'Presentation name',
          border:    OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('Rename'),
        ),
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

  const _EmptyHome({
    required this.primary,
    required this.secondary,
    required this.onNew,
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
          Text(
            'No presentations yet',
            style: TextStyle(
              fontSize:   22,
              fontWeight: FontWeight.bold,
              color:      primary.withValues(alpha: 0.60),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first deck to get started.',
            style: TextStyle(
                color: Colors.grey.shade500, fontSize: 14),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: onNew,
            icon:  const Icon(Icons.add),
            label: const Text('Create Presentation'),
            style: FilledButton.styleFrom(
              backgroundColor: primary,
              padding: const EdgeInsets.symmetric(
                  horizontal: 28, vertical: 14),
            ),
          ),

          // Slide type quick-starts
          const SizedBox(height: 40),
          Text(
            'Or start from a template:',
            style: TextStyle(
                color: Colors.grey.shade500, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: SlideDefaults.slideTypes.map((type) {
              return OutlinedButton.icon(
                onPressed: onNew,
                icon:  const Icon(Icons.add, size: 16),
                label: Text(SlideDefaults.typeLabel(type)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primary,
                  side: BorderSide(
                      color: primary.withValues(alpha: 0.40)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}