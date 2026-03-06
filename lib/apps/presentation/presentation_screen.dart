// lib/apps/presentation/presentation_screen.dart
//
// Thin coordinator.  Owns all state and delegates UI to sub-files.
// SongSelect collections are managed via SongCollectionStore.
//
// New in this version:
//   • _collections Map<String, SongCollection> for fast lookup
//   • _importCollection()  — insert a SongCollection into the open deck
//   • _toggleCollection()  — expand / collapse in place
//   • _moveCollection()    — shift the whole song block up or down
//   • _removeCollection()  — delete slides + deregister collection
//   • _reorderCollSlide()  — reorder a slide inside its collection

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_state.dart';
import '../../theme.dart';
import '../../models/church_profile.dart';a

import 'models/presentation_models.dart';
import 'models/presentation_service.dart';
import 'models/slide_defaults.dart';
import 'dialogs/stream_setup_dialog.dart';
import 'dialogs/record_setup_dialog.dart';
import 'widgets/presentation_widgets.dart';
import 'views/presentations_home.dart';
import 'views/deck_editor_view.dart';
import 'views/present_view.dart';
import 'songselect/songselect_import.dart';

class PresentationScreen extends StatefulWidget {
  const PresentationScreen({super.key});

  @override
  State<PresentationScreen> createState() => _PresentationScreenState();
}

class _PresentationScreenState extends State<PresentationScreen> {
  // ── services ──────────────────────────────────────────────────────────────
  final _service = PresentationService();

  // ── core state ────────────────────────────────────────────────────────────
  List<Deck> _decks       = [];
  Deck?      _openDeck;
  Slide?     _selectedSlide;
  bool       _presenting  = false;
  bool       _isStreaming = false;
  bool       _isRecording = false;

