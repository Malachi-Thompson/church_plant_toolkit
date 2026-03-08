// lib/apps/presentation/models/presentation_service.dart
//
// Thin service layer that delegates to PresentationDatabase.
// All deck data (including every slide and its full SlideStyle) is
// persisted in the normalized SQLite schema (decks + slides tables).

import 'presentation_models.dart';
import 'presentation_database.dart';

class PresentationService {
  final _db = PresentationDatabase.instance;

  // -- Decks -----------------------------------------------------------------

  /// Load all decks with their slides from the database.
  Future<List<Deck>> loadDecks() => _db.loadDecks();

  /// Persist a deck and all its slides (replaces existing slides for this deck).
  Future<void> saveDeck(Deck deck) => _db.saveDeck(deck);

  /// Persist multiple decks atomically.
  Future<void> saveDecks(List<Deck> decks) => _db.saveDecks(decks);

  /// Permanently delete a deck and all its slides.
  Future<void> deleteDeck(String deckId) => _db.deleteDeck(deckId);

  // -- Stream / Record settings ----------------------------------------------

  Future<StreamSettings> loadStreamSettings() => _db.loadStreamSettings();
  Future<void> saveStreamSettings(StreamSettings s) =>
      _db.saveStreamSettings(s);

  Future<RecordSettings> loadRecordSettings() => _db.loadRecordSettings();
  Future<void> saveRecordSettings(RecordSettings s) =>
      _db.saveRecordSettings(s);
}