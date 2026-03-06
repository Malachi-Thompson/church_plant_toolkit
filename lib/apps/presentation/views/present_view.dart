// lib/apps/presentation/views/present_view.dart
import 'package:flutter/material.dart';
import '../models/presentation_models.dart';
import '../widgets/presentation_widgets.dart';

/// Full-screen presentation view.  Handles swipe navigation, tap to
/// show/hide controls, and delegates Record / Stream toggles upward.
class PresentView extends StatefulWidget {
  final Deck         deck;
  final Color        primary;
  final Color        secondary;
  final VoidCallback onExit;
  final bool         isStreaming;
  final bool         isRecording;
  final VoidCallback onToggleStream;
  final VoidCallback onToggleRecord;

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
  int  _idx          = 0;
  bool _showControls = true;

  void _next() {
    if (_idx < widget.deck.slides.length - 1) setState(() => _idx++);
  }

  void _prev() {
    if (_idx > 0) setState(() => _idx--);
  }

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
          if (d.primaryVelocity! < 0) _next();
          if (d.primaryVelocity! > 0) _prev();
        },
        child: Stack(
          children: [
            // ── SLIDE CONTENT ──────────────────────────────────────────────
            SizedBox.expand(
              child: Container(
                color:   slide.bgColor,
                padding: const EdgeInsets.all(60),
                child: SlideContentPreview(slide: slide),
              ),
            ),

            // ── STATUS BADGES ──────────────────────────────────────────────
            if (widget.isRecording || widget.isStreaming)
              Positioned(
                top: 16, right: 16,
                child: Row(
                  children: [
                    if (widget.isRecording)
                      LiveBadge(label: 'REC', color: Colors.red),
                    if (widget.isStreaming) ...[
                      const SizedBox(width: 8),
                      LiveBadge(label: 'LIVE', color: Colors.green),
                    ],
                  ],
                ),
              ),

            // ── SLIDE COUNTER ──────────────────────────────────────────────
            Positioned(
              top: 16, left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color:        Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_idx + 1} / ${slides.length}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12),
                ),
              ),
            ),

            // ── CONTROLS OVERLAY ───────────────────────────────────────────
            if (_showControls)
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
                        icon: const Icon(
                            Icons.close, color: Colors.white),
                      ),
                      const Spacer(),

                      // Record
                      ControlButton(
                        icon:  widget.isRecording
                            ? Icons.stop_circle
                            : Icons.fiber_manual_record,
                        label: widget.isRecording ? 'Stop' : 'Record',
                        color: widget.isRecording
                            ? Colors.red
                            : Colors.white,
                        onTap: widget.onToggleRecord,
                      ),
                      const SizedBox(width: 20),

                      // Stream
                      ControlButton(
                        icon:  widget.isStreaming
                            ? Icons.wifi_off
                            : Icons.wifi,
                        label: widget.isStreaming ? 'Live' : 'Stream',
                        color: widget.isStreaming
                            ? Colors.green
                            : Colors.white,
                        onTap: widget.onToggleStream,
                      ),
                      const Spacer(),

                      // Prev / Next
                      IconButton(
                        onPressed: _idx > 0 ? _prev : null,
                        icon: const Icon(Icons.chevron_left,
                            color: Colors.white, size: 32),
                      ),
                      IconButton(
                        onPressed:
                            _idx < slides.length - 1 ? _next : null,
                        icon: const Icon(Icons.chevron_right,
                            color: Colors.white, size: 32),
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