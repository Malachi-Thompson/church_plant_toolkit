// lib/apps/presentation/songselect/songselect_import.dart
//
// CCLI SongSelect Integration
// ────────────────────────────────────────────────────────────────────────────
// Provides:
//   • SongCollection          — model: a named, collapsible group of lyric Slides
//   • SongCollectionStore     — persistence of collections + deck wiring helpers
//   • showSongSelectImport()  — bottom-sheet: search → select sections → import
//   • SongCollectionTile      — widget for _SlideListPanel (collapsed/expanded)
// ────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/presentation_models.dart';
import '../../../theme.dart';

// ══════════════════════════════════════════════════════════════════════════════
// 1.  MODELS
// ══════════════════════════════════════════════════════════════════════════════

/// A logical grouping of lyric [Slide]s representing one worship song.
///
/// In a [Deck], every slide that belongs to this collection stores its
/// [id] in [Slide.reference] as `"coll:<collectionId>|<sectionLabel>"`.
class SongCollection {
  final String id;
  String       songTitle;
  String       artist;
  String       ccliNumber;
  bool         isExpanded;
  List<Slide>  slides;

  SongCollection({
    required this.id,
    required this.songTitle,
    required this.artist,
    required this.ccliNumber,
    required this.slides,
    this.isExpanded = true,
  });

  Map<String, dynamic> toJson() => {
        'id':         id,
        'songTitle':  songTitle,
        'artist':     artist,
        'ccliNumber': ccliNumber,
        'isExpanded': isExpanded,
        'slideIds':   slides.map((s) => s.id).toList(),
      };

  static SongCollection fromJson(
    Map<String, dynamic> j,
    List<Slide> allSlides,
  ) {
    final ids = List<String>.from(j['slideIds'] ?? []);
    final map = {for (final s in allSlides) s.id: s};
    return SongCollection(
      id:         j['id']         ?? const Uuid().v4(),
      songTitle:  j['songTitle']  ?? '',
      artist:     j['artist']     ?? '',
      ccliNumber: j['ccliNumber'] ?? '',
      isExpanded: j['isExpanded'] ?? true,
      slides:     ids.map((id) => map[id]).whereType<Slide>().toList(),
    );
  }

  SongCollection copyWith({
    String?      songTitle,
    String?      artist,
    String?      ccliNumber,
    bool?        isExpanded,
    List<Slide>? slides,
  }) =>
      SongCollection(
        id:         id,
        songTitle:  songTitle  ?? this.songTitle,
        artist:     artist     ?? this.artist,
        ccliNumber: ccliNumber ?? this.ccliNumber,
        isExpanded: isExpanded ?? this.isExpanded,
        slides:     slides     ?? List.of(this.slides),
      );
}

// ── Reference tag helpers ──────────────────────────────────────────────────

const String _kCollTag = 'coll:';

String _makeRef(String collId, String original) =>
    '$_kCollTag$collId|$original';

String? _collIdOf(Slide slide) {
  if (!slide.reference.startsWith(_kCollTag)) return null;
  return slide.reference.substring(_kCollTag.length).split('|').first;
}

String _originalRef(Slide slide) {
  if (!slide.reference.startsWith(_kCollTag)) return slide.reference;
  final parts = slide.reference.split('|');
  return parts.length > 1 ? parts.sublist(1).join('|') : '';
}

// ══════════════════════════════════════════════════════════════════════════════
// 2.  COLLECTION STORE  (file-based persistence + deck-mutation helpers)
// ══════════════════════════════════════════════════════════════════════════════

class SongCollectionStore {
  static const _fileName = 'presentation_song_collections.json';

  // ── In-memory registry (collectionId → SongCollection) ────────────────────
  static final Map<String, SongCollection> _registry = {};

  static SongCollection? find(String id) => _registry[id];

