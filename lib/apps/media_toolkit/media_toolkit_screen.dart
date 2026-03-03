// lib/apps/media_toolkit/media_toolkit_screen.dart
//
// Media Toolkit — generates branded social media resources using the
// church's logo, primary color, secondary color, and name from AppState.
//
// Features:
//   • Social post templates (Facebook, Instagram, Twitter/X, Story, YouTube)
//   • Color palette export (hex codes + swatch preview with tap-to-copy)
//   • Brand style guide card (copyable text summary)
//   • File conversion: upload an image and apply brand overlay
//   • Copy-to-clipboard helpers for hex codes and captions

import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../models/app_state.dart';
import '../../models/church_profile.dart';
import '../../theme.dart';

// ── HELPERS ───────────────────────────────────────────────────────────────────

String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

Color _contrastOn(Color bg) {
  final lum = (0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b) / 255;
  return lum > 0.5 ? Colors.black : Colors.white;
}

// ── SOCIAL FORMAT ─────────────────────────────────────────────────────────────

class _SocialFormat {
  final String id;
  final String name;
  final String icon;
  final double w;
  final double h;
  final String note;

  const _SocialFormat({
    required this.id,
    required this.name,
    required this.icon,
    required this.w,
    required this.h,
    required this.note,
  });

  double get ratio => w / h;
}

const _formats = <_SocialFormat>[
  _SocialFormat(
      id: 'facebook_post',
      name: 'Facebook Post',
      icon: 'f',
      w: 1200,
      h: 630,
      note: '1200 × 630 px'),
  _SocialFormat(
      id: 'instagram_square',
      name: 'Instagram Square',
      icon: 'IG',
      w: 1080,
      h: 1080,
      note: '1080 × 1080 px'),
  _SocialFormat(
      id: 'instagram_portrait',
      name: 'Instagram Portrait',
      icon: 'IG',
      w: 1080,
      h: 1350,
      note: '1080 × 1350 px'),
  _SocialFormat(
      id: 'story',
      name: 'Story / Reel',
      icon: '▶',
      w: 1080,
      h: 1920,
      note: '1080 × 1920 px'),
  _SocialFormat(
      id: 'twitter',
      name: 'X / Twitter',
      icon: 'X',
      w: 1200,
      h: 675,
      note: '1200 × 675 px'),
  _SocialFormat(
      id: 'youtube_thumb',
      name: 'YouTube Thumb',
      icon: '▶',
      w: 1280,
      h: 720,
      note: '1280 × 720 px'),
];

enum _TemplateStyle { bold, minimal, gradient, frame }

const _templateStyleLabels = {
  _TemplateStyle.bold: 'Bold',
  _TemplateStyle.minimal: 'Minimal',
  _TemplateStyle.gradient: 'Gradient',
  _TemplateStyle.frame: 'Frame',
};

// ══════════════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class MediaToolkitScreen extends StatefulWidget {
  const MediaToolkitScreen({super.key});

  @override
  State<MediaToolkitScreen> createState() => _MediaToolkitScreenState();
}

