// lib/apps/presentation/presentation_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
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
import 'dialogs/deck_properties_dialog.dart';
import 'widgets/presentation_widgets.dart';
import 'views/presentations_home.dart';
import 'views/deck_editor_view.dart';
import 'views/present_view.dart';
import 'songselect/songselect_import.dart';

// ── Save status ────────────────────────────────────────────────────────────────
enum _SaveStatus { saved, saving, unsaved }

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

  // ── Save state ─────────────────────────────────────────────────────────────
  _SaveStatus _saveStatus = _SaveStatus.saved;
  Timer?      _debounce;
  Timer?      _periodicSave;
  DateTime?   _lastSaved;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadAll();
    _periodicSave = Timer.periodic(
      const Duration(seconds: 30),
      (_) { if (_saveStatus == _SaveStatus.unsaved) _flushSave(); },
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _periodicSave?.cancel();
    if (_saveStatus != _SaveStatus.saved) {
      if (_openDeck != null) _service.saveDeck(_openDeck!);
      _service.saveDecks(_decks);
    }
    super.dispose();
  }

  // ── Save helpers ───────────────────────────────────────────────────────────

  /// Mark data changed and schedule a debounced write.
  void _markDirty() {
    setState(() => _saveStatus = _SaveStatus.unsaved);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _flushSave);
  }

  /// Write the open deck (and all decks) to disk immediately.
  Future<void> _flushSave() async {
    _debounce?.cancel();
    _debounce = null;
    setState(() => _saveStatus = _SaveStatus.saving);
    try {
      // Save the open deck first for speed, then sync the full list
      if (_openDeck != null) {
        _openDeck!.lastModifiedAt = DateTime.now();
        await _service.saveDeck(_openDeck!);
      }
      await _service.saveDecks(_decks);
      await SongCollectionStore.saveAll();
      if (mounted) {
        setState(() {
          _saveStatus = _SaveStatus.saved;
          _lastSaved  = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _saveStatus = _SaveStatus.unsaved);
      _showSnack('Save failed: $e', Colors.red);
    }
  }

  // ── Unsaved-changes guard ──────────────────────────────────────────────────

  Future<bool> _guardUnsaved({String action = 'go back'}) async {
    if (_saveStatus == _SaveStatus.saved) return true;
    final result = await showDialog<_UnsavedAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UnsavedChangesDialog(action: action),
    );
    if (result == null || result == _UnsavedAction.cancel) return false;
    if (result == _UnsavedAction.save) { await _flushSave(); return true; }
    setState(() => _saveStatus = _SaveStatus.saved); // discard
    return true;
  }

  // ── Data loading ───────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    final decks  = await _service.loadDecks();
    final stream = await _service.loadStreamSettings();
    final record = await _service.loadRecordSettings();
    await SongCollectionStore.loadAll(decks);
    if (mounted) {
      setState(() {
        _decks          = decks;
        _streamSettings = stream;
        _recordSettings = record;
        _saveStatus     = _SaveStatus.saved;
        _lastSaved      = DateTime.now();
      });
    }
  }

  // ── Deck management ────────────────────────────────────────────────────────

  void _createDeck() async {
    final name = await _promptName(context, 'New Presentation');
    if (!mounted) return;
    final deck = Deck(
      id:        const Uuid().v4(),
      name:      name ?? 'New Presentation',
      slides:    [],
      createdAt: DateTime.now(),
    );
    final maxOrder = _decks.isEmpty ? -1
        : _decks.map((d) => d.sortOrder).reduce((a, b) => a > b ? a : b);
    deck.sortOrder = maxOrder + 1;
    setState(() {
      _decks.insert(0, deck);
      _openDeck      = deck;
      _selectedSlide = null;
    });
    await _flushSave();
  }

  Future<String?> _promptName(BuildContext ctx, String initial) async {
    final ctrl   = TextEditingController(text: initial);
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
    _markDirty();
  }

  Future<void> _deleteDeck(Deck deck) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Delete Presentation?'),
        content: Text('Delete "${deck.name}" and its .cpres file? This cannot be undone.'),
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
    // Remove from memory and delete the file
    await _service.deleteDeck(deck.id);
    setState(() {
      _decks.remove(deck);
      if (_openDeck?.id == deck.id) {
        _openDeck      = null;
        _selectedSlide = null;
      }
    });
    // No need to mark dirty — the file is already deleted
    setState(() => _saveStatus = _SaveStatus.saved);
  }

  Future<void> _renameDeck(Deck deck) async {
    final newName = await showRenameDeckDialog(context, deck.name);
    if (newName == null || newName == deck.name) return;
    setState(() => deck.name = newName);
    _markDirty();
  }

  void _duplicateDeck(Deck deck) {
    final copy = Deck(
      id:          const Uuid().v4(),
      name:        '${deck.name} (Copy)',
      description: deck.description,
      author:      deck.author,
      notes:       '',
      serviceDate: deck.serviceDate,
      tags:        List.of(deck.tags),
      createdAt:   DateTime.now(),
      sortOrder:   deck.sortOrder + 1,
      slides: deck.slides.map((s) => Slide(
            id:        const Uuid().v4(),
            type:      s.type,
            title:     s.title,
            body:      s.body,
            reference: s.reference,
            bgColor:   s.bgColor,
            textColor: s.textColor,
            fontSize:  s.fontSize,
            style:     s.style,
          )).toList(),
    );
    final idx = _decks.indexOf(deck);
    setState(() => _decks.insert(idx + 1, copy));
    _markDirty();
  }

  // ── Properties ─────────────────────────────────────────────────────────────

  Future<void> _showProperties(Deck deck) async {
    final state   = context.read<AppState>();
    final updated = await showDeckPropertiesDialog(
      context,
      deck:    deck,
      primary: state.brandPrimary,
    );
    if (updated == null || !mounted) return;

    // Apply all updated fields to the live deck object
    final idx = _decks.indexWhere((d) => d.id == deck.id);
    setState(() {
      deck.name           = updated.name;
      deck.description    = updated.description;
      deck.author         = updated.author;
      deck.notes          = updated.notes;
      deck.serviceDate    = updated.serviceDate;
      deck.tags           = updated.tags;
      deck.isPinned       = updated.isPinned;
      deck.isTemplate     = updated.isTemplate;
      deck.lastModifiedAt = updated.lastModifiedAt;
      if (idx >= 0) _decks[idx] = deck;
      // If the open deck was edited, reflect in _openDeck reference
      if (_openDeck?.id == deck.id) _openDeck = deck;
    });
    await _flushSave();
    _showSnack('Properties saved', Colors.green.shade700);
  }

  // ── Export / Import ─────────────────────────────────────────────────────────

  Future<void> _exportDeck(Deck deck) async {
    try {
      // Ask user where to save
      final outputFile = await FilePicker.platform.saveFile(
        dialogTitle:   'Export "${deck.name}"',
        fileName:      '${Deck.safeFileName(deck.name)}.cpres',
        allowedExtensions: ['cpres'],
        type:          FileType.custom,
      );
      if (outputFile == null || !mounted) return;

      await _service.exportDeck(deck, outputFile);
      _showSnack('Exported to $outputFile', Colors.green.shade700,
          duration: const Duration(seconds: 5));
    } catch (e) {
      _showSnack('Export failed: $e', Colors.red);
    }
  }

  Future<void> _importDeck() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle:       'Import Presentation',
        allowedExtensions: ['cpres'],
        type:              FileType.custom,
        allowMultiple:     false,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final path = result.files.first.path;
      if (path == null) return;

      final imported = await _service.importDeck(path);
      setState(() {
        // Avoid duplicates — replace if same id already exists
        _decks.removeWhere((d) => d.id == imported.id);
        _decks.insert(0, imported);
      });
      _showSnack('Imported "${imported.name}"', Colors.green.shade700);
    } catch (e) {
      _showSnack('Import failed: $e', Colors.red);
    }
  }

  // ── Slide management ───────────────────────────────────────────────────────

  void _addSlide(String type, Color primary) {
    if (_openDeck == null) return;
    final bg    = SlideDefaults.background(type, primary);
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
    _markDirty();
  }

  void _deleteSlide(Slide slide) {
    if (_openDeck != null) {
      for (final g in _openDeck!.groups) g.slideIds.remove(slide.id);
    }
    setState(() {
      _openDeck?.slides.remove(slide);
      if (_selectedSlide?.id == slide.id) _selectedSlide = null;
    });
    _markDirty();
  }

  void _reorderSlides(int oldIdx, int newIdx) {
    if (newIdx > oldIdx) newIdx--;
    final slide = _openDeck!.slides.removeAt(oldIdx);
    _openDeck!.slides.insert(newIdx, slide);
    setState(() {});
    _markDirty();
  }

  // ── Group management ───────────────────────────────────────────────────────

  void _createGroup(SlideGroup g) {
    if (_openDeck == null) return;
    setState(() => _openDeck!.groups.add(g));
    _markDirty();
  }

  void _updateGroup(SlideGroup updated) {
    if (_openDeck == null) return;
    final idx = _openDeck!.groups.indexWhere((g) => g.id == updated.id);
    if (idx < 0) return;
    setState(() => _openDeck!.groups[idx] = updated);
    _markDirty();
  }

  void _deleteGroup(String groupId) {
    if (_openDeck == null) return;
    setState(() => _openDeck!.groups.removeWhere((g) => g.id == groupId));
    _markDirty();
  }

  void _addSlideToGroup(String groupId, String slideId) {
    if (_openDeck == null) return;
    final g = _openDeck!.groups.firstWhere((g) => g.id == groupId,
        orElse: () => throw StateError('Group not found'));
    if (g.slideIds.contains(slideId)) return;
    setState(() => g.slideIds.add(slideId));
    _markDirty();
  }

  void _removeSlideFromGroup(String groupId, String slideId) {
    if (_openDeck == null) return;
    final g = _openDeck!.groups.firstWhere((g) => g.id == groupId,
        orElse: () => throw StateError('Group not found'));
    setState(() => g.slideIds.remove(slideId));
    _markDirty();
  }

  // ── Scripture import ───────────────────────────────────────────────────────

  Future<void> _handleImportScripture() async {
    if (_openDeck == null || !mounted) return;
    final state = context.read<AppState>();
    final slide = await showVersePickerDialog(
      context,
      primary:   state.brandPrimary,
      secondary: state.brandSecondary,
    );
    if (slide != null && mounted && _openDeck != null) {
      setState(() {
        _openDeck!.slides.add(slide);
        _selectedSlide = slide;
      });
      _markDirty();
    }
  }

  // ── Song collection management ─────────────────────────────────────────────

  void _importCollection(SongCollection collection) {
    if (_openDeck == null) return;
    setState(() => SongCollectionStore.insertIntoDeck(collection, _openDeck!));
    _markDirty();
  }

  void _toggleCollection(String collId) {
    final coll = SongCollectionStore.find(collId);
    if (coll == null) return;
    setState(() => coll.isExpanded = !coll.isExpanded);
    _markDirty();
  }

  void _moveCollection(String collId, int delta) {
    if (_openDeck == null) return;
    final deck     = _openDeck!;
    int   firstIdx = -1;
    for (var i = 0; i < deck.slides.length; i++) {
      if (_collIdOfSlide(deck.slides[i]) == collId) { firstIdx = i; break; }
    }
    if (firstIdx < 0) return;
    final coll      = SongCollectionStore.find(collId);
    final groupSize = coll?.slides.length ?? 0;
    final newFirst  = firstIdx + delta;
    if (newFirst < 0 || newFirst + groupSize > deck.slides.length) return;
    setState(() => SongCollectionStore.moveInDeck(collId, deck, newFirst));
    _markDirty();
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
      if (_selectedSlide != null && _collIdOfSlide(_selectedSlide!) == collId) {
        _selectedSlide = null;
      }
    });
    _markDirty();
  }

  void _reorderCollSlide(String collId, int oldIdx, int newIdx) {
    if (_openDeck == null) return;
    setState(() =>
        SongCollectionStore.reorderSlideInDeck(collId, _openDeck!, oldIdx, newIdx));
    _markDirty();
  }

  // ── Stream / record ────────────────────────────────────────────────────────

  Future<void> _handleToggleStream() async {
    if (_isStreaming) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title:   const Text('Stop Live Stream?'),
          content: const Text('This will end your live stream.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
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
        _showSnack('🔴 Stream ended', Colors.red);
      }
    } else {
      final copy = _streamSettings.copyWith();
      final ok   = await showStreamSetupDialog(context, copy);
      if (ok && mounted) {
        _streamSettings = copy;
        await _service.saveStreamSettings(_streamSettings);
        setState(() => _isStreaming = true);
        _showSnack(
            '🟢 Streaming live to '
            '${StreamSettings.platformDefaults[_streamSettings.platform]!['name']}',
            Colors.green);
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
            TextButton(onPressed: () => Navigator.pop(ctx, false),
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
        _showSnack(
            '⏹ Recording saved to '
            '${_recordSettings.savePath.isNotEmpty ? _recordSettings.savePath : 'default folder'}',
            Colors.blueGrey,
            duration: const Duration(seconds: 5));
      }
    } else {
      final copy = _recordSettings.copyWith();
      final ok   = await showRecordSetupDialog(context, copy);
      if (ok && mounted) {
        _recordSettings = copy;
        await _service.saveRecordSettings(_recordSettings);
        setState(() => _isRecording = true);
        _showSnack('⏺ Recording started', Colors.red);
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _showSnack(String msg, Color bg, {Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg),
      backgroundColor: bg,
      behavior:        SnackBarBehavior.floating,
      duration:        duration ?? const Duration(seconds: 3),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
                icon:    const Icon(Icons.arrow_back),
                tooltip: 'All Presentations',
                onPressed: () async {
                  final ok = await _guardUnsaved(action: 'leave this deck');
                  if (!mounted || !ok) return;
                  setState(() { _openDeck = null; _selectedSlide = null; });
                },
              )
            : null,
        title: Row(
          children: [
            if (profile != null) ...[
              ChurchLogo(
                logoPath:     profile.logoPath,
                primary:      primary,
                secondary:    secondary,
                size:         32,
                borderRadius: 8,
              ),
              const SizedBox(width: 10),
            ],
            if (_openDeck != null)
              Flexible(
                child: GestureDetector(
                  onTap: () async {
                    final newName = await _promptName(context, _openDeck!.name);
                    if (newName != null && newName != _openDeck!.name) {
                      setState(() => _openDeck!.name = newName);
                      _markDirty();
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(_openDeck!.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.edit_rounded,
                          size: 15,
                          color: contrastOn(primary).withValues(alpha: 0.55)),
                    ],
                  ),
                ),
              )
            else
              const Text('Presentation Studio',
                  style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          // Save status indicator (only when editing a deck)
          if (_openDeck != null)
            _SaveIndicator(
              status:    _saveStatus,
              lastSaved: _lastSaved,
              primary:   primary,
              onSave:    _saveStatus == _SaveStatus.unsaved ? _flushSave : null,
            ),

          // Properties button for the open deck
          if (_openDeck != null)
            IconButton(
              icon:    const Icon(Icons.info_outline_rounded),
              tooltip: 'Presentation Properties',
              color:   contrastOn(primary).withValues(alpha: 0.80),
              onPressed: () => _showProperties(_openDeck!),
            ),

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
              onRenameDeck:    _renameDeck,
              onDuplicateDeck: _duplicateDeck,
              onProperties:    _showProperties,
              onExportDeck:    _exportDeck,
              onImportDeck:    _importDeck,
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
                _markDirty();
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

// ══════════════════════════════════════════════════════════════════════════════
// SAVE STATUS INDICATOR
// ══════════════════════════════════════════════════════════════════════════════
class _SaveIndicator extends StatelessWidget {
  final _SaveStatus   status;
  final DateTime?     lastSaved;
  final Color         primary;
  final VoidCallback? onSave;

  const _SaveIndicator({
    required this.status,
    required this.primary,
    required this.lastSaved,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final fg        = contrastOn(primary);
    final isUnsaved = status == _SaveStatus.unsaved;
    final isSaving  = status == _SaveStatus.saving;

    final label = switch (status) {
      _SaveStatus.saved   => 'Saved',
      _SaveStatus.saving  => 'Saving…',
      _SaveStatus.unsaved => 'Unsaved',
    };
    final iconColor = switch (status) {
      _SaveStatus.saved   => Colors.greenAccent.shade400,
      _SaveStatus.saving  => Colors.white70,
      _SaveStatus.unsaved => Colors.orangeAccent,
    };

    return Tooltip(
      message: isSaving   ? 'Saving…'
              : isUnsaved  ? 'Tap to save now'
              : lastSaved != null ? 'Last saved ${_timeAgo(lastSaved!)}' : 'Saved',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onSave,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSaving)
                SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fg.withValues(alpha: 0.70)))
              else
                Icon(
                  switch (status) {
                    _SaveStatus.saved   => Icons.cloud_done_rounded,
                    _SaveStatus.saving  => Icons.cloud_upload_rounded,
                    _SaveStatus.unsaved => Icons.cloud_off_rounded,
                  },
                  size: 16, color: iconColor,
                ),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize:   11,
                      color:      isUnsaved
                          ? Colors.orangeAccent
                          : fg.withValues(alpha: 0.80),
                      fontWeight: isUnsaved
                          ? FontWeight.bold : FontWeight.normal)),
              if (isUnsaved) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color:        Colors.orangeAccent.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                        color: Colors.orangeAccent.withValues(alpha: 0.55)),
                  ),
                  child: const Text('Save now',
                      style: TextStyle(
                          fontSize: 9, color: Colors.orangeAccent,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// UNSAVED CHANGES DIALOG
// ══════════════════════════════════════════════════════════════════════════════
enum _UnsavedAction { save, discard, cancel }

class _UnsavedChangesDialog extends StatelessWidget {
  final String action;
  const _UnsavedChangesDialog({required this.action});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon:  const Icon(Icons.warning_amber_rounded,
          color: Colors.orange, size: 40),
      title: const Text('Unsaved Changes',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold)),
      content: Text(
        'You have unsaved changes. What would you like to do before you $action?',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, _UnsavedAction.discard),
              icon:  const Icon(Icons.delete_outline_rounded,
                  color: Colors.red, size: 16),
              label: const Text('Discard',
                  style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side:    const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, _UnsavedAction.cancel),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              child: const Text('Stay here'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, _UnsavedAction.save),
              icon:  const Icon(Icons.save_rounded, size: 16),
              label: const Text('Save & Go',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ]),
      ],
    );
  }
}