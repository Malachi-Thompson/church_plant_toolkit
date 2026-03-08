// lib/apps/presentation/models/presentation_state.dart
//
// PresentationState is a ChangeNotifier that lives at the APP level (not inside
// PresentationScreen). Because it is provided above the navigator, it survives
// every navigation — going to the main app and back never destroys it.
//
// How to wire it up in main.dart / your app root:
// ─────────────────────────────────────────────────
//   ChangeNotifierProvider(
//     create: (_) => PresentationState()..init(),
//     child: YourApp(),
//   )
//
// How to use it in PresentationScreen:
// ─────────────────────────────────────
//   final ps = context.watch<PresentationState>();
//   // read:  ps.decks, ps.openDeck, ps.selectedSlide, ps.saveStatus …
//   // write: ps.openDeckForEditing(deck), ps.markDirty(), ps.flushSave() …

import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'presentation_models.dart';
import 'presentation_service.dart';
import 'slide_defaults.dart';
import 'slide_group.dart';
import '../songselect/songselect_import.dart';

enum SaveStatus { saved, saving, unsaved }

class PresentationState extends ChangeNotifier {
  final _service = PresentationService();

  // ── Public state ───────────────────────────────────────────────────────────
  List<Deck>     decks          = [];
  Deck?          openDeck;
  Slide?         selectedSlide;
  bool           presenting     = false;
  bool           isStreaming    = false;
  bool           isRecording    = false;
  StreamSettings streamSettings = StreamSettings();
  RecordSettings recordSettings = RecordSettings();

  SaveStatus  saveStatus = SaveStatus.saved;
  DateTime?   lastSaved;
  bool        loaded     = false;
  bool        loading    = false;
  String?     loadError;

  // ── Internal ───────────────────────────────────────────────────────────────
  Timer? _debounce;
  Timer? _periodic;

  // ── Init / dispose ─────────────────────────────────────────────────────────

  /// Call once from your provider's create callback.
  Future<void> init() async {
    await _loadAll();
    _periodic = Timer.periodic(
      const Duration(seconds: 30),
      (_) { if (saveStatus == SaveStatus.unsaved) flushSave(); },
    );
  }

  @override
  void dispose() {
    _periodic?.cancel();
    _debounce?.cancel();
    // Best-effort flush on dispose
    if (saveStatus != SaveStatus.saved) {
      if (openDeck != null) _service.saveDeck(openDeck!);
      _service.saveDecks(decks);
      SongCollectionStore.saveAll();
    }
    super.dispose();
  }

  // ── Load ───────────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    if (loading) return;
    loading   = true;
    loadError = null;
    notifyListeners();

