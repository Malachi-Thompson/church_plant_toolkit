// lib/apps/presentation/dialogs/record_setup_dialog.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/presentation_models.dart';

/// Shows the recording quality/format/path dialog.
/// Returns `true` if the user confirmed.
Future<bool> showRecordSetupDialog(
  BuildContext context,
  RecordSettings settings,
) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _RecordSetupDialog(settings: settings),
  );
  return result == true;
}

class _RecordSetupDialog extends StatefulWidget {
  final RecordSettings settings;
  const _RecordSetupDialog({required this.settings});

  @override
  State<_RecordSetupDialog> createState() => _RecordSetupDialogState();
}

class _RecordSetupDialogState extends State<_RecordSetupDialog> {
  late TextEditingController _pathCtrl;

  @override
  void initState() {
    super.initState();
    if (widget.settings.savePath.isEmpty) {
      widget.settings.savePath = _defaultPath();
    }
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
    if (Platform.isIOS)     return 'Photos';
    if (Platform.isMacOS)
      return '${Platform.environment['HOME'] ?? ''}/Movies';
    if (Platform.isWindows)
      return '${Platform.environment['USERPROFILE'] ?? 'C:\\Users\\User'}\\Videos';
    return '${Platform.environment['HOME'] ?? ''}/Videos';
  }

  bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Widget build(BuildContext context) {
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
              _sectionLabel('Quality'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final q in ['high', 'medium', 'low'])
                    ChoiceChip(
                      label: Text(_qualityLabel(q)),
                      selected: widget.settings.quality == q,
                      selectedColor: Colors.red.shade100,
                      onSelected: (_) =>
                          setState(() => widget.settings.quality = q),
                    ),
                ],
              ),
              const SizedBox(height: 18),

              // Format
              _sectionLabel('Format'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in ['mp4', 'mkv', 'mov'])
                    ChoiceChip(
                      label: Text(f.toUpperCase()),
                      selected: widget.settings.format == f,
                      selectedColor: Colors.red.shade100,
                      onSelected: (_) =>
                          setState(() => widget.settings.format = f),
                    ),
                ],
              ),
              const SizedBox(height: 18),

              // Save location
              _sectionLabel('Save Location'),
              const SizedBox(height: 8),
              if (!_isMobile && !kIsWeb)
                TextField(
                  controller: _pathCtrl,
                  onChanged:  (v) => widget.settings.savePath = v,
                  decoration: InputDecoration(
                    hintText:   'Folder path',
                    border:     const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.folder_open),
                    suffixIcon: TextButton(
                      onPressed: () => setState(() {
                        widget.settings.savePath = _defaultPath();
                        _pathCtrl.text           = widget.settings.savePath;
                      }),
                      child: const Text('Default'),
                    ),
                  ),
                )
              else
                _mobileSaveInfo(),

              const SizedBox(height: 12),

              // Storage estimate
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color:        Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      'Estimated storage: ${widget.settings.estimatedStorage}',
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
          icon:  const Icon(Icons.fiber_manual_record),
          label: const Text('Start Recording'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }

  String _qualityLabel(String q) {
    switch (q) {
      case 'high':   return '🎬 High (1080p)';
      case 'medium': return '📹 Medium (720p)';
      case 'low':    return '📱 Low (480p)';
      default:       return q;
    }
  }

  Widget _mobileSaveInfo() {
    final IconData icon;
    final String   text;

    if (kIsWeb) {
      icon = Icons.download;
      text = 'Recording will be downloaded to your Downloads folder.';
    } else if (Platform.isIOS) {
      icon = Icons.photo_library;
      text = 'Recording will be saved to your Photos library.';
    } else {
      icon = Icons.sd_storage;
      text = 'Recording will be saved to the Movies folder on your device.';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

Widget _sectionLabel(String text) => Text(
  text,
  style: const TextStyle(fontWeight: FontWeight.bold),
);