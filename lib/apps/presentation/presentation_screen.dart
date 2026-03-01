// lib/apps/presentation/presentation_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../models/app_state.dart';
import '../../screens/dashboard_screen.dart';
import '../../theme.dart';

// ── MODELS ────────────────────────────────────────────────────────────────────
class Slide {
  final String id;
  String type;
  String title;
  String body;
  String reference;
  Color bgColor;
  Color textColor;
  double fontSize;

  Slide({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.reference = '',
    this.bgColor   = const Color(0xFF1A3A5C),
    this.textColor = Colors.white,
    this.fontSize  = 36,
  });

  Map<String, dynamic> toJson() => {
        'id': id, 'type': type, 'title': title, 'body': body,
        'reference': reference,
        'bgColor':   bgColor.toARGB32(),
        'textColor': textColor.toARGB32(),
        'fontSize':  fontSize,
      };

  factory Slide.fromJson(Map<String, dynamic> j) => Slide(
        id:        j['id'],
        type:      j['type'],
        title:     j['title'],
        body:      j['body'],
        reference: j['reference'] ?? '',
        bgColor:   Color(j['bgColor']   ?? 0xFF1A3A5C),
        textColor: Color(j['textColor'] ?? 0xFFFFFFFF),
        fontSize:  (j['fontSize'] ?? 36).toDouble(),
      );
}

class Deck {
  final String id;
  String name;
  List<Slide> slides;
  DateTime createdAt;

  Deck({required this.id, required this.name, required this.slides, required this.createdAt});

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name,
        'slides': slides.map((s) => s.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory Deck.fromJson(Map<String, dynamic> j) => Deck(
        id:        j['id'],
        name:      j['name'],
        slides:    (j['slides'] as List).map((s) => Slide.fromJson(s)).toList(),
        createdAt: DateTime.parse(j['createdAt']),
      );
}

// ── SCREEN ────────────────────────────────────────────────────────────────────
class PresentationScreen extends StatefulWidget {
  const PresentationScreen({super.key});

  @override
  State<PresentationScreen> createState() => _PresentationScreenState();
}

class _PresentationScreenState extends State<PresentationScreen> {
  List<Deck> _decks = [];
  Deck?  _selectedDeck;
  Slide? _selectedSlide;
  bool   _presenting  = false;
  bool   _isStreaming = false;
  bool   _isRecording = false;

  @override
  void initState() {
    super.initState();
    _loadDecks();
  }