  // ── File helpers ───────────────────────────────────────────────────────────

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  static Future<void> loadAll(List<Deck> decks) async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return;
      final list = jsonDecode(raw) as List;
      _registry.clear();
      for (final j in list) {
        final allSlides = decks.expand((d) => d.slides).toList();
        final coll      = SongCollection.fromJson(j, allSlides);
        _registry[coll.id] = coll;
      }
    } catch (_) {
      // Corrupt or missing file — start with empty registry
    }
  }

  static Future<void> saveAll() async {
    try {
      final f   = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(
          jsonEncode(_registry.values.map((c) => c.toJson()).toList()));
      await tmp.rename(f.path);
    } catch (_) {}
  }

  // ── Deck-mutation helpers ──────────────────────────────────────────────────

  /// Insert [collection]'s slides into [deck] at optional [atIndex].
  static void insertIntoDeck(
    SongCollection collection,
    Deck deck, {
    int? atIndex,
  }) {
    final tagged = collection.slides.map((s) {
      s.reference = _makeRef(collection.id, _originalRef(s));
      return s;
    }).toList();

    final idx = (atIndex ?? deck.slides.length).clamp(0, deck.slides.length);
    deck.slides.insertAll(idx, tagged);
    _registry[collection.id] = collection;
  }

  /// Remove all slides belonging to [collectionId] from [deck].
  static void removeFromDeck(String collectionId, Deck deck) {
    deck.slides.removeWhere((s) => _collIdOf(s) == collectionId);
    _registry.remove(collectionId);
  }

  /// Move the entire collection block so it starts at [newFirstIndex].
  static void moveInDeck(String collectionId, Deck deck, int newFirstIndex) {
    final group  = deck.slides.where((s) => _collIdOf(s) == collectionId).toList();
    final others = deck.slides.where((s) => _collIdOf(s) != collectionId).toList();
    final clamped = newFirstIndex.clamp(0, others.length);
    others.insertAll(clamped, group);
    deck.slides
      ..clear()
      ..addAll(others);
  }

  /// Reorder a slide *within* its collection block in the deck.
  static void reorderSlideInDeck(
    String collectionId,
    Deck   deck,
    int    oldGroupIdx,
    int    newGroupIdx,
  ) {
    final allIdxs = <int>[];
    for (var i = 0; i < deck.slides.length; i++) {
      if (_collIdOf(deck.slides[i]) == collectionId) allIdxs.add(i);
    }
    if (oldGroupIdx >= allIdxs.length || newGroupIdx >= allIdxs.length) return;

    final fromIdx = allIdxs[oldGroupIdx];
    final toIdx   = allIdxs[newGroupIdx];
    final tmp     = deck.slides[fromIdx];
    deck.slides[fromIdx] = deck.slides[toIdx];
    deck.slides[toIdx]   = tmp;

    final coll = _registry[collectionId];
    if (coll != null &&
        oldGroupIdx < coll.slides.length &&
        newGroupIdx < coll.slides.length) {
      final ts = coll.slides.removeAt(oldGroupIdx);
      coll.slides.insert(newGroupIdx, ts);
    }
  }

  // ── Query helpers ──────────────────────────────────────────────────────────

  static List<_SlideListItem> buildDisplayList(Deck deck) {
    final items = <_SlideListItem>[];
    final seen  = <String>{};

    for (var i = 0; i < deck.slides.length; i++) {
      final slide = deck.slides[i];
      final cid   = _collIdOf(slide);

      if (cid != null) {
        if (!seen.contains(cid)) {
          seen.add(cid);
          items.add(_SlideListItem.collection(cid, i));
        }
      } else {
        items.add(_SlideListItem.plain(i));
      }
    }
    return items;
  }
}

/// Discriminated union used by [SongCollectionStore.buildDisplayList].
class _SlideListItem {
  final bool   isCollection;
  final String collectionId;
  final int    deckIndex;

  const _SlideListItem._({
    required this.isCollection,
    required this.collectionId,
    required this.deckIndex,
  });

  factory _SlideListItem.collection(String id, int idx) =>
      _SlideListItem._(isCollection: true, collectionId: id, deckIndex: idx);

