// lib/apps/presentation/views/present_view.dart
//
// Full-screen presentation view.
// • Manual navigation: tap right/left half, arrow keys, or bottom bar
// • Auto-advance: when the current slide belongs to a group with
//   autoAdvanceSeconds set, a countdown timer fires automatically.
//   The timer resets on manual navigation and pauses when the
//   presenter taps the pause button.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/presentation_models.dart';
import '../models/slide_group.dart';
import '../widgets/presentation_widgets.dart';

class PresentView extends StatefulWidget {
  final Deck          deck;
  final Color         primary;
  final Color         secondary;
  final VoidCallback  onExit;
  final bool          isStreaming;
  final bool          isRecording;
  final VoidCallback  onToggleStream;
  final VoidCallback  onToggleRecord;

  const PresentView({
    super.key,
    required this.deck,
    required this.primary,
    required this.secondary,
    required this.onExit,
    required this.isStreaming,
    required this.isRecording,
    required this.onToggleStream,
    required this.onToggleRecord,
  });

  @override
  State<PresentView> createState() => _PresentViewState();
}

class _PresentViewState extends State<PresentView> {
  int  _idx         = 0;
  bool _showUI      = true;
  bool _autoPaused  = false;

  // Auto-advance state
  Timer?  _autoTimer;
  int     _countdown = 0;   // seconds remaining
  Timer?  _countdownTicker;

  // Keyboard focus
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _startAutoIfNeeded();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _countdownTicker?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  List<Slide> get _slides => widget.deck.slides;
  Slide?      get _current => _slides.isEmpty ? null : _slides[_idx];

  /// Returns the SlideGroup this slide belongs to, if any.
  SlideGroup? _groupOf(Slide? slide) {
    if (slide == null) return null;
    for (final g in widget.deck.groups) {
      if (g.slideIds.contains(slide.id)) return g;
    }
    return null;
  }

  // ── auto-advance ──────────────────────────────────────────────────────────

