// lib/apps/bulletin/widgets/bulletin_preview.dart
//
// Live in-app preview of a bulletin with proper paper proportions and an
// animated 3-D page-flip when the user taps the paper or presses the arrow
// buttons.
//
// Proportions are derived from real US Letter paper (8.5 × 11 in):
//   • Single page  : portrait  8.5 × 11   → aspect 0.773
//   • Bi-fold      : landscape 11 × 8.5   → aspect 1.294  (folded = 5.5 × 8.5)
//   • Half-sheet   : portrait  8.5 × 5.5  → aspect 1.545  (landscape half)
//   • Tri-fold     : landscape 11 × 8.5   → aspect 1.294  (each panel ≈ 3.67 × 8.5)
//
// The flip animation uses a Matrix4 perspective transform that squashes the
// width to 0 at the midpoint then grows back with the new page — giving the
// classic book-page-turn illusion.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../bulletin_model.dart';

// ══════════════════════════════════════════════════════════════════════════════
// PUBLIC ENTRY POINT
// ══════════════════════════════════════════════════════════════════════════════

class BulletinPreview extends StatefulWidget {
  final BulletinModel bulletin;
  final Color         primary;

  const BulletinPreview({
    super.key,
    required this.bulletin,
    required this.primary,
  });

  @override
  State<BulletinPreview> createState() => _BulletinPreviewState();
}

