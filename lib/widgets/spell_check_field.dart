// lib/widgets/spell_check_field.dart
//
// Drop-in replacement for TextField / TextFormField that:
//   • Paints red squiggly underlines under misspelled words (all platforms).
//   • RIGHT-CLICK  (desktop) on a misspelled word → correction menu.
//   • DOUBLE-TAP   (mobile / desktop) on a misspelled word → correction menu.
//   • Selecting a suggestion replaces the word instantly.
//   • "Ignore" removes the underline for the session.
//
// TRIGGER DESIGN
// ─────────────────────────────────────────────────────────────────────────────
// A Listener wraps everything. It is transparent to the gesture arena so the
// TextFormField keeps all its normal behaviour (focus, cursor, selection).
// The Listener does two things:
//   1. Records the pointer position so we can anchor the popup menu.
//   2. On kSecondaryMouseButton (right-click), finds the word under the cursor
//      via TextPainter hit-test and shows the menu.
//
// A translucent GestureDetector is layered on top (Positioned.fill) and only
// registers onDoubleTap. "Translucent" means single-taps still fall through to
// the TextFormField underneath, so focus and cursor placement are unaffected.
// On double-tap, Flutter has already selected the tapped word in the controller,
// so we read _ctrl.selection to find which misspelled range was hit.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import '../services/spell_check_service.dart';

// ── PUBLIC WIDGET ─────────────────────────────────────────────────────────────

class SpellCheckField extends StatefulWidget {
  final TextEditingController?     controller;
  final InputDecoration?           decoration;
  final int?                       maxLines;
  final int?                       minLines;
  final bool                       expands;
  final TextStyle?                 style;
  final TextInputType?             keyboardType;
  final bool                       readOnly;
  final bool                       autofocus;
  final String?                    initialValue;
  final ValueChanged<String>?      onChanged;
  final String? Function(String?)? validator;
  final TextCapitalization         textCapitalization;
  final FocusNode?                 focusNode;

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
  bool            _ownsController = false;
  List<TextRange> _misspelled     = [];
  Timer?          _debounce;
  final _svc = SpellCheckService();

  // Global position of the most recent pointer-down — used to anchor the menu.
  Offset _menuAnchor = Offset.zero;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ??
        TextEditingController(text: widget.initialValue ?? '');
    _ownsController = widget.controller == null;
    _ctrl.addListener(_onTextChanged);
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

  // ── Spell check ───────────────────────────────────────────────────────────

