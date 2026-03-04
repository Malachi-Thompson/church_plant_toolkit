// lib/apps/presentation/presentation_screen.dart
//
// Enhanced Presentation Studio
//  • Bible verse import (BSB via API)
//  • Planning Center song import (OAuth + Songs API)
//  • MP4 recording via ffmpeg_kit_flutter
//  • RTMP live streaming (concurrent with recording)
//  • Settings screen for recording / streaming config
//
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
// Recording / streaming (add to pubspec.yaml):
//   ffmpeg_kit_flutter_full_gpl: ^6.0.3
//   screen_recorder: ^0.3.0  (or use ffmpeg_kit raw capture)
import '../../models/app_state.dart';
import '../../screens/dashboard_screen.dart';
import '../../theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────

class Slide {
  final String id;
  String type;
  String title;
  String body;
  String reference;
  Color  bgColor;
  Color  textColor;
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

// ─────────────────────────────────────────────────────────────────────────────
// STREAM / RECORD SETTINGS MODEL
// ─────────────────────────────────────────────────────────────────────────────

class StreamRecordSettings {
  // Recording
  String outputFolder;
  String videoResolution;   // e.g. "1920x1080"
  int    videoBitrate;      // kbps
  int    audioBitrate;      // kbps
  String audioDevice;       // microphone label

  // Streaming
  String rtmpUrl;           // e.g. rtmp://a.rtmp.youtube.com/live2
  String streamKey;

  // Planning Center
  String pcAppId;
  String pcSecret;

  StreamRecordSettings({
    this.outputFolder     = '',
    this.videoResolution  = '1920x1080',
    this.videoBitrate     = 4000,
    this.audioBitrate     = 128,
    this.audioDevice      = 'Default',
    this.rtmpUrl          = '',
    this.streamKey        = '',
    this.pcAppId          = '',
    this.pcSecret         = '',
  });

  Map<String, dynamic> toJson() => {
    'outputFolder':    outputFolder,
    'videoResolution': videoResolution,
    'videoBitrate':    videoBitrate,
    'audioBitrate':    audioBitrate,
    'audioDevice':     audioDevice,
    'rtmpUrl':         rtmpUrl,
    'streamKey':       streamKey,
    'pcAppId':         pcAppId,
    'pcSecret':        pcSecret,
  };

  factory StreamRecordSettings.fromJson(Map<String, dynamic> j) =>
      StreamRecordSettings(
        outputFolder:    j['outputFolder']    ?? '',
        videoResolution: j['videoResolution'] ?? '1920x1080',
        videoBitrate:    j['videoBitrate']    ?? 4000,
        audioBitrate:    j['audioBitrate']    ?? 128,
        audioDevice:     j['audioDevice']     ?? 'Default',
        rtmpUrl:         j['rtmpUrl']         ?? '',
        streamKey:       j['streamKey']       ?? '',
        pcAppId:         j['pcAppId']         ?? '',
        pcSecret:        j['pcSecret']        ?? '',
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// PRESENTATION SCREEN
// ─────────────────────────────────────────────────────────────────────────────

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
  StreamRecordSettings _settings = StreamRecordSettings();

  // Simulated ffmpeg process handle
  Process? _ffmpegProcess;

  @override
  void initState() {
    super.initState();
    _loadDecks();
    _loadSettings();
  }

  // ── Persistence ─────────────────────────────────────────────────────────

  Future<void> _loadDecks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('presentation_decks');
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

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('presentation_settings');
    if (raw != null) {
      setState(() => _settings = StreamRecordSettings.fromJson(jsonDecode(raw)));
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('presentation_settings', jsonEncode(_settings.toJson()));
  }

  // ── Deck / slide helpers ─────────────────────────────────────────────────

  void _createDeck(Color primary) {
    final deck = Deck(
      id: const Uuid().v4(),
      name: 'New Presentation',
      slides: [],
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

  Color _defaultBg(String type, Color primary) {
    switch (type) {
      case 'title':        return primary;
      case 'scripture':    return Color.lerp(primary, Colors.black, 0.25)!;
      case 'lyric':        return Color.lerp(primary, Colors.black, 0.45)!;
      case 'announcement': return Color.lerp(primary, Colors.purple, 0.4)!;
      default:             return Colors.black;
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
      case 'scripture':    return 'For God so loved the world…';
      case 'lyric':        return 'Type your lyrics here';
      case 'announcement': return 'Details here';
      default: return '';
    }
  }

  // ── Bible verse import ───────────────────────────────────────────────────

  Future<void> _showVerseImport(Color primary, Color secondary) async {
    await showDialog(
      context: context,
      builder: (ctx) => _VerseImportDialog(
        primary:   primary,
        secondary: secondary,
        onImport: (slides) {
          if (_selectedDeck == null) return;
          setState(() {
            _selectedDeck!.slides.addAll(slides);
            _selectedSlide = slides.last;
          });
          _saveDecks();
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported ${slides.length} verse slide(s)')),
          );
        },
      ),
    );
  }

  // ── Planning Center song import ──────────────────────────────────────────

  Future<void> _showSongImport(Color primary, Color secondary) async {
    if (_settings.pcAppId.isEmpty || _settings.pcSecret.isEmpty) {
      _showSettingsRequiredSnack('Planning Center credentials');
      return;
    }
    await showDialog(
      context: context,
      builder: (ctx) => _PlanningCenterImportDialog(
        primary:   primary,
        secondary: secondary,
        appId:     _settings.pcAppId,
        secret:    _settings.pcSecret,
        onImport: (slides) {
          if (_selectedDeck == null) return;
          setState(() {
            _selectedDeck!.slides.addAll(slides);
            _selectedSlide = slides.last;
          });
          _saveDecks();
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported ${slides.length} lyric slide(s)')),
          );
        },
      ),
    );
  }

  void _showSettingsRequiredSnack(String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Please set up $what in Settings first.'),
        action: SnackBarAction(
          label: 'Open Settings',
          onPressed: () => _showSettings(),
        ),
      ),
    );
  }

