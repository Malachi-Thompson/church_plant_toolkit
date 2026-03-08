// lib/apps/presentation/models/presentation_database.dart
//
// Unified SQLite persistence for Presentation Studio.
//
// IMPORTANT: sqfliteFfiInit() and databaseFactory = databaseFactoryFfi
// are now called in main() BEFORE runApp(), not here lazily.
// Calling them lazily inside an async function can silently fail on Windows.
//
// pubspec.yaml dependencies needed:
//   sqflite: ^2.3.3
//   sqflite_common_ffi: ^2.3.3
//   path_provider: ^2.1.0
//   path: ^1.9.0

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
const _kDbVersion = 1;
const _tDecks     = 'decks';
const _tSettings  = 'app_settings';

// ─────────────────────────────────────────────────────────────────────────────
// PresentationDatabase  (singleton)
// ─────────────────────────────────────────────────────────────────────────────
class PresentationDatabase {
  PresentationDatabase._();
  static final PresentationDatabase instance = PresentationDatabase._();

  Database? _db;

  // ── open / init ────────────────────────────────────────────────────────────

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    // sqfliteFfiInit() is now called in main() before runApp() on desktop.
    // We do NOT call it here to avoid race conditions on Windows.
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath  = p.join(docsDir.path, _kDbName);
    dev.log('[PresentationDatabase] Opening DB at: $dbPath');

    final database = await openDatabase(
      dbPath,
      version:   _kDbVersion,
      onCreate:  _onCreate,
      onUpgrade: _onUpgrade,
    );

    dev.log('[PresentationDatabase] DB opened successfully');
    return database;
  }

  Future<void> _onCreate(Database db, int version) async {
    dev.log('[PresentationDatabase] Creating schema v$version');

    await db.execute('''
      CREATE TABLE $_tDecks (
        id               TEXT PRIMARY KEY,
        name             TEXT NOT NULL,
        sort_order       INTEGER NOT NULL DEFAULT 0,
        is_pinned        INTEGER NOT NULL DEFAULT 0,
        is_template      INTEGER NOT NULL DEFAULT 0,
        created_at       TEXT NOT NULL,
        last_used_at     TEXT,
        last_modified_at TEXT,
        service_date     TEXT,
        deck_json        TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $_tSettings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    dev.log('[PresentationDatabase] Schema created');
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    dev.log('[PresentationDatabase] Upgrade $oldV -> $newV');
  }

  // ── DECKS ──────────────────────────────────────────────────────────────────

  Future<List<Deck>> loadDecks() async {
    final d    = await db;
    final rows = await d.query(_tDecks, orderBy: 'sort_order DESC');
    dev.log('[PresentationDatabase] Loading ${rows.length} deck rows');

    final decks = <Deck>[];
    for (final row in rows) {
      try {
        final jsonStr = row['deck_json'];
        if (jsonStr == null || jsonStr is! String || jsonStr.isEmpty) {
          dev.log('[PresentationDatabase] Skipping row ${row['id']}: empty deck_json');
          continue;
        }
        final json = jsonDecode(jsonStr);
        if (json is! Map<String, dynamic>) {
          dev.log('[PresentationDatabase] Skipping row ${row['id']}: deck_json is not a Map');
          continue;
        }
        decks.add(Deck.fromJson(json));
      } catch (e, st) {
        // Log the full error so you can see exactly what's failing
        dev.log('[PresentationDatabase] Skipping corrupt row ${row['id']}: $e\n$st');
      }
    }

    dev.log('[PresentationDatabase] Successfully loaded ${decks.length} decks');
    return decks;
  }

  Future<void> saveDeck(Deck deck) async {
    final d   = await db;
    final row = _deckToRow(deck);
    await d.insert(
      _tDecks,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    dev.log('[PresentationDatabase] Saved "${deck.name}" (${deck.slides.length} slides)');
  }

  Future<void> saveDecks(List<Deck> decks) async {
    if (decks.isEmpty) return;
    final d = await db;
    await d.transaction((txn) async {
      for (final deck in decks) {
        await txn.insert(
          _tDecks,
          _deckToRow(deck),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    dev.log('[PresentationDatabase] Batch-saved ${decks.length} decks');
  }

  Future<void> deleteDeck(String deckId) async {
    final d = await db;
    await d.delete(_tDecks, where: 'id = ?', whereArgs: [deckId]);
    dev.log('[PresentationDatabase] Deleted $deckId');
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

  // ── SETTINGS HELPERS ───────────────────────────────────────────────────────

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

  // ── ROW BUILDER ────────────────────────────────────────────────────────────

  Map<String, dynamic> _deckToRow(Deck deck) {
    final json = jsonEncode(deck.toJson());
    return {
      'id':               deck.id,
      'name':             deck.name,
      'sort_order':       deck.sortOrder,
      'is_pinned':        deck.isPinned   ? 1 : 0,
      'is_template':      deck.isTemplate ? 1 : 0,
      'created_at':       deck.createdAt.toIso8601String(),
      'last_used_at':     deck.lastUsedAt?.toIso8601String(),
      'last_modified_at': deck.lastModifiedAt?.toIso8601String(),
      'service_date':     deck.serviceDate?.toIso8601String(),
      'deck_json':        json,
    };
  }

  // ── CLOSE ──────────────────────────────────────────────────────────────────

  Future<void> close() async {
    await _db?.close();
    _db = null;
    dev.log('[PresentationDatabase] Closed');
  }
}