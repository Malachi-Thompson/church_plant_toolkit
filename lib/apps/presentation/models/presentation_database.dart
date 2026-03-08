// lib/apps/presentation/models/presentation_database.dart
//
// Unified SQLite persistence for Presentation Studio.
//
// "Bad database factory" fix:
//   sqflite alone only works on Android & iOS.
//   On Windows, macOS, Linux you must call sqfliteFfiInit() and set
//   databaseFactory = databaseFactoryFfi BEFORE opening any database.
//   This file does that automatically so no other file needs changing.
//
// pubspec.yaml — add both of these:
//   sqflite: ^2.3.3
//   sqflite_common_ffi: ^2.3.3

import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
    // sqflite needs the FFI factory on every desktop platform.
    // Without this you get "Bad database factory" on Windows/macOS/Linux.
    if (!kIsWeb) {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      // Android + iOS use the default sqflite factory — nothing to change.
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath  = p.join(docsDir.path, _kDbName);
    dev.log('[PresentationDatabase] Opening DB at $dbPath');

    return openDatabase(
      dbPath,
      version:   _kDbVersion,
      onCreate:  _onCreate,
      onUpgrade: _onUpgrade,
    );
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
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    dev.log('[PresentationDatabase] Upgrade $oldV -> $newV');
    // Add migration steps here as the schema evolves.
  }

  // ── DECKS ──────────────────────────────────────────────────────────────────

  Future<List<Deck>> loadDecks() async {
    final d    = await db;
    final rows = await d.query(_tDecks, orderBy: 'sort_order DESC');

    final decks = <Deck>[];
    for (final row in rows) {
      try {
        final json = jsonDecode(row['deck_json'] as String)
            as Map<String, dynamic>;
        decks.add(Deck.fromJson(json));
      } catch (e) {
        dev.log('[PresentationDatabase] Skipping corrupt row '
            '${row['id']}: $e');
      }
    }
    return decks;
  }

  Future<void> saveDeck(Deck deck) async {
    final d = await db;
    await d.insert(
      _tDecks,
      _deckToRow(deck),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    dev.log('[PresentationDatabase] Saved "${deck.name}"');
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
    } catch (_) {
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
    } catch (_) {
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

  Map<String, dynamic> _deckToRow(Deck deck) => {
        'id':               deck.id,
        'name':             deck.name,
        'sort_order':       deck.sortOrder,
        'is_pinned':        deck.isPinned   ? 1 : 0,
        'is_template':      deck.isTemplate ? 1 : 0,
        'created_at':       deck.createdAt.toIso8601String(),
        'last_used_at':     deck.lastUsedAt?.toIso8601String(),
        'last_modified_at': deck.lastModifiedAt?.toIso8601String(),
        'service_date':     deck.serviceDate?.toIso8601String(),
        // Full deck JSON — every SlideStyle field is captured here
        'deck_json':        jsonEncode(deck.toJson()),
      };

  // ── CLOSE ──────────────────────────────────────────────────────────────────

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}