class _BulletinPreviewState extends State<BulletinPreview>
    with SingleTickerProviderStateMixin {
  int _visiblePage = 0; // which page is currently showing
  int _pendingPage = 0; // the page we are flipping TO

  late final AnimationController _flipCtrl;
  late final Animation<double>   _flipAnim;

  bool get _isFlipping => _flipCtrl.isAnimating;

  BulletinModel get b => widget.bulletin;

  int get _pageCount {
    switch (b.layout) {
      case BulletinLayout.bifold:
      case BulletinLayout.trifold:
        return 2;
      default:
        return 1;
    }
  }

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _flipAnim = CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOut);
    _flipCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() {
          _visiblePage = _pendingPage;
          _flipCtrl.reset();
        });
      }
    });
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  void _guardPage() {
    if (_visiblePage >= _pageCount) {
      _visiblePage = 0;
      _pendingPage = 0;
    }
  }

  void _flipTo(int targetPage) {
    if (_isFlipping || targetPage == _visiblePage) return;
    setState(() => _pendingPage = targetPage);
    _flipCtrl.forward(from: 0);
  }

  void _flipNext() => _flipTo((_visiblePage + 1) % _pageCount);
  void _flipPrev() => _flipTo((_visiblePage - 1 + _pageCount) % _pageCount);

  @override
  Widget build(BuildContext context) {
    _guardPage();
    final accent = _accentColor(b.accentColor);

    return Column(children: [
      // ── toolbar ─────────────────────────────────────────────────────────────
      _PreviewToolbar(
        layout:     b.layout,
        page:       _visiblePage,
        pageCount:  _pageCount,
        accent:     accent,
        isFlipping: _isFlipping,
        onFlipTo:   _flipTo,
      ),

      // ── paper stage ─────────────────────────────────────────────────────────
      Expanded(
        child: Container(
          color: const Color(0xFFD4D8E0),
          child: LayoutBuilder(builder: (ctx, constraints) {
            final paperSize = _fittedPaperSize(
              b.layout,
              constraints.maxWidth  - 80,
              constraints.maxHeight - 40,
            );

            return Stack(alignment: Alignment.center, children: [
              GestureDetector(
                onTap: _pageCount > 1 ? _flipNext : null,
                child: AnimatedBuilder(
                  animation: _flipAnim,
                  builder: (_, __) => _FlipWrapper(
                    progress:  _flipAnim.value,
                    frontPage: _buildPageWidget(b, accent, _visiblePage, paperSize),
                    backPage:  _buildPageWidget(b, accent, _pendingPage,  paperSize),
                    paperSize: paperSize,
                  ),
                ),
              ),

              if (_pageCount > 1) ...[
                Positioned(
                  left: 8,
                  child: _FlipArrowButton(
                    icon:      Icons.chevron_left_rounded,
                    onPressed: _isFlipping ? null : _flipPrev,
                    accent:    accent,
                  ),
                ),
                Positioned(
                  right: 8,
                  child: _FlipArrowButton(
                    icon:      Icons.chevron_right_rounded,
                    onPressed: _isFlipping ? null : _flipNext,
                    accent:    accent,
                  ),
                ),
              ],
            ]);
          }),
        ),
      ),

      // ── footer ──────────────────────────────────────────────────────────────
      _PreviewFooter(
        primary:   widget.primary,
        page:      _visiblePage,
        pageCount: _pageCount,
        layout:    b.layout,
      ),
    ]);
  }

  Widget _buildPageWidget(
      BulletinModel b, Color accent, int page, Size paperSize) {
    switch (b.layout) {
      case BulletinLayout.singlePage:
        return _SinglePagePreview(b: b, accent: accent, size: paperSize);
      case BulletinLayout.bifold:
        return page == 0
            ? _BifoldOutsidePreview(b: b, accent: accent, size: paperSize)
            : _BifoldInsidePreview(b: b, accent: accent, size: paperSize);
      case BulletinLayout.halfSheet:
        return _HalfSheetPreview(b: b, accent: accent, size: paperSize);
      case BulletinLayout.trifold:
        return page == 0
            ? _TrifoldOutsidePreview(b: b, accent: accent, size: paperSize)
            : _TrifoldInsidePreview(b: b, accent: accent, size: paperSize);
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAPER SIZE HELPER
// ══════════════════════════════════════════════════════════════════════════════

Size _fittedPaperSize(BulletinLayout layout, double maxW, double maxH) {
  final double aw, ah;
  switch (layout) {
    case BulletinLayout.singlePage:
      aw = 8.5; ah = 11.0;
      break;
    case BulletinLayout.bifold:
      aw = 11.0; ah = 8.5;
      break;
    case BulletinLayout.halfSheet:
      aw = 8.5; ah = 5.5;
      break;
    case BulletinLayout.trifold:
      aw = 11.0; ah = 8.5;
      break;
  }
  final ratio = aw / ah;
  double w = maxW;
  double h = w / ratio;
  if (h > maxH) {
    h = maxH;
    w = h * ratio;
  }
  return Size(w.clamp(200, 1400), h.clamp(150, 1100));
}

// ══════════════════════════════════════════════════════════════════════════════
// FLIP WRAPPER
// progress 0→0.5 : front rotates out (cos → 0)
// progress 0.5→1 : back  rotates in  (cos → 1)
// ══════════════════════════════════════════════════════════════════════════════

class _FlipWrapper extends StatelessWidget {
  final double progress;
  final Widget frontPage;
  final Widget backPage;
  final Size   paperSize;

  const _FlipWrapper({
    required this.progress,
    required this.frontPage,
    required this.backPage,
    required this.paperSize,
  });

  @override
  Widget build(BuildContext context) {
    final angle          = progress * math.pi;
    final isBack         = progress >= 0.5;
    final scaleX         = math.cos(angle).abs().clamp(0.0, 1.0);
    final scaleY         = 1.0 - math.sin(angle) * 0.04;
    final shadowOpacity  = (math.sin(angle) * 0.35).clamp(0.0, 0.35);
    final displayPage    = isBack ? backPage : frontPage;

    return SizedBox(
      width:  paperSize.width,
      height: paperSize.height,
      child: Stack(fit: StackFit.expand, children: [
        // Drop shadow — grows during flip
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withValues(alpha: 0.20 + shadowOpacity),
                  blurRadius:   24,
                  offset:       const Offset(0, 8),
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
        // Page — squashed horizontally
        Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0008)
            ..scale(scaleX, scaleY, 1.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: displayPage,
          ),
        ),
        // Glare / sheen overlay during flip
        if (progress > 0.02 && progress < 0.98)
          Positioned.fill(
            child: IgnorePointer(
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..scale(scaleX, scaleY, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      begin: isBack
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      end: isBack
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      colors: [
                        Colors.white
                            .withValues(alpha: shadowOpacity * 0.55),
                        Colors.transparent,
                        Colors.black
                            .withValues(alpha: shadowOpacity * 0.22),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TOOLBAR
// ══════════════════════════════════════════════════════════════════════════════

class _PreviewToolbar extends StatelessWidget {
  final BulletinLayout    layout;
  final int               page, pageCount;
  final Color             accent;
  final bool              isFlipping;
  final ValueChanged<int> onFlipTo;

  const _PreviewToolbar({
    required this.layout,
    required this.page,
    required this.pageCount,
    required this.accent,
    required this.isFlipping,
    required this.onFlipTo,
  });

  static const _labels = <BulletinLayout, List<String>>{
    BulletinLayout.bifold:  ['Outside', 'Inside'],
    BulletinLayout.trifold: ['Outside', 'Inside'],
  };
  static const _subs = <BulletinLayout, List<String>>{
    BulletinLayout.bifold:  ['Cover + Back', 'Service + Notes'],
    BulletinLayout.trifold: ['Cover + Spine', 'Service + Notes'],
  };

  @override
  Widget build(BuildContext context) {
    final labels = _labels[layout];
    final subs   = _subs[layout];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(children: [
        Icon(_layoutIcon(layout), size: 15, color: accent),
        const SizedBox(width: 6),
        Text(
          bulletinLayoutLabels[layout] ?? '',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accent),
        ),
        const Spacer(),
        if (labels != null)
          for (int i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _PageChip(
                label:    labels[i],
                subtitle: subs![i],
                selected: page == i,
                accent:   accent,
                onTap:    isFlipping ? null : () => onFlipTo(i),
              ),
            ),
      ]),
    );
  }

  IconData _layoutIcon(BulletinLayout l) {
    switch (l) {
      case BulletinLayout.singlePage: return Icons.article_outlined;
      case BulletinLayout.bifold:     return Icons.menu_book_outlined;
      case BulletinLayout.halfSheet:  return Icons.view_agenda_outlined;
      case BulletinLayout.trifold:    return Icons.view_column_outlined;
    }
  }
}

class _PageChip extends StatelessWidget {
  final String       label, subtitle;
  final bool         selected;
  final Color        accent;
  final VoidCallback? onTap;

  const _PageChip({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected
            ? accent.withValues(alpha: 0.12)
            : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? accent : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? accent : const Color(0xFF6B7280))),
        Text(subtitle,
            style: TextStyle(
                fontSize: 8.5,
                color: selected
                    ? accent.withValues(alpha: 0.7)
                    : const Color(0xFF9CA3AF))),
      ]),
    ),
  );
}

class _FlipArrowButton extends StatelessWidget {
  final IconData      icon;
  final VoidCallback? onPressed;
  final Color         accent;

  const _FlipArrowButton({
    required this.icon,
    required this.onPressed,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity:  onPressed != null ? 1.0 : 0.3,
    duration: const Duration(milliseconds: 150),
    child: Material(
      color:         Colors.white.withValues(alpha: 0.85),
      borderRadius:  BorderRadius.circular(24),
      elevation:     2,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 22, color: accent),
        ),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// FOOTER — info hint + page-dot indicators
// ══════════════════════════════════════════════════════════════════════════════

class _PreviewFooter extends StatelessWidget {
  final Color          primary;
  final int            page, pageCount;
  final BulletinLayout layout;

  const _PreviewFooter({
    required this.primary,
    required this.page,
    required this.pageCount,
    required this.layout,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
    color: Colors.white,
    child: Row(children: [
      Icon(Icons.info_outline, size: 12,
          color: primary.withValues(alpha: 0.35)),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          pageCount > 1
              ? 'Tap the paper or use arrows to flip pages. '
                'Approximate preview — use Print/PDF for exact output.'
              : 'Approximate preview — use Print/PDF for exact output.',
          style: TextStyle(
              fontSize: 9.5,
              color: primary.withValues(alpha: 0.4)),
        ),
      ),
      if (pageCount > 1) ...[
        const SizedBox(width: 8),
        for (int i = 0; i < pageCount; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width:  page == i ? 14 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: page == i
                  ? primary
                  : primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED COMPONENT HELPERS
// All page widgets receive an explicit [size] so font sizes and padding
// scale proportionally with the paper dimensions.
// Reference height is 792 pt (11 in @ 72 dpi for a portrait letter sheet).
// ══════════════════════════════════════════════════════════════════════════════

const _textDark  = Color(0xFF1C1C2E);
const _textMuted = Color(0xFF6B7280);
const _lineColor = Color(0xFFD1D5DB);
const _panelDiv  = Color(0xFFDDE1EA);

/// Scale a design font-size linearly with the paper's height.
/// Avoids double.clamp() which throws when min > max (can happen
/// when pt * 1.8 < 5.0 for very small design point values).
double _fs(double pt, Size s, {double refH = 792}) {
  final scaled = pt * s.height / refH;
  final upper  = pt * 1.8;
  final lower  = upper >= 5.0 ? 5.0 : 0.0;
  if (scaled < lower) return lower;
  if (scaled > upper) return upper;
  return scaled;
}

class _SectionHeading extends StatelessWidget {
  final String label;
  final Color  accent;
  final Size   s;

  const _SectionHeading(this.label, this.accent, this.s);

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: _fs(10, s), bottom: _fs(4, s)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        label.toUpperCase(),
        style: TextStyle(
            fontSize:   _fs(7.5, s),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
            color: accent),
      ),
      SizedBox(height: _fs(2, s)),
      Container(height: 1.5, color: accent),
    ]),
  );
}

class _SermonBlock extends StatelessWidget {
  final BulletinModel b;
  final Color         accent;
  final Size          s;

  const _SermonBlock({required this.b, required this.accent, required this.s});

  @override
  Widget build(BuildContext context) {
    if (b.sermonTitle.isEmpty && b.speakerName.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin:  EdgeInsets.only(bottom: _fs(7, s)),
      padding: EdgeInsets.symmetric(
          horizontal: _fs(9, s), vertical: _fs(6, s)),
      decoration: BoxDecoration(
        color:  accent.withValues(alpha: 0.08),
        border: Border(left: BorderSide(color: accent, width: 2.5)),
        borderRadius:
            const BorderRadius.horizontal(right: Radius.circular(4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (b.sermonTitle.isNotEmpty)
          Text(b.sermonTitle,
              style: TextStyle(
                  fontSize:   _fs(11, s),
                  fontWeight: FontWeight.bold,
                  color: accent)),
        if (b.speakerName.isNotEmpty)
          Text(b.speakerName,
              style: TextStyle(fontSize: _fs(8, s), color: _textMuted)),
        if (b.sermonScripture.isNotEmpty)
          Text(b.sermonScripture,
              style: TextStyle(
                  fontSize:   _fs(8, s),
                  fontStyle:  FontStyle.italic,
                  color: _textDark)),
        if (b.sermonSeriesName.isNotEmpty)
          Text('Series: ${b.sermonSeriesName}',
              style: TextStyle(fontSize: _fs(7.5, s), color: _textMuted)),
      ]),
    );
  }
}

class _OOSWidget extends StatelessWidget {
  final List<ServiceItem> items;
  final Color             accent;
  final Size              s;

  const _OOSWidget({required this.items, required this.accent, required this.s});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text('No service items.',
          style: TextStyle(fontSize: _fs(8, s), color: _textMuted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) => Padding(
        padding: EdgeInsets.symmetric(vertical: _fs(2, s)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: _fs(30, s),
            child: Text(item.time,
                style: TextStyle(
                    fontSize: _fs(7.5, s), color: _textMuted)),
          ),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.label,
                  style: TextStyle(
                      fontSize: _fs(8.5, s), color: _textDark)),
              if (item.detail.isNotEmpty)
                Text(item.detail,
                    style: TextStyle(
                        fontSize:  _fs(7.5, s),
                        color:     _textMuted,
                        fontStyle: FontStyle.italic)),
            ],
          )),
        ]),
      )).toList(),
    );
  }
}

