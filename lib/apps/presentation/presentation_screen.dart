// lib/apps/presentation/presentation_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

// ── STREAM / RECORD SETTINGS ─────────────────────────────────────────────────
class _StreamSettings {
  String rtmpUrl;
  String streamKey;
  String platform; // 'youtube', 'facebook', 'twitch', 'custom'

  _StreamSettings({
    this.rtmpUrl   = '',
    this.streamKey = '',
    this.platform  = 'youtube',
  });

  String get fullRtmpUrl {
    if (platform != 'custom' && rtmpUrl.isNotEmpty && streamKey.isNotEmpty) {
      return '$rtmpUrl/$streamKey';
    }
    return rtmpUrl;
  }

  Map<String, dynamic> toJson() =>
      {'rtmpUrl': rtmpUrl, 'streamKey': streamKey, 'platform': platform};

  factory _StreamSettings.fromJson(Map<String, dynamic> j) => _StreamSettings(
        rtmpUrl:   j['rtmpUrl']   ?? '',
        streamKey: j['streamKey'] ?? '',
        platform:  j['platform']  ?? 'youtube',
      );

  static const Map<String, Map<String, String>> platformDefaults = {
    'youtube':  {'name': 'YouTube Live',   'url': 'rtmp://a.rtmp.youtube.com/live2',      'icon': '▶'},
    'facebook': {'name': 'Facebook Live',  'url': 'rtmps://live-api-s.facebook.com:443/rtmp', 'icon': 'f'},
    'twitch':   {'name': 'Twitch',         'url': 'rtmp://live.twitch.tv/app',             'icon': '🎮'},
    'custom':   {'name': 'Custom RTMP',    'url': '',                                       'icon': '⚙'},
  };
}

class _RecordSettings {
  String savePath;
  String quality; // 'high', 'medium', 'low'
  String format;  // 'mp4', 'mkv', 'mov'

  _RecordSettings({
    this.savePath = '',
    this.quality  = 'high',
    this.format   = 'mp4',
  });

  Map<String, dynamic> toJson() =>
      {'savePath': savePath, 'quality': quality, 'format': format};

  factory _RecordSettings.fromJson(Map<String, dynamic> j) => _RecordSettings(
        savePath: j['savePath'] ?? '',
        quality:  j['quality']  ?? 'high',
        format:   j['format']   ?? 'mp4',
      );
}

// ── SCREEN ────────────────────────────────────────────────────────────────────
class PresentationScreen extends StatefulWidget {
  const PresentationScreen({super.key});

  @override
  State<PresentationScreen> createState() => _PresentationScreenState();
}

class _PresentationScreenState extends State<PresentationScreen> {
  List<Deck> _decks         = [];
  Deck?      _selectedDeck;
  Slide?     _selectedSlide;
  bool       _presenting    = false;
  bool       _isStreaming   = false;
  bool       _isRecording   = false;

