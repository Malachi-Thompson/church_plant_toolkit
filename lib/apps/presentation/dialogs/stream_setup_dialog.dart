// lib/apps/presentation/dialogs/stream_setup_dialog.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/presentation_models.dart';

/// Shows the live-stream platform picker and RTMP/stream-key entry.
/// Returns `true` if the user confirmed, `false` / null if cancelled.
Future<bool> showStreamSetupDialog(
  BuildContext context,
  StreamSettings settings,
) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _StreamSetupDialog(settings: settings),
  );
  return result == true;
}

class _StreamSetupDialog extends StatefulWidget {
  final StreamSettings settings;
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
      if (platform != 'custom') {
        widget.settings.rtmpUrl = StreamSettings.platformDefaults[platform]!['url']!;
        _urlCtrl.text = widget.settings.rtmpUrl;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
              _sectionLabel('Select Platform'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: StreamSettings.platformDefaults.entries.map((e) {
                  return ChoiceChip(
                    label: Text(e.value['name']!),
                    selected: widget.settings.platform == e.key,
                    onSelected: (_) => _selectPlatform(e.key),
                    selectedColor: Colors.green.shade100,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              if (widget.settings.platform != 'custom')
                _InfoBox(
                  color:  Colors.blue,
                  title:  '📋 How to get your stream key:',
                  body:   _instructions(widget.settings.platform),
                ),

              if (widget.settings.platform == 'custom') ...[
                const SizedBox(height: 4),
                _sectionLabel('RTMP Server URL'),
                const SizedBox(height: 6),
                TextField(
                  controller: _urlCtrl,
                  onChanged:  (v) => widget.settings.rtmpUrl = v.trim(),
                  decoration: const InputDecoration(
                    hintText:    'rtmp://your-server/live',
                    border:      OutlineInputBorder(),
                    prefixIcon:  Icon(Icons.link),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              const SizedBox(height: 12),
              _sectionLabel('Stream Key'),
              const SizedBox(height: 6),
              TextField(
                controller:  _keyCtrl,
                obscureText: _obscureKey,
                onChanged:   (v) => widget.settings.streamKey = v.trim(),
                decoration: InputDecoration(
                  hintText:   'Paste your stream key here',
                  border:     const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.key),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(_obscureKey
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                        tooltip: _obscureKey ? 'Show' : 'Hide',
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: 'Copy',
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: _keyCtrl.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Stream key copied')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
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

              if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ...[
                const SizedBox(height: 12),
                _InfoBox(
                  color: Colors.orange,
                  title: '📱 Mobile tip',
                  body:  'Use a stable Wi-Fi or 4G/5G connection for '
                         'uninterrupted streaming.',
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
          icon:  const Icon(Icons.stream),
          label: const Text('Go Live'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            final key = _keyCtrl.text.trim();
            final url = widget.settings.platform == 'custom'
                ? _urlCtrl.text.trim()
                : StreamSettings.platformDefaults[widget.settings.platform]!['url']!;

            if (key.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Please enter your stream key'),
                backgroundColor: Colors.orange,
              ));
              return;
            }
            if (widget.settings.platform == 'custom' && url.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Please enter an RTMP server URL'),
                backgroundColor: Colors.orange,
              ));
              return;
            }
            widget.settings.rtmpUrl   = url;
            widget.settings.streamKey = key;
            Navigator.pop(context, true);
          },
        ),
      ],
    );
  }

  String _instructions(String platform) {
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

// ── SHARED SMALL WIDGETS ──────────────────────────────────────────────────────

Widget _sectionLabel(String text) => Text(
  text,
  style: const TextStyle(fontWeight: FontWeight.bold),
);

class _InfoBox extends StatelessWidget {
  final MaterialColor color;
  final String        title;
  final String        body;

  const _InfoBox({
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        color.shade50,
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: color.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: color.shade900)),
          const SizedBox(height: 4),
          Text(body,
              style: TextStyle(fontSize: 12, color: color.shade800)),
        ],
      ),
    );
  }
}