class _AnnWidget extends StatelessWidget {
  final List<Announcement> items;
  final Color              accent;
  final Size               s;

  const _AnnWidget({required this.items, required this.accent, required this.s});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text('No announcements this week.',
          style: TextStyle(
              fontSize:  _fs(8, s),
              color:     _textMuted,
              fontStyle: FontStyle.italic));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((a) => Padding(
        padding: EdgeInsets.only(bottom: _fs(6, s)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(a.title,
              style: TextStyle(
                  fontSize:   _fs(8.5, s),
                  fontWeight: FontWeight.bold,
                  color: accent)),
          if (a.body.isNotEmpty)
            Text(a.body,
                style: TextStyle(fontSize: _fs(8, s), color: _textDark)),
        ]),
      )).toList(),
    );
  }
}

class _PrayerWidget extends StatelessWidget {
  final String text;
  final Size   s;

  const _PrayerWidget(this.text, this.s);

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return Text('See prayer card insert.',
          style: TextStyle(
              fontSize:  _fs(8, s),
              color:     _textMuted,
              fontStyle: FontStyle.italic));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map((l) => Padding(
                padding: EdgeInsets.symmetric(vertical: _fs(1.5, s)),
                child: Text('🙏 $l',
                    style: TextStyle(
                        fontSize: _fs(8, s), color: _textDark)),
              ))
          .toList(),
    );
  }
}

