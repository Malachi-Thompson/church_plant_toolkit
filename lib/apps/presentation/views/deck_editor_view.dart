// lib/apps/presentation/views/deck_editor_view.dart
//
// Two-column editor: slide list | slide editor.
// Supports slide groups with optional auto-advance timers.
import 'package:flutter/material.dart';
import '../models/presentation_models.dart';
import '../models/slide_defaults.dart';
import '../models/slide_group.dart';
import '../dialogs/slide_group_dialog.dart';
import '../widgets/presentation_widgets.dart';
import '../songselect/songselect_import.dart';
import 'slide_editor_view.dart';

class DeckEditorView extends StatelessWidget {
  final Deck                                    deck;
  final Slide?                                  selectedSlide;
  final Color                                   primary;
  final Color                                   secondary;
  final ValueChanged<Slide>                     onSelectSlide;
  final ValueChanged<String>                    onAddSlide;
  final ValueChanged<Slide>                     onDeleteSlide;
  final Function(int, int)                      onReorderSlides;
  final VoidCallback                            onSlideChanged;
  final VoidCallback                            onImportScripture;
  // ── group callbacks ───────────────────────────────────────────────────────
  final ValueChanged<SlideGroup>                onCreateGroup;
  final ValueChanged<SlideGroup>                onUpdateGroup;
  final ValueChanged<String>                    onDeleteGroup;
  final void Function(String groupId, String slideId) onAddSlideToGroup;
  final void Function(String groupId, String slideId) onRemoveSlideFromGroup;
  // ── song collection callbacks ─────────────────────────────────────────────
  final ValueChanged<SongCollection>            onImportCollection;
  final ValueChanged<String>                    onToggleCollection;
  final void Function(String collId, int delta) onMoveCollection;
  final ValueChanged<String>                    onRemoveCollection;
  final void Function(String, int, int)         onReorderCollectionSlide;

