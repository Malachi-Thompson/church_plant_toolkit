// lib/apps/presentation/models/presentation_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'presentation_models.dart';

class PresentationService {
  static const _decksKey          = 'presentation_decks';
  static const _streamSettingsKey = 'presentation_stream_settings';
  static const _recordSettingsKey = 'presentation_record_settings';

  // ── DECKS ──────────────────────────────────────────────────────────────────

  Future<List<Deck>> loadDecks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_decksKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((d) => Deck.fromJson(d)).toList();
  }

  Future<void> saveDecks(List<Deck> decks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _decksKey,
      jsonEncode(decks.map((d) => d.toJson()).toList()),
    );
  }

  // ── STREAM SETTINGS ────────────────────────────────────────────────────────

  Future<StreamSettings> loadStreamSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_streamSettingsKey);
    if (raw == null) return StreamSettings();
    return StreamSettings.fromJson(jsonDecode(raw));
  }

  Future<void> saveStreamSettings(StreamSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_streamSettingsKey, jsonEncode(settings.toJson()));
  }

  // ── RECORD SETTINGS ────────────────────────────────────────────────────────

  Future<RecordSettings> loadRecordSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_recordSettingsKey);
    if (raw == null) return RecordSettings();
    return RecordSettings.fromJson(jsonDecode(raw));
  }

  Future<void> saveRecordSettings(RecordSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recordSettingsKey, jsonEncode(settings.toJson()));
  }
}