class _NotesWidget extends StatelessWidget {
  final String prompt;
  final Size   s;

  const _NotesWidget(this.prompt, this.s);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(prompt,
          style: TextStyle(
              fontSize:   _fs(9, s),
              fontWeight: FontWeight.bold,
              color: _textDark)),
      SizedBox(height: _fs(6, s)),
      for (int i = 0; i < 9; i++)
        Container(
          height: _fs(18, s),
          margin: EdgeInsets.only(bottom: _fs(2, s)),
          decoration: const BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: _lineColor))),
        ),
    ],
  );
}

class _ContactCard extends StatelessWidget {
  final BulletinModel b;
  final Size          s;

  const _ContactCard({required this.b, required this.s});

  @override
  Widget build(BuildContext context) => Container(
    margin:  EdgeInsets.only(top: _fs(8, s)),
    padding: EdgeInsets.all(_fs(8, s)),
    decoration: BoxDecoration(
      border: Border.all(color: _lineColor, width: 1.5),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(b.contactCardHeading,
          style: TextStyle(
              fontSize:   _fs(8, s),
              fontWeight: FontWeight.bold,
              color: _textDark)),
      SizedBox(height: _fs(5, s)),
      _cf('Name'),  _cf('Email'), _cf('Phone'),
      SizedBox(height: _fs(4, s)),
      Wrap(spacing: _fs(8, s), children: [
        _cbox('First-time visitor'),
        _cbox('Prayer request'),
      ]),
    ]),
  );

  Widget _cf(String label) => Padding(
    padding: EdgeInsets.only(bottom: _fs(5, s)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(fontSize: _fs(6.5, s), color: _textMuted)),
      SizedBox(height: _fs(2, s)),
      Container(height: 1, color: _textDark),
    ]),
  );

  Widget _cbox(String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width:  _fs(8, s),
        height: _fs(8, s),
        decoration: BoxDecoration(
            border:       Border.all(color: _textMuted),
            borderRadius: BorderRadius.circular(2)),
      ),
      SizedBox(width: _fs(3, s)),
      Text(label,
          style: TextStyle(fontSize: _fs(7, s), color: _textDark)),
    ],
  );
}