  const DeckEditorView({
    super.key,
    required this.deck,
    required this.selectedSlide,
    required this.primary,
    required this.secondary,
    required this.onSelectSlide,
    required this.onAddSlide,
    required this.onDeleteSlide,
    required this.onReorderSlides,
    required this.onSlideChanged,
    required this.onImportScripture,
    required this.onCreateGroup,
    required this.onUpdateGroup,
    required this.onDeleteGroup,
    required this.onAddSlideToGroup,
    required this.onRemoveSlideFromGroup,
    required this.onImportCollection,
    required this.onToggleCollection,
    required this.onMoveCollection,
    required this.onRemoveCollection,
    required this.onReorderCollectionSlide,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── SLIDE LIST ─────────────────────────────────────────────────────
        SizedBox(
          width: 240,
          child: _SlideListPanel(
            deck:                    deck,
            selectedSlide:           selectedSlide,
            primary:                 primary,
            secondary:               secondary,
            onSelectSlide:           onSelectSlide,
            onAddSlide:              onAddSlide,
            onDeleteSlide:           onDeleteSlide,
            onReorderSlides:         onReorderSlides,
            onImportScripture:       onImportScripture,
            onCreateGroup:           onCreateGroup,
            onUpdateGroup:           onUpdateGroup,
            onDeleteGroup:           onDeleteGroup,
            onAddSlideToGroup:       onAddSlideToGroup,
            onRemoveSlideFromGroup:  onRemoveSlideFromGroup,
            onImportCollection:      onImportCollection,
            onToggleCollection:      onToggleCollection,
            onMoveCollection:        onMoveCollection,
            onRemoveCollection:      onRemoveCollection,
            onReorderCollectionSlide: onReorderCollectionSlide,
            importContext:           context,
          ),
        ),
        const VerticalDivider(width: 1),

        // ── SLIDE EDITOR / PLACEHOLDER ─────────────────────────────────────
        Expanded(
          child: selectedSlide != null
              ? SlideEditorView(
                  slide:     selectedSlide!,
                  primary:   primary,
                  secondary: secondary,
                  onChanged: onSlideChanged,
                )
              : _EmptyPrompt(
                  primary:   primary,
                  secondary: secondary,
                  onAdd:     onAddSlide,
                ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SLIDE LIST PANEL
// ══════════════════════════════════════════════════════════════════════════════
class _SlideListPanel extends StatelessWidget {
  final Deck                            deck;
  final Slide?                          selectedSlide;
  final Color                           primary;
  final Color                           secondary;
  final ValueChanged<Slide>             onSelectSlide;
  final ValueChanged<String>            onAddSlide;
  final ValueChanged<Slide>             onDeleteSlide;
  final Function(int, int)              onReorderSlides;
  final VoidCallback                    onImportScripture;
  final ValueChanged<SlideGroup>        onCreateGroup;
  final ValueChanged<SlideGroup>        onUpdateGroup;
  final ValueChanged<String>            onDeleteGroup;
  final void Function(String, String)   onAddSlideToGroup;
  final void Function(String, String)   onRemoveSlideFromGroup;
  final ValueChanged<SongCollection>    onImportCollection;
  final ValueChanged<String>            onToggleCollection;
  final void Function(String, int)      onMoveCollection;
  final ValueChanged<String>            onRemoveCollection;
  final void Function(String, int, int) onReorderCollectionSlide;
  final BuildContext                    importContext;

  const _SlideListPanel({
    required this.deck,
    required this.selectedSlide,
    required this.primary,
    required this.secondary,
    required this.onSelectSlide,
    required this.onAddSlide,
    required this.onDeleteSlide,
    required this.onReorderSlides,
    required this.onImportScripture,
    required this.onCreateGroup,
    required this.onUpdateGroup,
    required this.onDeleteGroup,
    required this.onAddSlideToGroup,
    required this.onRemoveSlideFromGroup,
    required this.onImportCollection,
    required this.onToggleCollection,
    required this.onMoveCollection,
    required this.onRemoveCollection,
    required this.onReorderCollectionSlide,
    required this.importContext,
  });

  Future<void> _openSongImport() async {
    final coll = await showSongSelectImport(
        importContext, primary: primary, secondary: secondary);
    if (coll != null) onImportCollection(coll);
  }

  Future<void> _createGroup() async {
    final group = await showSlideGroupDialog(
        importContext, primary: primary);
    if (group != null) onCreateGroup(group);
  }

  @override
  Widget build(BuildContext context) {
    final items       = SongCollectionStore.buildDisplayList(deck);
    final groups      = deck.groups;                   // List<SlideGroup>
    // Slides not yet in any group
    final groupedIds  = groups.expand((g) => g.slideIds).toSet();

    return Column(
      children: [
        // ── Action buttons ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: PopupMenuButton<String>(
            onSelected: onAddSlide,
            itemBuilder: (_) => SlideDefaults.slideTypes
                .map((t) => PopupMenuItem(
                      value: t,
                      child: Text(SlideDefaults.typeLabel(t)),
                    ))
                .toList(),
            child: _ActionButton(
              icon:    Icons.add,
              label:   'Add Slide',
              primary: primary,
              filled:  true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: _ActionButton(
            icon:      Icons.collections_bookmark_rounded,
            label:     'New Group',
            primary:   primary,
            onPressed: _createGroup,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: _ActionButton(
            icon:      Icons.menu_book_rounded,
            label:     'Import Scripture',
            primary:   primary,
            onPressed: onImportScripture,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: _ActionButton(
            icon:      Icons.music_note_rounded,
            label:     'Import Song (CCLI)',
            primary:   primary,
            onPressed: _openSongImport,
          ),
        ),

        const Divider(height: 1),

        // ── Slide / Group / Collection list ───────────────────────────────
        Expanded(
          child: deck.slides.isEmpty && groups.isEmpty
              ? const EmptyStateMessage(
                  icon:    Icons.add_photo_alternate_outlined,
                  message: 'No slides yet',
                  color:   Colors.grey,
                )
              : ListView.builder(
                  padding:   const EdgeInsets.only(bottom: 20),
                  itemCount: _listItemCount(items, groups, groupedIds),
                  itemBuilder: (_, i) =>
                      _buildListItem(i, items, groups, groupedIds),
                ),
        ),
      ],
    );
  }

  // ── List item builder ─────────────────────────────────────────────────────

  int _listItemCount(List items, List<SlideGroup> groups,
      Set<String> groupedIds) {
    // Groups + song collections + ungrouped plain slides
    int count = groups.length;
    for (final item in items) {
      if (item.isCollection) {
        count++;
      } else {
        final slide = deck.slides[item.deckIndex];
        if (!groupedIds.contains(slide.id)) count++;
      }
    }
    return count;
  }

  Widget _buildListItem(int listIdx, List items,
      List<SlideGroup> groups, Set<String> groupedIds) {
    // Walk through: first groups, then ungrouped slides & collections
    if (listIdx < groups.length) {
      return _GroupTile(
        key:                 ValueKey('group_${groups[listIdx].id}'),
        group:               groups[listIdx],
        deck:                deck,
        primary:             primary,
        secondary:           secondary,
        selectedSlide:       selectedSlide,
        onSelectSlide:       onSelectSlide,
        onUpdateGroup:       onUpdateGroup,
        onDeleteGroup:       onDeleteGroup,
        onRemoveFromGroup:   onRemoveSlideFromGroup,
        importContext:       importContext,
      );
    }

    // Ungrouped items (slides + song collections)
    int cursor = listIdx - groups.length;
    for (final item in items) {
      if (item.isCollection) {
        if (cursor == 0) {
          final coll = SongCollectionStore.find(item.collectionId);
          if (coll == null) return const SizedBox.shrink();
          return SongCollectionTile(
            key:            ValueKey('coll_${coll.id}'),
            collection:     coll,
            deck:           deck,
            primary:        primary,
            secondary:      secondary,
            selectedSlide:  selectedSlide,
            onSelectSlide:  onSelectSlide,
            onToggleExpand: () => onToggleCollection(coll.id),
            onMoveGroup:    (d) => onMoveCollection(coll.id, d),
            onRemove:       () => onRemoveCollection(coll.id),
            onReorderSlide: (o, n) =>
                onReorderCollectionSlide(coll.id, o, n),
          );
        }
        cursor--;
      } else {
        final slide = deck.slides[item.deckIndex];
        if (groupedIds.contains(slide.id)) continue;
        if (cursor == 0) {
          return _UngroupedSlideTile(
            key:       ValueKey(slide.id),
            slide:     slide,
            deckIndex: item.deckIndex,
            deckLen:   deck.slides.length,
            selected:  selectedSlide?.id == slide.id,
            primary:   primary,
            secondary: secondary,
            groups:    deck.groups,
            onTap:     () => onSelectSlide(slide),
            onDelete:  () => onDeleteSlide(slide),
            onMoveUp:  item.deckIndex > 0
                ? () => onReorderSlides(item.deckIndex, item.deckIndex - 1)
                : null,
            onMoveDown: item.deckIndex < deck.slides.length - 1
                ? () => onReorderSlides(item.deckIndex, item.deckIndex + 2)
                : null,
            onAssignGroup: (gId) => onAddSlideToGroup(gId, slide.id),
          );
        }
        cursor--;
      }
    }
    return const SizedBox.shrink();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GROUP TILE
// ══════════════════════════════════════════════════════════════════════════════
class _GroupTile extends StatefulWidget {
  final SlideGroup                         group;
  final Deck                               deck;
  final Color                              primary;
  final Color                              secondary;
  final Slide?                             selectedSlide;
  final ValueChanged<Slide>                onSelectSlide;
  final ValueChanged<SlideGroup>           onUpdateGroup;
  final ValueChanged<String>               onDeleteGroup;
  final void Function(String, String)      onRemoveFromGroup;
  final BuildContext                       importContext;

  const _GroupTile({
    super.key,
    required this.group,
    required this.deck,
    required this.primary,
    required this.secondary,
    required this.selectedSlide,
    required this.onSelectSlide,
    required this.onUpdateGroup,
    required this.onDeleteGroup,
    required this.onRemoveFromGroup,
    required this.importContext,
  });

  @override
  State<_GroupTile> createState() => _GroupTileState();
}

class _GroupTileState extends State<_GroupTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final g   = widget.group;
    final p   = widget.primary;
    final slides = g.slideIds
        .map((id) =>
            widget.deck.slides.firstWhere((s) => s.id == id,
                orElse: () => Slide(
                    id: id, type: 'blank',
                    title: '?', body: '',
                    bgColor: Colors.grey, textColor: Colors.white)))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Group header ─────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          decoration: BoxDecoration(
            color:        p.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border:       Border.all(color: p.withValues(alpha: 0.22)),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                  child: Row(
                    children: [
                      Icon(_expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          color: p, size: 18),
                      const SizedBox(width: 6),
                      Icon(Icons.collections_bookmark_rounded,
                          color: p, size: 15),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(g.name,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color:      p,
                                fontSize:   13),
                            overflow: TextOverflow.ellipsis),
                      ),
                      // Timer badge
                      if (g.hasAutoAdvance)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:        p.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer_rounded,
                                  color: p, size: 11),
                              const SizedBox(width: 3),
                              Text('${g.autoAdvanceSeconds}s',
                                  style: TextStyle(
                                      color:      p,
                                      fontSize:   10,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      // Options menu
                      PopupMenuButton<String>(
                        padding:     EdgeInsets.zero,
                        iconSize:    18,
                        icon:        Icon(Icons.more_vert_rounded,
                            color: p, size: 18),
                        onSelected: (v) async {
                          if (v == 'edit') {
                            final updated =
                                await showSlideGroupDialog(
                              widget.importContext,
                              primary:  p,
                              existing: g,
                            );
                            if (updated != null) {
                              widget.onUpdateGroup(updated);
                            }
                          } else if (v == 'delete') {
                            widget.onDeleteGroup(g.id);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'edit',
                              child: ListTile(
                                leading: Icon(Icons.edit_rounded),
                                title:   Text('Edit group'),
                                dense:   true,
                              )),
                          const PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                leading: Icon(Icons.delete_outline_rounded,
                                    color: Colors.red),
                                title:   Text('Delete group',
                                    style: TextStyle(color: Colors.red)),
                                dense:   true,
                              )),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Slide count sub-label
              if (!_expanded)
                Padding(
                  padding: const EdgeInsets.only(
                      left: 40, bottom: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${slides.length} slide${slides.length == 1 ? '' : 's'}',
                      style: TextStyle(
                          fontSize: 11,
                          color:    Colors.grey.shade500),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ── Slides inside group ──────────────────────────────────────────
        if (_expanded)
          ...slides.asMap().entries.map((e) {
            final s = e.value;
            return Padding(
              key:     ValueKey('gs_${s.id}'),
              padding: const EdgeInsets.only(left: 20),
              child: Dismissible(
                key:       ValueKey('gdis_${s.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding:   const EdgeInsets.only(right: 12),
                  color:     Colors.orange.shade100,
                  child: Icon(Icons.remove_circle_outline,
                      color: Colors.orange.shade700),
                ),
                onDismissed: (_) =>
                    widget.onRemoveFromGroup(g.id, s.id),
                child: Stack(
                  children: [
                    SlideThumbnail(
                      slide:               s,
                      selected:            widget.selectedSlide?.id == s.id,
                      selectedBorderColor: widget.secondary,
                      onTap: () => widget.onSelectSlide(s),
                    ),
                    if (g.hasAutoAdvance)
                      Positioned(
                        bottom: 4, right: 4,
                        child: _TimerBadge(secs: g.autoAdvanceSeconds!),
                      ),
                  ],
                ),
              ),
            );
          }),

        if (_expanded && slides.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 6, 8, 6),
            child: Text('No slides — assign slides via ⋮ menu',
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade400)),
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// UNGROUPED SLIDE TILE  (with "Add to group" popup)
// ══════════════════════════════════════════════════════════════════════════════
class _UngroupedSlideTile extends StatelessWidget {
  final Slide              slide;
  final int                deckIndex;
  final int                deckLen;
  final bool               selected;
  final Color              primary;
  final Color              secondary;
  final List<SlideGroup>   groups;
  final VoidCallback       onTap;
  final VoidCallback       onDelete;
  final VoidCallback?      onMoveUp;
  final VoidCallback?      onMoveDown;
  final ValueChanged<String> onAssignGroup;

  const _UngroupedSlideTile({
    super.key,
    required this.slide,
    required this.deckIndex,
    required this.deckLen,
    required this.selected,
    required this.primary,
    required this.secondary,
    required this.groups,
    required this.onTap,
    required this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
    required this.onAssignGroup,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Dismissible(
        key:       ValueKey('dis_${slide.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding:   const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color:        Colors.red,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        onDismissed: (_) => onDelete(),
        child: Row(
          children: [
            Expanded(
              child: SlideThumbnail(
                slide:               slide,
                selected:            selected,
                selectedBorderColor: secondary,
                onTap:               onTap,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onMoveUp   != null)
                  _Arr(icon: Icons.arrow_upward_rounded,   onTap: onMoveUp!),
                if (onMoveDown != null)
                  _Arr(icon: Icons.arrow_downward_rounded, onTap: onMoveDown!),
                if (groups.isNotEmpty)
                  PopupMenuButton<String>(
                    padding:  EdgeInsets.zero,
                    iconSize: 14,
                    tooltip:  'Add to group',
                    icon: Icon(Icons.add_to_photos_rounded,
                        size: 14, color: primary.withValues(alpha: 0.60)),
                    onSelected: onAssignGroup,
                    itemBuilder: (_) => groups
                        .map((g) => PopupMenuItem(
                              value: g.id,
                              child: Row(children: [
                                Icon(Icons.collections_bookmark_rounded,
                                    size: 14, color: primary),
                                const SizedBox(width: 8),
                                Text(g.name,
                                    style:
                                        const TextStyle(fontSize: 13)),
                              ]),
                            ))
                        .toList(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SMALL SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════
class _TimerBadge extends StatelessWidget {
  final int secs;
  const _TimerBadge({required this.secs});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color:        Colors.black54,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer_rounded, color: Colors.white, size: 10),
            const SizedBox(width: 2),
            Text('${secs}s',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

class _ActionButton extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final Color        primary;
  final bool         filled;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.primary,
    this.filled    = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: filled
            ? Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 14),
                decoration: BoxDecoration(
                  color:        primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border:       Border.all(
                      color: primary.withValues(alpha: 0.28)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: primary, size: 18),
                    const SizedBox(width: 6),
                    Text(label,
                        style: TextStyle(
                            color:      primary,
                            fontWeight: FontWeight.bold,
                            fontSize:   13)),
                  ],
                ),
              )
            : OutlinedButton.icon(
                onPressed: onPressed,
                icon:  Icon(icon, color: primary, size: 16),
                label: Text(label,
                    style: TextStyle(color: primary, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  side:    BorderSide(
                      color: primary.withValues(alpha: 0.38)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
      );
}

class _Arr extends StatelessWidget {
  final IconData     icon;
  final VoidCallback onTap;
  const _Arr({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 14, color: Colors.grey.shade400),
        ),
      );
}

class _EmptyPrompt extends StatelessWidget {
  final Color              primary;
  final Color              secondary;
  final ValueChanged<String> onAdd;

  const _EmptyPrompt({
    required this.primary,
    required this.secondary,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined,
                size: 64, color: primary.withValues(alpha: 0.40)),
            const SizedBox(height: 16),
            Text('Add your first slide',
                style: TextStyle(
                    fontSize: 18,
                    color:    primary.withValues(alpha: 0.70))),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12, runSpacing: 12,
              children: SlideDefaults.slideTypes.map((type) =>
                  ElevatedButton(
                    onPressed: () => onAdd(type),
                    style: ElevatedButton.styleFrom(
                        backgroundColor:
                            primary.withValues(alpha: 0.10),
                        foregroundColor: primary),
                    child: Text(SlideDefaults.typeLabel(type)),
                  )).toList(),
            ),
          ],
        ),
      );
}