  _StreamSettings _streamSettings = _StreamSettings();
  _RecordSettings _recordSettings = _RecordSettings();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString('presentation_decks');
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      setState(() => _decks = list.map((d) => Deck.fromJson(d)).toList());
    }

    final streamRaw = prefs.getString('presentation_stream_settings');
    if (streamRaw != null) {
      _streamSettings = _StreamSettings.fromJson(jsonDecode(streamRaw));
    }

    final recordRaw = prefs.getString('presentation_record_settings');
    if (recordRaw != null) {
      _recordSettings = _RecordSettings.fromJson(jsonDecode(recordRaw));
    }
  }

  Future<void> _saveDecks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('presentation_decks',
        jsonEncode(_decks.map((d) => d.toJson()).toList()));
  }

  Future<void> _saveStreamSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'presentation_stream_settings', jsonEncode(_streamSettings.toJson()));
  }

  Future<void> _saveRecordSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'presentation_record_settings', jsonEncode(_recordSettings.toJson()));
  }

  // ── STREAM DIALOG ───────────────────────────────────────────────────────────

  Future<bool> _showStreamDialog() async {
    final settings = _StreamSettings(
      rtmpUrl:   _streamSettings.rtmpUrl,
      streamKey: _streamSettings.streamKey,
      platform:  _streamSettings.platform,
    );

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _StreamSetupDialog(settings: settings),
    );

    if (result == true) {
      _streamSettings = settings;
      await _saveStreamSettings();
      return true;
    }
    return false;
  }

  // ── RECORD DIALOG ───────────────────────────────────────────────────────────

  Future<bool> _showRecordDialog() async {
    final settings = _RecordSettings(
      savePath: _recordSettings.savePath,
      quality:  _recordSettings.quality,
      format:   _recordSettings.format,
    );

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _RecordSetupDialog(settings: settings),
    );

    if (result == true) {
      _recordSettings = settings;
      await _saveRecordSettings();
      return true;
    }
    return false;
  }

  // ── TOGGLE HANDLERS ─────────────────────────────────────────────────────────

  Future<void> _handleToggleStream() async {
    if (_isStreaming) {
      // Stop streaming
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Stop Live Stream?'),
          content: const Text(
              'This will end your live stream. Viewers will see the stream as ended.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Stop Stream',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm == true) {
        setState(() => _isStreaming = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🔴 Stream ended'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } else {
      // Start streaming — show setup dialog
      final ok = await _showStreamDialog();
      if (ok && mounted) {
        setState(() => _isStreaming = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '🟢 Streaming live to ${_StreamSettings.platformDefaults[_streamSettings.platform]!['name']}'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleToggleRecord() async {
    if (_isRecording) {
      // Stop recording
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Stop Recording?'),
          content: const Text('This will save and finalize your recording.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Stop Recording',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm == true) {
        setState(() => _isRecording = false);
        if (mounted) {
          final savePath = _recordSettings.savePath.isNotEmpty
              ? _recordSettings.savePath
              : _defaultSavePath();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⏹ Recording saved to $savePath'),
              backgroundColor: Colors.blueGrey,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } else {
      // Start recording — show setup dialog
      final ok = await _showRecordDialog();
      if (ok && mounted) {
        setState(() => _isRecording = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⏺ Recording started'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _defaultSavePath() {
    if (kIsWeb) return 'Downloads folder';
    if (Platform.isAndroid) return '/storage/emulated/0/Movies';
    if (Platform.isIOS) return 'Photos app';
    if (Platform.isMacOS) return '~/Movies';
    if (Platform.isWindows) return r'C:\Users\Videos';
    return '~/Videos';
  }

  // ── DECK / SLIDE MANAGEMENT ─────────────────────────────────────────────────

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

  // ── BUILD ───────────────────────────────────────────────────────────────────

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
        onToggleStream:  _handleToggleStream,
        onToggleRecord:  _handleToggleRecord,
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
          // Live indicators visible even outside present mode
          if (_isRecording)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _Badge(label: 'REC', color: Colors.red),
            ),
          if (_isStreaming)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _Badge(label: 'LIVE', color: Colors.green),
            ),
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
                    : _NoDeckSelected(primary: primary),
          ),
        ],
      ),
    );
  }
}

// ── STREAM SETUP DIALOG ───────────────────────────────────────────────────────
class _StreamSetupDialog extends StatefulWidget {
  final _StreamSettings settings;
  const _StreamSetupDialog({required this.settings});

  @override
  State<_StreamSetupDialog> createState() => _StreamSetupDialogState();
}

class _StreamSetupDialogState extends State<_StreamSetupDialog> {
  late TextEditingController _urlCtrl;
  late TextEditingController _keyCtrl;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.settings.rtmpUrl);
    _keyCtrl = TextEditingController(text: widget.settings.streamKey);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  void _selectPlatform(String platform) {
    setState(() {
      widget.settings.platform = platform;
      final defaults = _StreamSettings.platformDefaults[platform]!;
      if (platform != 'custom') {
        widget.settings.rtmpUrl = defaults['url']!;
        _urlCtrl.text = defaults['url']!;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.wifi, color: Colors.green),
          SizedBox(width: 10),
          Text('Live Stream Setup'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Platform selector
              Text('Select Platform',
                  style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _StreamSettings.platformDefaults.entries.map((e) {
                  final selected = widget.settings.platform == e.key;
                  return ChoiceChip(
                    label: Text(e.value['name']!),
                    selected: selected,
                    onSelected: (_) => _selectPlatform(e.key),
                    selectedColor: Colors.green.shade100,
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Platform instructions
              if (widget.settings.platform != 'custom')
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('📋 How to get your stream key:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900)),
                      const SizedBox(height: 6),
                      Text(_platformInstructions(widget.settings.platform),
                          style: TextStyle(
                              fontSize: 12, color: Colors.blue.shade800)),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              // RTMP URL (editable for custom, read-only for presets)
              if (widget.settings.platform == 'custom') ...[
                Text('RTMP Server URL',
                    style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                TextField(
                  controller: _urlCtrl,
                  onChanged: (v) => widget.settings.rtmpUrl = v.trim(),
                  decoration: const InputDecoration(
                    hintText: 'rtmp://your-server/live',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Stream Key
              Text('Stream Key',
                  style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              TextField(
                controller: _keyCtrl,
                obscureText: _obscureKey,
                onChanged: (v) => widget.settings.streamKey = v.trim(),
                decoration: InputDecoration(
                  hintText: 'Paste your stream key here',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.key),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                            _obscureKey ? Icons.visibility : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                        tooltip: _obscureKey ? 'Show' : 'Hide',
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: _keyCtrl.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Stream key copied')),
                          );
                        },
                        tooltip: 'Copy',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Security note
              const Row(
                children: [
                  Icon(Icons.lock_outline, size: 14, color: Colors.grey),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Your stream key is stored locally and never shared.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                ],
              ),

              // Platform-specific mobile note
              if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.phone_android,
                          size: 16, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Mobile tip: Ensure you have a stable Wi-Fi or 4G/5G connection for uninterrupted streaming.',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            final key = _keyCtrl.text.trim();
            final url = widget.settings.platform == 'custom'
                ? _urlCtrl.text.trim()
                : _StreamSettings.platformDefaults[widget.settings.platform]!['url']!;

            if (key.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please enter your stream key'),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }
            if (widget.settings.platform == 'custom' && url.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please enter an RTMP server URL'),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }

            widget.settings.rtmpUrl   = url;
            widget.settings.streamKey = key;
            Navigator.pop(context, true);
          },
          icon: const Icon(Icons.stream),
          label: const Text('Go Live'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green,
              foregroundColor: Colors.white),
        ),
      ],
    );
  }

  String _platformInstructions(String platform) {
    switch (platform) {
      case 'youtube':
        return '1. Go to YouTube Studio → Go Live\n'
               '2. Click "Stream" tab\n'
               '3. Copy the Stream key from "Stream settings"';
      case 'facebook':
        return '1. Go to facebook.com/live/producer\n'
               '2. Create a new live video\n'
               '3. Copy the Stream key shown';
      case 'twitch':
        return '1. Go to Twitch → Settings → Stream\n'
               '2. Click "Copy" next to Primary Stream key';
      default:
        return 'Enter your RTMP server URL and stream key below.';
    }
  }
}

// ── RECORD SETUP DIALOG ───────────────────────────────────────────────────────
class _RecordSetupDialog extends StatefulWidget {
  final _RecordSettings settings;
  const _RecordSetupDialog({required this.settings});

  @override
  State<_RecordSetupDialog> createState() => _RecordSetupDialogState();
}

class _RecordSetupDialogState extends State<_RecordSetupDialog> {
  late TextEditingController _pathCtrl;

  @override
  void initState() {
    super.initState();
    _pathCtrl = TextEditingController(text: widget.settings.savePath);
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  String _defaultPath() {
    if (kIsWeb) return 'Downloads';
    if (Platform.isAndroid) return '/storage/emulated/0/Movies';
    if (Platform.isIOS) return 'Photos';
    if (Platform.isMacOS) return '${Platform.environment['HOME'] ?? ''}/Movies';
    if (Platform.isWindows) {
      return '${Platform.environment['USERPROFILE'] ?? 'C:\\Users\\User'}\\Videos';
    }
    return '${Platform.environment['HOME'] ?? ''}/Videos';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Use default path if none set
    if (widget.settings.savePath.isEmpty) {
      widget.settings.savePath = _defaultPath();
      _pathCtrl.text = widget.settings.savePath;
    }

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.fiber_manual_record, color: Colors.red),
          SizedBox(width: 10),
          Text('Recording Setup'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Quality
              Text('Quality',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final q in ['high', 'medium', 'low'])
                    ChoiceChip(
                      label: Text({
                        'high':   '🎬 High (1080p)',
                        'medium': '📹 Medium (720p)',
                        'low':    '📱 Low (480p)',
                      }[q]!),
                      selected: widget.settings.quality == q,
                      onSelected: (_) =>
                          setState(() => widget.settings.quality = q),
                      selectedColor: Colors.red.shade100,
                    ),
                ],
              ),
              const SizedBox(height: 18),

              // Format
              Text('Format',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in ['mp4', 'mkv', 'mov'])
                    ChoiceChip(
                      label: Text(f.toUpperCase()),
                      selected: widget.settings.format == f,
                      onSelected: (_) =>
                          setState(() => widget.settings.format = f),
                      selectedColor: Colors.red.shade100,
                    ),
                ],
              ),
              const SizedBox(height: 18),

              // Save location
              if (!kIsWeb && !Platform.isIOS && !Platform.isAndroid) ...[
                Text('Save Location',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _pathCtrl,
                  onChanged: (v) => widget.settings.savePath = v,
                  decoration: InputDecoration(
                    hintText: 'Folder path',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.folder_open),
                    suffixIcon: TextButton(
                      onPressed: () {
                        // Reset to default
                        setState(() {
                          widget.settings.savePath = _defaultPath();
                          _pathCtrl.text = widget.settings.savePath;
                        });
                      },
                      child: const Text('Default'),
                    ),
                  ),
                ),
              ] else ...[
                // Mobile / web save info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        kIsWeb
                            ? Icons.download
                            : (Platform.isIOS
                                ? Icons.photo_library
                                : Icons.sd_storage),
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          kIsWeb
                              ? 'Recording will be downloaded to your Downloads folder.'
                              : Platform.isIOS
                                  ? 'Recording will be saved to your Photos library.'
                                  : 'Recording will be saved to Movies folder on your device.',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Storage estimate
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      'Estimated storage: ${_estimateStorage(widget.settings.quality)}/hour',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.fiber_manual_record),
          label: const Text('Start Recording'),
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red, foregroundColor: Colors.white),
        ),
      ],
    );
  }

  String _estimateStorage(String quality) {
    switch (quality) {
      case 'high':   return '~4 GB';
      case 'medium': return '~2 GB';
      case 'low':    return '~700 MB';
      default:       return '~2 GB';
    }
  }
}

// ── DECK LIST ─────────────────────────────────────────────────────────────────
class _DeckList extends StatelessWidget {
  final List<Deck>         decks;
  final Deck?              selectedDeck;
  final Color              primary;
  final Color              secondary;
  final ValueChanged<Deck> onSelect;
  final VoidCallback       onAdd;
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
              icon: Icon(Icons.add, color: contrastOn(primary)),
              label: Text('New Deck',
                  style: TextStyle(color: contrastOn(primary))),
              style: ElevatedButton.styleFrom(backgroundColor: primary),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: decks.isEmpty
              ? const Center(
                  child: Text('No presentations yet',
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: decks.length,
                  itemBuilder: (_, i) {
                    final deck     = decks[i];
                    final selected = selectedDeck?.id == deck.id;
                    return ListTile(
                      selected:  selected,
                      selectedTileColor: primary.withValues(alpha: 0.1),
                      leading: Icon(Icons.slideshow,
                          color: selected ? primary : Colors.grey),
                      title: Text(deck.name,
                          style: TextStyle(
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal)),
                      subtitle: Text('${deck.slides.length} slides',
                          style: const TextStyle(fontSize: 11)),
                      onTap: () => onSelect(deck),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: Colors.red),
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
  final Deck              deck;
  final Slide?            selectedSlide;
  final Color             primary;
  final Color             secondary;
  final ValueChanged<Slide>      onSelect;
  final ValueChanged<String>     onAdd;
  final ValueChanged<Slide>      onDelete;
  final Function(int, int)       onReorder;

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
        // Add slide buttons
        Padding(
          padding: const EdgeInsets.all(8),
          child: PopupMenuButton<String>(
            onSelected: onAdd,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'title',        child: Text('Title Slide')),
              PopupMenuItem(value: 'scripture',    child: Text('Scripture')),
              PopupMenuItem(value: 'lyric',        child: Text('Lyrics')),
              PopupMenuItem(value: 'announcement', child: Text('Announcement')),
              PopupMenuItem(value: 'blank',        child: Text('Blank')),
            ],
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color:        primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border:       Border.all(color: primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, color: primary, size: 18),
                  const SizedBox(width: 6),
                  Text('Add Slide',
                      style: TextStyle(color: primary,
                          fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: deck.slides.isEmpty
              ? const Center(
                  child: Text('No slides', style: TextStyle(color: Colors.grey)))
              : ReorderableListView.builder(
                  itemCount: deck.slides.length,
                  onReorder:   onReorder,
                  itemBuilder: (_, i) {
                    final s        = deck.slides[i];
                    final selected = selectedSlide?.id == s.id;
                    return GestureDetector(
                      key:     ValueKey(s.id),
                      onTap:   () => onSelect(s),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        height: 70,
                        decoration: BoxDecoration(
                          color: s.bgColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected ? secondary : Colors.transparent,
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

  List<Color> _bgPresets() {
    final p = widget.primary;
    return [
      p,
      Color.lerp(p, Colors.black, 0.25)!,
      Color.lerp(p, Colors.black, 0.5)!,
      Color.lerp(p, Colors.white, 0.7)!,
      Colors.black,
      Colors.white,
      Colors.blueGrey.shade900,
      Colors.purple.shade900,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final slide = widget.slide;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live preview
          Center(
            child: Container(
              width: 480, height: 270,
              decoration: BoxDecoration(
                color:        slide.bgColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color:     Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20),
                ],
              ),
              padding: const EdgeInsets.all(32),
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
                            color:     slide.textColor.withValues(alpha: 0.65),
                            fontSize:  slide.fontSize * 0.2,
                            fontStyle: FontStyle.italic)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Fields
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
                labelText: 'Title', border: OutlineInputBorder()),
            onChanged: (v) {
              slide.title = v;
              widget.onChanged();
              setState(() {});
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
                labelText: 'Body text', border: OutlineInputBorder()),
            onChanged: (v) {
              slide.body = v;
              widget.onChanged();
              setState(() {});
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _refCtrl,
            decoration: const InputDecoration(
                labelText: 'Reference (optional)',
                border: OutlineInputBorder()),
            onChanged: (v) {
              slide.reference = v;
              widget.onChanged();
              setState(() {});
            },
          ),
          const SizedBox(height: 20),

          // Font size
          Row(
            children: [
              const Text('Font size: '),
              Expanded(
                child: Slider(
                  value: slide.fontSize,
                  min: 20, max: 80,
                  divisions: 12,
                  label: slide.fontSize.round().toString(),
                  onChanged: (v) {
                    slide.fontSize = v;
                    widget.onChanged();
                    setState(() {});
                  },
                ),
              ),
              Text(slide.fontSize.round().toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),

          // Background color
          const Text('Background color:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _bgPresets().map((color) {
              final sel = slide.bgColor.toARGB32() == color.toARGB32();
              return GestureDetector(
                onTap: () {
                  slide.bgColor  = color;
                  slide.textColor = contrastOn(color);
                  widget.onChanged();
                  setState(() {});
                },
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color:        color,
                    shape:        BoxShape.circle,
                    border: Border.all(
                      color: sel ? widget.secondary : Colors.grey.shade300,
                      width: sel ? 3 : 1,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
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

            // Slide counter (always visible)
            Positioned(
              top: 16, left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${_idx + 1} / ${slides.length}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12)),
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
            ],
          ],
        ),
      ),
    );
  }
}

// ── EMPTY / PLACEHOLDER WIDGETS ───────────────────────────────────────────────
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
          Icon(Icons.add_photo_alternate_outlined,
              size: 64, color: primary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text('Add your first slide',
              style: TextStyle(
                  fontSize: 18, color: primary.withValues(alpha: 0.7))),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12, runSpacing: 12,
            children: [
              for (final type in ['title', 'scripture', 'lyric', 'announcement', 'blank'])
                ElevatedButton(
                  onPressed: () => onAdd(type),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: primary.withValues(alpha: 0.1),
                      foregroundColor: primary),
                  child: Text(type[0].toUpperCase() + type.substring(1)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoDeckSelected extends StatelessWidget {
  final Color primary;
  const _NoDeckSelected({required this.primary});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.slideshow,
              size: 72, color: primary.withValues(alpha: 0.25)),
          const SizedBox(height: 16),
          Text('Select or create a deck to get started',
              style: TextStyle(
                  color: primary.withValues(alpha: 0.5), fontSize: 15)),
        ],
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