  Future<void> _loadDecks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('presentation_decks');
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      setState(() => _decks = list.map((d) => Deck.fromJson(d)).toList());
    }
  }

  Future<void> _saveDecks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('presentation_decks',
        jsonEncode(_decks.map((d) => d.toJson()).toList()));
  }

  void _createDeck(Color primary) {
    final deck = Deck(
      id:        const Uuid().v4(),
      name:      'New Presentation',
      slides:    [],
      createdAt: DateTime.now(),
    );
    setState(() {
      _decks.insert(0, deck);
      _selectedDeck  = deck;
      _selectedSlide = null;
    });
    _saveDecks();
  }

  void _addSlide(String type, Color primary, Color secondary) {
    if (_selectedDeck == null) return;
    // Default background: use brand primary for title/blank slides
    final defaultBg = _defaultBg(type, primary);
    final slide = Slide(
      id:        const Uuid().v4(),
      type:      type,
      title:     _defaultTitle(type),
      body:      _defaultBody(type),
      bgColor:   defaultBg,
      textColor: contrastOn(defaultBg),
    );
    setState(() {
      _selectedDeck!.slides.add(slide);
      _selectedSlide = slide;
    });
    _saveDecks();
  }

  // Default background colors reference the church brand
  Color _defaultBg(String type, Color primary) {
    switch (type) {
      case 'title':        return primary;
      case 'scripture':    return Color.lerp(primary, Colors.black, 0.25)!;
      case 'lyric':        return Color.lerp(primary, Colors.black, 0.45)!;
      case 'announcement': return Color.lerp(primary, Colors.purple, 0.4)!;
      case 'blank':        return Colors.black;
      default:             return primary;
    }
  }

  String _defaultTitle(String type) {
    switch (type) {
      case 'title':        return 'Service Title';
      case 'scripture':    return 'Scripture';
      case 'lyric':        return 'Verse 1';
      case 'announcement': return 'Announcement';
      default: return '';
    }
  }

  String _defaultBody(String type) {
    switch (type) {
      case 'title':        return 'Welcome!';
      case 'scripture':    return 'For God so loved the world...';
      case 'lyric':        return 'Type your lyrics here';
      case 'announcement': return 'Details here';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state     = context.watch<AppState>();
    final primary   = state.brandPrimary;
    final secondary = state.brandSecondary;
    final profile   = state.churchProfile;

    if (_presenting && _selectedDeck != null) {
      return _PresentView(
        deck:            _selectedDeck!,
        primary:         primary,
        secondary:       secondary,
        onExit:          () => setState(() => _presenting = false),
        isStreaming:     _isStreaming,
        isRecording:     _isRecording,
        onToggleStream:  () => setState(() => _isStreaming  = !_isStreaming),
        onToggleRecord:  () => setState(() => _isRecording  = !_isRecording),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: contrastOn(primary),
        title: Row(
          children: [
            if (profile != null)
              ChurchLogo(
                logoPath:     profile.logoPath,
                primary:      primary,
                secondary:    secondary,
                size:         32,
                borderRadius: 8,
              ),
            if (profile != null) const SizedBox(width: 10),
            const Text('Presentation Studio',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          if (_selectedDeck != null)
            TextButton.icon(
              onPressed: () => setState(() => _presenting = true),
              icon: Icon(Icons.slideshow, color: contrastOn(primary)),
              label: Text('Present',
                  style: TextStyle(color: contrastOn(primary))),
            ),
        ],
      ),
      body: Row(
        children: [
          // Deck list
          SizedBox(
            width: 220,
            child: _DeckList(
              decks:        _decks,
              selectedDeck: _selectedDeck,
              primary:      primary,
              secondary:    secondary,
              onSelect: (deck) => setState(() {
                _selectedDeck  = deck;
                _selectedSlide = null;
              }),
              onAdd:    () => _createDeck(primary),
              onDelete: (deck) {
                setState(() {
                  _decks.remove(deck);
                  if (_selectedDeck?.id == deck.id) _selectedDeck = null;
                });
                _saveDecks();
              },
            ),
          ),
          const VerticalDivider(width: 1),
          // Slide list
          if (_selectedDeck != null) ...[
            SizedBox(
              width: 190,
              child: _SlideList(
                deck:          _selectedDeck!,
                selectedSlide: _selectedSlide,
                primary:       primary,
                secondary:     secondary,
                onSelect: (s) => setState(() => _selectedSlide = s),
                onAdd:    (type) => _addSlide(type, primary, secondary),
                onDelete: (s) {
                  setState(() {
                    _selectedDeck!.slides.remove(s);
                    if (_selectedSlide?.id == s.id) _selectedSlide = null;
                  });
                  _saveDecks();
                },
                onReorder: (oldIdx, newIdx) {
                  if (newIdx > oldIdx) newIdx--;
                  final slide = _selectedDeck!.slides.removeAt(oldIdx);
                  _selectedDeck!.slides.insert(newIdx, slide);
                  _saveDecks();
                  setState(() {});
                },
              ),
            ),
            const VerticalDivider(width: 1),
          ],
          // Editor / placeholder
          Expanded(
            child: _selectedSlide != null
                ? _SlideEditor(
                    slide:     _selectedSlide!,
                    primary:   primary,
                    secondary: secondary,
                    onChanged: () { _saveDecks(); setState(() {}); },
                  )
                : _selectedDeck != null
                    ? _DeckEmpty(
                        primary:   primary,
                        secondary: secondary,
                        onAdd: (type) => _addSlide(type, primary, secondary),
                      )
                    : _NoDeck(primary: primary),
          ),
        ],
      ),
    );
  }
}

// ── DECK LIST ─────────────────────────────────────────────────────────────────
class _DeckList extends StatelessWidget {
  final List<Deck> decks;
  final Deck? selectedDeck;
  final Color primary;
  final Color secondary;
  final ValueChanged<Deck> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<Deck> onDelete;

  const _DeckList({
    required this.decks, required this.selectedDeck,
    required this.primary, required this.secondary,
    required this.onSelect, required this.onAdd, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New Deck'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: contrastOn(primary),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: decks.length,
            itemBuilder: (ctx, i) {
              final deck     = decks[i];
              final selected = selectedDeck?.id == deck.id;
              return ListTile(
                selected:          selected,
                selectedTileColor: primary.withValues(alpha: 0.1),
                leading: Icon(Icons.slideshow,
                    size: 20,
                    color: selected ? primary : textMid),
                title: Text(deck.name,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? primary : textDark)),
                subtitle: Text('${deck.slides.length} slides',
                    style: const TextStyle(fontSize: 11, color: textMid)),
                onTap: () => onSelect(deck),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: Colors.red),
                  onPressed: () => onDelete(deck),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── SLIDE LIST ────────────────────────────────────────────────────────────────
class _SlideList extends StatelessWidget {
  final Deck deck;
  final Slide? selectedSlide;
  final Color primary;
  final Color secondary;
  final ValueChanged<Slide> onSelect;
  final ValueChanged<String> onAdd;
  final ValueChanged<Slide> onDelete;
  final void Function(int, int) onReorder;

  const _SlideList({
    required this.deck, required this.selectedSlide,
    required this.primary, required this.secondary,
    required this.onSelect, required this.onAdd,
    required this.onDelete, required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: PopupMenuButton<String>(
            onSelected: onAdd,
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'title',        child: Text('Title Slide')),
              PopupMenuItem(value: 'scripture',    child: Text('Scripture')),
              PopupMenuItem(value: 'lyric',        child: Text('Song Lyric')),
              PopupMenuItem(value: 'announcement', child: Text('Announcement')),
              PopupMenuItem(value: 'blank',        child: Text('Blank')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 16, color: contrastOn(primary)),
                  const SizedBox(width: 6),
                  Text('Add Slide',
                      style: TextStyle(
                          color: contrastOn(primary), fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: deck.slides.length,
            onReorder: onReorder,
            itemBuilder: (ctx, i) {
              final slide    = deck.slides[i];
              final selected = selectedSlide?.id == slide.id;
              return GestureDetector(
                key: ValueKey(slide.id),
                onTap: () => onSelect(slide),
                child: Container(
                  height: 80,
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: slide.bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:  selected ? secondary : Colors.transparent,
                      width:  selected ? 2.5 : 0,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(slide.title,
                                style: TextStyle(
                                    color: slide.textColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text(slide.body,
                                style: TextStyle(
                                    color: slide.textColor.withValues(alpha: 0.7),
                                    fontSize: 9),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 2, right: 2,
                        child: GestureDetector(
                          onTap: () => onDelete(slide),
                          child: const Icon(Icons.close,
                              size: 14, color: Colors.white70),
                        ),
                      ),
                      Positioned(
                        bottom: 4, right: 4,
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 9)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── SLIDE EDITOR ──────────────────────────────────────────────────────────────
class _SlideEditor extends StatefulWidget {
  final Slide slide;
  final Color primary;
  final Color secondary;
  final VoidCallback onChanged;

  const _SlideEditor({
    required this.slide, required this.primary,
    required this.secondary, required this.onChanged,
  });

  @override
  State<_SlideEditor> createState() => _SlideEditorState();
}

class _SlideEditorState extends State<_SlideEditor> {
  late TextEditingController _titleCtrl;
  late TextEditingController _bodyCtrl;
  late TextEditingController _refCtrl;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  @override
  void didUpdateWidget(_SlideEditor old) {
    super.didUpdateWidget(old);
    if (old.slide.id != widget.slide.id) {
      _titleCtrl.dispose();
      _bodyCtrl.dispose();
      _refCtrl.dispose();
      _initControllers();
    }
  }

  void _initControllers() {
    _titleCtrl = TextEditingController(text: widget.slide.title);
    _bodyCtrl  = TextEditingController(text: widget.slide.body);
    _refCtrl   = TextEditingController(text: widget.slide.reference);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  // Presets: first 4 are derived from brand colors, rest are universal
  List<Color> _bgPresets() {
    final p = widget.primary;
    return [
      p,
      Color.lerp(p, Colors.black, 0.25)!,
      Color.lerp(p, Colors.black, 0.5)!,
      Color.lerp(p, Colors.white, 0.7)!,
      Colors.black,
      const Color(0xFF1B2838),
      Colors.white,
      const Color(0xFF006400),
      const Color(0xFF7B0000),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final primary   = widget.primary;
    final secondary = widget.secondary;
    final presets   = _bgPresets();

    return Row(
      children: [
        // ── Left: edit panel ────────────────────────────────────────────
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Edit Slide',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: primary)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title / Heading'),
                  onChanged: (v) { widget.slide.title = v; widget.onChanged(); },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bodyCtrl,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Body Text'),
                  onChanged: (v) { widget.slide.body = v; widget.onChanged(); },
                ),
                if (widget.slide.type == 'scripture') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _refCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Reference', hintText: 'e.g. John 3:16'),
                    onChanged: (v) {
                      widget.slide.reference = v;
                      widget.onChanged();
                    },
                  ),
                ],
                const SizedBox(height: 16),
                // Font size
                Row(
                  children: [
                    const Text('Font Size:',
                        style: TextStyle(fontSize: 13, color: textMid)),
                    Expanded(
                      child: Slider(
                        value:       widget.slide.fontSize,
                        min:         18,
                        max:         72,
                        divisions:   18,
                        activeColor: primary,
                        label:       widget.slide.fontSize.round().toString(),
                        onChanged: (v) {
                          widget.slide.fontSize = v;
                          widget.onChanged();
                          setState(() {});
                        },
                      ),
                    ),
                    Text('${widget.slide.fontSize.round()}pt',
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                // Background color
                const Text('Background:',
                    style: TextStyle(fontSize: 13, color: textMid)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: presets.map((c) {
                    final sel = c.toARGB32() == widget.slide.bgColor.toARGB32();
                    return GestureDetector(
                      onTap: () {
                        widget.slide.bgColor   = c;
                        widget.slide.textColor = contrastOn(c);
                        widget.onChanged();
                        setState(() {});
                      },
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color:  c,
                          shape:  BoxShape.circle,
                          border: Border.all(
                            color: sel ? secondary : Colors.grey.shade300,
                            width: sel ? 3 : 1,
                          ),
                          boxShadow: sel
                              ? [const BoxShadow(
                                  color: Colors.black26, blurRadius: 4)]
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                // Brand color hint
                const SizedBox(height: 8),
                Text('First 4 swatches use your brand colors.',
                    style: TextStyle(
                        fontSize: 11,
                        color: primary.withValues(alpha: 0.6),
                        fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        // ── Right: live preview ──────────────────────────────────────────
        Expanded(
          flex: 2,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Preview',
                    style: TextStyle(
                        fontSize: 13,
                        color: primary,
                        fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _SlidePreview(slide: widget.slide),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── SLIDE PREVIEW WIDGET ──────────────────────────────────────────────────────
class _SlidePreview extends StatelessWidget {
  final Slide slide;
  const _SlidePreview({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: slide.bgColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.2), blurRadius: 12),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (slide.title.isNotEmpty)
            Text(slide.title,
                style: TextStyle(
                    color:      slide.textColor,
                    fontSize:   slide.fontSize * 0.38,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
          if (slide.body.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(slide.body,
                style: TextStyle(
                    color:    slide.textColor,
                    fontSize: slide.fontSize * 0.28,
                    height:   1.5),
                textAlign: TextAlign.center),
          ],
          if (slide.reference.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(slide.reference,
                style: TextStyle(
                    color:      slide.textColor.withValues(alpha: 0.65),
                    fontSize:   slide.fontSize * 0.2,
                    fontStyle:  FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}

// ── FULL SCREEN PRESENTATION VIEW ─────────────────────────────────────────────
class _PresentView extends StatefulWidget {
  final Deck     deck;
  final Color    primary;
  final Color    secondary;
  final VoidCallback onExit;
  final bool     isStreaming;
  final bool     isRecording;
  final VoidCallback onToggleStream;
  final VoidCallback onToggleRecord;

  const _PresentView({
    required this.deck, required this.primary, required this.secondary,
    required this.onExit,
    required this.isStreaming, required this.isRecording,
    required this.onToggleStream, required this.onToggleRecord,
  });

  @override
  State<_PresentView> createState() => _PresentViewState();
}

class _PresentViewState extends State<_PresentView> {
  int  _idx         = 0;
  bool _showControls = true;

  @override
  Widget build(BuildContext context) {
    final slides = widget.deck.slides;
    if (slides.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('No slides in this deck.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: widget.onExit,
                child: const Text('Exit'),
              ),
            ],
          ),
        ),
      );
    }

    final slide     = slides[_idx];
    final secondary = widget.secondary;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        onHorizontalDragEnd: (d) {
          if (d.primaryVelocity! < 0 && _idx < slides.length - 1) {
            setState(() => _idx++);
          } else if (d.primaryVelocity! > 0 && _idx > 0) {
            setState(() => _idx--);
          }
        },
        child: Stack(
          children: [
            // Slide fill
            SizedBox.expand(
              child: Container(
                color: slide.bgColor,
                padding: const EdgeInsets.all(60),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (slide.title.isNotEmpty)
                      Text(slide.title,
                          style: TextStyle(
                              color:      slide.textColor,
                              fontSize:   slide.fontSize,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                    if (slide.body.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(slide.body,
                          style: TextStyle(
                              color:    slide.textColor,
                              fontSize: slide.fontSize * 0.65,
                              height:   1.6),
                          textAlign: TextAlign.center),
                    ],
                    if (slide.reference.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(slide.reference,
                          style: TextStyle(
                              color:     slide.textColor.withValues(alpha: 0.65),
                              fontSize:  slide.fontSize * 0.42,
                              fontStyle: FontStyle.italic)),
                    ],
                  ],
                ),
              ),
            ),

            // Status badges
            if (widget.isRecording || widget.isStreaming)
              Positioned(
                top: 16, right: 16,
                child: Row(
                  children: [
                    if (widget.isRecording)
                      _Badge(label: 'REC', color: Colors.red),
                    if (widget.isStreaming) ...[
                      const SizedBox(width: 8),
                      _Badge(label: 'LIVE', color: Colors.green),
                    ],
                  ],
                ),
              ),

            // Controls overlay
            if (_showControls) ...[
              // Bottom gradient bar
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.82),
                      ],
                      begin: Alignment.topCenter,
                      end:   Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Exit
                      IconButton(
                        onPressed: widget.onExit,
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                      const Spacer(),
                      // Record toggle
                      _ControlBtn(
                        icon:  widget.isRecording
                            ? Icons.stop_circle
                            : Icons.fiber_manual_record,
                        label: widget.isRecording ? 'Stop' : 'Record',
                        color: widget.isRecording ? Colors.red : Colors.white,
                        onTap: widget.onToggleRecord,
                      ),
                      const SizedBox(width: 20),
                      // Stream toggle
                      _ControlBtn(
                        icon:  widget.isStreaming ? Icons.wifi_off : Icons.wifi,
                        label: widget.isStreaming ? 'Live' : 'Stream',
                        color: widget.isStreaming ? Colors.green : Colors.white,
                        onTap: widget.onToggleStream,
                      ),
                      const Spacer(),
                      // Navigation
                      IconButton(
                        onPressed: _idx > 0
                            ? () => setState(() => _idx--)
                            : null,
                        icon: const Icon(Icons.chevron_left,
                            color: Colors.white, size: 32),
                      ),
                      Text('${_idx + 1} / ${slides.length}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14)),
                      IconButton(
                        onPressed: _idx < slides.length - 1
                            ? () => setState(() => _idx++)
                            : null,
                        icon: const Icon(Icons.chevron_right,
                            color: Colors.white, size: 32),
                      ),
                    ],
                  ),
                ),
              ),

              // Thumbnail strip
              Positioned(
                bottom: 70, left: 0, right: 0,
                child: SizedBox(
                  height: 58,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: slides.length,
                    itemBuilder: (ctx, i) {
                      final s   = slides[i];
                      final sel = i == _idx;
                      return GestureDetector(
                        onTap: () => setState(() => _idx = i),
                        child: Container(
                          width: 88, height: 52,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: s.bgColor,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: sel ? secondary : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: Center(
                            child: Text(s.title,
                                style: TextStyle(
                                    color: s.textColor,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── HELPERS ───────────────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String label;
  final Color  color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            label == 'REC' ? Icons.fiber_manual_record : Icons.wifi,
            color: Colors.white, size: 11,
          ),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  final VoidCallback onTap;

  const _ControlBtn({
    required this.icon, required this.label,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}

class _DeckEmpty extends StatelessWidget {
  final Color primary;
  final Color secondary;
  final ValueChanged<String> onAdd;

  const _DeckEmpty({
    required this.primary, required this.secondary, required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_to_photos_outlined,
              size: 64, color: primary.withValues(alpha: 0.25)),
          const SizedBox(height: 16),
          const Text('Add a slide to get started',
              style: TextStyle(color: textMid, fontSize: 16)),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: [
              _QuickAdd(label: 'Title Slide',   type: 'title',        primary: primary, onAdd: onAdd),
              _QuickAdd(label: 'Scripture',      type: 'scripture',    primary: primary, onAdd: onAdd),
              _QuickAdd(label: 'Song Lyric',     type: 'lyric',        primary: primary, onAdd: onAdd),
              _QuickAdd(label: 'Announcement',   type: 'announcement', primary: primary, onAdd: onAdd),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickAdd extends StatelessWidget {
  final String label;
  final String type;
  final Color  primary;
  final ValueChanged<String> onAdd;

  const _QuickAdd({
    required this.label, required this.type,
    required this.primary, required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () => onAdd(type),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: primary),
        foregroundColor: primary,
      ),
      child: Text(label),
    );
  }
}

class _NoDeck extends StatelessWidget {
  final Color primary;
  const _NoDeck({required this.primary});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.present_to_all_outlined,
              size: 64, color: primary.withValues(alpha: 0.25)),
          const SizedBox(height: 16),
          const Text('Select or create a presentation',
              style: TextStyle(color: textMid, fontSize: 16)),
        ],
      ),
    );
  }
}