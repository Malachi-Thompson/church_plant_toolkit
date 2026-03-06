// lib/apps/presentation/presentation_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_state.dart';
import '../../models/church_profile.dart';
import '../../services/bible_service.dart';
import '../../theme.dart';

import 'models/presentation_models.dart';
import 'models/presentation_service.dart';
import 'models/slide_defaults.dart';
import 'models/slide_group.dart';
import 'dialogs/stream_setup_dialog.dart';
import 'dialogs/record_setup_dialog.dart';
import 'dialogs/verse_picker_dialog.dart';
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
  final _service = PresentationService();

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
    final name = await _promptName(context, 'New Presentation');
    if (!mounted) return;
    final deck = Deck(
      id:        const Uuid().v4(),
      name:      name ?? 'New Presentation',
      slides:    [],
      createdAt: DateTime.now(),
    );
    final maxOrder = _decks.isEmpty
        ? -1
        : _decks.map((d) => d.sortOrder).reduce((a, b) => a > b ? a : b);
    deck.sortOrder = maxOrder + 1;
    setState(() {
      _decks.insert(0, deck);
      _openDeck      = deck;
      _selectedSlide = null;
    });
    _service.saveDecks(_decks);
  }

  Future<String?> _promptName(BuildContext ctx, String initial) async {
    final ctrl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Name your presentation'),
        content: TextField(
          controller:         ctrl,
          autofocus:          true,
          decoration: const InputDecoration(
            labelText: 'Presentation name',
            border:    OutlineInputBorder(),
          ),
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
                  style: TextStyle(color: Colors.white))),
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
    final newName = await showRenameDeckDialog(context, deck.name);
    if (newName == null || newName == deck.name) return;
    setState(() => deck.name = newName);
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
      // Groups are not copied — slide IDs would differ
    );
    final idx = _decks.indexOf(deck);
    setState(() => _decks.insert(idx + 1, copy));
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
    // Also remove from any groups
    if (_openDeck != null) {
      for (final g in _openDeck!.groups) {
        g.slideIds.remove(slide.id);
      }
    }
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

  // ── slide group management ────────────────────────────────────────────────

  void _createGroup(SlideGroup group) {
    if (_openDeck == null) return;
    setState(() => _openDeck!.groups.add(group));
    _service.saveDecks(_decks);
  }

  void _updateGroup(SlideGroup updated) {
    if (_openDeck == null) return;
    final idx = _openDeck!.groups.indexWhere((g) => g.id == updated.id);
    if (idx < 0) return;
    setState(() => _openDeck!.groups[idx] = updated);
    _service.saveDecks(_decks);
  }

  void _deleteGroup(String groupId) {
    if (_openDeck == null) return;
    setState(() =>
        _openDeck!.groups.removeWhere((g) => g.id == groupId));
    _service.saveDecks(_decks);
  }

  void _addSlideToGroup(String groupId, String slideId) {
    if (_openDeck == null) return;
    final group = _openDeck!.groups.firstWhere((g) => g.id == groupId,
        orElse: () => throw StateError('Group not found'));
    if (group.slideIds.contains(slideId)) return;
    setState(() => group.slideIds.add(slideId));
    _service.saveDecks(_decks);
  }

  void _removeSlideFromGroup(String groupId, String slideId) {
    if (_openDeck == null) return;
    final group = _openDeck!.groups.firstWhere((g) => g.id == groupId,
        orElse: () => throw StateError('Group not found'));
    setState(() => group.slideIds.remove(slideId));
    _service.saveDecks(_decks);
  }

  // ── scripture import ──────────────────────────────────────────────────────

  Future<void> _handleImportScripture() async {
    if (_openDeck == null || !mounted) return;
    final state     = context.read<AppState>();
    final primary   = state.brandPrimary;
    final secondary = state.brandSecondary;

    final slide = await showVersePickerDialog(
      context,
      primary:   primary,
      secondary: secondary,
    );
    if (slide != null && mounted && _openDeck != null) {
      setState(() {
        _openDeck!.slides.add(slide);
        _selectedSlide = slide;
      });
      _service.saveDecks(_decks);
    }
  }

  // ── song collection management ────────────────────────────────────────────

  void _importCollection(SongCollection collection) {
    if (_openDeck == null) return;
    setState(() => SongCollectionStore.insertIntoDeck(collection, _openDeck!));
    _saveAll();
  }

  void _toggleCollection(String collId) {
    final coll = SongCollectionStore.find(collId);
    if (coll == null) return;
    setState(() => coll.isExpanded = !coll.isExpanded);
    SongCollectionStore.saveAll();
  }

  void _moveCollection(String collId, int delta) {
    if (_openDeck == null) return;
    final deck = _openDeck!;
    int firstIdx = -1;
    for (var i = 0; i < deck.slides.length; i++) {
      if (_collIdOfSlide(deck.slides[i]) == collId) {
        firstIdx = i;
        break;
      }
    }
    if (firstIdx < 0) return;
    final coll      = SongCollectionStore.find(collId);
    final groupSize = coll?.slides.length ?? 0;
    final newFirst  = firstIdx + delta;
    if (newFirst < 0 || newFirst + groupSize > deck.slides.length) return;
    setState(() => SongCollectionStore.moveInDeck(collId, deck, newFirst));
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
    setState(() => SongCollectionStore.reorderSlideInDeck(
        collId, _openDeck!, oldIdx, newIdx));
    _saveAll();
  }

  // ── stream / record ───────────────────────────────────────────────────────

  Future<void> _handleToggleStream() async {
    if (_isStreaming) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title:   const Text('Stop Live Stream?'),
          content: const Text('This will end your live stream.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Stop Stream',
                    style: TextStyle(color: Colors.white))),
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
                    style: TextStyle(color: Colors.white))),
          ],
        ),
      );
      if (confirm == true) {
        setState(() => _isRecording = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '⏹ Recording saved to '
                '${_recordSettings.savePath.isNotEmpty ? _recordSettings.savePath : 'default folder'}'),
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
                icon:      const Icon(Icons.arrow_back),
                tooltip:   'All Presentations',
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
              GestureDetector(
                onTap: () async {
                  final newName =
                      await _promptName(context, _openDeck!.name);
                  if (newName != null && newName != _openDeck!.name) {
                    setState(() => _openDeck!.name = newName);
                    _service.saveDecks(_decks);
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_openDeck!.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    Icon(Icons.edit_rounded,
                        size:  15,
                        color: contrastOn(primary)
                            .withValues(alpha: 0.60)),
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
              icon:      const Icon(Icons.add),
              tooltip:   'New Presentation',
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
              onRenameDeck:    _renameDeck,
              onDuplicateDeck: _duplicateDeck,
            )
          : DeckEditorView(
              deck:                    _openDeck!,
              selectedSlide:           _selectedSlide,
              primary:                 primary,
              secondary:               secondary,
              onSelectSlide:           (s) => setState(() => _selectedSlide = s),
              onAddSlide:              (t) => _addSlide(t, primary),
              onDeleteSlide:           _deleteSlide,
              onReorderSlides:         _reorderSlides,
              onSlideChanged: () {
                _service.saveDecks(_decks);
                setState(() {});
              },
              onImportScripture:       _handleImportScripture,
              onCreateGroup:           _createGroup,
              onUpdateGroup:           _updateGroup,
              onDeleteGroup:           _deleteGroup,
              onAddSlideToGroup:       _addSlideToGroup,
              onRemoveSlideFromGroup:  _removeSlideFromGroup,
              onImportCollection:      _importCollection,
              onToggleCollection:      _toggleCollection,
              onMoveCollection:        _moveCollection,
              onRemoveCollection:      _removeCollection,
              onReorderCollectionSlide: _reorderCollSlide,
            ),
    );
  }
}