  factory _SlideListItem.plain(int idx) =>
      _SlideListItem._(isCollection: false, collectionId: '', deckIndex: idx);
}

// ══════════════════════════════════════════════════════════════════════════════
// 3.  CCLI SONGSELECT API
// ══════════════════════════════════════════════════════════════════════════════

class _SongSelectService {
  static const _base = 'https://api.ccli.com/v1';
  final String apiKey;
  _SongSelectService(this.apiKey);

  Future<List<_SongResult>> search(String query) async {
    final uri = Uri.parse('$_base/songs/search')
        .replace(queryParameters: {'q': query, 'limit': '25'});
    final res = await http.get(uri, headers: _h());
    if (res.statusCode != 200) {
      throw Exception('SongSelect search failed (${res.statusCode})');
    }
    final data  = jsonDecode(res.body);
    final items = (data['songs'] ?? data['results'] ?? []) as List;
    return items.map((j) => _SongResult.fromJson(j)).toList();
  }

  Future<_SongDetail> fetchLyrics(String songId) async {
    final uri = Uri.parse('$_base/songs/$songId/lyrics');
    final res = await http.get(uri, headers: _h());
    if (res.statusCode != 200) {
      throw Exception('SongSelect lyrics failed (${res.statusCode})');
    }
    return _SongDetail.fromJson(jsonDecode(res.body));
  }

  Map<String, String> _h() => {
        'Authorization': 'Bearer $apiKey',
        'Accept':        'application/json',
      };
}

class _SongResult {
  final String id;
  final String title;
  final String artist;
  final String ccliNumber;

  const _SongResult({
    required this.id,
    required this.title,
    required this.artist,
    required this.ccliNumber,
  });

  factory _SongResult.fromJson(Map<String, dynamic> j) => _SongResult(
        id:         (j['id']         ?? j['songId'] ?? '').toString(),
        title:      j['title']       ?? j['name']   ?? '',
        artist:     j['author']      ?? j['artist'] ?? '',
        ccliNumber: (j['ccliNumber'] ?? j['ccli']   ?? '').toString(),
      );
}

class _SongDetail {
  final String                    title;
  final String                    artist;
  final String                    ccliNumber;
  final List<Map<String, String>> sections;

  const _SongDetail({
    required this.title,
    required this.artist,
    required this.ccliNumber,
    required this.sections,
  });

