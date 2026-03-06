// lib/apps/presentation/views/slide_editor_view.dart
import 'package:flutter/material.dart';
import '../models/presentation_models.dart';
import '../../../theme.dart';

/// Right-panel editor that lets the user edit a single [Slide] in place.
class SlideEditorView extends StatefulWidget {
  final Slide        slide;
  final Color        primary;
  final Color        secondary;
  final VoidCallback onChanged;

  const SlideEditorView({
    super.key,
    required this.slide,
    required this.primary,
    required this.secondary,
    required this.onChanged,
  });

  @override
  State<SlideEditorView> createState() => _SlideEditorViewState();
}

class _SlideEditorViewState extends State<SlideEditorView> {
  late TextEditingController _titleCtrl;
  late TextEditingController _bodyCtrl;
  late TextEditingController _refCtrl;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  @override
  void didUpdateWidget(SlideEditorView old) {
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
      Color.lerp(p, Colors.black, 0.50)!,
      Color.lerp(p, Colors.white, 0.70)!,
      Colors.black,
      Colors.white,
      Colors.blueGrey.shade900,
      Colors.purple.shade900,
    ];
  }

  void _notify() {
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final slide = widget.slide;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── LIVE PREVIEW ────────────────────────────────────────────────
          Center(
            child: Container(
              width: 480,
              height: 270,
              decoration: BoxDecoration(
                color:        slide.bgColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color:     Colors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (slide.title.isNotEmpty)
                    Text(
                      slide.title,
                      style: TextStyle(
                        color:      slide.textColor,
                        fontSize:   slide.fontSize * 0.38,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  if (slide.body.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      slide.body,
                      style: TextStyle(
                        color:    slide.textColor,
                        fontSize: slide.fontSize * 0.28,
                        height:   1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (slide.reference.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      slide.reference,
                      style: TextStyle(
                        color:     slide.textColor.withValues(alpha: 0.65),
                        fontSize:  slide.fontSize * 0.20,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          // ── FIELDS ──────────────────────────────────────────────────────
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Title',
              border:    OutlineInputBorder(),
            ),
            onChanged: (v) {
              slide.title = v;
              _notify();
            },
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _bodyCtrl,
            maxLines:   4,
            decoration: const InputDecoration(
              labelText: 'Body text',
              border:    OutlineInputBorder(),
            ),
            onChanged: (v) {
              slide.body = v;
              _notify();
            },
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _refCtrl,
            decoration: const InputDecoration(
              labelText: 'Reference (optional)',
              border:    OutlineInputBorder(),
            ),
            onChanged: (v) {
              slide.reference = v;
              _notify();
            },
          ),
          const SizedBox(height: 20),

          // ── FONT SIZE ────────────────────────────────────────────────────
          Row(
            children: [
              const Text('Font size:'),
              Expanded(
                child: Slider(
                  value:     slide.fontSize,
                  min:       20,
                  max:       80,
                  divisions: 12,
                  label:     slide.fontSize.round().toString(),
                  onChanged: (v) {
                    slide.fontSize = v;
                    _notify();
                  },
                ),
              ),
              SizedBox(
                width: 32,
                child: Text(
                  slide.fontSize.round().toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── BACKGROUND COLOR ─────────────────────────────────────────────
          const Text(
            'Background color:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing:    8,
            runSpacing: 8,
            children: _bgPresets().map((color) {
              final sel = slide.bgColor.toARGB32() == color.toARGB32();
              return GestureDetector(
                onTap: () {
                  slide.bgColor   = color;
                  slide.textColor = contrastOn(color);
                  _notify();
                },
                child: Container(
                  width:  36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: sel
                          ? widget.secondary
                          : Colors.grey.shade300,
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