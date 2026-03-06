// lib/apps/presentation/widgets/presentation_widgets.dart
//
// Small reusable widgets shared across the presentation feature:
//   _Badge, _ControlBtn, slide thumbnail preview
import 'package:flutter/material.dart';
import '../models/presentation_models.dart';

// ── LIVE BADGE (REC / LIVE) ───────────────────────────────────────────────────
class LiveBadge extends StatelessWidget {
  final String label;
  final Color  color;

  const LiveBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color:        color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            label == 'REC' ? Icons.fiber_manual_record : Icons.wifi,
            color: Colors.white,
            size:  11,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color:      Colors.white,
              fontSize:   11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ── CONTROL BUTTON (icon + label column) ─────────────────────────────────────
class ControlButton extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final Color        color;
  final VoidCallback onTap;

  const ControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
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

// ── SLIDE THUMBNAIL ───────────────────────────────────────────────────────────
class SlideThumbnail extends StatelessWidget {
  final Slide slide;
  final bool  selected;
  final Color selectedBorderColor;
  final double height;
  final VoidCallback? onTap;

  const SlideThumbnail({
    super.key,
    required this.slide,
    required this.selectedBorderColor,
    this.selected = false,
    this.height   = 70,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color:        slide.bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? selectedBorderColor : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Center(
          child: Text(
            slide.title,
            style: TextStyle(
              color:      slide.textColor,
              fontSize:   8,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines:  2,
            overflow:  TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

// ── SLIDE CONTENT PREVIEW (editor / present view) ────────────────────────────
class SlideContentPreview extends StatelessWidget {
  final Slide  slide;
  final double fontScale; // multiplier applied on top of slide.fontSize

  const SlideContentPreview({
    super.key,
    required this.slide,
    this.fontScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (slide.title.isNotEmpty)
          Text(
            slide.title,
            style: TextStyle(
              color:      slide.textColor,
              fontSize:   slide.fontSize * fontScale,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        if (slide.body.isNotEmpty) ...[
          SizedBox(height: 24 * fontScale),
          Text(
            slide.body,
            style: TextStyle(
              color:    slide.textColor,
              fontSize: slide.fontSize * 0.65 * fontScale,
              height:   1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (slide.reference.isNotEmpty) ...[
          SizedBox(height: 14 * fontScale),
          Text(
            slide.reference,
            style: TextStyle(
              color:     slide.textColor.withValues(alpha: 0.65),
              fontSize:  slide.fontSize * 0.42 * fontScale,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

// ── EMPTY STATE ───────────────────────────────────────────────────────────────
class EmptyStateMessage extends StatelessWidget {
  final IconData icon;
  final String   message;
  final Color    color;

  const EmptyStateMessage({
    super.key,
    required this.icon,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: color.withValues(alpha: 0.35)),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 15,
              color:    color.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}