// lib/apps/presentation/widgets/presentation_widgets.dart
//
// Shared widgets.  SlideContentPreview and SlideThumbnail honour the full
// SlideStyle (bg image, gradient, overlay, fonts, text-box …).
//
// Key fix: SlideThumbnail no longer accepts a fixed `height`. It renders
// at a 16:9 aspect ratio so the slide is never cropped or letter-boxed
// regardless of how wide the parent container is.
import 'dart:convert' show base64Decode;
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/presentation_models.dart';

// ══════════════════════════════════════════════════════════════════════════════
// LIVE BADGE
// ══════════════════════════════════════════════════════════════════════════════
class LiveBadge extends StatelessWidget {
  final String label;
  final Color  color;
  const LiveBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(label == 'REC' ? Icons.fiber_manual_record : Icons.wifi,
                color: Colors.white, size: 11),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// CONTROL BUTTON
// ══════════════════════════════════════════════════════════════════════════════
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
  Widget build(BuildContext context) => GestureDetector(
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

// ══════════════════════════════════════════════════════════════════════════════
// SLIDE BACKGROUND PAINTER  (gradient + overlay pattern)
// ══════════════════════════════════════════════════════════════════════════════
class SlideBackgroundPainter extends CustomPainter {
  final SlideStyle style;
  final Color      bgColor;

  SlideBackgroundPainter({required this.style, required this.bgColor});

  @override
  void paint(Canvas canvas, Size size) {
    // ── solid bg or gradient ──────────────────────────────────────────────
    if (style.useGradient) {
      final paint = Paint()
        ..shader = LinearGradient(
          begin:  style.gradientBegin,
          end:    style.gradientEndAlign,
          colors: [bgColor, style.gradientEnd],
        ).createShader(Offset.zero & size);
      canvas.drawRect(Offset.zero & size, paint);
    } else {
      canvas.drawRect(Offset.zero & size, Paint()..color = bgColor);
    }

    // ── overlay pattern ───────────────────────────────────────────────────
    if (style.overlay == SlideOverlay.none) return;

    final op = style.overlayOpacity.clamp(0.0, 1.0);
    final oc = style.overlayColor.withValues(alpha: op);
    final p  = Paint()
      ..color       = oc
      ..strokeWidth = 1
      ..style       = PaintingStyle.stroke;

    switch (style.overlay) {
      case SlideOverlay.crosshatch:
        _crosshatch(canvas, size, p, 28);
        break;
      case SlideOverlay.dots:
        _dots(canvas, size, oc);
        break;
      case SlideOverlay.diagonal:
        _diagonal(canvas, size, p, 22);
        break;
      case SlideOverlay.vignette:
        _vignette(canvas, size, oc);
        break;
      case SlideOverlay.grain:
        _grain(canvas, size, oc);
        break;
      default:
        break;
    }
  }

  void _crosshatch(Canvas canvas, Size s, Paint p, double gap) {
    for (double x = 0; x < s.width; x += gap)
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), p);
    for (double y = 0; y < s.height; y += gap)
      canvas.drawLine(Offset(0, y), Offset(s.width, y), p);
  }

  void _diagonal(Canvas canvas, Size s, Paint p, double gap) {
    for (double i = -s.height; i < s.width + s.height; i += gap)
      canvas.drawLine(Offset(i, 0), Offset(i + s.height, s.height), p);
  }

  void _dots(Canvas canvas, Size s, Color c) {
    final p = Paint()..color = c;
    const gap = 20.0;
    for (double x = 0; x < s.width; x += gap)
      for (double y = 0; y < s.height; y += gap)
        canvas.drawCircle(Offset(x, y), 1.2, p);
  }

  void _vignette(Canvas canvas, Size s, Color c) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.transparent, c.withValues(alpha: c.a)],
        stops:  const [0.45, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
    canvas.drawRect(Offset.zero & s, paint);
  }

  void _grain(Canvas canvas, Size s, Color c) {
    final rng = math.Random(42);
    final p   = Paint()..color = c;
    for (var i = 0; i < 2000; i++) {
      canvas.drawCircle(
          Offset(rng.nextDouble() * s.width, rng.nextDouble() * s.height),
          0.8, p);
    }
  }

  @override
  bool shouldRepaint(SlideBackgroundPainter old) =>
      old.style != style || old.bgColor != bgColor;
}