  // ── Recording ────────────────────────────────────────────────────────────
  //
  // Uses ffmpeg_kit_flutter to record the screen to MP4.
  // Add to pubspec.yaml:
  //   ffmpeg_kit_flutter_full_gpl: ^6.0.3
  //
  // On desktop (macOS / Linux / Windows), we use the avfoundation / x11grab
  // / gdigrab input device.  On mobile a capture approach via RepaintBoundary
  // would be used instead.  The implementation here is wired for desktop/macOS.

  Future<void> _startRecording() async {
    final folder = _settings.outputFolder.isNotEmpty
        ? _settings.outputFolder
        : (await getApplicationDocumentsDirectory()).path;

    final ts       = DateTime.now().toIso8601String().replaceAll(':', '-');
    final outPath  = '$folder/recording_$ts.mp4';
    final res      = _settings.videoResolution;
    final vBitrate = _settings.videoBitrate;
    final aBitrate = _settings.audioBitrate;

    // Build FFmpeg command (macOS screen capture; adapt per platform)
    // For cross-platform you'd detect Platform.isLinux / isWindows etc.
    final args = [
      '-f', 'avfoundation',
      '-capture_cursor', '1',
      '-i', '1:0',                 // screen:audio
      '-vf', 'scale=$res',
      '-c:v', 'libx264',
      '-preset', 'ultrafast',
      '-b:v', '${vBitrate}k',
      '-c:a', 'aac',
      '-b:a', '${aBitrate}k',
      '-movflags', '+faststart',
      outPath,
    ];

    // Using Process.start directly (ffmpeg must be on PATH).
    // Replace with FFmpegKit.executeAsync when using ffmpeg_kit_flutter.
    try {
      _ffmpegProcess = await Process.start('ffmpeg', args);
      setState(() => _isRecording = true);

      // Monitor exit
      _ffmpegProcess!.exitCode.then((_) {
        if (mounted) setState(() => _isRecording = false);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording failed to start: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    // Send 'q' to gracefully stop ffmpeg
    _ffmpegProcess?.stdin.write('q');
    await _ffmpegProcess?.stdin.flush();
    _ffmpegProcess = null;
    setState(() => _isRecording = false);
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  // ── Streaming ────────────────────────────────────────────────────────────
  //
  // RTMP streaming via FFmpeg – works with YouTube Live, Facebook Live,
  // Restream, Boxcast, etc.  Recording and streaming can run concurrently
  // by using FFmpeg's tee muxer.

  Process? _streamProcess;

  Future<void> _startStreaming() async {
    if (_settings.rtmpUrl.isEmpty || _settings.streamKey.isEmpty) {
      _showSettingsRequiredSnack('RTMP URL and stream key');
      return;
    }

    final rtmpFull = '${_settings.rtmpUrl}/${_settings.streamKey}';
    final res      = _settings.videoResolution;
    final vBitrate = _settings.videoBitrate;
    final aBitrate = _settings.audioBitrate;

    final args = [
      '-f', 'avfoundation',
      '-capture_cursor', '1',
      '-i', '1:0',
      '-vf', 'scale=$res',
      '-c:v', 'libx264',
      '-preset', 'veryfast',
      '-b:v', '${vBitrate}k',
      '-maxrate', '${vBitrate}k',
      '-bufsize', '${vBitrate * 2}k',
      '-pix_fmt', 'yuv420p',
      '-g', '50',             // keyframe interval (2s at 25fps)
      '-c:a', 'aac',
      '-b:a', '${aBitrate}k',
      '-f', 'flv',
      rtmpFull,
    ];

    try {
      _streamProcess = await Process.start('ffmpeg', args);
      setState(() => _isStreaming = true);
      _streamProcess!.exitCode.then((_) {
        if (mounted) setState(() => _isStreaming = false);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Streaming failed to start: $e')),
        );
      }
    }
  }

  Future<void> _stopStreaming() async {
    _streamProcess?.stdin.write('q');
    await _streamProcess?.stdin.flush();
    _streamProcess = null;
    setState(() => _isStreaming = false);
  }

  Future<void> _toggleStreaming() async {
    if (_isStreaming) {
      await _stopStreaming();
    } else {
      await _startStreaming();
    }
  }

  // ── Settings ─────────────────────────────────────────────────────────────

  Future<void> _showSettings() async {
    await showDialog(
      context: context,
      builder: (ctx) => _SettingsDialog(
        settings: _settings,
        onSave: (updated) {
          setState(() => _settings = updated);
          _saveSettings();
          Navigator.pop(ctx);
        },
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state     = context.watch<AppState>();
    final primary   = state.brandPrimary;
    final secondary = state.brandSecondary;
    final profile   = state.churchProfile;

    if (_presenting && _selectedDeck != null) {
      return _PresentView(
        deck:           _selectedDeck!,
        primary:        primary,
        secondary:      secondary,
        onExit:         () => setState(() => _presenting = false),
        isStreaming:    _isStreaming,
        isRecording:    _isRecording,
        onToggleStream: () {
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Live streaming is available on desktop only.'),
            behavior: SnackBarBehavior.floating,
          ));
          return;
        }
        setState(() => _isStreaming = !_isStreaming);
      },
      onToggleRecord: () {
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Recording is available on desktop only.'),
            behavior: SnackBarBehavior.floating,
          ));
          return;
        }
        setState(() => _isRecording = !_isRecording);
      },
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
                logoPath:  profile.logoPath,
                primary:   primary,
                secondary: secondary,
                size: 32,
                borderRadius: 8,
              ),
            if (profile != null) const SizedBox(width: 10),
            const Text('Presentation Studio',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          // Record button
          if (_isRecording || _isStreaming) ...[
            if (_isRecording)
              _StatusBadge(label: 'REC', color: Colors.red),
            if (_isStreaming)
              _StatusBadge(label: 'LIVE', color: Colors.green),
            const SizedBox(width: 8),
          ],
          // Import verse
          IconButton(
            tooltip: 'Import Bible Verse',
            icon:    Icon(Icons.menu_book_outlined, color: contrastOn(primary)),
            onPressed: () => _showVerseImport(primary, secondary),
          ),
          // Import Planning Center song
          IconButton(
            tooltip: 'Import Song (Planning Center)',
            icon:    Icon(Icons.music_note_outlined, color: contrastOn(primary)),
            onPressed: () => _showSongImport(primary, secondary),
          ),
          // Record toggle
          IconButton(
            tooltip: _isRecording ? 'Stop Recording' : 'Record to MP4',
            icon: Icon(
              _isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
              color: _isRecording ? Colors.red.shade200 : contrastOn(primary),
            ),
            onPressed: _toggleRecording,
          ),
          // Stream toggle
          IconButton(
            tooltip: _isStreaming ? 'Stop Streaming' : 'Go Live (RTMP)',
            icon: Icon(
              _isStreaming ? Icons.wifi_off : Icons.sensors,
              color: _isStreaming ? Colors.green.shade200 : contrastOn(primary),
            ),
            onPressed: _toggleStreaming,
          ),
          // Settings
          IconButton(
            tooltip: 'Recording & Streaming Settings',
            icon: Icon(Icons.settings_outlined, color: contrastOn(primary)),
            onPressed: _showSettings,
          ),
          // Present
          if (_selectedDeck != null)
            TextButton.icon(
              onPressed: () => setState(() => _presenting = true),
              icon:  Icon(Icons.slideshow, color: contrastOn(primary)),
              label: Text('Present',
                  style: TextStyle(color: contrastOn(primary))),
            ),
        ],
      ),
      body: Row(
        children: [
          // ── Deck list ────────────────────────────────────────────────────
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
          // ── Slide list ───────────────────────────────────────────────────
          if (_selectedDeck != null) ...[
            SizedBox(
              width: 190,
              child: _SlideList(
                deck:          _selectedDeck!,
                selectedSlide: _selectedSlide,
                primary:       primary,
                secondary:     secondary,
                onSelect:  (s) => setState(() => _selectedSlide = s),
                onAdd:     (type) => _addSlide(type, primary, secondary),
                onDelete:  (s) {
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
          // ── Editor / placeholder ─────────────────────────────────────────
          Expanded(
            child: _selectedSlide != null
                ? _SlideEditor(
                    slide:     _selectedSlide!,
                    primary:   primary,
                    secondary: secondary,
                    onChanged: () { _saveDecks(); setState(() {}); },
                  )
                : _selectedDeck != null
                    ? _EmptyDeckPlaceholder(
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

// ─────────────────────────────────────────────────────────────────────────────
// STATUS BADGE (AppBar)
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color  color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BIBLE VERSE IMPORT DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _VerseImportDialog extends StatefulWidget {
  final Color primary;
  final Color secondary;
  final void Function(List<Slide>) onImport;
  const _VerseImportDialog({
    required this.primary, required this.secondary, required this.onImport,
  });

  @override
  State<_VerseImportDialog> createState() => _VerseImportDialogState();
}

class _VerseImportDialogState extends State<_VerseImportDialog> {
  final _ctrl    = TextEditingController();
  bool  _loading = false;
  String? _error;

  // Fetches from the free BSB (Berean Standard Bible) API
  // Endpoint: https://bolls.life/get-text/{translation}/{book}/{chapter}/
  // We also support simple verse lookup via the bolls.life API.
  Future<void> _fetch() async {
    final query = _ctrl.text.trim();
    if (query.isEmpty) return;

    setState(() { _loading = true; _error = null; });

    try {
      // Attempt to parse "Book Chapter:Verse[-Verse]", e.g. "John 3:16" or "Ps 23:1-6"
      // Use bolls.life REST API (free, no key needed)
      // GET https://bolls.life/get-verse/{translation}/{book_id}/{chapter}/{verse}/
      // We'll use the search endpoint for simplicity:
      // GET https://bolls.life/search/{translation}/{query}/
      final encoded = Uri.encodeComponent(query);
      final url = Uri.parse(
          'https://bolls.life/search/BSB/$encoded/');

      final resp = await http.get(url).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) throw Exception('API error ${resp.statusCode}');

      final List data = jsonDecode(resp.body);
      if (data.isEmpty) {
        setState(() { _error = 'No verses found for "$query"'; _loading = false; });
        return;
      }

      final slides = <Slide>[];
      final bgColor = Color.lerp(widget.primary, Colors.black, 0.25)!;

      for (final verse in data.take(10)) {
        final text = (verse['text'] as String? ?? '').trim();
        final ref  = '${verse['bookname'] ?? ''} ${verse['chapter']}:${verse['verse']}';
        if (text.isEmpty) continue;

        slides.add(Slide(
          id:        const Uuid().v4(),
          type:      'scripture',
          title:     ref,
          body:      text,
          reference: ref,
          bgColor:   bgColor,
          textColor: contrastOn(bgColor),
        ));
      }

      if (slides.isEmpty) {
        setState(() { _error = 'Could not parse verse data'; _loading = false; });
        return;
      }

      widget.onImport(slides);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Icon(Icons.menu_book, color: primary),
        const SizedBox(width: 8),
        const Text('Import Bible Verse'),
      ]),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a verse reference or keyword to search the Berean Standard Bible.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'e.g. John 3:16  or  "faith hope love"',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onSubmitted: (_) => _fetch(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            if (_loading) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: primary,
              foregroundColor: contrastOn(primary)),
          onPressed: _loading ? null : _fetch,
          icon: const Icon(Icons.download, size: 16),
          label: const Text('Import'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PLANNING CENTER SONG IMPORT DIALOG
// ─────────────────────────────────────────────────────────────────────────────
//
// Planning Center is the #1 church management platform (used by 80 000+
// churches).  Its Worship/Songs API lets you search songs and retrieve
// arrangements + lyrics.
//
// Auth: HTTP Basic with Application ID + Secret
//   generated at https://api.planningcenteronline.com/oauth/applications
// Docs: https://developer.planning.center/docs/#/apps/services/songs

class _PlanningCenterImportDialog extends StatefulWidget {
  final Color  primary;
  final Color  secondary;
  final String appId;
  final String secret;
  final void Function(List<Slide>) onImport;

  const _PlanningCenterImportDialog({
    required this.primary, required this.secondary,
    required this.appId, required this.secret, required this.onImport,
  });

  @override
  State<_PlanningCenterImportDialog> createState() =>
      _PlanningCenterImportDialogState();
}

class _PlanningCenterImportDialogState
    extends State<_PlanningCenterImportDialog> {
  final _ctrl        = TextEditingController();
  bool  _loading     = false;
  String? _error;
  List<Map<String, dynamic>> _results = [];
  String? _selectedSongId;
  String? _selectedSongTitle;
  List<Map<String, dynamic>> _arrangements = [];

  String get _basicAuth {
    final creds = base64Encode(utf8.encode('${widget.appId}:${widget.secret}'));
    return 'Basic $creds';
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _loading = true; _error = null; _results = []; });

    try {
      final url = Uri.parse(
          'https://api.planningcenteronline.com/services/v2/songs?where[title]=$q&per_page=20');
      final resp = await http.get(url, headers: {'Authorization': _basicAuth})
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 401) throw Exception('Invalid Planning Center credentials');
      if (resp.statusCode != 200) throw Exception('API error ${resp.statusCode}');

      final body = jsonDecode(resp.body) as Map;
      final data = (body['data'] as List?) ?? [];

      setState(() {
        _results = data
            .map((s) => {
                  'id':    s['id'],
                  'title': s['attributes']['title'] ?? 'Untitled',
                  'author': s['attributes']['author'] ?? '',
                })
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadArrangements(String songId, String songTitle) async {
    setState(() { _loading = true; _selectedSongId = songId;
                  _selectedSongTitle = songTitle; _arrangements = []; });

    try {
      final url = Uri.parse(
          'https://api.planningcenteronline.com/services/v2/songs/$songId/arrangements?per_page=10');
      final resp = await http.get(url, headers: {'Authorization': _basicAuth})
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) throw Exception('API error ${resp.statusCode}');

      final body = jsonDecode(resp.body) as Map;
      final data = (body['data'] as List?) ?? [];

      setState(() {
        _arrangements = data.map((a) => {
          'id':    a['id'],
          'name':  a['attributes']['name'] ?? 'Default',
          'chord': a['attributes']['chord_chart'] ?? '',
          'notes': a['attributes']['notes'] ?? '',
        }).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// Fetch the chord chart / lyrics text for a specific arrangement
  Future<void> _importArrangement(String arrangementId, String arrangementName) async {
    setState(() => _loading = true);
    try {
      // Fetch arrangement detail (includes chord_chart with lyrics)
      final url = Uri.parse(
          'https://api.planningcenteronline.com/services/v2/songs/$_selectedSongId/arrangements/$arrangementId');
      final resp = await http.get(url, headers: {'Authorization': _basicAuth})
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) throw Exception('API error ${resp.statusCode}');

      final body = jsonDecode(resp.body) as Map;
      final attrs = body['data']?['attributes'] ?? {};
      final rawLyrics = (attrs['chord_chart'] ?? attrs['lyrics'] ?? '') as String;

      final slides = _parseLyricsToSlides(rawLyrics, _selectedSongTitle!);
      if (slides.isEmpty) {
        setState(() { _error = 'No lyrics found in this arrangement'; _loading = false; });
        return;
      }

      widget.onImport(slides);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// Splits a lyrics blob into one slide per section
  List<Slide> _parseLyricsToSlides(String raw, String songTitle) {
    if (raw.trim().isEmpty) return [];

    final bgColor = const Color(0xFF1A1A2E); // dark for lyrics
    final slides  = <Slide>[];

    // Split on blank lines – each paragraph = one slide
    final sections = raw.split(RegExp(r'\n{2,}'));
    int idx = 1;
    for (final section in sections) {
      final text = section.trim();
      if (text.isEmpty) continue;

      // Determine section label
      final firstLine = text.split('\n').first.trim();
      final isLabel   = firstLine.startsWith(RegExp(r'[A-Z][a-z]'));
      final title     = isLabel ? firstLine : 'Verse $idx';
      final body      = isLabel ? text.substring(firstLine.length).trim() : text;
      if (!isLabel) idx++;

      slides.add(Slide(
        id:        const Uuid().v4(),
        type:      'lyric',
        title:     '$songTitle – $title',
        body:      body,
        reference: songTitle,
        bgColor:   bgColor,
        textColor: Colors.white,
        fontSize:  36,
      ));
    }
    return slides;
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Icon(Icons.music_note, color: primary),
        const SizedBox(width: 8),
        const Text('Import from Planning Center'),
      ]),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          children: [
            // Search row
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search song title…',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: primary,
                    foregroundColor: contrastOn(primary)),
                onPressed: _loading ? null : _search,
                child: const Text('Search'),
              ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 8),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_arrangements.isNotEmpty) ...[
              // Arrangement picker
              Text('Choose arrangement for "$_selectedSongTitle"',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.builder(
                  itemCount: _arrangements.length,
                  itemBuilder: (ctx, i) {
                    final a = _arrangements[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.queue_music, color: primary),
                      title: Text(a['name']),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: contrastOn(primary),
                            padding: const EdgeInsets.symmetric(horizontal: 12)),
                        onPressed: () => _importArrangement(a['id'], a['name']),
                        child: const Text('Import'),
                      ),
                    );
                  },
                ),
              ),
              TextButton(
                onPressed: () => setState(() { _arrangements = []; _selectedSongId = null; }),
                child: const Text('← Back to results'),
              ),
            ] else if (_results.isNotEmpty) ...[
              // Song list
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (ctx, i) {
                    final s = _results[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.music_note, color: primary),
                      title: Text(s['title']),
                      subtitle: s['author'].isNotEmpty ? Text(s['author']) : null,
                      onTap: () => _loadArrangements(s['id'], s['title']),
                      trailing: const Icon(Icons.chevron_right),
                    );
                  },
                ),
              ),
            ] else ...[
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('Search for a song above',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SETTINGS DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsDialog extends StatefulWidget {
  final StreamRecordSettings settings;
  final void Function(StreamRecordSettings) onSave;

  const _SettingsDialog({required this.settings, required this.onSave});

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final TextEditingController _folderCtrl;
  late final TextEditingController _rtmpCtrl;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _pcAppCtrl;
  late final TextEditingController _pcSecretCtrl;
  late String _resolution;
  late int    _vBitrate;
  late int    _aBitrate;
  bool _showKey = false;
  bool _showSecret = false;

  @override
  void initState() {
    super.initState();
    _tabs         = TabController(length: 3, vsync: this);
    _folderCtrl   = TextEditingController(text: widget.settings.outputFolder);
    _rtmpCtrl     = TextEditingController(text: widget.settings.rtmpUrl);
    _keyCtrl      = TextEditingController(text: widget.settings.streamKey);
    _pcAppCtrl    = TextEditingController(text: widget.settings.pcAppId);
    _pcSecretCtrl = TextEditingController(text: widget.settings.pcSecret);
    _resolution   = widget.settings.videoResolution;
    _vBitrate     = widget.settings.videoBitrate;
    _aBitrate     = widget.settings.audioBitrate;
  }

  @override
  void dispose() {
    _tabs.dispose();
    _folderCtrl.dispose();
    _rtmpCtrl.dispose();
    _keyCtrl.dispose();
    _pcAppCtrl.dispose();
    _pcSecretCtrl.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(StreamRecordSettings(
      outputFolder:    _folderCtrl.text.trim(),
      videoResolution: _resolution,
      videoBitrate:    _vBitrate,
      audioBitrate:    _aBitrate,
      audioDevice:     widget.settings.audioDevice,
      rtmpUrl:         _rtmpCtrl.text.trim(),
      streamKey:       _keyCtrl.text.trim(),
      pcAppId:         _pcAppCtrl.text.trim(),
      pcSecret:        _pcSecretCtrl.text.trim(),
    ));
  }

  static const _resolutions = ['1920x1080', '1280x720', '854x480', '640x360'];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [
        Icon(Icons.settings),
        SizedBox(width: 8),
        Text('Recording & Streaming Settings'),
      ]),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          children: [
            TabBar(
              controller: _tabs,
              labelColor: Theme.of(context).colorScheme.primary,
              tabs: const [
                Tab(icon: Icon(Icons.fiber_manual_record, size: 18), text: 'Recording'),
                Tab(icon: Icon(Icons.sensors, size: 18), text: 'Streaming'),
                Tab(icon: Icon(Icons.music_note, size: 18), text: 'Planning Center'),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  // ── Recording tab ──────────────────────────────────────
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Output Folder',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _folderCtrl,
                              decoration: InputDecoration(
                                hintText: 'Leave blank for Documents folder',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                isDense: true,
                              ),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        const Text('Video Resolution',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          value: _resolution,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                          items: _resolutions
                              .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                              .toList(),
                          onChanged: (v) => setState(() => _resolution = v!),
                        ),
                        const SizedBox(height: 16),
                        const Text('Video Bitrate (kbps)',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        Slider(
                          value: _vBitrate.toDouble(),
                          min: 500, max: 12000, divisions: 23,
                          label: '${_vBitrate}k',
                          onChanged: (v) => setState(() => _vBitrate = v.round()),
                        ),
                        const Text('Audio Bitrate (kbps)',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        Slider(
                          value: _aBitrate.toDouble(),
                          min: 64, max: 320, divisions: 8,
                          label: '${_aBitrate}k',
                          onChanged: (v) => setState(() => _aBitrate = v.round()),
                        ),
                        Text('Output files will be saved as .mp4 (H.264 + AAC)',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),

                  // ── Streaming tab ──────────────────────────────────────
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('RTMP Server URL',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _rtmpCtrl,
                          decoration: InputDecoration(
                            hintText: 'rtmp://a.rtmp.youtube.com/live2',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: [
                            ActionChip(
                              label: const Text('YouTube'),
                              onPressed: () => _rtmpCtrl.text =
                                  'rtmp://a.rtmp.youtube.com/live2',
                            ),
                            ActionChip(
                              label: const Text('Facebook'),
                              onPressed: () => _rtmpCtrl.text =
                                  'rtmps://live-api-s.facebook.com:443/rtmp',
                            ),
                            ActionChip(
                              label: const Text('Boxcast'),
                              onPressed: () => _rtmpCtrl.text =
                                  'rtmp://publish.boxcast.tv/live',
                            ),
                            ActionChip(
                              label: const Text('Restream'),
                              onPressed: () => _rtmpCtrl.text =
                                  'rtmp://live.restream.io/live',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text('Stream Key',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _keyCtrl,
                          obscureText: !_showKey,
                          decoration: InputDecoration(
                            hintText: 'xxxx-xxxx-xxxx-xxxx',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: Icon(_showKey
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setState(() => _showKey = !_showKey),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Recording and streaming can run simultaneously.\n'
                          'Both use the resolution and bitrate settings from the Recording tab.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),

                  // ── Planning Center tab ────────────────────────────────
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Text('Planning Center API Credentials',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          TextButton.icon(
                            icon: const Icon(Icons.open_in_new, size: 14),
                            label: const Text('Get credentials'),
                            onPressed: () => launchUrl(Uri.parse(
                                'https://api.planningcenteronline.com/oauth/applications')),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Text(
                          'Create a Personal Access Token at '
                          'api.planningcenteronline.com → Personal Access Tokens. '
                          'You\'ll need access to the Services (Worship) product.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pcAppCtrl,
                          decoration: InputDecoration(
                            labelText: 'Application ID',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pcSecretCtrl,
                          obscureText: !_showSecret,
                          decoration: InputDecoration(
                            labelText: 'Secret',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: Icon(_showSecret
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setState(() => _showSecret = !_showSecret),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save Settings'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DECK LIST
// ─────────────────────────────────────────────────────────────────────────────

class _DeckList extends StatelessWidget {
  final List<Deck> decks;
  final Deck?      selectedDeck;
  final Color      primary;
  final Color      secondary;
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
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: contrastOn(primary)),
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New Presentation'),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: decks.length,
            itemBuilder: (ctx, i) {
              final deck     = decks[i];
              final selected = deck.id == selectedDeck?.id;
              return ListTile(
                selected: selected,
                selectedTileColor: primary.withValues(alpha: 0.1),
                dense: true,
                leading: Icon(Icons.slideshow,
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
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
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

// ─────────────────────────────────────────────────────────────────────────────
// SLIDE LIST
// ─────────────────────────────────────────────────────────────────────────────

class _SlideList extends StatelessWidget {
  final Deck  deck;
  final Slide? selectedSlide;
  final Color  primary;
  final Color  secondary;
  final ValueChanged<Slide>  onSelect;
  final ValueChanged<String> onAdd;
  final ValueChanged<Slide>  onDelete;
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
                  borderRadius: BorderRadius.circular(8)),
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
                    color:  slide.bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? secondary : Colors.transparent,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(slide.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: slide.textColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                      if (slide.body.isNotEmpty)
                        Text(slide.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: slide.textColor.withValues(alpha: 0.75),
                                fontSize: 10)),
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

// ─────────────────────────────────────────────────────────────────────────────
// SLIDE EDITOR
// ─────────────────────────────────────────────────────────────────────────────

class _SlideEditor extends StatefulWidget {
  final Slide  slide;
  final Color  primary;
  final Color  secondary;
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

  List<Color> _bgPresets() => [
    widget.primary,
    Color.lerp(widget.primary, Colors.black, 0.25)!,
    Color.lerp(widget.primary, Colors.black, 0.45)!,
    Colors.black,
    Colors.white,
    const Color(0xFF1B2838),
    const Color(0xFF006400),
    const Color(0xFF7B0000),
  ];

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.slide.title);
    _bodyCtrl  = TextEditingController(text: widget.slide.body);
    _refCtrl   = TextEditingController(text: widget.slide.reference);
  }

  @override
  void didUpdateWidget(_SlideEditor old) {
    super.didUpdateWidget(old);
    if (old.slide.id != widget.slide.id) {
      _titleCtrl.text = widget.slide.title;
      _bodyCtrl.text  = widget.slide.body;
      _refCtrl.text   = widget.slide.reference;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary   = widget.primary;
    final secondary = widget.secondary;
    final presets   = _bgPresets();

    return Row(
      children: [
        // ── Left: edit panel ─────────────────────────────────────────────
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
                        labelText: 'Reference',
                        hintText: 'e.g. John 3:16'),
                    onChanged: (v) { widget.slide.reference = v; widget.onChanged(); },
                  ),
                ],
                const SizedBox(height: 20),
                const Text('Font Size',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Slider(
                  value: widget.slide.fontSize,
                  min: 18, max: 72,
                  label: widget.slide.fontSize.round().toString(),
                  onChanged: (v) {
                    setState(() => widget.slide.fontSize = v);
                    widget.onChanged();
                  },
                ),
                const SizedBox(height: 16),
                const Text('Background Color',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: presets.map((c) {
                    final sel = widget.slide.bgColor.toARGB32() == c.toARGB32();
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          widget.slide.bgColor   = c;
                          widget.slide.textColor = contrastOn(c);
                        });
                        widget.onChanged();
                      },
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: sel ? secondary : Colors.grey.shade300,
                            width: sel ? 3 : 1,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        // ── Right: preview ───────────────────────────────────────────────
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: _SlidePreview(slide: widget.slide),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SLIDE PREVIEW
// ─────────────────────────────────────────────────────────────────────────────

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
                    color: slide.textColor,
                    fontSize: slide.fontSize * 0.38,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
          if (slide.body.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(slide.body,
                style: TextStyle(
                    color: slide.textColor,
                    fontSize: slide.fontSize * 0.28,
                    height: 1.5),
                textAlign: TextAlign.center),
          ],
          if (slide.reference.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(slide.reference,
                style: TextStyle(
                    color: slide.textColor.withValues(alpha: 0.65),
                    fontSize: slide.fontSize * 0.2,
                    fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY / NO DECK PLACEHOLDERS
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyDeckPlaceholder extends StatelessWidget {
  final Color  primary;
  final Color  secondary;
  final ValueChanged<String> onAdd;

  const _EmptyDeckPlaceholder({
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
              _QuickAdd(label: 'Title Slide',   type: 'title',     primary: primary, onAdd: onAdd),
              _QuickAdd(label: 'Scripture',     type: 'scripture', primary: primary, onAdd: onAdd),
              _QuickAdd(label: 'Song Lyric',    type: 'lyric',     primary: primary, onAdd: onAdd),
              _QuickAdd(label: 'Announcement',  type: 'announcement', primary: primary, onAdd: onAdd),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickAdd extends StatelessWidget {
  final String label, type;
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
          side: BorderSide(color: primary), foregroundColor: primary),
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

// ─────────────────────────────────────────────────────────────────────────────
// FULL-SCREEN PRESENTATION VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _PresentView extends StatefulWidget {
  final Deck         deck;
  final Color        primary;
  final Color        secondary;
  final VoidCallback onExit;
  final bool         isStreaming;
  final bool         isRecording;
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
  int  _idx          = 0;
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

    final slide = slides[_idx];

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
            // ── Slide fill ───────────────────────────────────────────────
            SizedBox.expand(
              child: Container(
                color:   slide.bgColor,
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

            // ── Status badges (top-right) ────────────────────────────────
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

            // ── Controls overlay ─────────────────────────────────────────
            if (_showControls)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Row(
                    children: [
                      // Slide nav
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios,
                            color: Colors.white),
                        onPressed: _idx > 0
                            ? () => setState(() => _idx--)
                            : null,
                      ),
                      Text('${_idx + 1} / ${slides.length}',
                          style: const TextStyle(color: Colors.white)),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward_ios,
                            color: Colors.white),
                        onPressed: _idx < slides.length - 1
                            ? () => setState(() => _idx++)
                            : null,
                      ),
                      const Spacer(),
                      // Record
                      IconButton(
                        tooltip: widget.isRecording
                            ? 'Stop Recording'
                            : 'Record to MP4',
                        icon: Icon(
                          widget.isRecording
                              ? Icons.stop_circle
                              : Icons.fiber_manual_record,
                          color: widget.isRecording
                              ? Colors.red
                              : Colors.white,
                        ),
                        onPressed: widget.onToggleRecord,
                      ),
                      // Stream
                      IconButton(
                        tooltip: widget.isStreaming
                            ? 'Stop Streaming'
                            : 'Go Live',
                        icon: Icon(
                          widget.isStreaming
                              ? Icons.wifi_off
                              : Icons.sensors,
                          color: widget.isStreaming
                              ? Colors.green
                              : Colors.white,
                        ),
                        onPressed: widget.onToggleStream,
                      ),
                      const SizedBox(width: 8),
                      // Exit
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.15)),
                        onPressed: widget.onExit,
                        icon: const Icon(Icons.close,
                            size: 16, color: Colors.white),
                        label: const Text('Exit',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color  color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8, height: 8,
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}