  void _startAutoIfNeeded() {
    _autoTimer?.cancel();
    _countdownTicker?.cancel();

    if (_autoPaused) return;
    final group = _groupOf(_current);
    if (group == null || !group.hasAutoAdvance) {
      setState(() => _countdown = 0);
      return;
    }

    final secs = group.autoAdvanceSeconds!;
    setState(() => _countdown = secs);

    // Tick every second to update countdown display
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _countdown = (_countdown - 1).clamp(0, secs));
    });

    // Fire advance after full duration
    _autoTimer = Timer(Duration(seconds: secs), () {
      if (!mounted) return;
      _countdownTicker?.cancel();
      _goNext(auto: true);
    });
  }

  void _cancelAuto() {
    _autoTimer?.cancel();
    _countdownTicker?.cancel();
    setState(() => _countdown = 0);
  }

  void _togglePause() {
    setState(() => _autoPaused = !_autoPaused);
    if (_autoPaused) {
      _cancelAuto();
    } else {
      _startAutoIfNeeded();
    }
  }

  // ── navigation ────────────────────────────────────────────────────────────

  void _goNext({bool auto = false}) {
    if (_slides.isEmpty) return;
    if (_idx < _slides.length - 1) {
      if (!auto) _autoPaused = false; // manual tap un-pauses
      setState(() => _idx++);
      _startAutoIfNeeded();
    } else if (auto) {
      // Reached end during auto — stop
      _cancelAuto();
    }
  }

  void _goPrev() {
    if (_idx > 0) {
      _autoPaused = false;
      setState(() => _idx--);
      _startAutoIfNeeded();
    }
  }

  void _jumpTo(int i) {
    if (i < 0 || i >= _slides.length) return;
    _autoPaused = false;
    setState(() => _idx = i);
    _startAutoIfNeeded();
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final slide  = _current;
    final group  = _groupOf(slide);
    final hasAuto = group?.hasAutoAdvance ?? false;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (e) {
        if (e is! KeyDownEvent) return;
        if (e.logicalKey == LogicalKeyboardKey.arrowRight ||
            e.logicalKey == LogicalKeyboardKey.space) {
          _goNext();
        } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _goPrev();
        } else if (e.logicalKey == LogicalKeyboardKey.escape) {
          widget.onExit();
        }
      },
      child: Scaffold(
        backgroundColor: slide?.bgColor ?? Colors.black,
        body: GestureDetector(
          onTap: () => setState(() => _showUI = !_showUI),
          child: Stack(
            children: [
              // ── SLIDE CONTENT ──────────────────────────────────────────
              if (slide != null)
                Positioned.fill(
                  child: SlideContentPreview(slide: slide),
                ),

              // ── LEFT / RIGHT tap zones ─────────────────────────────────
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap:    _goPrev,
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap:    () => _goNext(),
                      ),
                    ),
                  ],
                ),
              ),

              // ── AUTO-ADVANCE COUNTDOWN RING ───────────────────────────
              if (hasAuto && _countdown > 0 && !_autoPaused)
                Positioned(
                  top: 16, right: 16,
                  child: _CountdownRing(
                    countdown: _countdown,
                    total:     group!.autoAdvanceSeconds!,
                    primary:   widget.primary,
                    onPause:   _togglePause,
                  ),
                ),

              // ── PAUSED BADGE ──────────────────────────────────────────
              if (hasAuto && _autoPaused)
                Positioned(
                  top: 16, right: 16,
                  child: GestureDetector(
                    onTap: _togglePause,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color:        Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: widget.primary.withValues(alpha: 0.60)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow_rounded,
                              color: widget.primary, size: 16),
                          const SizedBox(width: 6),
                          Text('Paused',
                              style: TextStyle(
                                  color:     widget.primary,
                                  fontSize:  12,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── TOP UI BAR ────────────────────────────────────────────
              if (_showUI)
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: _TopBar(
                    idx:           _idx,
                    total:         _slides.length,
                    isStreaming:   widget.isStreaming,
                    isRecording:   widget.isRecording,
                    onToggleStream: widget.onToggleStream,
                    onToggleRecord: widget.onToggleRecord,
                    onExit:        widget.onExit,
                    primary:       widget.primary,
                    groupName:     group?.name,
                    hasAuto:       hasAuto,
                    autoPaused:    _autoPaused,
                    onTogglePause: hasAuto ? _togglePause : null,
                  ),
                ),

              // ── BOTTOM SLIDE STRIP ────────────────────────────────────
              if (_showUI)
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: _SlideStrip(
                    slides:   _slides,
                    current:  _idx,
                    primary:  widget.primary,
                    secondary: widget.secondary,
                    groups:   widget.deck.groups,
                    onSelect: _jumpTo,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// COUNTDOWN RING  (circular timer indicator)
// ══════════════════════════════════════════════════════════════════════════════
class _CountdownRing extends StatelessWidget {
  final int        countdown;
  final int        total;
  final Color      primary;
  final VoidCallback onPause;

  const _CountdownRing({
    required this.countdown,
    required this.total,
    required this.primary,
    required this.onPause,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? countdown / total : 0.0;

    return GestureDetector(
      onTap: onPause,
      child: SizedBox(
        width: 52, height: 52,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value:            progress,
                strokeWidth:      3.5,
                backgroundColor:  Colors.white24,
                valueColor:
                    AlwaysStoppedAnimation<Color>(primary),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$countdown',
                    style: const TextStyle(
                        color:      Colors.white,
                        fontSize:   14,
                        fontWeight: FontWeight.bold,
                        height:     1.1)),
                const Icon(Icons.pause_rounded,
                    color: Colors.white70, size: 10),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TOP BAR
// ══════════════════════════════════════════════════════════════════════════════
class _TopBar extends StatelessWidget {
  final int          idx;
  final int          total;
  final bool         isStreaming;
  final bool         isRecording;
  final VoidCallback onToggleStream;
  final VoidCallback onToggleRecord;
  final VoidCallback onExit;
  final Color        primary;
  final String?      groupName;
  final bool         hasAuto;
  final bool         autoPaused;
  final VoidCallback? onTogglePause;

  const _TopBar({
    required this.idx,
    required this.total,
    required this.isStreaming,
    required this.isRecording,
    required this.onToggleStream,
    required this.onToggleRecord,
    required this.onExit,
    required this.primary,
    this.groupName,
    this.hasAuto      = false,
    this.autoPaused   = false,
    this.onTogglePause,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      child: Row(
        children: [
          // Exit
          IconButton(
            icon:    const Icon(Icons.close_rounded, color: Colors.white),
            tooltip: 'Exit (Esc)',
            onPressed: onExit,
          ),
          // Slide counter
          Text('${idx + 1} / $total',
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13)),
          if (groupName != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color:        primary.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.collections_bookmark_rounded,
                    color: Colors.white70, size: 11),
                const SizedBox(width: 4),
                Text(groupName!,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11)),
              ]),
            ),
          ],
          const Spacer(),
          // Stream
          if (isStreaming || true) // always show the button
            _TopBtn(
              icon:    Icons.wifi_tethering_rounded,
              label:   isStreaming ? 'LIVE' : 'Stream',
              color:   isStreaming ? Colors.green : Colors.white54,
              onTap:   onToggleStream,
            ),
          const SizedBox(width: 4),
          // Record
          _TopBtn(
            icon:    Icons.fiber_manual_record_rounded,
            label:   isRecording ? 'REC' : 'Record',
            color:   isRecording ? Colors.red : Colors.white54,
            onTap:   onToggleRecord,
          ),
        ],
      ),
    );
  }
}

class _TopBtn extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final Color        color;
  final VoidCallback onTap;
  const _TopBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color:        Colors.black38,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color:      color,
                    fontSize:   11,
                    fontWeight: FontWeight.bold)),
          ]),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// BOTTOM SLIDE STRIP
// ══════════════════════════════════════════════════════════════════════════════
class _SlideStrip extends StatelessWidget {
  final List<Slide>       slides;
  final int               current;
  final Color             primary;
  final Color             secondary;
  final List<SlideGroup>  groups;
  final ValueChanged<int> onSelect;

  const _SlideStrip({
    required this.slides,
    required this.current,
    required this.primary,
    required this.secondary,
    required this.groups,
    required this.onSelect,
  });

  SlideGroup? _groupOf(String slideId) {
    for (final g in groups) {
      if (g.slideIds.contains(slideId)) return g;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end:   Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount:       slides.length,
        itemBuilder: (_, i) {
          final s     = slides[i];
          final sel   = i == current;
          final group = _groupOf(s.id);
          return GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              width:  sel ? 80 : 68,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: sel ? secondary : Colors.white30,
                  width: sel ? 2.5 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: SlideRenderer(slide: s, fontScale: 0.15),
                    ),
                    if (group?.hasAutoAdvance == true)
                      Positioned(
                        bottom: 2, right: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color:        Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_rounded,
                                  color: Colors.white70, size: 8),
                              const SizedBox(width: 2),
                              Text('${group!.autoAdvanceSeconds}s',
                                  style: const TextStyle(
                                      color:    Colors.white,
                                      fontSize: 7,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}