    try {
      final d = await _service.loadDecks();
      final s = await _service.loadStreamSettings();
      final r = await _service.loadRecordSettings();
      await SongCollectionStore.loadAll(d);

      decks          = d;
      streamSettings = s;
      recordSettings = r;
      saveStatus     = SaveStatus.saved;
      lastSaved      = DateTime.now();
    } catch (e) {
      loadError = e.toString();
      dev.log('[PresentationState] load error: $e');
    } finally {
      loading = false;
      loaded  = true;
      notifyListeners();
    }
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  /// Schedule a debounced save (use for continuous edits like typing).
  void markDirty() {
    saveStatus = SaveStatus.unsaved;
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), flushSave);
  }

  /// Immediately persist everything to the DB.
  Future<void> flushSave() async {
    _debounce?.cancel();
    _debounce  = null;
    saveStatus = SaveStatus.saving;
    notifyListeners();

    try {
      if (openDeck != null) {
        openDeck!.lastModifiedAt = DateTime.now();
        await _service.saveDeck(openDeck!);
      }
      await _service.saveDecks(decks);
      await SongCollectionStore.saveAll();
      saveStatus = SaveStatus.saved;
      lastSaved  = DateTime.now();
    } catch (e) {
      saveStatus = SaveStatus.unsaved;
      dev.log('[PresentationState] save error: $e');
      rethrow; // let the screen show a snackbar
    } finally {
      notifyListeners();
    }
  }

  // ── Deck CRUD ──────────────────────────────────────────────────────────────

  Future<Deck> createDeck(String name) async {
    final maxOrder = decks.isEmpty
        ? 0
        : decks.map((d) => d.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    final deck = Deck(
      id:        const Uuid().v4(),
      name:      name.isEmpty ? 'New Presentation' : name,
      slides:    [],
      createdAt: DateTime.now(),
      sortOrder: maxOrder,
    );
    decks.insert(0, deck);
    openDeck      = deck;
    selectedSlide = null;
    notifyListeners();
    await flushSave(); // immediate — never lose a brand-new deck
    return deck;
  }

  Future<void> deleteDeck(Deck deck) async {
    await _service.deleteDeck(deck.id);
    decks.remove(deck);
    if (openDeck?.id == deck.id) {
      openDeck      = null;
      selectedSlide = null;
    }
    saveStatus = SaveStatus.saved;
    notifyListeners();
  }

  Future<void> renameDeck(Deck deck, String newName) async {
    deck.name = newName;
    notifyListeners();
    await flushSave();
  }

  void duplicateDeck(Deck deck) {
    final copy = Deck(
      id:          const Uuid().v4(),
      name:        '${deck.name} (Copy)',
      description: deck.description,
      author:      deck.author,
      tags:        List.of(deck.tags),
      serviceDate: deck.serviceDate,
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
    final idx = decks.indexOf(deck);
    decks.insert(idx + 1, copy);
    notifyListeners();
    flushSave();
  }

  Future<void> updateDeckProperties(Deck updated) async {
    final idx = decks.indexWhere((d) => d.id == updated.id);
    if (idx >= 0) decks[idx] = updated;
    if (openDeck?.id == updated.id) openDeck = updated;
    notifyListeners();
    await flushSave();
  }

  void openDeckForEditing(Deck deck) {
    deck.lastUsedAt = DateTime.now();
    openDeck        = deck;
    selectedSlide   = null;
    notifyListeners();
    _service.saveDeck(deck); // fire-and-forget for lastUsedAt
  }

  void closeOpenDeck() {
    openDeck      = null;
    selectedSlide = null;
    notifyListeners();
  }

  // ── Slide CRUD ─────────────────────────────────────────────────────────────

  void addSlide(String type, {required Color primary}) {
    if (openDeck == null) return;
    final bg = SlideDefaults.background(type, primary);
    final slide = Slide(
      id:        const Uuid().v4(),
      type:      type,
      title:     SlideDefaults.title(type),
      body:      SlideDefaults.body(type),
      bgColor:   bg,
      textColor: contrastOn(bg),
    );
    openDeck!.slides.add(slide);
    selectedSlide = slide;
    markDirty();
  }

  void deleteSlide(Slide slide) {
    openDeck?.groups.forEach((g) => g.slideIds.remove(slide.id));
    openDeck?.slides.remove(slide);
    if (selectedSlide?.id == slide.id) selectedSlide = null;
    markDirty();
  }

  void reorderSlides(int oldIdx, int newIdx) {
    if (openDeck == null) return;
    if (newIdx > oldIdx) newIdx--;
    final slide = openDeck!.slides.removeAt(oldIdx);
    openDeck!.slides.insert(newIdx, slide);
    markDirty();
  }

  void selectSlide(Slide? slide) {
    selectedSlide = slide;
    notifyListeners();
  }

  void notifySlideChanged() => markDirty();

  // ── Group CRUD ─────────────────────────────────────────────────────────────

  void createGroup(SlideGroup g) {
    openDeck?.groups.add(g);
    markDirty();
  }

  void updateGroup(SlideGroup updated) {
    if (openDeck == null) return;
    final idx = openDeck!.groups.indexWhere((g) => g.id == updated.id);
    if (idx >= 0) openDeck!.groups[idx] = updated;
    markDirty();
  }

  void deleteGroup(String groupId) {
    openDeck?.groups.removeWhere((g) => g.id == groupId);
    markDirty();
  }

  void addSlideToGroup(String groupId, String slideId) {
    final g = openDeck?.groups.firstWhere((g) => g.id == groupId,
        orElse: () => throw StateError('Group not found'));
    if (g != null && !g.slideIds.contains(slideId)) {
      g.slideIds.add(slideId);
      markDirty();
    }
  }

  void removeSlideFromGroup(String groupId, String slideId) {
    openDeck?.groups
        .firstWhere((g) => g.id == groupId,
            orElse: () => throw StateError('Group not found'))
        .slideIds
        .remove(slideId);
    markDirty();
  }

  // ── Song collections ───────────────────────────────────────────────────────

  void importCollection(SongCollection collection) {
    if (openDeck == null) return;
    SongCollectionStore.insertIntoDeck(collection, openDeck!);
    markDirty();
  }

  void toggleCollection(String collId) {
    final coll = SongCollectionStore.find(collId);
    if (coll == null) return;
    coll.isExpanded = !coll.isExpanded;
    markDirty();
  }

  void moveCollection(String collId, int delta) {
    if (openDeck == null) return;
    int firstIdx = -1;
    for (var i = 0; i < openDeck!.slides.length; i++) {
      if (_collIdOfSlide(openDeck!.slides[i]) == collId) {
        firstIdx = i;
        break;
      }
    }
    if (firstIdx < 0) return;
    final coll      = SongCollectionStore.find(collId);
    final groupSize = coll?.slides.length ?? 0;
    final newFirst  = firstIdx + delta;
    if (newFirst < 0 || newFirst + groupSize > openDeck!.slides.length) return;
    SongCollectionStore.moveInDeck(collId, openDeck!, newFirst);
    markDirty();
  }

  void removeCollection(String collId) {
    if (openDeck == null) return;
    SongCollectionStore.removeFromDeck(collId, openDeck!);
    if (selectedSlide != null &&
        _collIdOfSlide(selectedSlide!) == collId) {
      selectedSlide = null;
    }
    markDirty();
  }

  void reorderCollectionSlide(String collId, int oldIdx, int newIdx) {
    if (openDeck == null) return;
    SongCollectionStore.reorderSlideInDeck(collId, openDeck!, oldIdx, newIdx);
    markDirty();
  }

  String? _collIdOfSlide(Slide s) {
    const tag = 'coll:';
    if (!s.reference.startsWith(tag)) return null;
    return s.reference.substring(tag.length).split('|').first;
  }

  // ── Stream / record ────────────────────────────────────────────────────────

  Future<void> saveStreamSettings(StreamSettings s) async {
    streamSettings = s;
    isStreaming    = true;
    await _service.saveStreamSettings(s);
    notifyListeners();
  }

  void stopStream() {
    isStreaming = false;
    notifyListeners();
  }

  Future<void> saveRecordSettings(RecordSettings r) async {
    recordSettings = r;
    isRecording    = true;
    await _service.saveRecordSettings(r);
    notifyListeners();
  }

  void stopRecord() {
    isRecording = false;
    notifyListeners();
  }

  void setPresenting(bool value) {
    presenting = value;
    notifyListeners();
  }
}