class _ChurchFooter extends StatelessWidget {
  final BulletinModel b;
  final Size          s;

  const _ChurchFooter({required this.b, required this.s});

  @override
  Widget build(BuildContext context) {
    final parts = [
      b.churchAddress, b.churchPhone, b.churchWebsite, b.churchEmail,
    ].where((x) => x.isNotEmpty).toList();
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: _fs(8, s)),
      child: Text(parts.join(' · '),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: _fs(7.5, s), color: _textMuted)),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAPER SHEET WRAPPER
// Enforces exact paper dimensions + white background + subtle corner rounding.
// ══════════════════════════════════════════════════════════════════════════════

class _PaperSheet extends StatelessWidget {
  final Size   size;
  final Widget child;

  const _PaperSheet({required this.size, required this.child});

  @override
  Widget build(BuildContext context) => SizedBox(
    width:  size.width,
    height: size.height,
    child: Material(
      color:         Colors.white,
      borderRadius:  BorderRadius.circular(3),
      clipBehavior:  Clip.antiAlias,
      child: child,
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// SINGLE PAGE  (portrait 8.5 × 11)
// ══════════════════════════════════════════════════════════════════════════════

class _SinglePagePreview extends StatelessWidget {
  final BulletinModel b;
  final Color         accent;
  final Size          size;

  const _SinglePagePreview(
      {required this.b, required this.accent, required this.size});

  @override
  Widget build(BuildContext context) {
    final s   = size;
    final pad = _fs(16, s);

    return _PaperSheet(
      size: size,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: accent,
          padding: EdgeInsets.symmetric(
              vertical: _fs(18, s), horizontal: pad),
          child: Column(children: [
            Text(
              b.churchName.isNotEmpty ? b.churchName : 'Church Name',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize:   _fs(18, s),
                  fontWeight: FontWeight.w900,
                  color: Colors.white),
            ),
            if (b.serviceDate != null) ...[
              SizedBox(height: _fs(3, s)),
              Text(
                DateFormat('MMMM d, yyyy').format(b.serviceDate!),
                style: TextStyle(
                    fontSize: _fs(9, s), color: Colors.white70),
              ),
            ],
          ]),
        ),
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _SermonBlock(b: b, accent: accent, s: s),
            _SectionHeading('Order of Service', accent, s),
            _OOSWidget(items: b.orderOfService, accent: accent, s: s),
            _SectionHeading('Announcements', accent, s),
            _AnnWidget(items: b.announcements, accent: accent, s: s),
            if (b.prayerRequests.trim().isNotEmpty) ...[
              _SectionHeading('Prayer Requests', accent, s),
              _PrayerWidget(b.prayerRequests, s),
            ],
            if (b.includeSermonNotes) ...[
              _SectionHeading(b.sermonNotesPrompt, accent, s),
              _NotesWidget(b.sermonNotesPrompt, s),
            ],
            if (b.includeContactCard)
              _ContactCard(b: b, s: s),
            _ChurchFooter(b: b, s: s),
          ]),
        )),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BI-FOLD  (landscape 11 × 8.5, 2 panels)