  factory _SongDetail.fromJson(Map<String, dynamic> j) {
    final raw = (j['sections'] ?? j['lyrics'] ?? []) as List;
    return _SongDetail(
      title:      j['title']                  ?? '',
      artist:     j['author'] ?? j['artist']  ?? '',
      ccliNumber: (j['ccliNumber'] ?? '').toString(),
      sections:   raw.map<Map<String, String>>((s) => {
        'label': (s['label'] ?? s['type']    ?? 'Section').toString(),
        'text':  (s['text']  ?? s['content'] ?? '').toString(),
      }).toList(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 4.  CREDENTIAL SETTINGS  (also migrated to file-based storage)
// ══════════════════════════════════════════════════════════════════════════════

class SongSelectCredentials {
  String apiKey;
  String licenseNumber;

  SongSelectCredentials({this.apiKey = '', this.licenseNumber = ''});

  bool get isConfigured => apiKey.isNotEmpty;

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/ccli_credentials.json');
  }

  static Future<SongSelectCredentials> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return SongSelectCredentials();
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return SongSelectCredentials();
      final j = jsonDecode(raw);
      return SongSelectCredentials(
        apiKey:        j['apiKey']        ?? '',
        licenseNumber: j['licenseNumber'] ?? '',
      );
    } catch (_) {
      return SongSelectCredentials();
    }
  }

  Future<void> save() async {
    try {
      final f = await _file();
      await f.writeAsString(
          jsonEncode({'apiKey': apiKey, 'licenseNumber': licenseNumber}));
    } catch (_) {}
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 5.  IMPORT BOTTOM-SHEET
// ══════════════════════════════════════════════════════════════════════════════

Future<SongCollection?> showSongSelectImport(
  BuildContext context, {
  required Color primary,
  required Color secondary,
}) {
  return showModalBottomSheet<SongCollection>(
    context:            context,
    isScrollControlled: true,
    backgroundColor:    Colors.transparent,
    builder: (_) => SongSelectImportSheet(
      primary:   primary,
      secondary: secondary,
    ),
  );
}

class SongSelectImportSheet extends StatefulWidget {
  final Color primary;
  final Color secondary;

  const SongSelectImportSheet({
    super.key,
    required this.primary,
    required this.secondary,
  });

  @override
  State<SongSelectImportSheet> createState() => _SongSelectImportSheetState();
}

enum _SheetPage { search, lyrics, settings }

class _SongSelectImportSheetState extends State<SongSelectImportSheet> {
  _SheetPage _page = _SheetPage.search;

  SongSelectCredentials _creds = SongSelectCredentials();
  final _apiKeyCtrl  = TextEditingController();
  final _licenseCtrl = TextEditingController();

  final _searchCtrl   = TextEditingController();
  List<_SongResult> _results       = [];
  bool              _loadingSearch  = false;
  String            _searchError    = '';

  _SongResult?  _selected;
  _SongDetail?  _detail;
  bool          _loadingLyrics = false;
  String        _lyricsError   = '';
  Set<int>      _included      = {};

  @override
  void initState() {
    super.initState();
    _loadCreds();
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _licenseCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCreds() async {
    _creds = await SongSelectCredentials.load();
    _apiKeyCtrl.text  = _creds.apiKey;
    _licenseCtrl.text = _creds.licenseNumber;
    if (!_creds.isConfigured) setState(() => _page = _SheetPage.settings);
  }

  Future<void> _saveCreds() async {
    _creds.apiKey        = _apiKeyCtrl.text.trim();
    _creds.licenseNumber = _licenseCtrl.text.trim();
    await _creds.save();
    setState(() => _page = _SheetPage.search);
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loadingSearch = true;
      _searchError   = '';
      _results       = [];
    });
    try {
      final svc = _SongSelectService(_creds.apiKey);
      final res = await svc.search(q);
      setState(() => _results = res);
    } catch (e) {
      setState(() => _searchError = e.toString());
    } finally {
      setState(() => _loadingSearch = false);
    }
  }

  Future<void> _pickSong(_SongResult song) async {
    setState(() {
      _selected      = song;
      _loadingLyrics = true;
      _lyricsError   = '';
      _detail        = null;
      _page          = _SheetPage.lyrics;
    });
    try {
      final svc    = _SongSelectService(_creds.apiKey);
      final detail = await svc.fetchLyrics(song.id);
      setState(() {
        _detail   = detail;
        _included = Set.from(List.generate(detail.sections.length, (i) => i));
      });
    } catch (e) {
      setState(() => _lyricsError = e.toString());
    } finally {
      setState(() => _loadingLyrics = false);
    }
  }

  SongCollection _buildCollection() {
    final d  = _detail!;
    final bg = Color.lerp(widget.primary, Colors.black, 0.45)!;
    final fg = contrastOn(bg);

    final sections = d.sections.asMap().entries
        .where((e) => _included.contains(e.key))
        .map((e) => e.value)
        .toList();

    final slides = sections.map((sec) => Slide(
          id:        const Uuid().v4(),
          type:      'lyric',
          title:     sec['label']!,
          body:      sec['text']!,
          bgColor:   bg,
          textColor: fg,
          fontSize:  36,
        )).toList();

    return SongCollection(
      id:         const Uuid().v4(),
      songTitle:  d.title,
      artist:     d.artist,
      ccliNumber: d.ccliNumber,
      slides:     slides,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p  = widget.primary;
    final mq = MediaQuery.of(context);

    return Container(
      height: mq.size.height * 0.90,
      decoration: BoxDecoration(
        color:        Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
              color:      Colors.black.withValues(alpha: 0.15),
              blurRadius: 24,
              offset:     const Offset(0, -4))
        ],
      ),
      child: Column(
        children: [
          _DragHandle(),
          _SheetHeader(
            primary:    p,
            page:       _page,
            selected:   _selected,
            onSettings: () => setState(() => _page = _SheetPage.settings),
            onBack: () => setState(() {
              _page = _SheetPage.search;
            }),
            onClose: () => Navigator.pop(context),
          ),
          const Divider(height: 1),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: switch (_page) {
                _SheetPage.settings => _SettingsPanel(
                    key:         const ValueKey('settings'),
                    primary:     p,
                    apiKeyCtrl:  _apiKeyCtrl,
                    licenseCtrl: _licenseCtrl,
                    onSave:      _saveCreds,
                  ),
                _SheetPage.lyrics => _LyricsPanel(
                    key:           const ValueKey('lyrics'),
                    primary:       p,
                    detail:        _detail,
                    loading:       _loadingLyrics,
                    error:         _lyricsError,
                    included:      _included,
                    onToggle: (i, v) => setState(() {
                      if (v) _included.add(i); else _included.remove(i);
                    }),
                    onToggleAll: () => setState(() {
                      if (_detail == null) return;
                      if (_included.length == _detail!.sections.length) {
                        _included.clear();
                      } else {
                        _included = Set.from(
                            List.generate(_detail!.sections.length, (i) => i));
                      }
                    }),
                    onReorder: (o, n) => setState(() {
                      if (_detail == null) return;
                      if (n > o) n--;
                      final sec = _detail!.sections.removeAt(o);
                      _detail!.sections.insert(n, sec);
                      _included = Set.from(
                        _included.map((idx) {
                          if (idx == o) return n;
                          if (o < n && idx > o && idx <= n) return idx - 1;
                          if (o > n && idx >= n && idx < o) return idx + 1;
                          return idx;
                        }),
                      );
                    }),
                    onImport:      () => Navigator.pop(context, _buildCollection()),
                    includedCount: _included.length,
                  ),
                _SheetPage.search => _SearchPanel(
                    key:        const ValueKey('search'),
                    primary:    p,
                    searchCtrl: _searchCtrl,
                    results:    _results,
                    loading:    _loadingSearch,
                    error:      _searchError,
                    configured: _creds.isConfigured,
                    onSearch:   _search,
                    onPickSong: _pickSong,
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 6.  SHEET PANELS
// ══════════════════════════════════════════════════════════════════════════════

class _SettingsPanel extends StatelessWidget {
  final Color                  primary;
  final TextEditingController  apiKeyCtrl;
  final TextEditingController  licenseCtrl;
  final VoidCallback           onSave;

  const _SettingsPanel({
    super.key,
    required this.primary,
    required this.apiKeyCtrl,
    required this.licenseCtrl,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final p = primary;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:    const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:        p.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border:       Border.all(color: p.withValues(alpha: 0.20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline, size: 16, color: p),
                  const SizedBox(width: 6),
                  Text('How to get your API key',
                      style: TextStyle(fontWeight: FontWeight.bold, color: p)),
                ]),
                const SizedBox(height: 8),
                const Text(
                  '1. Log in at songselect.ccli.com\n'
                  '2. Go to My Account → Integrations / API Access\n'
                  '3. Create a new application — copy the Bearer token\n'
                  '4. Paste both values below and tap Save',
                  style: TextStyle(fontSize: 12, height: 1.65),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _FieldLabel('CCLI API Key / Bearer Token'),
          const SizedBox(height: 6),
          TextField(
            controller:  apiKeyCtrl,
            obscureText: true,
            decoration:  _dec('Paste your API Bearer token'),
          ),
          const SizedBox(height: 16),
          _FieldLabel('CCLI License Number'),
          const SizedBox(height: 6),
          TextField(
            controller:   licenseCtrl,
            decoration:   _dec('e.g. 1234567'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: p,
                foregroundColor: contrastOn(p),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Save & Continue',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchPanel extends StatelessWidget {
  final Color                     primary;
  final TextEditingController     searchCtrl;
  final List<_SongResult>         results;
  final bool                      loading;
  final String                    error;
  final bool                      configured;
  final VoidCallback              onSearch;
  final ValueChanged<_SongResult> onPickSong;

  const _SearchPanel({
    super.key,
    required this.primary,
    required this.searchCtrl,
    required this.results,
    required this.loading,
    required this.error,
    required this.configured,
    required this.onSearch,
    required this.onPickSong,
  });

  @override
  Widget build(BuildContext context) {
    final p = primary;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller:      searchCtrl,
                  decoration:      _dec('Search by title, artist, or CCLI #'),
                  onSubmitted:     (_) => onSearch(),
                  textInputAction: TextInputAction.search,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 52, height: 52,
                child: ElevatedButton(
                  onPressed: loading ? null : onSearch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: p,
                    foregroundColor: contrastOn(p),
                    padding:         EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: loading
                      ? SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: contrastOn(p)))
                      : const Icon(Icons.search),
                ),
              ),
            ],
          ),
        ),
        if (error.isNotEmpty) _ErrorBanner(message: error),
        if (!configured)
          _InfoBanner(
            message: 'No CCLI credentials found — tap ⚙ above to add them.',
            primary: p,
          ),
        Expanded(
          child: results.isEmpty && !loading
              ? _EmptySearch(primary: p)
              : ListView.separated(
                  itemCount:        results.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 56),
                  itemBuilder: (_, i) {
                    final song = results[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: p.withValues(alpha: 0.12),
                        child: Icon(Icons.music_note, color: p, size: 18),
                      ),
                      title: Text(song.title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${song.artist}  •  CCLI ${song.ccliNumber}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                      trailing: Icon(Icons.chevron_right, color: p),
                      onTap:    () => onPickSong(song),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _LyricsPanel extends StatelessWidget {
  final Color                    primary;
  final _SongDetail?             detail;
  final bool                     loading;
  final String                   error;
  final Set<int>                 included;
  final void Function(int, bool) onToggle;
  final VoidCallback             onToggleAll;
  final void Function(int, int)  onReorder;
  final VoidCallback             onImport;
  final int                      includedCount;

  const _LyricsPanel({
    super.key,
    required this.primary,
    required this.detail,
    required this.loading,
    required this.error,
    required this.included,
    required this.onToggle,
    required this.onToggleAll,
    required this.onReorder,
    required this.onImport,
    required this.includedCount,
  });

  @override
  Widget build(BuildContext context) {
    final p = primary;
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error.isNotEmpty) return Center(child: _ErrorBanner(message: error));
    if (detail == null) return const Center(child: CircularProgressIndicator());

    final d = detail!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.title,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize:   15,
                            color:      p)),
                    Text('${d.artist}  •  CCLI ${d.ccliNumber}',
                        style: TextStyle(
                            fontSize: 11,
                            color:    Colors.grey.shade600)),
                  ],
                ),
              ),
              TextButton(
                onPressed: onToggleAll,
                child: Text(
                  included.length == d.sections.length
                      ? 'Deselect All'
                      : 'Select All',
                  style: TextStyle(color: p, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
            'Choose and reorder sections — each becomes a slide:',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ReorderableListView.builder(
            padding:    const EdgeInsets.fromLTRB(12, 8, 12, 100),
            itemCount:  d.sections.length,
            onReorder:  onReorder,
            itemBuilder: (_, i) => _SectionCard(
              key:      ValueKey('sec_$i'),
              index:    i,
              label:    d.sections[i]['label']!,
              text:     d.sections[i]['text']!,
              included: included.contains(i),
              primary:  p,
              onToggle: (v) => onToggle(i, v),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: includedCount == 0 ? null : onImport,
                icon:  const Icon(Icons.download_rounded),
                label: Text(
                  'Import $includedCount '
                  'Slide${includedCount == 1 ? '' : 's'} as Song Collection',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:         p,
                  foregroundColor:         contrastOn(p),
                  disabledBackgroundColor: Colors.grey.shade200,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatefulWidget {
  final int                  index;
  final String               label;
  final String               text;
  final bool                 included;
  final Color                primary;
  final void Function(bool)  onToggle;

  const _SectionCard({
    super.key,
    required this.index,
    required this.label,
    required this.text,
    required this.included,
    required this.primary,
    required this.onToggle,
  });

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p        = widget.primary;
    final included = widget.included;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape:  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color:  included ? p.withValues(alpha: 0.06) : null,
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
            leading: Checkbox(
              value:       included,
              onChanged:   (v) => widget.onToggle(v ?? false),
              activeColor: p,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
            ),
            title: Text(
              widget.label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color:      included ? p : null,
                fontSize:   13,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReorderableDragStartListener(
                  index: widget.index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child:   Icon(Icons.drag_handle,
                        color: Colors.grey, size: 20),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
            onTap: () => widget.onToggle(!included),
          ),
          if (_expanded)
            Container(
              width:   double.infinity,
              margin:  const EdgeInsets.fromLTRB(14, 0, 14, 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:        Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.text,
                style: const TextStyle(fontSize: 12, height: 1.65),
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 7.  SONG COLLECTION TILE
// ══════════════════════════════════════════════════════════════════════════════

class SongCollectionTile extends StatelessWidget {
  final SongCollection      collection;
  final Deck                deck;
  final Color               primary;
  final Color               secondary;
  final Slide?              selectedSlide;
  final ValueChanged<Slide> onSelectSlide;
  final VoidCallback        onToggleExpand;
  final ValueChanged<int>   onMoveGroup;
  final Function(int, int)  onReorderSlide;
  final VoidCallback        onRemove;

  const SongCollectionTile({
    super.key,
    required this.collection,
    required this.deck,
    required this.primary,
    required this.secondary,
    required this.selectedSlide,
    required this.onSelectSlide,
    required this.onToggleExpand,
    required this.onMoveGroup,
    required this.onReorderSlide,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final p = primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin:     const EdgeInsets.fromLTRB(4, 6, 4, 0),
          decoration: BoxDecoration(
            color:        p.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(9),
            border:       Border.all(color: p.withValues(alpha: 0.28)),
          ),
          child: ListTile(
            dense:   true,
            leading: CircleAvatar(
              radius:          14,
              backgroundColor: p.withValues(alpha: 0.15),
              child: Icon(Icons.music_note, color: p, size: 15),
            ),
            title: Text(
              collection.songTitle,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13, color: p),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${collection.slides.length} slides  •  ${collection.artist}',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _IconBtn(
                  icon: Icons.arrow_upward_rounded, size: 16,
                  tooltip: 'Move song up', color: p,
                  onTap: () => onMoveGroup(-1),
                ),
                _IconBtn(
                  icon: Icons.arrow_downward_rounded, size: 16,
                  tooltip: 'Move song down', color: p,
                  onTap: () => onMoveGroup(1),
                ),
                _IconBtn(
                  icon: collection.isExpanded
                      ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  tooltip: collection.isExpanded ? 'Collapse' : 'Expand',
                  color: p,
                  onTap: onToggleExpand,
                ),
                _IconBtn(
                  icon: Icons.delete_outline_rounded, size: 16,
                  tooltip: 'Remove song', color: Colors.red,
                  onTap: () => _confirmRemove(context),
                ),
              ],
            ),
          ),
        ),

        if (collection.isExpanded && collection.slides.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics:    const NeverScrollableScrollPhysics(),
            itemCount:  collection.slides.length,
            onReorder:  onReorderSlide,
            buildDefaultDragHandles: false,
            itemBuilder: (_, i) {
              final slide    = collection.slides[i];
              final selected = selectedSlide?.id == slide.id;
              return _SlideMiniTile(
                key:       ValueKey(slide.id),
                slide:     slide,
                index:     i,
                selected:  selected,
                primary:   p,
                secondary: secondary,
                onTap:     () => onSelectSlide(slide),
              );
            },
          ),
      ],
    );
  }

  void _confirmRemove(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title:   const Text('Remove Song?'),
        content: Text(
            'Remove "${collection.songTitle}" and all its slides from this deck?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                onRemove();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Remove')),
        ],
      ),
    );
  }
}

class _SlideMiniTile extends StatelessWidget {
  final Slide        slide;
  final int          index;
  final bool         selected;
  final Color        primary;
  final Color        secondary;
  final VoidCallback onTap;

  const _SlideMiniTile({
    super.key,
    required this.slide,
    required this.index,
    required this.selected,
    required this.primary,
    required this.secondary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin:     const EdgeInsets.fromLTRB(16, 2, 4, 2),
        padding:    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.14)
              : Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? secondary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 4, height: 32,
              decoration: BoxDecoration(
                  color:        slide.bgColor,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(slide.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (slide.body.isNotEmpty)
                    Text(slide.body,
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(left: 4),
                child:   Icon(Icons.drag_handle, size: 16, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 8.  SMALL SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width:  40, height: 4,
          decoration: BoxDecoration(
            color:        Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _SheetHeader extends StatelessWidget {
  final Color        primary;
  final _SheetPage   page;
  final _SongResult? selected;
  final VoidCallback onSettings;
  final VoidCallback onBack;
  final VoidCallback onClose;

  const _SheetHeader({
    required this.primary,
    required this.page,
    required this.selected,
    required this.onSettings,
    required this.onBack,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final p        = primary;
    final showBack = page != _SheetPage.search;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              icon:      const Icon(Icons.arrow_back_rounded),
              onPressed: onBack,
              color:     Colors.grey,
            )
          else
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color:        p.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.music_note_rounded, color: p, size: 20),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  page == _SheetPage.settings
                      ? 'CCLI Credentials'
                      : page == _SheetPage.lyrics
                          ? selected?.title ?? 'Song Sections'
                          : 'CCLI SongSelect',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16, color: p),
                ),
                Text(
                  page == _SheetPage.settings
                      ? 'API key & license number'
                      : page == _SheetPage.lyrics
                          ? 'Pick sections to import'
                          : 'Import worship songs',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          if (page == _SheetPage.search)
            IconButton(
              icon:      const Icon(Icons.settings_outlined),
              onPressed: onSettings,
              tooltip:   'CCLI Settings',
              color:     Colors.grey,
            ),
          IconButton(
            icon:      const Icon(Icons.close_rounded),
            color:     Colors.grey,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13));
}

class _IconBtn extends StatelessWidget {
  final IconData     icon;
  final double       size;
  final String       tooltip;
  final Color        color;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.size,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => IconButton(
        icon:        Icon(icon, size: size, color: color),
        tooltip:     tooltip,
        onPressed:   onTap,
        padding:     EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        margin:     const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding:    const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:        Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(color: Colors.red.shade200),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: Colors.red, fontSize: 12))),
        ]),
      );
}

class _InfoBanner extends StatelessWidget {
  final String message;
  final Color  primary;
  const _InfoBanner({required this.message, required this.primary});

  @override
  Widget build(BuildContext context) => Container(
        margin:     const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding:    const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:        primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(color: primary.withValues(alpha: 0.20)),
        ),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, color: primary, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: TextStyle(color: primary, fontSize: 12))),
        ]),
      );
}

class _EmptySearch extends StatelessWidget {
  final Color primary;
  const _EmptySearch({required this.primary});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_rounded,
                size: 54, color: primary.withValues(alpha: 0.18)),
            const SizedBox(height: 14),
            Text('Search for a worship song',
                style: TextStyle(
                    color: primary.withValues(alpha: 0.50), fontSize: 14)),
            const SizedBox(height: 4),
            const Text('by title, artist, or CCLI number',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      );
}

InputDecoration _dec(String hint) => InputDecoration(
      hintText:       hint,
      hintStyle:      const TextStyle(fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border:         OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder:  OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:   BorderSide(color: Colors.grey.shade300)),
    );