  void _onTextChanged() {
    widget.onChanged?.call(_ctrl.text);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _check(_ctrl.text);
    });
  }

  void _check(String text) {
    final ranges = _svc.misspelledRanges(text);
    if (mounted) setState(() => _misspelled = ranges);
  }

  // ── Listener: position recording + right-click ────────────────────────────

  void _onPointerDown(PointerDownEvent event) {
    _menuAnchor = event.position;  // always record for menu anchor

    if (event.buttons != kSecondaryMouseButton) return;

    // Right-click: find the word under the pointer via TextPainter hit-test.
    final offset = _charOffsetAt(event.position);
    if (offset == null) return;

    final range = _rangeAt(offset);
    if (range == null) return;

    // Defer so the field finishes its own pointer handling first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showMenu(range);
    });
  }

  // ── Double-tap ────────────────────────────────────────────────────────────

  void _onDoubleTap() {
    // Flutter selects the whole word before this fires, so _ctrl.selection
    // already spans the double-tapped word.
    final sel = _ctrl.selection;
    if (!sel.isValid || sel.isCollapsed) return;

    final range = _rangeOverlapping(sel.start, sel.end);
    if (range == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showMenu(range);
    });
  }

  // ── Hit-test helpers ──────────────────────────────────────────────────────

  /// Converts a global screen position to a character index using TextPainter.
  int? _charOffsetAt(Offset global) {
    final ro = context.findRenderObject();
    if (ro == null || !ro.attached) return null;
    final box   = ro as RenderBox;
    final local = box.globalToLocal(global);
    final pad   = _contentPadding();
    final w     = (box.size.width - pad.horizontal).clamp(1.0, box.size.width);

    final tp = TextPainter(
      text:          TextSpan(text: _ctrl.text, style: widget.style ?? const TextStyle()),
      textDirection: TextDirection.ltr,
      maxLines:      widget.expands ? null : widget.maxLines,
    )..layout(maxWidth: w);

    return tp.getPositionForOffset(
      Offset(local.dx - pad.left, local.dy - pad.top),
    ).offset;
  }

  TextRange? _rangeAt(int offset) {
    for (final r in _misspelled) {
      if (offset >= r.start && offset <= r.end) return r;
    }
    return null;
  }

  TextRange? _rangeOverlapping(int start, int end) {
    for (final r in _misspelled) {
      if (r.start < end && r.end > start) return r;
    }
    return null;
  }

  EdgeInsets _contentPadding() {
    final pad = widget.decoration?.contentPadding;
    if (pad is EdgeInsets) return pad;
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 16);
  }

  // ── Suggestion menu ───────────────────────────────────────────────────────

  void _showMenu(TextRange range) {
    if (!mounted) return;
    final word        = _ctrl.text.substring(range.start, range.end);
    final suggestions = _svc.suggestions(word);
    final screen      = MediaQuery.of(context).size;
    final a           = _menuAnchor;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        a.dx, a.dy,
        screen.width - a.dx, screen.height - a.dy,
      ),
      shape:     RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
      items: [
        // ── Header ──────────────────────────────────────────────────────────
        PopupMenuItem<String>(
          enabled: false,
          height:  38,
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '"$word" — misspelled',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12, color: Colors.red,
                  fontWeight: FontWeight.w600, fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ]),
        ),

        const PopupMenuDivider(height: 1),

        // ── Suggestions ─────────────────────────────────────────────────────
        if (suggestions.isEmpty)
          const PopupMenuItem<String>(
            enabled: false,
            height:  36,
            child: Text('No suggestions found',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
          )
        else
          ...suggestions.map((s) => PopupMenuItem<String>(
            value:  s,
            height: 42,
            child: Row(children: [
              const Icon(Icons.spellcheck, size: 15, color: Colors.green),
              const SizedBox(width: 10),
              Text(s, style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500)),
            ]),
          )),

        const PopupMenuDivider(height: 1),

        // ── Ignore ──────────────────────────────────────────────────────────
        PopupMenuItem<String>(
          value:  '__ignore__',
          height: 40,
          child: Row(children: [
            const Icon(Icons.do_not_disturb_alt_outlined,
                size: 15, color: Colors.grey),
            const SizedBox(width: 10),
            const Text('Ignore',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
          ]),
        ),
      ],
    ).then((chosen) {
      if (!mounted || chosen == null) return;
      if (chosen == '__ignore__') {
        _svc.addIgnored(word);
        _check(_ctrl.text);
      } else {
        _replaceWord(range, chosen);
      }
    });
  }

  // ── Word replacement ──────────────────────────────────────────────────────

  void _replaceWord(TextRange range, String suggestion) {
    final original   = _ctrl.text.substring(range.start, range.end);
    final correction = _matchCase(original, suggestion);
    final newText    = _ctrl.text.replaceRange(range.start, range.end, correction);
    _ctrl.value = TextEditingValue(
      text:      newText,
      selection: TextSelection.collapsed(
          offset: range.start + correction.length),
    );
    _check(newText);
  }

  String _matchCase(String original, String suggestion) {
    if (original.isEmpty || suggestion.isEmpty) return suggestion;
    if (original == original.toUpperCase()) return suggestion.toUpperCase();
    if (original[0] == original[0].toUpperCase()) {
      return suggestion[0].toUpperCase() + suggestion.substring(1);
    }
    return suggestion;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = widget.style ?? DefaultTextStyle.of(context).style;

    return Listener(
      onPointerDown: _onPointerDown,           // position + right-click
      child: Stack(
        children: [
          // ── Squiggly text field ──────────────────────────────────────────
          _SquigglyTextField(
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
          ),
          // ── Double-tap overlay ───────────────────────────────────────────
          // HitTestBehavior.translucent: single-taps fall through to the
          // TextFormField below; only onDoubleTap is consumed here.
          Positioned.fill(
            child: GestureDetector(
              behavior:    HitTestBehavior.translucent,
              onDoubleTap: _onDoubleTap,
            ),
          ),
        ],
      ),
    );
  }
}

// ── INTERNAL: SQUIGGLY TEXT FIELD ─────────────────────────────────────────────

class _SquigglyTextField extends StatelessWidget {
  final TextEditingController      controller;
  final List<TextRange>            misspelled;
  final InputDecoration            decoration;
  final int?                       maxLines;
  final int?                       minLines;
  final bool                       expands;
  final TextStyle                  style;
  final TextInputType?             keyboardType;
  final bool                       readOnly;
  final bool                       autofocus;
  final String? Function(String?)? validator;
  final TextCapitalization         textCapitalization;
  final FocusNode?                 focusNode;

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
      builder: (context, _) => Stack(
        children: [
          // ── Squiggle painter ───────────────────────────────────────────────
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
          // ── Input field ────────────────────────────────────────────────────
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
          ),
        ],
      ),
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

    final contentPad = _contentPadding();
    final paintWidth = (maxWidth - contentPad.horizontal).clamp(1.0, maxWidth);

    final tp = TextPainter(
      text:          TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines:      maxLines,
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
          Offset(box.left  + contentPad.left, box.bottom + contentPad.top),
          Offset(box.right + contentPad.left, box.bottom + contentPad.top),
        );
      }
    }
  }

  void _drawSquiggle(Canvas canvas, Paint paint, Offset start, Offset end) {
    const waveWidth  = 4.0;
    const waveHeight = 2.0;
    final path = Path()..moveTo(start.dx, start.dy);
    double x = start.dx;
    bool   up = true;
    while (x < end.dx) {
      final nextX = (x + waveWidth).clamp(start.dx, end.dx);
      path.quadraticBezierTo(
        x + waveWidth / 2, start.dy + (up ? -waveHeight : waveHeight),
        nextX, start.dy,
      );
      x  = nextX;
      up = !up;
    }
    canvas.drawPath(path, paint);
  }

  EdgeInsets _contentPadding() {
    final pad = decoration.contentPadding;
    if (pad is EdgeInsets) return pad;
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 16);
  }

  @override
  bool shouldRepaint(_SquigglePainter old) =>
      old.text != text || old.misspelled != misspelled || old.maxWidth != maxWidth;
}