// ══════════════════════════════════════════════════════════════════════════════

class _BifoldOutsidePreview extends StatelessWidget {
  final BulletinModel b;
  final Color         accent;
  final Size          size;

  const _BifoldOutsidePreview(
      {required this.b, required this.accent, required this.size});

  @override
  Widget build(BuildContext context) {
    final s   = size;
    final pad = _fs(14, s);
    final date = b.serviceDate != null
        ? DateFormat('MMMM d, yyyy').format(b.serviceDate!)
        : '';

    return _PaperSheet(
      size: size,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Panel L — back
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _SectionHeading('Prayer Requests', accent, s),
            _PrayerWidget(b.prayerRequests, s),
            if (b.includeContactCard)
              _ContactCard(b: b, s: s),
          ]),
        )),
        Container(width: 1, color: _panelDiv),
        // Panel R — cover
        Expanded(child: Container(
          color:   accent,
          padding: EdgeInsets.all(pad),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
              b.churchName.isNotEmpty ? b.churchName : 'Church Name',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize:   _fs(18, s),
                  fontWeight: FontWeight.w900,
                  color: Colors.white),
            ),
            if (date.isNotEmpty) ...[
              SizedBox(height: _fs(4, s)),
              Text(date,
                  style: TextStyle(
                      fontSize: _fs(9, s), color: Colors.white70)),
            ],
            if (b.sermonTitle.isNotEmpty) ...[
              Container(
                width:  _fs(40, s), height: 1.5,
                margin: EdgeInsets.symmetric(vertical: _fs(12, s)),
                color:  Colors.white38,
              ),
              Text("TODAY'S MESSAGE",
                  style: TextStyle(
                      fontSize:      _fs(6.5, s),
                      letterSpacing: 0.9,
                      color: Colors.white54)),
              SizedBox(height: _fs(4, s)),
              Text(b.sermonTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize:   _fs(12, s),
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              if (b.speakerName.isNotEmpty) ...[
                SizedBox(height: _fs(4, s)),
                Text(b.speakerName,
                    style: TextStyle(
                        fontSize: _fs(9, s), color: Colors.white70)),
              ],
              if (b.sermonScripture.isNotEmpty)
                Text(b.sermonScripture,
                    style: TextStyle(
                        fontSize:  _fs(8, s),
                        fontStyle: FontStyle.italic,
                        color: Colors.white60)),
            ],
          ]),
        )),
      ]),
    );
  }
}