class _MediaToolkitScreenState extends State<MediaToolkitScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final primary = state.brandPrimary;
    final secondary = state.brandSecondary;
    final profile = state.churchProfile;
    if (profile == null) return const SizedBox();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Media Toolkit',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: primary,
        foregroundColor: _contrastOn(primary),
        bottom: TabBar(
          controller: _tabs,
          labelColor: _contrastOn(primary),
          unselectedLabelColor:
              _contrastOn(primary).withValues(alpha: 0.6),
          indicatorColor: secondary,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.image_outlined), text: 'Post Templates'),
            Tab(icon: Icon(Icons.palette_outlined), text: 'Brand Kit'),
            Tab(
                icon: Icon(Icons.transform_outlined),
                text: 'Convert Files'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _PostTemplatesTab(
              primary: primary,
              secondary: secondary,
              profile: profile),
          _BrandKitTab(
              primary: primary,
              secondary: secondary,
              profile: profile),
          _ConvertTab(
              primary: primary,
              secondary: secondary,
              profile: profile),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 1 — POST TEMPLATES
// ══════════════════════════════════════════════════════════════════════════════

class _PostTemplatesTab extends StatefulWidget {
  final Color primary;
  final Color secondary;
  final ChurchProfile profile;

  const _PostTemplatesTab(
      {required this.primary,
      required this.secondary,
      required this.profile});

  @override
  State<_PostTemplatesTab> createState() => _PostTemplatesTabState();
}

class _PostTemplatesTabState extends State<_PostTemplatesTab> {
  _SocialFormat _selectedFormat = _formats[0];
  _TemplateStyle _selectedStyle = _TemplateStyle.bold;
  final _headlineCtrl = TextEditingController(text: 'Join Us Sunday');
  final _subCtrl = TextEditingController(text: '10:00 AM · Grace Community');
  final _taglineCtrl = TextEditingController();
  final _previewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _taglineCtrl.text = widget.profile.tagline.isNotEmpty
        ? widget.profile.tagline
        : widget.profile.name;
  }

  @override
  void dispose() {
    _headlineCtrl.dispose();
    _subCtrl.dispose();
    _taglineCtrl.dispose();
    super.dispose();
  }

  void _copyCaption() {
    final text =
        '${_headlineCtrl.text}\n${_subCtrl.text}\n\n${widget.profile.name}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Caption copied to clipboard!'),
          duration: Duration(seconds: 2)),
    );
  }

  Future<void> _saveImage(BuildContext context) async {
    try {
      final boundary = _previewKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file =
          File('${dir.path}/${_selectedFormat.id}_$stamp.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Saved to ${file.path}'),
              duration: const Duration(seconds: 3)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Format picker ──────────────────────────────────────────────
          _sectionLabel('Platform & Format'),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _formats.map((f) {
                final sel = f.id == _selectedFormat.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedFormat = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: sel ? widget.primary : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: sel
                                ? widget.primary
                                : const Color(0xFFDDE1EC)),
                        boxShadow: sel
                            ? [
                                BoxShadow(
                                    color: widget.primary
                                        .withValues(alpha: 0.2),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2))
                              ]
                            : null,
                      ),
                      child: Column(
                        children: [
                          Text(f.icon,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: sel
                                      ? _contrastOn(widget.primary)
                                      : widget.primary)),
                          const SizedBox(height: 4),
                          Text(f.name,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: sel
                                      ? _contrastOn(widget.primary)
                                      : textDark)),
                          Text(f.note,
                              style: TextStyle(
                                  fontSize: 9,
                                  color: sel
                                      ? _contrastOn(widget.primary)
                                          .withValues(alpha: 0.7)
                                      : textMid)),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),

          // ── Template style ─────────────────────────────────────────────
          _sectionLabel('Template Style'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _TemplateStyle.values.map((s) {
              final sel = s == _selectedStyle;
              return ChoiceChip(
                label: Text(_templateStyleLabels[s]!),
                selected: sel,
                onSelected: (_) => setState(() => _selectedStyle = s),
                selectedColor: widget.primary,
                labelStyle: TextStyle(
                    color: sel ? _contrastOn(widget.primary) : textDark,
                    fontWeight: FontWeight.w600),
                backgroundColor: Colors.white,
                side: BorderSide(
                    color:
                        sel ? widget.primary : const Color(0xFFDDE1EC)),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // ── Text fields ────────────────────────────────────────────────
          _sectionLabel('Text Content'),
          const SizedBox(height: 10),
          _inputField('Headline', _headlineCtrl,
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          _inputField('Sub-text / Date & Time', _subCtrl,
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          _inputField('Church name / tagline', _taglineCtrl,
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 20),

          // ── Preview ────────────────────────────────────────────────────
          _sectionLabel('Preview'),
          const SizedBox(height: 10),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: RepaintBoundary(
                key: _previewKey,
                child: AspectRatio(
                  aspectRatio: _selectedFormat.ratio,
                  child: _TemplateCanvas(
                    format: _selectedFormat,
                    style: _selectedStyle,
                    primary: widget.primary,
                    secondary: widget.secondary,
                    headline: _headlineCtrl.text,
                    subtext: _subCtrl.text,
                    churchName: _taglineCtrl.text,
                    logoPath: widget.profile.logoPath,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Actions ────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copyCaption,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy Caption'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: widget.primary,
                      side: BorderSide(color: widget.primary),
                      padding:
                          const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _saveImage(context),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Save Image'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: widget.primary,
                      foregroundColor: _contrastOn(widget.primary),
                      padding:
                          const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Save then upload directly to your social platform.',
              style: TextStyle(fontSize: 11, color: textMid),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ── TEMPLATE CANVAS ───────────────────────────────────────────────────────────

class _TemplateCanvas extends StatelessWidget {
  final _SocialFormat format;
  final _TemplateStyle style;
  final Color primary;
  final Color secondary;
  final String headline;
  final String subtext;
  final String churchName;
  final String logoPath;

  const _TemplateCanvas({
    required this.format,
    required this.style,
    required this.primary,
    required this.secondary,
    required this.headline,
    required this.subtext,
    required this.churchName,
    required this.logoPath,
  });

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case _TemplateStyle.bold:
        return _boldTemplate();
      case _TemplateStyle.minimal:
        return _minimalTemplate();
      case _TemplateStyle.gradient:
        return _gradientTemplate();
      case _TemplateStyle.frame:
        return _frameTemplate();
    }
  }

  Widget _boldTemplate() {
    final onPrimary = _contrastOn(primary);
    return Container(
      color: primary,
      child: Stack(
        children: [
          Positioned(
            right: -30,
            bottom: -30,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: secondary.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 20,
            top: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: secondary.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _logoWidget(size: 40, onDark: true),
                const Spacer(),
                Text(headline,
                    style: TextStyle(
                        color: onPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        height: 1.1),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: secondary,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 8),
                Text(subtext,
                    style: TextStyle(
                        color: onPrimary.withValues(alpha: 0.85),
                        fontSize: 13)),
                const SizedBox(height: 16),
                Text(churchName,
                    style: TextStyle(
                        color: secondary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _minimalTemplate() {
    return Container(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _logoWidget(size: 28, onDark: false),
              const SizedBox(width: 8),
              Text(churchName,
                  style: TextStyle(
                      color: primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8)),
            ]),
            const Spacer(),
            Container(width: 32, height: 3, color: secondary),
            const SizedBox(height: 10),
            Text(headline,
                style: TextStyle(
                    color: primary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.15)),
            const SizedBox(height: 8),
            Text(subtext,
                style: const TextStyle(color: textMid, fontSize: 13)),
            const Spacer(),
            const Divider(color: Color(0xFFEAEDF3)),
          ],
        ),
      ),
    );
  }

  Widget _gradientTemplate() {
    final onGrad = _contrastOn(primary);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary,
            Color.lerp(primary, secondary, 0.5)!,
            secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _logoWidget(size: 44, onDark: true),
            const SizedBox(height: 16),
            Text(headline,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: onGrad,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(
                          color: Colors.black38,
                          blurRadius: 6,
                          offset: const Offset(0, 2))
                    ])),
            const SizedBox(height: 10),
            Text(subtext,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: onGrad.withValues(alpha: 0.9),
                    fontSize: 13)),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(churchName,
                  style: TextStyle(
                      color: onGrad,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frameTemplate() {
    return Container(
      color: const Color(0xFFF5F7FB),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: primary, width: 3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _logoWidget(size: 28, onDark: false),
                  const SizedBox(width: 8),
                  Text(churchName,
                      style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 0.8)),
                  const Spacer(),
                  Container(width: 8, height: 8, color: secondary),
                ]),
                const Spacer(),
                Container(width: 24, height: 3, color: secondary),
                const SizedBox(height: 8),
                Text(headline,
                    style: TextStyle(
                        color: primary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.1)),
                const SizedBox(height: 6),
                Text(subtext,
                    style: const TextStyle(
                        color: textMid, fontSize: 12)),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logoWidget({required double size, required bool onDark}) {
    if (logoPath.isNotEmpty && File(logoPath).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.2),
        child: Image.file(File(logoPath),
            width: size, height: size, fit: BoxFit.cover),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: 0.2)
            : primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(size * 0.2),
      ),
      child: Icon(Icons.church,
          size: size * 0.6,
          color: onDark ? Colors.white : primary),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 2 — BRAND KIT
// ══════════════════════════════════════════════════════════════════════════════

class _BrandKitTab extends StatelessWidget {
  final Color primary;
  final Color secondary;
  final ChurchProfile profile;

  const _BrandKitTab(
      {required this.primary,
      required this.secondary,
      required this.profile});

  void _copy(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('$label copied!'),
          duration: const Duration(seconds: 2)),
    );
  }

  Map<String, List<Color>> _buildPalette() {
    return {
      'Primary': [
        Color.lerp(primary, Colors.white, 0.6)!,
        Color.lerp(primary, Colors.white, 0.3)!,
        primary,
        Color.lerp(primary, Colors.black, 0.25)!,
        Color.lerp(primary, Colors.black, 0.5)!,
      ],
      'Secondary': [
        Color.lerp(secondary, Colors.white, 0.6)!,
        Color.lerp(secondary, Colors.white, 0.3)!,
        secondary,
        Color.lerp(secondary, Colors.black, 0.25)!,
        Color.lerp(secondary, Colors.black, 0.5)!,
      ],
      'Neutrals': [
        const Color(0xFFFFFFFF),
        const Color(0xFFF5F7FB),
        const Color(0xFFDDE1EC),
        const Color(0xFF6B7280),
        const Color(0xFF111827),
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = _buildPalette();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Color palette ──────────────────────────────────────────────
          _sectionLabel('Brand Color Palette'),
          const SizedBox(height: 4),
          const Text('Tap any swatch to copy its hex code.',
              style: TextStyle(fontSize: 12, color: textMid)),
          const SizedBox(height: 14),
          ...palette.entries.map((entry) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.key,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textDark)),
                  const SizedBox(height: 6),
                  Row(
                    children: entry.value.map((c) {
                      final hex = _hex(c);
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => _copy(context, hex, hex),
                          child: Tooltip(
                            message: hex,
                            child: Container(
                              height: 56,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: c,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(hex,
                                    style: TextStyle(
                                        color: _contrastOn(c),
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],
              )),

          const SizedBox(height: 8),
          // ── Typography ─────────────────────────────────────────────────
          _sectionLabel('Typography'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEAEDF3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Headline',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: primary)),
                const SizedBox(height: 4),
                Text('Sub-heading · Medium Weight',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: primary.withValues(alpha: 0.75))),
                const SizedBox(height: 4),
                const Text(
                    'Body text for longer descriptions. Clear and readable.',
                    style: TextStyle(
                        fontSize: 13, color: textMid, height: 1.5)),
                const SizedBox(height: 4),
                const Text('CAPTION / LABEL · UPPERCASE',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: textMid)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Logo usage ─────────────────────────────────────────────────
          _sectionLabel('Logo Usage'),
          const SizedBox(height: 10),
          Row(
            children: [
              _logoBadge(bg: primary),
              const SizedBox(width: 12),
              _logoBadge(bg: Colors.white, border: true),
              const SizedBox(width: 12),
              _logoBadge(bg: Colors.black),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Your logo on primary, white, and dark backgrounds.',
              style: TextStyle(fontSize: 11, color: textMid)),
          const SizedBox(height: 20),

          // ── Style guide card ───────────────────────────────────────────
          _sectionLabel('Style Guide Card'),
          const SizedBox(height: 10),
          _StyleGuideCard(
              primary: primary, secondary: secondary, profile: profile),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _copyStyleGuide(context),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy Style Guide Text'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: primary,
                  side: BorderSide(color: primary),
                  padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoBadge({required Color bg, bool border = false}) {
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: border
                ? Border.all(
                    color: const Color(0xFFDDE1EC), width: 1.5)
                : null,
          ),
          child: Center(
            child: profile.logoPath.isNotEmpty &&
                    File(profile.logoPath).existsSync()
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Image.file(File(profile.logoPath),
                        fit: BoxFit.contain),
                  )
                : Icon(Icons.church, size: 36, color: _contrastOn(bg)),
          ),
        ),
      ),
    );
  }

  void _copyStyleGuide(BuildContext context) {
    final text = '''
${profile.name} — Brand Style Guide
════════════════════════════════
Primary Color:   ${_hex(primary)}
Secondary Color: ${_hex(secondary)}

Primary Tints:
  Light:  ${_hex(Color.lerp(primary, Colors.white, 0.6)!)}
  Mid:    ${_hex(Color.lerp(primary, Colors.white, 0.3)!)}
  Base:   ${_hex(primary)}
  Dark:   ${_hex(Color.lerp(primary, Colors.black, 0.25)!)}
  Darker: ${_hex(Color.lerp(primary, Colors.black, 0.5)!)}

Secondary Tints:
  Light:  ${_hex(Color.lerp(secondary, Colors.white, 0.6)!)}
  Mid:    ${_hex(Color.lerp(secondary, Colors.white, 0.3)!)}
  Base:   ${_hex(secondary)}
  Dark:   ${_hex(Color.lerp(secondary, Colors.black, 0.25)!)}
  Darker: ${_hex(Color.lerp(secondary, Colors.black, 0.5)!)}

Typography: Bold/heavy for headlines, medium for sub-heads, regular for body.
''';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Style guide copied!'),
          duration: Duration(seconds: 2)),
    );
  }
}

class _StyleGuideCard extends StatelessWidget {
  final Color primary;
  final Color secondary;
  final ChurchProfile profile;

  const _StyleGuideCard(
      {required this.primary,
      required this.secondary,
      required this.profile});

  @override
  Widget build(BuildContext context) {
    final onPrimary = _contrastOn(primary);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEAEDF3)),
        color: Colors.white,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: primary,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                profile.logoPath.isNotEmpty &&
                        File(profile.logoPath).existsSync()
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(File(profile.logoPath),
                            width: 32, height: 32, fit: BoxFit.cover),
                      )
                    : Icon(Icons.church, color: onPrimary, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(profile.name,
                      style: TextStyle(
                          color: onPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: secondary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Brand Guide',
                      style: TextStyle(
                          color: _contrastOn(secondary),
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _swatchTile('Primary', primary),
                const SizedBox(width: 10),
                _swatchTile('Secondary', secondary),
                const SizedBox(width: 10),
                _swatchTile(
                    'Light', Color.lerp(primary, Colors.white, 0.8)!),
                const SizedBox(width: 10),
                _swatchTile(
                    'Dark', Color.lerp(primary, Colors.black, 0.5)!),
              ],
            ),
          ),
          if (profile.tagline.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 14, bottom: 14),
              child: Text('"${profile.tagline}"',
                  style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: primary,
                      fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _swatchTile(String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFDDE1EC)),
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(fontSize: 9, color: textMid),
              textAlign: TextAlign.center),
          Text(_hex(color),
              style: const TextStyle(
                  fontSize: 8,
                  color: textMid,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 3 — CONVERT FILES
// ══════════════════════════════════════════════════════════════════════════════

enum _OverlayPosition { topLeft, topRight, bottomLeft, bottomRight, center }

const _overlayPositionLabels = {
  _OverlayPosition.topLeft: 'Top Left',
  _OverlayPosition.topRight: 'Top Right',
  _OverlayPosition.bottomLeft: 'Bottom Left',
  _OverlayPosition.bottomRight: 'Bottom Right',
  _OverlayPosition.center: 'Center',
};

class _ConvertTab extends StatefulWidget {
  final Color primary;
  final Color secondary;
  final ChurchProfile profile;

  const _ConvertTab(
      {required this.primary,
      required this.secondary,
      required this.profile});

  @override
  State<_ConvertTab> createState() => _ConvertTabState();
}

class _ConvertTabState extends State<_ConvertTab> {
  File? _uploadedFile;
  String? _uploadedName;
  _OverlayPosition _overlayPos = _OverlayPosition.bottomLeft;
  bool _showLogo = true;
  bool _showChurchName = true;
  double _overlayOpacity = 0.85;
  final _previewKey = GlobalKey();

  Future<void> _pickFile() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: false);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _uploadedFile = File(result.files.single.path!);
        _uploadedName = result.files.single.name;
      });
    }
  }

  Future<void> _saveConverted(BuildContext context) async {
    try {
      final boundary = _previewKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/branded_$stamp.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Saved to ${file.path}'),
              duration: const Duration(seconds: 3)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Upload an Image'),
          const SizedBox(height: 4),
          const Text(
            'Upload any image and apply your branding as an overlay — perfect for event photos, announcements, and more.',
            style: TextStyle(fontSize: 12, color: textMid, height: 1.5),
          ),
          const SizedBox(height: 14),

          // ── Upload drop zone ───────────────────────────────────────────
          GestureDetector(
            onTap: _pickFile,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: _uploadedFile != null
                    ? primary.withValues(alpha: 0.05)
                    : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: _uploadedFile != null
                        ? primary
                        : const Color(0xFFDDE1EC),
                    width: _uploadedFile != null ? 2 : 1),
              ),
              child: Column(
                children: [
                  Icon(
                    _uploadedFile != null
                        ? Icons.check_circle_outline
                        : Icons.upload_file_outlined,
                    color: _uploadedFile != null ? primary : textMid,
                    size: 36,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _uploadedFile != null
                        ? (_uploadedName ?? 'File selected')
                        : 'Tap to upload an image',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color:
                            _uploadedFile != null ? primary : textMid),
                  ),
                  if (_uploadedFile == null)
                    const Text('JPG, PNG supported',
                        style: TextStyle(fontSize: 11, color: textMid)),
                ],
              ),
            ),
          ),

          if (_uploadedFile != null) ...[
            const SizedBox(height: 20),
            _sectionLabel('Branding Overlay Options'),
            const SizedBox(height: 10),
            const Text('Overlay Position',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textDark)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _OverlayPosition.values.map((p) {
                final sel = p == _overlayPos;
                return ChoiceChip(
                  label: Text(_overlayPositionLabels[p]!,
                      style: const TextStyle(fontSize: 12)),
                  selected: sel,
                  onSelected: (_) => setState(() => _overlayPos = p),
                  selectedColor: primary,
                  labelStyle: TextStyle(
                      color: sel ? _contrastOn(primary) : textDark,
                      fontWeight: FontWeight.w600),
                  backgroundColor: Colors.white,
                  side: BorderSide(
                      color: sel ? primary : const Color(0xFFDDE1EC)),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('Overlay Opacity',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textDark)),
                const Spacer(),
                Text('${(_overlayOpacity * 100).round()}%',
                    style: TextStyle(fontSize: 12, color: primary)),
              ],
            ),
            Slider(
              value: _overlayOpacity,
              min: 0.3,
              max: 1.0,
              divisions: 14,
              activeColor: primary,
              onChanged: (v) => setState(() => _overlayOpacity = v),
            ),
            SwitchListTile(
              title: const Text('Show Logo',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textDark)),
              value: _showLogo,
              activeColor: primary,
              onChanged: (v) => setState(() => _showLogo = v),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('Show Church Name',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textDark)),
              value: _showChurchName,
              activeColor: primary,
              onChanged: (v) => setState(() => _showChurchName = v),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 20),
            _sectionLabel('Preview'),
            const SizedBox(height: 10),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: RepaintBoundary(
                    key: _previewKey,
                    child: _BrandedImagePreview(
                      file: _uploadedFile!,
                      primary: primary,
                      secondary: widget.secondary,
                      profile: widget.profile,
                      overlayPos: _overlayPos,
                      overlayOpacity: _overlayOpacity,
                      showLogo: _showLogo,
                      showChurchName: _showChurchName,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _saveConverted(context),
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Save Branded Image'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: _contrastOn(primary),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ],

          const SizedBox(height: 24),
          // ── Size reference table ───────────────────────────────────────
          _sectionLabel('Social Media Size Reference'),
          const SizedBox(height: 10),
          ..._formats.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(f.icon,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: primary)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.name,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textDark)),
                          Text(f.note,
                              style: const TextStyle(
                                  fontSize: 11, color: textMid)),
                        ],
                      ),
                    ),
                    // mini aspect ratio diagram
                    SizedBox(
                      width: 50,
                      height: 36,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: f.ratio.clamp(0.4, 2.5),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: primary.withValues(alpha: 0.35),
                                  width: 1.5),
                              borderRadius: BorderRadius.circular(3),
                              color: primary.withValues(alpha: 0.05),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _BrandedImagePreview extends StatelessWidget {
  final File file;
  final Color primary;
  final Color secondary;
  final ChurchProfile profile;
  final _OverlayPosition overlayPos;
  final double overlayOpacity;
  final bool showLogo;
  final bool showChurchName;

  const _BrandedImagePreview({
    required this.file,
    required this.primary,
    required this.secondary,
    required this.profile,
    required this.overlayPos,
    required this.overlayOpacity,
    required this.showLogo,
    required this.showChurchName,
  });

  Alignment get _alignment {
    switch (overlayPos) {
      case _OverlayPosition.topLeft:
        return Alignment.topLeft;
      case _OverlayPosition.topRight:
        return Alignment.topRight;
      case _OverlayPosition.bottomLeft:
        return Alignment.bottomLeft;
      case _OverlayPosition.bottomRight:
        return Alignment.bottomRight;
      case _OverlayPosition.center:
        return Alignment.center;
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPrimary = _contrastOn(primary);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(file, fit: BoxFit.cover),
          Align(
            alignment: _alignment,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: overlayOpacity),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showLogo) ...[
                      profile.logoPath.isNotEmpty &&
                              File(profile.logoPath).existsSync()
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.file(
                                  File(profile.logoPath),
                                  width: 28,
                                  height: 28,
                                  fit: BoxFit.cover),
                            )
                          : Icon(Icons.church,
                              color: onPrimary, size: 22),
                      if (showChurchName) const SizedBox(width: 8),
                    ],
                    if (showChurchName)
                      Text(
                        profile.name,
                        style: TextStyle(
                            color: onPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── SHARED HELPERS ─────────────────────────────────────────────────────────────

Widget _sectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.w700, color: textDark),
      ),
    );

Widget _inputField(String label, TextEditingController ctrl,
        {ValueChanged<String>? onChanged}) =>
    TextFormField(
      controller: ctrl,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFDDE1EC)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFDDE1EC)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );