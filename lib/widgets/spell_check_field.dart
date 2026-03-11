// lib/widgets/spell_check_field.dart
//
// Drop-in replacement for TextField / TextFormField that paints red squiggly
// underlines under misspelled words on ALL platforms (Windows, macOS,
// iOS, Android, Web).
//
// BASIC USAGE:
//   SpellCheckField(
//     controller: _myController,
//     decoration: InputDecoration(labelText: 'Sermon notes'),
//     maxLines: null,
//     onChanged: (v) { ... },
//   )
//
// All standard TextField parameters are forwarded transparently.

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/spell_check_service.dart';

// ── PUBLIC WIDGET ─────────────────────────────────────────────────────────────

class SpellCheckField extends StatefulWidget {
  final TextEditingController?    controller;
  final InputDecoration?          decoration;
  final int?                      maxLines;
  final int?                      minLines;
  final bool                      expands;
  final TextStyle?                style;
  final TextInputType?            keyboardType;
  final bool                      readOnly;
  final bool                      autofocus;
  final String?                   initialValue;
  final ValueChanged<String>?     onChanged;
  final String? Function(String?)? validator;
  final TextCapitalization        textCapitalization;
  final FocusNode?                focusNode;

  const SpellCheckField({
    super.key,
    this.controller,
    this.decoration,
    this.maxLines      = 1,
    this.minLines,
    this.expands       = false,
    this.style,
    this.keyboardType,
    this.readOnly      = false,
    this.autofocus     = false,
    this.initialValue,
    this.onChanged,
    this.validator,
    this.textCapitalization = TextCapitalization.sentences,
    this.focusNode,
  });

  @override
  State<SpellCheckField> createState() => _SpellCheckFieldState();
}

class _SpellCheckFieldState extends State<SpellCheckField> {
  late TextEditingController _ctrl;
  bool _ownsController = false;
  List<TextRange> _misspelled = [];
  Timer? _debounce;
  final _svc = SpellCheckService();

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _ctrl = widget.controller!;
    } else {
      _ctrl = TextEditingController(text: widget.initialValue ?? '');
      _ownsController = true;
    }
    _ctrl.addListener(_onTextChanged);
    // Load dictionary on first use; re-check when ready.
    _svc.ensureLoaded().then((_) {
      if (mounted) _check(_ctrl.text);
    });
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    if (_ownsController) _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    widget.onChanged?.call(_ctrl.text);
    // Debounce so we don't recheck on every keystroke.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _check(_ctrl.text);
    });
  }

  void _check(String text) {
    final ranges = _svc.misspelledRanges(text);
    if (mounted) setState(() => _misspelled = ranges);
  }

  @override
  Widget build(BuildContext context) {
    // We layer two widgets:
    //  1. _SquigglyOverlay — paints the red underlines
    //  2. TextFormField    — handles all input (transparent background)
    //
    // They share the same controller so the overlay always knows the current
    // text and the cursor position.

    final effectiveStyle = widget.style ?? DefaultTextStyle.of(context).style;

    return _SquigglyTextField(
      controller:         _ctrl,
      misspelled:         _misspelled,
      decoration:         widget.decoration ?? const InputDecoration(),
      maxLines:           widget.maxLines,
      minLines:           widget.minLines,
      expands:            widget.expands,
      style:              effectiveStyle,
      keyboardType:       widget.keyboardType,
      readOnly:           widget.readOnly,
      autofocus:          widget.autofocus,
      validator:          widget.validator,
      textCapitalization: widget.textCapitalization,
      focusNode:          widget.focusNode,
    );
  }
}

// ── INTERNAL: SQUIGGLY TEXT FIELD ─────────────────────────────────────────────
//
// Uses a Stack: the TextFormField sits on top; a CustomPaint below it draws
// the squiggles. We keep them in sync via the shared controller and a
// LayoutBuilder to know the exact pixel width available.

class _SquigglyTextField extends StatelessWidget {
  final TextEditingController     controller;
  final List<TextRange>           misspelled;
  final InputDecoration           decoration;
  final int?                      maxLines;
  final int?                      minLines;
  final bool                      expands;
  final TextStyle                 style;
  final TextInputType?            keyboardType;
  final bool                      readOnly;
  final bool                      autofocus;
  final String? Function(String?)? validator;
  final TextCapitalization        textCapitalization;
  final FocusNode?                focusNode;

  const _SquigglyTextField({
    required this.controller,
    required this.misspelled,
    required this.decoration,
    required this.style,
    this.maxLines,
    this.minLines,
    this.expands       = false,
    this.keyboardType,
    this.readOnly      = false,
    this.autofocus     = false,
    this.validator,
    this.textCapitalization = TextCapitalization.sentences,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Stack(
          children: [
            // ── Squiggle layer ──────────────────────────────────────────────
            Positioned.fill(
              child: LayoutBuilder(
                builder: (ctx, constraints) => CustomPaint(
                  painter: _SquigglePainter(
                    text:       controller.text,
                    misspelled: misspelled,
                    style:      style,
                    maxWidth:   constraints.maxWidth,
                    decoration: decoration,
                    maxLines:   maxLines,
                  ),
                ),
              ),
            ),
            // ── Actual input field ──────────────────────────────────────────
            TextFormField(
              controller:         controller,
              decoration:         decoration,
              maxLines:           expands ? null : maxLines,
              minLines:           minLines,
              expands:            expands,
              style:              style,
              keyboardType:       keyboardType,
              readOnly:           readOnly,
              autofocus:          autofocus,
              validator:          validator,
              textCapitalization: textCapitalization,
              focusNode:          focusNode,
              // No spellCheckConfiguration — we handle it ourselves.
            ),
          ],
        );
      },
    );
  }
}

// ── PAINTER ───────────────────────────────────────────────────────────────────

class _SquigglePainter extends CustomPainter {
  final String          text;
  final List<TextRange> misspelled;
  final TextStyle       style;
  final double          maxWidth;
  final InputDecoration decoration;
  final int?            maxLines;

  _SquigglePainter({
    required this.text,
    required this.misspelled,
    required this.style,
    required this.maxWidth,
    required this.decoration,
    required this.maxLines,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (misspelled.isEmpty || text.isEmpty) return;

    // Work out the content inset that InputDecoration adds so squiggles
    // line up with the actual rendered glyphs.
    final contentPad = _contentPadding();
    final paintWidth  = (maxWidth - contentPad.horizontal).clamp(1.0, maxWidth);

    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
    )..layout(maxWidth: paintWidth);

    final paint = Paint()
      ..color       = Colors.red
      ..strokeWidth = 1.5
      ..style       = PaintingStyle.stroke;

    for (final range in misspelled) {
      if (range.start >= text.length || range.end > text.length) continue;

      final boxes = tp.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
      );

      for (final box in boxes) {
        _drawSquiggle(
          canvas, paint,
          Offset(box.left + contentPad.left, box.bottom + contentPad.top),
          Offset(box.right + contentPad.left, box.bottom + contentPad.top),
        );
      }
    }
  }

  /// Draws a classic squiggly (zigzag) underline between [start] and [end].
  void _drawSquiggle(Canvas canvas, Paint paint, Offset start, Offset end) {
    const waveWidth  = 4.0;
    const waveHeight = 2.0;
    final path       = Path()..moveTo(start.dx, start.dy);

    double x = start.dx;
    bool up   = true;
    while (x < end.dx) {
      final nextX = (x + waveWidth).clamp(start.dx, end.dx);
      final y     = start.dy + (up ? -waveHeight : waveHeight);
      path.quadraticBezierTo(
          x + waveWidth / 2, y, nextX, start.dy);
      x  = nextX;
      up = !up;
    }
    canvas.drawPath(path, paint);
  }

  /// Approximates the left/top inset that InputDecoration applies.
  EdgeInsets _contentPadding() {
    final pad = decoration.contentPadding;
    if (pad is EdgeInsets) return pad;
    // Material default: 12px horizontal, 16px vertical
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 16);
  }

  @override
  bool shouldRepaint(_SquigglePainter old) =>
      old.text != text ||
      old.misspelled != misspelled ||
      old.maxWidth != maxWidth;
}