class _BifoldInsidePreview extends StatelessWidget {
  final BulletinModel b;
  final Color         accent;
  final Size          size;

  const _BifoldInsidePreview(
      {required this.b, required this.accent, required this.size});

  @override
  Widget build(BuildContext context) {
    final s   = size;
    final pad = _fs(14, s);

    return _PaperSheet(
      size: size,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _SermonBlock(b: b, accent: accent, s: s),
            _SectionHeading('Order of Service', accent, s),
            _OOSWidget(items: b.orderOfService, accent: accent, s: s),
          ]),
        )),
        Container(width: 1, color: _panelDiv),
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _SectionHeading('Announcements', accent, s),
            _AnnWidget(items: b.announcements, accent: accent, s: s),
            if (b.includeSermonNotes) ...[
              _SectionHeading(b.sermonNotesPrompt, accent, s),
              _NotesWidget(b.sermonNotesPrompt, s),
            ],
            _ChurchFooter(b: b, s: s),
          ]),
        )),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HALF SHEET  (full letter sheet with cut line; each half is 8.5 × 5.5)
// ══════════════════════════════════════════════════════════════════════════════

class _HalfSheetPreview extends StatelessWidget {
  final BulletinModel b;
  final Color         accent;
  final Size          size;

  const _HalfSheetPreview(
      {required this.b, required this.accent, required this.size});

  @override
  Widget build(BuildContext context) {
    final halfH    = (size.height - 12) / 2;
    final halfSize = Size(size.width, halfH);

    return _PaperSheet(
      size: size,
      child: Column(children: [
        _buildHalf(halfSize),
        SizedBox(
          height: 12,
          child: Row(children: [
            const Expanded(child: Divider(color: Color(0xFFBBBBBB))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('✂',
                  style: TextStyle(
                      fontSize: _fs(9, size),
                      color: const Color(0xFFBBBBBB))),
            ),
            const Expanded(child: Divider(color: Color(0xFFBBBBBB))),
          ]),
        ),
        _buildHalf(halfSize),
      ]),
    );
  }

  Widget _buildHalf(Size hs) {
    final pad = _fs(10, hs);
    return SizedBox(
      height: hs.height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Mini cover strip
        Container(
          width:   hs.width * 0.28,
          color:   accent,
          padding: EdgeInsets.all(pad),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
              b.churchName.isNotEmpty ? b.churchName : 'Church',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize:   _fs(11, hs),
                  fontWeight: FontWeight.w900,
                  color: Colors.white),
            ),
            if (b.serviceDate != null) ...[
              SizedBox(height: _fs(3, hs)),
              Text(
                DateFormat('MMM d, y').format(b.serviceDate!),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: _fs(7.5, hs), color: Colors.white70),
              ),
            ],
          ]),
        ),
        Container(width: 1, color: _panelDiv),
        // Content
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _SermonBlock(b: b, accent: accent, s: hs),
            _SectionHeading('Order of Service', accent, hs),
            _OOSWidget(items: b.orderOfService, accent: accent, s: hs),
            _SectionHeading('Announcements', accent, hs),
            _AnnWidget(items: b.announcements, accent: accent, s: hs),
          ]),
        )),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TRI-FOLD  (landscape 11 × 8.5, 3 panels)
// ══════════════════════════════════════════════════════════════════════════════

class _TrifoldOutsidePreview extends StatelessWidget {
  final BulletinModel b;
  final Color         accent;
  final Size          size;

  const _TrifoldOutsidePreview(
      {required this.b, required this.accent, required this.size});

