// lib/apps/presentation/models/presentation_service.dart
//
// Per-deck file storage.  Each deck is saved as its own .cpres file inside
// a "presentations/" sub-folder of the app documents directory.
//
// File layout:
//   <documents>/presentations/<deckId>.cpres   ← one per deck (JSON)
//   <documents>/presentation_stream_settings.json
//   <documents>/presentation_record_settings.json

import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'presentation_models.dart';

class PresentationService {

  // ── Directory helpers ──────────────────────────────────────────────────────

  Future<Directory> _decksDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir  = Directory('${docs.path}/presentations');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _deckFile(String deckId) async {
    final dir = await _decksDir();
    return File('${dir.path}/$deckId.cpres');
  }

  Future<File> _settingsFile(String name) async {
    final docs = await getApplicationDocumentsDirectory();
    return File('${docs.path}/$name');
  }

  // ── Low-level JSON helpers ─────────────────────────────────────────────────

  Future<dynamic> _readJson(File f) async {
    try {
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return null;
      return jsonDecode(raw);
    } catch (e) {
      dev.log('[PresentationService] ERROR reading ${f.path}: $e');
      return null;
    }
  }

  Future<void> _writeJson(File f, dynamic data) async {
    try {
      final json = jsonEncode(data);
      dev.log('[PresentationService] Writing ${f.path} (${json.length} bytes)');
      if (Platform.isWindows) {
        await f.writeAsString(json);
      } else {
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(json);
        if (await f.exists()) await f.delete();
        await tmp.rename(f.path);
      }
      dev.log('[PresentationService] ✓ Written ${f.path}');
    } catch (e, st) {
      dev.log('[PresentationService] ERROR writing ${f.path}: $e\n$st');
      rethrow;
    }
  }

  // ── DECKS — per-file API ───────────────────────────────────────────────────

  /// Load all decks by reading every .cpres file in the presentations/ folder.
  Future<List<Deck>> loadDecks() async {
    final dir   = await _decksDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.cpres'))
        .toList();

    final decks = <Deck>[];
    for (final f in files) {
      final raw = await _readJson(f);
      if (raw == null) continue;
      try {
        final deck = Deck.fromJson(raw as Map<String, dynamic>);
        deck.filePath = f.path;
        decks.add(deck);
      } catch (e) {
        dev.log('[PresentationService] Skipping corrupt file ${f.path}: $e');
      }
    }

    decks.sort((a, b) => b.sortOrder.compareTo(a.sortOrder));
    return decks;
  }

  /// Save a single deck to its own .cpres file.
  Future<void> saveDeck(Deck deck) async {
    final f = await _deckFile(deck.id);
    deck.filePath = f.path;
    await _writeJson(f, deck.toJson());
  }

  /// Save all decks (convenience wrapper — calls saveDeck for each).
  Future<void> saveDecks(List<Deck> decks) async {
    for (final d in decks) {
      await saveDeck(d);
    }
  }

  /// Delete a deck's .cpres file from disk.
  Future<void> deleteDeck(String deckId) async {
    final f = await _deckFile(deckId);
    if (await f.exists()) await f.delete();
    dev.log('[PresentationService] Deleted $deckId.cpres');
  }

  /// Rename a deck's file (the id stays the same; only the stored name changes).
  Future<void> renameDeck(Deck deck) => saveDeck(deck);

  /// Export a deck to a user-chosen path. Returns the exported file.
  Future<File> exportDeck(Deck deck, String exportPath) async {
    final dest = File(exportPath.endsWith('.cpres')
        ? exportPath
        : '$exportPath.cpres');
    await dest.writeAsString(jsonEncode(deck.toJson()));
    dev.log('[PresentationService] Exported ${deck.name} → ${dest.path}');
    return dest;
  }

  /// Import a .cpres file. Returns the loaded Deck or throws on error.
  Future<Deck> importDeck(String filePath) async {
    final f   = File(filePath);
    final raw = await _readJson(f);
    if (raw == null) throw Exception('Could not read file: $filePath');
    final deck = Deck.fromJson(raw as Map<String, dynamic>);
    // Save it into our managed folder with a fresh id to avoid collisions
    final imported = Deck(
      id:          deck.id,
      name:        deck.name,
      description: deck.description,
      tags:        deck.tags,
      isTemplate:  deck.isTemplate,
      isPinned:    deck.isPinned,
      sortOrder:   deck.sortOrder,
      slides:      deck.slides,
      groups:      deck.groups,
      createdAt:   deck.createdAt,
      lastUsedAt:  deck.lastUsedAt,
      author:      deck.author,
      serviceDate: deck.serviceDate,
      notes:       deck.notes,
    );
    await saveDeck(imported);
    return imported;
  }

  /// Returns the managed presentations folder path (for display to user).
  Future<String> presentationsFolderPath() async {
    final dir = await _decksDir();
    return dir.path;
  }

  // ── STREAM SETTINGS ────────────────────────────────────────────────────────

  Future<StreamSettings> loadStreamSettings() async {
    final f   = await _settingsFile('presentation_stream_settings.json');
    final raw = await _readJson(f);
    if (raw == null) return StreamSettings();
    try { return StreamSettings.fromJson(raw); } catch (_) { return StreamSettings(); }
  }

  Future<void> saveStreamSettings(StreamSettings s) async {
    final f = await _settingsFile('presentation_stream_settings.json');
    await _writeJson(f, s.toJson());
  }

  // ── RECORD SETTINGS ────────────────────────────────────────────────────────

  Future<RecordSettings> loadRecordSettings() async {
    final f   = await _settingsFile('presentation_record_settings.json');
    final raw = await _readJson(f);
    if (raw == null) return RecordSettings();
    try { return RecordSettings.fromJson(raw); } catch (_) { return RecordSettings(); }
  }

  Future<void> saveRecordSettings(RecordSettings s) async {
    final f = await _settingsFile('presentation_record_settings.json');
    await _writeJson(f, s.toJson());
  }
}