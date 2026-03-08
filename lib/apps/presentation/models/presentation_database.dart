// lib/apps/presentation/models/presentation_database.dart
//
// Normalized SQLite persistence for Presentation Studio.
//
// Schema (v2):
//   decks  — one row per deck (metadata + groups JSON, NO slides blob)
//   slides — one row per slide (deck_id FK, slide_order, all slide fields)
//   app_settings — key/value for stream/record settings
//
// Migration from v1:
//   Old v1 schema stored all slides in a `deck_json` TEXT blob.
//   On first open with v2, all old decks are read, their slides
//   are written into the new `slides` table, then the old `decks`
//   table is dropped and replaced with the new normalized schema.
//
// IMPORTANT: sqfliteFfiInit() + databaseFactory = databaseFactoryFfi
// MUST be called synchronously in main() BEFORE runApp() on Windows/Linux/macOS.

import 'dart:convert';
import 'dart:developer' as dev;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'presentation_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Schema constants
// ─────────────────────────────────────────────────────────────────────────────
const _kDbName    = 'presentation_studio.db';
const _kDbVersion = 3;
const _tDecks     = 'decks';
const _tSlides    = 'slides';
const _tSettings  = 'app_settings';

// ─────────────────────────────────────────────────────────────────────────────
// PresentationDatabase  (singleton)
// ─────────────────────────────────────────────────────────────────────────────
class PresentationDatabase {
  PresentationDatabase._();
  static final PresentationDatabase instance = PresentationDatabase._();

  Database? _db;

  // ── open ───────────────────────────────────────────────────────────────────

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath  = p.join(docsDir.path, _kDbName);
    dev.log('[PresentationDatabase] Opening DB at: $dbPath');

    final database = await openDatabase(
      dbPath,
      version:   _kDbVersion,
      onCreate:  _onCreate,
      onUpgrade: _onUpgrade,
    );

