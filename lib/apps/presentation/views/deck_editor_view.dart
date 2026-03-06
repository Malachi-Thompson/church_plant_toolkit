// lib/apps/presentation/views/deck_editor_view.dart
//
// Two-column editor: slide list | slide editor.
// The left deck-list panel has been removed entirely.
// Navigation back to all decks is via the AppBar ← in presentation_screen.dart.
import 'package:flutter/material.dart';
import '../models/presentation_models.dart';
import '../models/slide_defaults.dart';
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
          width: 230,
          child: _SlideListPanel(
            deck:                     deck,
            selectedSlide:            selectedSlide,
            primary:                  primary,
            secondary:                secondary,
            onSelectSlide:            onSelectSlide,
            onAddSlide:               onAddSlide,
            onDeleteSlide:            onDeleteSlide,
            onReorderSlides:          onReorderSlides,
            onImportCollection:       onImportCollection,
            onToggleCollection:       onToggleCollection,
            onMoveCollection:         onMoveCollection,
            onRemoveCollection:       onRemoveCollection,
            onReorderCollectionSlide: onReorderCollectionSlide,
            importContext:            context,
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
              : _EmptyPrompt(primary: primary, secondary: secondary,
                  onAdd: onAddSlide),
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
    required this.onImportCollection,
    required this.onToggleCollection,
    required this.onMoveCollection,
    required this.onRemoveCollection,
    required this.onReorderCollectionSlide,
    required this.importContext,
  });

  Future<void> _openImport() async {
    final coll = await showSongSelectImport(
        importContext, primary: primary, secondary: secondary);
    if (coll != null) onImportCollection(coll);
  }

  @override
  Widget build(BuildContext context) {
    final items = SongCollectionStore.buildDisplayList(deck);

    return Column(
      children: [
        // ── Add Slide ──────────────────────────────────────────────────────
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
            child: Container(
              width:   double.infinity,
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
                  Icon(Icons.add, color: primary, size: 18),
                  const SizedBox(width: 6),
                  Text('Add Slide',
                      style: TextStyle(
                          color:      primary,
                          fontWeight: FontWeight.bold,
                          fontSize:   13)),
                ],
              ),
            ),
          ),
        ),

        // ── Import Song (CCLI) ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openImport,
              icon:  Icon(Icons.music_note_rounded, color: primary, size: 16),
              label: Text('Import Song (CCLI)',
                  style: TextStyle(color: primary, fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 9),
                side:    BorderSide(color: primary.withValues(alpha: 0.38)),
                shape:   RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ),
        const Divider(height: 1),

        // ── Slide / Collection list ────────────────────────────────────────
        Expanded(
          child: deck.slides.isEmpty
              ? const EmptyStateMessage(
                  icon:    Icons.add_photo_alternate_outlined,
                  message: 'No slides yet',
                  color:   Colors.grey,
                )
              : ListView.builder(
                  padding:   const EdgeInsets.only(bottom: 20),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final item = items[i];

                    // ── song collection ──────────────────────────────────
                    if (item.isCollection) {
                      final coll =
                          SongCollectionStore.find(item.collectionId);
                      if (coll == null) return const SizedBox.shrink();
                      return SongCollectionTile(
                        key:            ValueKey('coll_${coll.id}'),
                        collection:     coll,
                        deck:           deck,
                        primary:        primary,
                        secondary:      secondary,
                        selectedSlide:  selectedSlide,
                        onSelectSlide:  onSelectSlide,
                        onToggleExpand: () =>
                            onToggleCollection(coll.id),
                        onMoveGroup:    (d) =>
                            onMoveCollection(coll.id, d),
                        onRemove:       () =>
                            onRemoveCollection(coll.id),
                        onReorderSlide: (o, n) =>
                            onReorderCollectionSlide(coll.id, o, n),
                      );
                    }

                    // ── plain slide ──────────────────────────────────────
                    final slide = deck.slides[item.deckIndex];
                    return Padding(
                      key:     ValueKey(slide.id),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
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
                          child: const Icon(Icons.delete_outline,
                              color: Colors.white),
                        ),
                        onDismissed: (_) => onDeleteSlide(slide),
                        child: _SlideTile(
                          slide:      slide,
                          selected:   selectedSlide?.id == slide.id,
                          secondary:  secondary,
                          onTap:      () => onSelectSlide(slide),
                          onMoveUp:   item.deckIndex > 0
                              ? () => onReorderSlides(
                                    item.deckIndex, item.deckIndex - 1)
                              : null,
                          onMoveDown:
                              item.deckIndex < deck.slides.length - 1
                                  ? () => onReorderSlides(
                                        item.deckIndex,
                                        item.deckIndex + 2)
                                  : null,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── individual slide tile ──────────────────────────────────────────────────────
class _SlideTile extends StatelessWidget {
  final Slide         slide;
  final bool          selected;
  final Color         secondary;
  final VoidCallback  onTap;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _SlideTile({
    required this.slide,
    required this.selected,
    required this.secondary,
    required this.onTap,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: SlideThumbnail(
              slide:               slide,
              selected:            selected,
              selectedBorderColor: secondary,
              onTap:               onTap,
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            if (onMoveUp   != null) _Arr(icon: Icons.arrow_upward_rounded,   onTap: onMoveUp!),
            if (onMoveDown != null) _Arr(icon: Icons.arrow_downward_rounded, onTap: onMoveDown!),
          ]),
        ],
      );
}

class _Arr extends StatelessWidget {
  final IconData icon; final VoidCallback onTap;
  const _Arr({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(3),
            child: Icon(icon, size: 14, color: Colors.grey.shade400)));
}

// ── empty prompt ──────────────────────────────────────────────────────────────
class _EmptyPrompt extends StatelessWidget {
  final Color              primary;
  final Color              secondary;
  final ValueChanged<String> onAdd;
  const _EmptyPrompt({required this.primary, required this.secondary,
      required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add_photo_alternate_outlined,
              size: 64, color: primary.withValues(alpha: 0.40)),
          const SizedBox(height: 16),
          Text('Add your first slide',
              style: TextStyle(fontSize: 18,
                  color: primary.withValues(alpha: 0.70))),
          const SizedBox(height: 24),
          Wrap(spacing: 12, runSpacing: 12,
              children: SlideDefaults.slideTypes.map((type) =>
                  ElevatedButton(
                    onPressed: () => onAdd(type),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: primary.withValues(alpha: 0.10),
                        foregroundColor: primary),
                    child: Text(SlideDefaults.typeLabel(type)),
                  )).toList()),
        ]),
      );
}