  StreamSettings _streamSettings = StreamSettings();
  RecordSettings _recordSettings = RecordSettings();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final decks  = await _service.loadDecks();
    final stream = await _service.loadStreamSettings();
    final record = await _service.loadRecordSettings();
    await SongCollectionStore.loadAll(decks);
    setState(() {
      _decks          = decks;
      _streamSettings = stream;
      _recordSettings = record;
    });
  }

  Future<void> _saveAll() async {
    await _service.saveDecks(_decks);
    await SongCollectionStore.saveAll();
  }

  // ── deck management ───────────────────────────────────────────────────────

  void _createDeck() async {
    // Prompt for a name immediately on creation
    final name = await _promptName(context, 'New Presentation');
    if (!mounted) return;
    final deck = Deck(
      id:        const Uuid().v4(),
      name:      name ?? 'New Presentation',
      slides:    [],
      createdAt: DateTime.now(),
    );
    setState(() {
      // assign a sortOrder one higher than the current max
      final maxOrder = _decks.isEmpty
          ? -1
          : _decks.map((d) => d.sortOrder).reduce((a, b) => a > b ? a : b);
      deck.sortOrder = maxOrder + 1;
      _decks.insert(0, deck);
      _openDeck      = deck;
      _selectedSlide = null;
    });
    _service.saveDecks(_decks);
  }

  /// Shows a simple dialog that lets the user type a name.
  /// Returns null if they cancel.
  Future<String?> _promptName(BuildContext ctx, String initial) async {
    final ctrl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Name your presentation'),
        content: TextField(
          controller:  ctrl,
          autofocus:   true,
          decoration:  const InputDecoration(
              labelText: 'Presentation name',
              border:    OutlineInputBorder()),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(dctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('Skip')),
          ElevatedButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    ctrl.dispose();
    return result?.isEmpty == true ? null : result;
  }

  void _openDeckForEditing(Deck deck) {
    deck.lastUsedAt = DateTime.now();
    setState(() {
      _openDeck      = deck;
      _selectedSlide = null;
    });
    _service.saveDecks(_decks);
  }

  Future<void> _deleteDeck(Deck deck) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Delete Presentation?'),
        content: Text('Delete "${deck.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      _decks.remove(deck);
      if (_openDeck?.id == deck.id) {
        _openDeck      = null;
        _selectedSlide = null;
      }
    });
    _service.saveDecks(_decks);
  }

  void _duplicateDeck(Deck deck) {
    final copy = Deck(
      id:          const Uuid().v4(),
      name:        '${deck.name} (Copy)',
      description: deck.description,
      tags:        List.of(deck.tags),
      createdAt:   DateTime.now(),
      sortOrder:   deck.sortOrder + 1,
      slides: deck.slides
          .map((s) => Slide(
                id:        const Uuid().v4(),
                type:      s.type,
                title:     s.title,
                body:      s.body,
                reference: s.reference,
                bgColor:   s.bgColor,
                textColor: s.textColor,
                fontSize:  s.fontSize,
                style:     s.style,
              ))
          .toList(),
    );
    final idx = _decks.indexOf(deck);
    setState(() => _decks.insert(idx + 1, copy));
    _service.saveDecks(_decks);
  }

  void _onDeckChanged(Deck deck) {
    // deck is mutated in place by the home screen / edit-details sheet;
    // we just need to persist and rebuild
    setState(() {});
    _service.saveDecks(_decks);
  }

  // ── slide management ──────────────────────────────────────────────────────

  void _addSlide(String type, Color primary) {
    if (_openDeck == null) return;
    final bg = SlideDefaults.background(type, primary);
    final slide = Slide(
      id:        const Uuid().v4(),
      type:      type,
      title:     SlideDefaults.title(type),
      body:      SlideDefaults.body(type),
      bgColor:   bg,
      textColor: contrastOn(bg),
    );
    setState(() {
      _openDeck!.slides.add(slide);
      _selectedSlide = slide;
    });
    _service.saveDecks(_decks);
  }

  void _deleteSlide(Slide slide) {
    setState(() {
      _openDeck?.slides.remove(slide);
      if (_selectedSlide?.id == slide.id) _selectedSlide = null;
    });
    _service.saveDecks(_decks);
  }

  void _reorderSlides(int oldIdx, int newIdx) {
    if (newIdx > oldIdx) newIdx--;
    final slide = _openDeck!.slides.removeAt(oldIdx);
    _openDeck!.slides.insert(newIdx, slide);
    _service.saveDecks(_decks);
    setState(() {});
  }

  // ── song collection management ────────────────────────────────────────────

  void _importCollection(SongCollection collection) {
    if (_openDeck == null) return;
    setState(() {
      SongCollectionStore.insertIntoDeck(collection, _openDeck!);
    });
    _saveAll();
  }

  void _toggleCollection(String collId) {
    final coll = SongCollectionStore.find(collId);
    if (coll == null) return;
    setState(() => coll.isExpanded = !coll.isExpanded);
    SongCollectionStore.saveAll();
  }

  /// [delta] is -1 (up) or +1 (down).
  void _moveCollection(String collId, int delta) {
    if (_openDeck == null) return;
    final deck = _openDeck!;

    // Find the current first index of the collection's slides
    int firstIdx = -1;
    for (var i = 0; i < deck.slides.length; i++) {
      if (_collIdOfSlide(deck.slides[i]) == collId) {
        firstIdx = i;
        break;
      }
    }
    if (firstIdx < 0) return;

    final coll       = SongCollectionStore.find(collId);
    final groupSize  = coll?.slides.length ?? 0;
    final newFirst   = firstIdx + delta;

    // Don't go out of bounds
    if (newFirst < 0 || newFirst + groupSize > deck.slides.length) return;

    setState(() {
      SongCollectionStore.moveInDeck(collId, deck, newFirst);
    });
    _saveAll();
  }

  String? _collIdOfSlide(Slide s) {
    const tag = 'coll:';
    if (!s.reference.startsWith(tag)) return null;
    return s.reference.substring(tag.length).split('|').first;
  }

  void _removeCollection(String collId) {
    if (_openDeck == null) return;
    setState(() {
      SongCollectionStore.removeFromDeck(collId, _openDeck!);
      if (_selectedSlide != null &&
          _collIdOfSlide(_selectedSlide!) == collId) {
        _selectedSlide = null;
      }
    });
    _saveAll();
  }

  void _reorderCollSlide(String collId, int oldIdx, int newIdx) {
    if (_openDeck == null) return;
    setState(() {
      SongCollectionStore.reorderSlideInDeck(
          collId, _openDeck!, oldIdx, newIdx);
    });
    _saveAll();
  }

  // ── stream / record toggles ───────────────────────────────────────────────

  Future<void> _handleToggleStream() async {
    if (_isStreaming) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title:   const Text('Stop Live Stream?'),
          content: const Text(
              'This will end your live stream. Viewers will see the stream as ended.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Stop Stream',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm == true) {
        setState(() => _isStreaming = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:         Text('🔴 Stream ended'),
            backgroundColor: Colors.red,
            behavior:        SnackBarBehavior.floating,
          ));
        }
      }
    } else {
      final copy = _streamSettings.copyWith();
      final ok   = await showStreamSetupDialog(context, copy);
      if (ok && mounted) {
        _streamSettings = copy;
        await _service.saveStreamSettings(_streamSettings);
        setState(() => _isStreaming = true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '🟢 Streaming live to '
              '${StreamSettings.platformDefaults[_streamSettings.platform]!['name']}'),
          backgroundColor: Colors.green,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _handleToggleRecord() async {
    if (_isRecording) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title:   const Text('Stop Recording?'),
          content: const Text('This will save and finalize your recording.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Stop Recording',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm == true) {
        setState(() => _isRecording = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '⏹ Recording saved to ${_recordSettings.savePath.isNotEmpty ? _recordSettings.savePath : 'default folder'}'),
            backgroundColor: Colors.blueGrey,
            behavior:        SnackBarBehavior.floating,
            duration:        const Duration(seconds: 5),
          ));
        }
      }
    } else {
      final copy = _recordSettings.copyWith();
      final ok   = await showRecordSetupDialog(context, copy);
      if (ok && mounted) {
        _recordSettings = copy;
        await _service.saveRecordSettings(_recordSettings);
        setState(() => _isRecording = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:         Text('⏺ Recording started'),
          backgroundColor: Colors.red,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state     = context.watch<AppState>();
    final primary   = state.brandPrimary;
    final secondary = state.brandSecondary;
    final profile   = state.churchProfile;

    // Full-screen present mode
    if (_presenting && _openDeck != null) {
      return PresentView(
        deck:           _openDeck!,
        primary:        primary,
        secondary:      secondary,
        onExit:         () => setState(() => _presenting = false),
        isStreaming:    _isStreaming,
        isRecording:    _isRecording,
        onToggleStream: _handleToggleStream,
        onToggleRecord: _handleToggleRecord,
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: contrastOn(primary),
        leading: _openDeck != null
            ? IconButton(
                icon:    const Icon(Icons.arrow_back),
                tooltip: 'All Presentations',
                onPressed: () => setState(() {
                  _openDeck      = null;
                  _selectedSlide = null;
                }),
              )
            : null,
        title: Row(
          children: [
            if (profile != null)
              ChurchLogo(
                logoPath:     profile.logoPath,
                primary:      primary,
                secondary:    secondary,
                size:         32,
                borderRadius: 8,
              ),
            if (profile != null) const SizedBox(width: 10),
            if (_openDeck != null)
              // tappable name → inline rename
              GestureDetector(
                onTap: () async {
                  final newName = await _promptName(context, _openDeck!.name);
                  if (newName != null && newName != _openDeck!.name) {
                    _openDeck!.name = newName;
                    _onDeckChanged(_openDeck!);
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_openDeck!.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    Icon(Icons.edit_rounded,
                        size: 15, color: contrastOn(primary).withValues(alpha: 0.60)),
                  ],
                ),
              )
            else
              const Text('Presentation Studio',
                  style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          if (_isRecording)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: LiveBadge(label: 'REC', color: Colors.red),
            ),
          if (_isStreaming)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: LiveBadge(label: 'LIVE', color: Colors.green),
            ),
          if (_openDeck != null)
            TextButton.icon(
              onPressed: () => setState(() => _presenting = true),
              icon:  Icon(Icons.slideshow, color: contrastOn(primary)),
              label: Text('Present',
                  style: TextStyle(color: contrastOn(primary))),
            ),
          if (_openDeck == null)
            IconButton(
              icon:    const Icon(Icons.add),
              tooltip: 'New Presentation',
              onPressed: _createDeck,
            ),
        ],
      ),
      body: _openDeck == null
          ? PresentationsHome(
              decks:           _decks,
              primary:         primary,
              secondary:       secondary,
              onOpenDeck:      _openDeckForEditing,
              onNewDeck:       _createDeck,
              onDeleteDeck:    _deleteDeck,
              onDeckChanged:   _onDeckChanged,
              onDuplicateDeck: _duplicateDeck,
            )
          : DeckEditorView(
              deck:           _openDeck!,
              selectedSlide:  _selectedSlide,
              primary:        primary,
              secondary:      secondary,
              onSelectSlide:  (s) => setState(() => _selectedSlide = s),
              onAddSlide:     (t) => _addSlide(t, primary),
              onDeleteSlide:   _deleteSlide,
              onReorderSlides: _reorderSlides,
              onSlideChanged: () {
                _service.saveDecks(_decks);
                setState(() {});
              },
              onImportCollection:       _importCollection,
              onToggleCollection:       _toggleCollection,
              onMoveCollection:         _moveCollection,
              onRemoveCollection:       _removeCollection,
              onReorderCollectionSlide: _reorderCollSlide,
            ),
    );
  }
}