// ══════════════════════════════════════════════════════════════════════════════
// FULL SLIDE RENDERER
// ══════════════════════════════════════════════════════════════════════════════
/// Renders a complete slide including bg colour/image/gradient, tint, overlay,
/// text box, and styled text. Pass [fontScale] < 1 for thumbnail use.
///
/// Important: this widget expands to fill whatever space is given to it.
/// Always wrap in a sized/constrained parent (AspectRatio, SizedBox, etc.)
/// so it has a definite size — never place it directly in an unbounded context.
class SlideRenderer extends StatelessWidget {
  final Slide  slide;
  final double fontScale;
  final bool   showReference;

  const SlideRenderer({
    super.key,
    required this.slide,
    this.fontScale     = 1.0,
    this.showReference = true,
  });

  @override
  Widget build(BuildContext context) {
    final s  = slide.style;
    final ta = _textAlign(s.textAlign);

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. background (colour / gradient painted)
          CustomPaint(
            painter: SlideBackgroundPainter(
                style: s, bgColor: slide.bgColor),
          ),

          // 2. background image
          if (s.bgImagePath != null && s.bgImagePath!.isNotEmpty)
            Opacity(
              opacity: s.bgImageOpacity.clamp(0.0, 1.0),
              child: _BgImage(path: s.bgImagePath!, fit: _boxFit(s.bgFit)),
            ),

          // 3. bg tint
          if (s.bgTintOpacity > 0)
            Container(
                color: s.bgTint.withValues(
                    alpha: s.bgTintOpacity.clamp(0.0, 1.0))),

          // 4. text content
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 32, vertical: 24),
              child: _TextContent(
                slide:         slide,
                fontScale:     fontScale,
                textAlign:     ta,
                showReference: showReference,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static TextAlign _textAlign(SlideTextAlign a) {
    switch (a) {
      case SlideTextAlign.left:   return TextAlign.left;
      case SlideTextAlign.right:  return TextAlign.right;
      case SlideTextAlign.center: return TextAlign.center;
    }
  }

  static BoxFit _boxFit(SlideBgFit f) {
    switch (f) {
      case SlideBgFit.contain: return BoxFit.contain;
      case SlideBgFit.fill:    return BoxFit.fill;
      case SlideBgFit.cover:   return BoxFit.cover;
    }
  }
}

// ── background image widget ───────────────────────────────────────────────────
class _BgImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  const _BgImage({required this.path, required this.fit});

  @override
  Widget build(BuildContext context) {
    if (path.startsWith('data:')) {
      final comma = path.indexOf(',');
      if (comma >= 0) {
        try {
          final bytes = base64Decode(path.substring(comma + 1));
          return Image.memory(bytes, fit: fit,
              width: double.infinity, height: double.infinity);
        } catch (_) {}
      }
    }
    if (!kIsWeb) {
      try {
        return Image.file(File(path), fit: fit,
            width: double.infinity, height: double.infinity);
      } catch (_) {}
    }
    return const SizedBox.shrink();
  }
}

// ── text content ──────────────────────────────────────────────────────────────
class _TextContent extends StatelessWidget {
  final Slide     slide;
  final double    fontScale;
  final TextAlign textAlign;
  final bool      showReference;

  const _TextContent({
    required this.slide,
    required this.fontScale,
    required this.textAlign,
    required this.showReference,
  });

  List<Shadow>? _shadows(SlideStyle s) {
    if (!s.textShadow) return null;
    return [
      Shadow(
        color:      s.shadowColor.withValues(alpha: 0.75),
        blurRadius: s.shadowBlur,
        offset:     const Offset(1, 2),
      ),
    ];
  }

