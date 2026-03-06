// lib/apps/presentation/presentation_screen.dart
//
// Thin coordinator.  Owns state and delegates all UI to feature sub-files:
//
//   models/
//     presentation_models.dart   – Slide, Deck, StreamSettings, RecordSettings
//     presentation_service.dart  – SharedPreferences load/save
//     slide_defaults.dart        – Default bg / title / body per slide type
//
//   dialogs/
//     stream_setup_dialog.dart   – RTMP / platform picker dialog
//     record_setup_dialog.dart   – Quality / format / path dialog
//
//   widgets/
//     presentation_widgets.dart  – LiveBadge, ControlButton, SlideThumbnail, …
//
//   views/
//     presentations_home.dart    – Deck organizer (first screen shown)
//     deck_editor_view.dart      – Three-column deck / slide / editor layout
//     slide_editor_view.dart     – Single-slide text + colour editor
//     present_view.dart          – Full-screen presentation with controls

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/app_state.dart';
import '../../screens/dashboard_screen.dart';
import '../../theme.dart';

import 'models/presentation_models.dart';
import 'models/presentation_service.dart';
import 'models/slide_defaults.dart';
import 'dialogs/stream_setup_dialog.dart';
import 'dialogs/record_setup_dialog.dart';
import 'widgets/presentation_widgets.dart';
import 'views/presentations_home.dart';
import 'views/deck_editor_view.dart';
import 'views/present_view.dart';

class PresentationScreen extends StatefulWidget {
  const PresentationScreen({super.key});

  @override
  State<PresentationScreen> createState() => _PresentationScreenState();
}

class _PresentationScreenState extends State<PresentationScreen> {
  // ── SERVICES ────────────────────────────────────────────────────────────────
  final _service = PresentationService();

  // ── STATE ────────────────────────────────────────────────────────────────────
  List<Deck> _decks        = [];
  Deck?      _openDeck;        // null → show home screen
  Slide?     _selectedSlide;
  bool       _presenting   = false;
  bool       _isStreaming  = false;
  bool       _isRecording  = false;

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
    setState(() {
      _decks          = decks;
      _streamSettings = stream;
      _recordSettings = record;
    });
  }

  // ── DECK MANAGEMENT ──────────────────────────────────────────────────────────

  void _createDeck() {
    final deck = Deck(
      id:        const Uuid().v4(),
      name:      'New Presentation',
      slides:    [],
      createdAt: DateTime.now(),
    );
    setState(() {
      _decks.insert(0, deck);
      _openDeck      = deck;
      _selectedSlide = null;
    });
    _service.saveDecks(_decks);
  }

  void _openDeckForEditing(Deck deck) {
    // Update lastUsedAt
    deck.lastUsedAt = DateTime.now();
    setState(() {
      _openDeck      = deck;
      _selectedSlide = null;
    });
    _service.saveDecks(_decks);
  }

  void _deleteDeck(Deck deck) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Presentation?'),
        content: Text('Delete "${deck.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red),
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

  Future<void> _renameDeck(Deck deck) async {
    final newName =
        await showRenameDeckDialog(context, deck.name);
    if (newName == null || newName == deck.name) return;
    setState(() => deck.name = newName);
    _service.saveDecks(_decks);
  }

  void _duplicateDeck(Deck deck) {
    final copy = Deck(
      id:        const Uuid().v4(),
      name:      '${deck.name} (Copy)',
      createdAt: DateTime.now(),
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
              ))
          .toList(),
    );
    final idx = _decks.indexOf(deck);
    setState(() => _decks.insert(idx + 1, copy));
    _service.saveDecks(_decks);
  }

  // ── SLIDE MANAGEMENT ─────────────────────────────────────────────────────────

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

  // ── STREAM / RECORD TOGGLE ────────────────────────────────────────────────────

  Future<void> _handleToggleStream() async {
    if (_isStreaming) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Stop Live Stream?'),
          content: const Text(
              'This will end your live stream. Viewers will see the stream as ended.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red),
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
          title: const Text('Stop Recording?'),
          content: const Text(
              'This will save and finalize your recording.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red),
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

  // ── BUILD ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state     = context.watch<AppState>();
    final primary   = state.brandPrimary;
    final secondary = state.brandSecondary;
    final profile   = state.churchProfile;

    // ── Full-screen present mode ─────────────────────────────────────────────
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

    // ── App shell ────────────────────────────────────────────────────────────
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: contrastOn(primary),
        // Back arrow to home when a deck is open
        leading: _openDeck != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
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
            Text(
              _openDeck != null
                  ? _openDeck!.name
                  : 'Presentation Studio',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          // Live status badges
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
          // Present button (only when a deck is open)
          if (_openDeck != null)
            TextButton.icon(
              onPressed: () => setState(() => _presenting = true),
              icon:  Icon(Icons.slideshow,
                  color: contrastOn(primary)),
              label: Text('Present',
                  style: TextStyle(color: contrastOn(primary))),
            ),
          // New deck button on home screen
          if (_openDeck == null)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'New Presentation',
              onPressed: _createDeck,
            ),
        ],
      ),
      body: _openDeck == null
          // ── HOME: deck organizer ────────────────────────────────────────
          ? PresentationsHome(
              decks:          _decks,
              primary:        primary,
              secondary:      secondary,
              onOpenDeck:     _openDeckForEditing,
              onNewDeck:      _createDeck,
              onDeleteDeck:   _deleteDeck,
              onRenameDeck:   _renameDeck,
              onDuplicateDeck: _duplicateDeck,
            )
          // ── EDITOR: three-column deck/slide/content ─────────────────────
          : DeckEditorView(
              decks:          _decks,
              selectedDeck:   _openDeck,
              selectedSlide:  _selectedSlide,
              primary:        primary,
              secondary:      secondary,
              onSelectDeck: (d) => setState(() {
                _openDeck      = d;
                _selectedSlide = null;
              }),
              onAddDeck:      _createDeck,
              onDeleteDeck:   _deleteDeck,
              onSelectSlide: (s) => setState(() => _selectedSlide = s),
              onAddSlide:    (t) => _addSlide(t, primary),
              onDeleteSlide:  _deleteSlide,
              onReorderSlides: _reorderSlides,
              onSlideChanged: () {
                _service.saveDecks(_decks);
                setState(() {});
              },
            ),
    );
  }
}