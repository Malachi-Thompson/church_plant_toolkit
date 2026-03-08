// lib/apps/presentation/models/presentation_service.dart
//
// Thin service layer that delegates everything to PresentationDatabase.
// Export / import of .cpres files has been intentionally removed.
// All deck data (including every SlideStyle field) is persisted inside
// the SQLite database so nothing is ever lost between app launches.

import 'presentation_models.dart';
import 'presentation_database.dart';

class PresentationService {
  final _db = PresentationDatabase.instance;

  // ── DECKS ──────────────────────────────────────────────────────────────────

  /// Load all decks from the database.
  Future<List<Deck>> loadDecks() => _db.loadDecks();

  /// Persist a single deck (all metadata + every slide style field).
  Future<void> saveDeck(Deck deck) => _db.saveDeck(deck);

  /// Persist all decks in one atomic transaction.
  Future<void> saveDecks(List<Deck> decks) => _db.saveDecks(decks);

  /// Permanently delete a deck from the database.
  Future<void> deleteDeck(String deckId) => _db.deleteDeck(deckId);

  // ── STREAM / RECORD SETTINGS ───────────────────────────────────────────────

  Future<StreamSettings> loadStreamSettings() => _db.loadStreamSettings();
  Future<void> saveStreamSettings(StreamSettings s) =>
      _db.saveStreamSettings(s);

  Future<RecordSettings> loadRecordSettings() => _db.loadRecordSettings();
  Future<void> saveRecordSettings(RecordSettings s) =>
      _db.saveRecordSettings(s);
}