  Widget _wrap(SlideStyle s, Widget child) {
    if (!s.showTextBox) return child;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: s.textBoxPaddingH * fontScale,
          vertical:   s.textBoxPaddingV * fontScale),
      decoration: BoxDecoration(
        color:        s.textBoxColor.withValues(alpha: s.textBoxOpacity),
        borderRadius: BorderRadius.circular(s.textBoxRadius),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s       = slide.style;
    final shadows = _shadows(s);
    final ff      = s.fontFamily;
    final ls      = s.letterSpacing;
    final lh      = s.lineHeight;
    final tc      = slide.textColor;

    return _wrap(
      s,
      Column(
        mainAxisSize:       MainAxisSize.min,
        crossAxisAlignment: _crossAlign(s.textAlign),
        children: [
          if (slide.title.isNotEmpty)
            Text(
              slide.title,
              textAlign: textAlign,
              style: TextStyle(
                color:         tc,
                fontSize:      slide.fontSize * s.titleScale * fontScale,
                fontWeight:    s.titleBold   ? FontWeight.bold   : FontWeight.normal,
                fontStyle:     s.titleItalic ? FontStyle.italic  : FontStyle.normal,
                fontFamily:    ff == 'sans-serif' || ff == 'serif' ? null : ff,
                letterSpacing: ls,
                height:        lh,
                shadows:       shadows,
              ),
            ),
          if (slide.body.isNotEmpty) ...[
            SizedBox(height: 10 * fontScale),
            Text(
              slide.body,
              textAlign: textAlign,
              style: TextStyle(
                color:         tc,
                fontSize:      slide.fontSize * 0.65 * s.bodyScale * fontScale,
                fontWeight:    s.bodyBold   ? FontWeight.bold  : FontWeight.normal,
                fontStyle:     s.bodyItalic ? FontStyle.italic : FontStyle.normal,
                fontFamily:    ff == 'sans-serif' || ff == 'serif' ? null : ff,
                letterSpacing: ls,
                height:        lh,
                shadows:       shadows,
              ),
            ),
          ],
          if (showReference && slide.reference.isNotEmpty) ...[
            SizedBox(height: 8 * fontScale),
            Text(
              slide.reference,
              textAlign: textAlign,
              style: TextStyle(
                color:         tc.withValues(alpha: 0.65),
                fontSize:      slide.fontSize * 0.40 * fontScale,
                fontStyle:     FontStyle.italic,
                fontFamily:    ff == 'sans-serif' || ff == 'serif' ? null : ff,
                letterSpacing: ls,
                shadows:       shadows,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static CrossAxisAlignment _crossAlign(SlideTextAlign a) {
    switch (a) {
      case SlideTextAlign.left:   return CrossAxisAlignment.start;
      case SlideTextAlign.right:  return CrossAxisAlignment.end;
      case SlideTextAlign.center: return CrossAxisAlignment.center;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SLIDE THUMBNAIL
// ══════════════════════════════════════════════════════════════════════════════
/// Small 16:9 preview card used in the slide list panel and strip.
///
/// Previously accepted a fixed `height` which caused the rendered slide to be
/// cropped at arbitrary aspect ratios. Now it always renders at 16:9 so the
/// full slide is visible regardless of how wide the container is.
class SlideThumbnail extends StatelessWidget {
  final Slide slide;
  final bool  selected;
  final Color selectedBorderColor;
  final VoidCallback? onTap;

  const SlideThumbnail({
    super.key,
    required this.slide,
    required this.selectedBorderColor,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderWidth = selected ? 2.5 : 1.5;
    final borderColor = selected
        ? selectedBorderColor
        : Colors.grey.withValues(alpha: 0.25);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: borderWidth),
          // Subtle shadow so the card lifts off the panel background
          boxShadow: selected
              ? [
                  BoxShadow(
                      color:      selectedBorderColor.withValues(alpha: 0.25),
                      blurRadius: 6,
                      spreadRadius: 1)
                ]
              : [
                  BoxShadow(
                      color:      Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4)
                ],
        ),
        // AspectRatio enforces 16:9 — the renderer fills this exactly,
        // so nothing is ever cropped.
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6.5),
            child: SlideRenderer(
              slide:         slide,
              fontScale:     0.18,
              showReference: false,
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SLIDE CONTENT PREVIEW  (alias — kept for present_view.dart compat)
// ══════════════════════════════════════════════════════════════════════════════
class SlideContentPreview extends StatelessWidget {
  final Slide  slide;
  final double fontScale;

  const SlideContentPreview({
    super.key,
    required this.slide,
    this.fontScale = 1.0,
  });

  @override
  Widget build(BuildContext context) => SlideRenderer(
        slide:     slide,
        fontScale: fontScale,
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ══════════════════════════════════════════════════════════════════════════════
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
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: color.withValues(alpha: 0.35)),
            const SizedBox(height: 16),
            Text(message,
                style: TextStyle(
                    fontSize: 15, color: color.withValues(alpha: 0.55))),
          ],
        ),
      );
}