    dev.log('[PresentationDatabase] DB opened (v$_kDbVersion)');
    return database;
  }

  // ── onCreate — fresh install ───────────────────────────────────────────────

  Future<void> _onCreate(Database db, int version) async {
    dev.log('[PresentationDatabase] Creating schema v$version');
    await _createNormalizedSchema(db);
    await _createSettingsTable(db);
    dev.log('[PresentationDatabase] Schema created');
  }

  // ── onUpgrade — v1 blob → v2 normalized ───────────────────────────────────

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    dev.log('[PresentationDatabase] Upgrading $oldV → $newV');

    if (oldV == 1 && newV >= 2) {
      await _migrateV1ToV2(db);
    }
    if (oldV <= 2 && newV >= 3) {
      await _migrateV2ToV3(db);
    }
  }

  Future<void> _migrateV2ToV3(Database db) async {
    dev.log('[PresentationDatabase] v2→v3: adding master style columns');
    final cols = {
      'master_style_id':     "TEXT NOT NULL DEFAULT 'your_brand'",
      'master_bg_color':     'INTEGER NOT NULL DEFAULT 0',
      'master_accent_color': 'INTEGER NOT NULL DEFAULT 0',
      'master_text_color':   'INTEGER NOT NULL DEFAULT 0',
    };
    for (final entry in cols.entries) {
      try {
        await db.execute(
          'ALTER TABLE $_tDecks ADD COLUMN ${entry.key} ${entry.value}');
      } catch (e) {
        dev.log('[PresentationDatabase] v2→v3 note (${entry.key}): $e');
      }
    }
    dev.log('[PresentationDatabase] v2→v3 done');
  }

  // ── Schema builders ────────────────────────────────────────────────────────

  Future<void> _createNormalizedSchema(Database db) async {
    // Decks table — no slides blob
    await db.execute('''
      CREATE TABLE $_tDecks (
        id               TEXT PRIMARY KEY,
        name             TEXT NOT NULL,
        description      TEXT NOT NULL DEFAULT '',
        author           TEXT NOT NULL DEFAULT '',
        notes            TEXT NOT NULL DEFAULT '',
        service_date     TEXT,
        tags_json        TEXT NOT NULL DEFAULT '[]',
        is_template      INTEGER NOT NULL DEFAULT 0,
        is_pinned        INTEGER NOT NULL DEFAULT 0,
        sort_order       INTEGER NOT NULL DEFAULT 0,
        groups_json      TEXT NOT NULL DEFAULT '[]',
        master_style_id      TEXT NOT NULL DEFAULT 'your_brand',
        master_bg_color      INTEGER NOT NULL DEFAULT 0,
        master_accent_color  INTEGER NOT NULL DEFAULT 0,
        master_text_color    INTEGER NOT NULL DEFAULT 0,
        created_at       TEXT NOT NULL,
        last_used_at     TEXT,
        last_modified_at TEXT
      )
    ''');

    // Slides table — normalized, one row per slide
    await db.execute('''
      CREATE TABLE $_tSlides (
        id           TEXT PRIMARY KEY,
        deck_id      TEXT NOT NULL REFERENCES $_tDecks(id) ON DELETE CASCADE,
        slide_order  INTEGER NOT NULL DEFAULT 0,
        type         TEXT NOT NULL DEFAULT 'blank',
        title        TEXT NOT NULL DEFAULT '',
        body         TEXT NOT NULL DEFAULT '',
        reference    TEXT NOT NULL DEFAULT '',
        bg_color     INTEGER NOT NULL DEFAULT 0xFF1A3A5C,
        text_color   INTEGER NOT NULL DEFAULT 0xFFFFFFFF,
        font_size    REAL    NOT NULL DEFAULT 36,
        style_json   TEXT    NOT NULL DEFAULT '{}'
      )
    ''');

    // Index for fast per-deck slide queries
    await db.execute(
        'CREATE INDEX idx_slides_deck ON $_tSlides(deck_id, slide_order)');
  }

  Future<void> _createSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tSettings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  // ── v1 → v2 migration ─────────────────────────────────────────────────────

  Future<void> _migrateV1ToV2(Database db) async {
    dev.log('[PresentationDatabase] Starting v1→v2 migration');

    // 1. Read all old deck blobs
    final List<Map<String, dynamic>> oldRows;
    try {
      oldRows = await db.query('decks');
    } catch (e) {
      dev.log('[PresentationDatabase] Migration: could not read old decks: $e');
      await _createNormalizedSchema(db);
      return;
    }

    dev.log('[PresentationDatabase] Migration: ${oldRows.length} old deck rows');

    // 2. Parse each old deck
    final List<Deck> migratedDecks = [];
    for (final row in oldRows) {
      try {
        final jsonStr = row['deck_json'] as String?;
        if (jsonStr == null || jsonStr.isEmpty) continue;
        final j = jsonDecode(jsonStr);
        if (j is! Map) continue;
        migratedDecks.add(Deck.fromJson(Map<String, dynamic>.from(j)));
      } catch (e) {
        dev.log('[PresentationDatabase] Migration: skipping corrupt row: $e');
      }
    }

    // 3. Drop old tables and create new schema
    await db.execute('DROP TABLE IF EXISTS decks');
    await _createNormalizedSchema(db);

    // 4. Write migrated decks into new normalized tables
    for (final deck in migratedDecks) {
      try {
        await db.insert(_tDecks, deck.toRow(),
            conflictAlgorithm: ConflictAlgorithm.replace);

        for (var i = 0; i < deck.slides.length; i++) {
          await db.insert(_tSlides, deck.slides[i].toRow(deck.id, i),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      } catch (e) {
        dev.log('[PresentationDatabase] Migration: error writing deck '
            '"${deck.name}": $e');
      }
    }

    dev.log('[PresentationDatabase] Migration complete: '
        '${migratedDecks.length} decks migrated');
  }

  // ── LOAD ───────────────────────────────────────────────────────────────────

  /// Load all decks with their slides in one efficient pass.
  Future<List<Deck>> loadDecks() async {
    final d = await db;

    // Load all deck rows
    final deckRows = await d.query(_tDecks, orderBy: 'sort_order DESC, created_at DESC');
    dev.log('[PresentationDatabase] Loading ${deckRows.length} decks');

    if (deckRows.isEmpty) return [];

    // Load all slides in one query, ordered by deck and position
    final slideRows = await d.query(_tSlides,
        orderBy: 'deck_id, slide_order ASC');

    // Group slides by deck_id
    final slidesByDeck = <String, List<Slide>>{};
    for (final row in slideRows) {
      final deckId = row['deck_id'] as String;
      try {
        slidesByDeck.putIfAbsent(deckId, () => []).add(Slide.fromRow(row));
      } catch (e) {
        dev.log('[PresentationDatabase] Skipping corrupt slide row: $e');
      }
    }

    // Assemble decks with their slides
    final decks = <Deck>[];
    for (final row in deckRows) {
      try {
        final deck = Deck.fromRow(row);
        deck.slides.addAll(slidesByDeck[deck.id] ?? []);
        decks.add(deck);
      } catch (e) {
        dev.log('[PresentationDatabase] Skipping corrupt deck row: $e');
      }
    }

    dev.log('[PresentationDatabase] Loaded ${decks.length} decks with '
        '${slidesByDeck.values.fold(0, (s, l) => s + l.length)} total slides');
    return decks;
  }

  // ── SAVE DECK ──────────────────────────────────────────────────────────────

  /// Save a deck's metadata AND all its slides atomically.
  /// Replaces any existing slides for this deck.
  Future<void> saveDeck(Deck deck) async {
    final d = await db;
    await d.transaction((txn) async {
      // Upsert deck metadata row
      await txn.insert(_tDecks, deck.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace);

      // Delete all existing slides for this deck, then re-insert
      await txn.delete(_tSlides,
          where: 'deck_id = ?', whereArgs: [deck.id]);

      for (var i = 0; i < deck.slides.length; i++) {
        await txn.insert(_tSlides, deck.slides[i].toRow(deck.id, i),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    dev.log('[PresentationDatabase] Saved deck "${deck.name}" '
        '(${deck.slides.length} slides)');
  }

  /// Save multiple decks atomically.
  Future<void> saveDecks(List<Deck> decks) async {
    if (decks.isEmpty) return;
    final d = await db;
    await d.transaction((txn) async {
      for (final deck in decks) {
        await txn.insert(_tDecks, deck.toRow(),
            conflictAlgorithm: ConflictAlgorithm.replace);

        await txn.delete(_tSlides,
            where: 'deck_id = ?', whereArgs: [deck.id]);

        for (var i = 0; i < deck.slides.length; i++) {
          await txn.insert(_tSlides, deck.slides[i].toRow(deck.id, i),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
    dev.log('[PresentationDatabase] Batch-saved ${decks.length} decks');
  }

  // ── SAVE SINGLE SLIDE ──────────────────────────────────────────────────────

  /// Update a single slide in place (e.g. after editing content/style).
  /// Does NOT rewrite all slides — just upserts this one row.
  Future<void> saveSlide(String deckId, Slide slide, int order) async {
    final d = await db;
    await d.insert(_tSlides, slide.toRow(deckId, order),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Update only the slide_order for a batch of slides (after reorder).
  Future<void> updateSlideOrders(
      String deckId, List<String> orderedIds) async {
    final d = await db;
    await d.transaction((txn) async {
      for (var i = 0; i < orderedIds.length; i++) {
        await txn.update(
          _tSlides,
          {'slide_order': i},
          where: 'id = ? AND deck_id = ?',
          whereArgs: [orderedIds[i], deckId],
        );
      }
    });
  }

  // ── DELETE ─────────────────────────────────────────────────────────────────

  /// Delete a deck and all its slides (CASCADE handles slides automatically).
  Future<void> deleteDeck(String deckId) async {
    final d = await db;
    // Explicitly delete slides first for safety (in case FK cascade is off)
    await d.delete(_tSlides, where: 'deck_id = ?', whereArgs: [deckId]);
    await d.delete(_tDecks,  where: 'id = ?',      whereArgs: [deckId]);
    dev.log('[PresentationDatabase] Deleted deck $deckId');
  }

  // ── APP SETTINGS ───────────────────────────────────────────────────────────

  Future<StreamSettings> loadStreamSettings() async {
    final raw = await _getSetting('stream_settings');
    if (raw == null) return StreamSettings();
    try {
      return StreamSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      dev.log('[PresentationDatabase] loadStreamSettings error: $e');
      return StreamSettings();
    }
  }

  Future<void> saveStreamSettings(StreamSettings s) =>
      _setSetting('stream_settings', jsonEncode(s.toJson()));

  Future<RecordSettings> loadRecordSettings() async {
    final raw = await _getSetting('record_settings');
    if (raw == null) return RecordSettings();
    try {
      return RecordSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      dev.log('[PresentationDatabase] loadRecordSettings error: $e');
      return RecordSettings();
    }
  }

  Future<void> saveRecordSettings(RecordSettings s) =>
      _setSetting('record_settings', jsonEncode(s.toJson()));

  // ── Settings helpers ───────────────────────────────────────────────────────

  Future<String?> _getSetting(String key) async {
    final d    = await db;
    final rows = await d.query(
      _tSettings,
      columns:   ['value'],
      where:     'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> _setSetting(String key, String value) async {
    final d = await db;
    await d.insert(
      _tSettings,
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Close ──────────────────────────────────────────────────────────────────

  Future<void> close() async {
    await _db?.close();
    _db = null;
    dev.log('[PresentationDatabase] Closed');
  }
}