  @override
  Widget build(BuildContext context) {
    final s   = size;
    final pad = _fs(12, s);
    final date = b.serviceDate != null
        ? DateFormat('MMMM d, yyyy').format(b.serviceDate!)
        : '';

    return _PaperSheet(
      size: size,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Panel 1 — back
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _SectionHeading('Prayer Requests', accent, s),
            _PrayerWidget(b.prayerRequests, s),
            if (b.includeContactCard)
              _ContactCard(b: b, s: s),
          ]),
        )),
        Container(width: 1, color: _panelDiv),
        // Panel 2 — spine
        Expanded(child: Container(
          color:   const Color(0xFFF8F9FA),
          padding: EdgeInsets.all(pad),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
              b.churchName.isNotEmpty ? b.churchName : 'Church',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize:   _fs(12, s),
                  fontWeight: FontWeight.bold,
                  color: accent),
            ),
            SizedBox(height: _fs(8, s)),
            if (b.churchAddress.isNotEmpty)
              Text(b.churchAddress,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: _fs(7.5, s), color: _textMuted)),
            if (b.churchPhone.isNotEmpty)
              Text(b.churchPhone,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: _fs(7.5, s), color: _textMuted)),
            if (b.churchWebsite.isNotEmpty)
              Text(b.churchWebsite,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: _fs(7.5, s), color: _textMuted)),
          ]),
        )),
        Container(width: 1, color: _panelDiv),
        // Panel 3 — cover
        Expanded(child: Container(
          color:   accent,
          padding: EdgeInsets.all(pad),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
              b.churchName.isNotEmpty ? b.churchName : 'Church Name',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize:   _fs(16, s),
                  fontWeight: FontWeight.w900,
                  color: Colors.white),
            ),
            if (date.isNotEmpty) ...[
              SizedBox(height: _fs(3, s)),
              Text(date,
                  style: TextStyle(
                      fontSize: _fs(8, s), color: Colors.white70)),
            ],
            if (b.sermonTitle.isNotEmpty) ...[
              Container(
                width:  _fs(32, s), height: 1.5,
                margin: EdgeInsets.symmetric(vertical: _fs(10, s)),
                color:  Colors.white38,
              ),
              Text("TODAY'S MESSAGE",
                  style: TextStyle(
                      fontSize:      _fs(6, s),
                      letterSpacing: 0.8,
                      color: Colors.white54)),
              SizedBox(height: _fs(4, s)),
              Text(b.sermonTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize:   _fs(11, s),
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              if (b.speakerName.isNotEmpty)
                Text(b.speakerName,
                    style: TextStyle(
                        fontSize: _fs(8, s), color: Colors.white70)),
              if (b.sermonScripture.isNotEmpty)
                Text(b.sermonScripture,
                    style: TextStyle(
                        fontSize:  _fs(7.5, s),
                        fontStyle: FontStyle.italic,
                        color: Colors.white60)),
            ],
          ]),
        )),
      ]),
    );
  }
}

class _TrifoldInsidePreview extends StatelessWidget {
  final BulletinModel b;
  final Color         accent;
  final Size          size;

  const _TrifoldInsidePreview(
      {required this.b, required this.accent, required this.size});

  @override
  Widget build(BuildContext context) {
    final s   = size;
    final pad = _fs(12, s);

    return _PaperSheet(
      size: size,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _SermonBlock(b: b, accent: accent, s: s),
            _SectionHeading('Order of Service', accent, s),
            _OOSWidget(items: b.orderOfService, accent: accent, s: s),
          ]),
        )),
        Container(width: 1, color: _panelDiv),
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _SectionHeading('Announcements', accent, s),
            _AnnWidget(items: b.announcements, accent: accent, s: s),
          ]),
        )),
        Container(width: 1, color: _panelDiv),
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (b.includeSermonNotes) ...[
              _SectionHeading(b.sermonNotesPrompt, accent, s),
              _NotesWidget(b.sermonNotesPrompt, s),
            ],
            _ChurchFooter(b: b, s: s),
          ]),
        )),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// UTILITY
// ══════════════════════════════════════════════════════════════════════════════

Color _accentColor(String hex) {
  try {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  } catch (_) {
    return const Color(0xFF1A3A5C);
  }
}