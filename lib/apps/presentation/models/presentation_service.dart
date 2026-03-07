// lib/apps/presentation/models/presentation_service.dart
//
// Persists decks and settings as JSON files in the app's documents directory.
// This is more reliable than shared_preferences for larger/structured data,
// and works correctly on Windows, macOS, Linux, Android, and iOS.
//
// File layout (inside getApplicationDocumentsDirectory()):
//   presentation_decks.json
//   presentation_stream_settings.json
//   presentation_record_settings.json

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'presentation_models.dart';

class PresentationService {
  // ── file path helpers ─────────────────────────────────────────────────────

  Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  /// Read JSON from a file. Returns null if the file doesn't exist or is empty.
  Future<dynamic> _readJson(String name) async {
    try {
      final f = await _file(name);
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return null;
      return jsonDecode(raw);
    } catch (e) {
      // Corrupt file — return null so callers fall back to defaults
      return null;
    }
  }

  /// Write JSON to a file atomically (write to .tmp then rename).
  Future<void> _writeJson(String name, dynamic data) async {
    final f   = await _file(name);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data));
    await tmp.rename(f.path);
  }

  // ── DECKS ──────────────────────────────────────────────────────────────────

  Future<List<Deck>> loadDecks() async {
    final raw = await _readJson('presentation_decks.json');
    if (raw == null) return [];
    try {
      return (raw as List).map((d) => Deck.fromJson(d)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveDecks(List<Deck> decks) async {
    await _writeJson(
      'presentation_decks.json',
      decks.map((d) => d.toJson()).toList(),
    );
  }

  // ── STREAM SETTINGS ────────────────────────────────────────────────────────

  Future<StreamSettings> loadStreamSettings() async {
    final raw = await _readJson('presentation_stream_settings.json');
    if (raw == null) return StreamSettings();
    try {
      return StreamSettings.fromJson(raw);
    } catch (_) {
      return StreamSettings();
    }
  }

  Future<void> saveStreamSettings(StreamSettings settings) async {
    await _writeJson('presentation_stream_settings.json', settings.toJson());
  }

  // ── RECORD SETTINGS ────────────────────────────────────────────────────────

  Future<RecordSettings> loadRecordSettings() async {
    final raw = await _readJson('presentation_record_settings.json');
    if (raw == null) return RecordSettings();
    try {
      return RecordSettings.fromJson(raw);
    } catch (_) {
      return RecordSettings();
    }
  }

  Future<void> saveRecordSettings(RecordSettings settings) async {
    await _writeJson('presentation_record_settings.json', settings.toJson());
  }
}