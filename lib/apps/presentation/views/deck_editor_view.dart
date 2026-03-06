// lib/apps/presentation/views/deck_editor_view.dart
//
// The three-column editor: deck list | slide list | slide editor.
// This is the main working area once a user has selected or created a deck.
import 'package:flutter/material.dart';
import '../models/presentation_models.dart';
import '../models/slide_defaults.dart';
import '../widgets/presentation_widgets.dart';
import 'slide_editor_view.dart';

class DeckEditorView extends StatelessWidget {
  final List<Deck>             decks;
  final Deck?                  selectedDeck;
  final Slide?                 selectedSlide;
  final Color                  primary;
  final Color                  secondary;
  final ValueChanged<Deck>     onSelectDeck;
  final VoidCallback           onAddDeck;
  final ValueChanged<Deck>     onDeleteDeck;
  final ValueChanged<Slide>    onSelectSlide;
  final ValueChanged<String>   onAddSlide;
  final ValueChanged<Slide>    onDeleteSlide;
  final Function(int, int)     onReorderSlides;
  final VoidCallback           onSlideChanged;

  const DeckEditorView({
    super.key,
    required this.decks,
    required this.selectedDeck,
    required this.selectedSlide,
    required this.primary,
    required this.secondary,
    required this.onSelectDeck,
    required this.onAddDeck,
    required this.onDeleteDeck,
    required this.onSelectSlide,
    required this.onAddSlide,
    required this.onDeleteSlide,
    required this.onReorderSlides,
    required this.onSlideChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── DECK LIST ──────────────────────────────────────────────────────
        SizedBox(
          width: 220,
          child: _DeckListPanel(
            decks:        decks,
            selectedDeck: selectedDeck,
            primary:      primary,
            onSelect:     onSelectDeck,
            onAdd:        onAddDeck,
            onDelete:     onDeleteDeck,
          ),
        ),
        const VerticalDivider(width: 1),

        // ── SLIDE LIST ─────────────────────────────────────────────────────
        if (selectedDeck != null) ...[
          SizedBox(
            width: 190,
            child: _SlideListPanel(
              deck:          selectedDeck!,
              selectedSlide: selectedSlide,
              primary:       primary,
              secondary:     secondary,
              onSelect:      onSelectSlide,
              onAdd:         onAddSlide,
              onDelete:      onDeleteSlide,
              onReorder:     onReorderSlides,
            ),
          ),
          const VerticalDivider(width: 1),
        ],

        // ── EDITOR / PLACEHOLDER ───────────────────────────────────────────
        Expanded(
          child: selectedSlide != null
              ? SlideEditorView(
                  slide:     selectedSlide!,
                  primary:   primary,
                  secondary: secondary,
                  onChanged: onSlideChanged,
                )
              : selectedDeck != null
                  ? _DeckEmptyPrompt(
                      primary:   primary,
                      secondary: secondary,
                      onAdd:     onAddSlide,
                    )
                  : EmptyStateMessage(
                      icon:    Icons.slideshow,
                      message: 'Select or create a deck to get started',
                      color:   primary,
                    ),
        ),
      ],
    );
  }
}

// ── DECK LIST PANEL ───────────────────────────────────────────────────────────
class _DeckListPanel extends StatelessWidget {
  final List<Deck>         decks;
  final Deck?              selectedDeck;
  final Color              primary;
  final ValueChanged<Deck> onSelect;
  final VoidCallback       onAdd;
  final ValueChanged<Deck> onDelete;

  const _DeckListPanel({
    required this.decks,
    required this.selectedDeck,
    required this.primary,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onAdd,
              icon:  const Icon(Icons.add),
              label: const Text('New Deck'),
              style: ElevatedButton.styleFrom(backgroundColor: primary),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: decks.isEmpty
              ? const EmptyStateMessage(
                  icon:    Icons.folder_open,
                  message: 'No presentations yet',
                  color:   Colors.grey,
                )
              : ListView.builder(
                  itemCount: decks.length,
                  itemBuilder: (_, i) {
                    final deck = decks[i];
                    final sel  = selectedDeck?.id == deck.id;
                    return ListTile(
                      selected:          sel,
                      selectedTileColor: primary.withValues(alpha: 0.10),
                      leading: Icon(Icons.slideshow,
                          color: sel ? primary : Colors.grey),
                      title: Text(
                        deck.name,
                        style: TextStyle(
                          fontWeight: sel
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        '${deck.slideCount} slides',
                        style: const TextStyle(fontSize: 11),
                      ),
                      onTap: () => onSelect(deck),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: Colors.red),
                        onPressed: () => onDelete(deck),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── SLIDE LIST PANEL ──────────────────────────────────────────────────────────
class _SlideListPanel extends StatelessWidget {
  final Deck               deck;
  final Slide?             selectedSlide;
  final Color              primary;
  final Color              secondary;
  final ValueChanged<Slide>    onSelect;
  final ValueChanged<String>   onAdd;
  final ValueChanged<Slide>    onDelete;
  final Function(int, int)     onReorder;

  const _SlideListPanel({
    required this.deck,
    required this.selectedSlide,
    required this.primary,
    required this.secondary,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Add slide button
        Padding(
          padding: const EdgeInsets.all(8),
          child: PopupMenuButton<String>(
            onSelected: onAdd,
            itemBuilder: (_) => SlideDefaults.slideTypes
                .map((t) => PopupMenuItem(
                      value: t,
                      child: Text(SlideDefaults.typeLabel(t)),
                    ))
                .toList(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color:        primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: primary.withValues(alpha: 0.30)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, color: primary, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Add Slide',
                    style: TextStyle(
                      color:      primary,
                      fontWeight: FontWeight.bold,
                      fontSize:   13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: deck.slides.isEmpty
              ? const EmptyStateMessage(
                  icon:    Icons.add_photo_alternate_outlined,
                  message: 'No slides yet',
                  color:   Colors.grey,
                )
              : ReorderableListView.builder(
                  itemCount: deck.slides.length,
                  onReorder: onReorder,
                  itemBuilder: (_, i) {
                    final s = deck.slides[i];
                    return Padding(
                      key:     ValueKey(s.id),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: SlideThumbnail(
                        slide:             s,
                        selected:          selectedSlide?.id == s.id,
                        selectedBorderColor: secondary,
                        onTap: () => onSelect(s),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── EMPTY DECK PROMPT ─────────────────────────────────────────────────────────
class _DeckEmptyPrompt extends StatelessWidget {
  final Color              primary;
  final Color              secondary;
  final ValueChanged<String> onAdd;

  const _DeckEmptyPrompt({
    required this.primary,
    required this.secondary,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined,
              size: 64, color: primary.withValues(alpha: 0.40)),
          const SizedBox(height: 16),
          Text(
            'Add your first slide',
            style: TextStyle(
              fontSize: 18,
              color:    primary.withValues(alpha: 0.70),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12, runSpacing: 12,
            children: SlideDefaults.slideTypes.map((type) {
              return ElevatedButton(
                onPressed: () => onAdd(type),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary.withValues(alpha: 0.10),
                  foregroundColor: primary,
                ),
                child: Text(SlideDefaults.typeLabel(type)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}