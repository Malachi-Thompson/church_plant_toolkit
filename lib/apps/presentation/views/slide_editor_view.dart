// lib/apps/presentation/views/slide_editor_view.dart
//
// Slide editor — live preview + tabbed style panel.
// On mobile (< 600 px) the preview is smaller and the tab panel
// is shown as a bottom sheet triggered by a floating action button,
// keeping the full slide preview visible.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/presentation_models.dart';
import '../widgets/presentation_widgets.dart';
import '../../../theme.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ENTRY POINT
// ══════════════════════════════════════════════════════════════════════════════
class SlideEditorView extends StatefulWidget {
  final Slide slide;
  final Color primary;
  final Color secondary;
  final VoidCallback onChanged;
  /// Called when user taps "Reset to master style". Null = hide the button.
  final VoidCallback? onResetToMaster;
  /// Navigate back to the master style panel (deselects the current slide).
  final VoidCallback? onOpenMasterStyle;

  const SlideEditorView({
    super.key,
    required this.slide,
    required this.primary,
    required this.secondary,
    required this.onChanged,
    this.onResetToMaster,
    this.onOpenMasterStyle,
  });

  @override
  State<SlideEditorView> createState() => _SlideEditorViewState();
}

class _SlideEditorViewState extends State<SlideEditorView>
    with SingleTickerProviderStateMixin {
  late TabController        _tabs;
  late TextEditingController _titleCtrl;
  late TextEditingController _bodyCtrl;
  late TextEditingController _refCtrl;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
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
    _tabs.dispose();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged();
    setState(() {});
  }

  void _updateStyle(SlideStyle Function(SlideStyle) updater) {
    widget.slide.style = updater(widget.slide.style);
    widget.slide.styleOverridden = true;
    _notify();
  }

  void _openEditSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize:     0.35,
        maxChildSize:     0.92,
        builder: (ctx, sc) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                  color:      Colors.black.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset:     const Offset(0, -4))
            ],
          ),
          child: Column(
            children: [
              // drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              // Master Style nav button (mobile)
              if (widget.onOpenMasterStyle != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: widget.onOpenMasterStyle,
                      icon: Icon(Icons.palette_rounded,
                          size: 15, color: widget.primary),
                      label: Text('Master Style',
                          style: TextStyle(color: widget.primary)),
                      style: TextButton.styleFrom(
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                      ),
                    ),
                  ),
                ),
              // Tab bar
              TabBar(
                controller: _tabs,
                labelColor: widget.primary,
                unselectedLabelColor: Colors.grey,
                indicatorColor: widget.primary,
                indicatorWeight: 2.5,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(icon: Icon(Icons.text_fields, size: 17), text: 'Content'),
                  Tab(icon: Icon(Icons.wallpaper, size: 17), text: 'Background'),
                  Tab(icon: Icon(Icons.font_download, size: 17), text: 'Text Style'),
                  Tab(icon: Icon(Icons.auto_awesome, size: 17), text: 'Effects'),
                ],
              ),
              if (widget.slide.styleOverridden && widget.onResetToMaster != null)
                _OverrideBanner(primary: widget.primary, onReset: widget.onResetToMaster!),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: _tabBodies(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _tabBodies(BuildContext context) => [
    _ContentTab(
      slide: widget.slide,
      titleCtrl: _titleCtrl,
      bodyCtrl: _bodyCtrl,
      refCtrl: _refCtrl,
      onChanged: _notify,
    ),
    _BackgroundTab(
      slide: widget.slide,
      primary: widget.primary,
      secondary: widget.secondary,
      onChanged: _notify,
      onStyle: _updateStyle,
    ),
    _TextStyleTab(
      slide: widget.slide,
      primary: widget.primary,
      onChanged: _notify,
      onStyle: _updateStyle,
    ),
    _EffectsTab(
      slide: widget.slide,
      primary: widget.primary,
      secondary: widget.secondary,
      onChanged: _notify,
      onStyle: _updateStyle,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final slide   = widget.slide;
    final p       = widget.primary;
    final isWide  = MediaQuery.of(context).size.width >= 600;

    if (isWide) {
      // ── Desktop / tablet: two-panel layout ──────────────────────────────
      // LayoutBuilder gives us the real panel dimensions so the preview
      // never overflows horizontally OR vertically.
      return LayoutBuilder(
        builder: (context, constraints) {
          // Reserve space for TabBar (~48 px) + tabs min content (~160 px)
          // + padding. Preview gets whatever is left, capped at 480 wide.
          const tabBarH    = 48.0;
          const tabMinH    = 160.0;
          const vPadding   = 32.0; // top 20 + bottom 12
          final availH     = constraints.maxHeight.isFinite
              ? constraints.maxHeight : 600.0;
          final maxPreviewH = (availH - tabBarH - tabMinH - vPadding)
              .clamp(60.0, double.infinity);

          // Width: fill panel up to 480 px, maintain 16:9
          final availW   = constraints.maxWidth.isFinite
              ? constraints.maxWidth : 480.0;
          final byWidth  = (availW - 48).clamp(0.0, 480.0); // 24px h-padding each side
          final byHeight = maxPreviewH * (16 / 9);
          final previewW = byWidth < byHeight ? byWidth : byHeight;
          final previewH = previewW * (9 / 16);

          return Column(
            children: [
              // -- Master Style nav button
              if (widget.onOpenMasterStyle != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: widget.onOpenMasterStyle,
                      icon: const Icon(Icons.palette_rounded, size: 15),
                      label: const Text('Master Style'),
                      style: TextButton.styleFrom(
                        foregroundColor: p,
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Center(
                  child: Container(
                    width: previewW, height: previewH,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 20)
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SlideRenderer(slide: slide, fontScale: 1.0),
                    ),
                  ),
                ),
              ),
              TabBar(
                controller: _tabs,
                labelColor: p,
                unselectedLabelColor: Colors.grey,
                indicatorColor: p,
                indicatorWeight: 2.5,
                tabs: const [
                  Tab(icon: Icon(Icons.text_fields, size: 18), text: 'Content'),
                  Tab(icon: Icon(Icons.wallpaper, size: 18), text: 'Background'),
                  Tab(icon: Icon(Icons.font_download, size: 18), text: 'Text Style'),
                  Tab(icon: Icon(Icons.auto_awesome, size: 18), text: 'Effects'),
                ],
              ),
              if (widget.slide.styleOverridden && widget.onResetToMaster != null)
                _OverrideBanner(primary: p, onReset: widget.onResetToMaster!),              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: _tabBodies(context),
                ),
              ),
            ],
          );
        },
      );
    }

    // ── Mobile: full-bleed preview + floating edit button ───────────────────
    return Stack(
      children: [
        // Full preview
        Positioned.fill(
          child: SlideRenderer(slide: slide, fontScale: 1.0),
        ),
        // Edit FAB
        Positioned(
          bottom: 24, right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'slide_edit_fab',
            backgroundColor: p,
            foregroundColor: contrastOn(p),
            icon: const Icon(Icons.tune_rounded, size: 20),
            label: const Text('Edit Slide',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => _openEditSheet(context),
          ),
        ),
        // Slide type chip
        Positioned(
          top: 12, left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              slide.type.toUpperCase(),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1),
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 1 — CONTENT
// ══════════════════════════════════════════════════════════════════════════════
class _ContentTab extends StatelessWidget {
  final Slide slide;
  final TextEditingController titleCtrl;
  final TextEditingController bodyCtrl;
  final TextEditingController refCtrl;
  final VoidCallback onChanged;

  const _ContentTab({
    required this.slide, required this.titleCtrl, required this.bodyCtrl,
    required this.refCtrl, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: titleCtrl,
            decoration: _dec('Title / Song section'),
            onChanged: (v) { slide.title = v; onChanged(); },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: bodyCtrl, maxLines: 6,
            decoration: _dec('Body text / Lyrics'),
            onChanged: (v) { slide.body = v; onChanged(); },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: refCtrl,
            decoration: _dec('Reference / Scripture (optional)'),
            onChanged: (v) { slide.reference = v; onChanged(); },
          ),
          const SizedBox(height: 20),
          _SectionLabel('Font size'),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: slide.fontSize,
                  min: 16, max: 80, divisions: 16,
                  label: slide.fontSize.round().toString(),
                  onChanged: (v) { slide.fontSize = v; onChanged(); },
                ),
              ),
              SizedBox(
                width: 36,
                child: Text('${slide.fontSize.round()}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 2 — BACKGROUND
// ══════════════════════════════════════════════════════════════════════════════
class _BackgroundTab extends StatefulWidget {
  final Slide slide; final Color primary; final Color secondary;
  final VoidCallback onChanged;
  final void Function(SlideStyle Function(SlideStyle)) onStyle;

  const _BackgroundTab({
    required this.slide, required this.primary, required this.secondary,
    required this.onChanged, required this.onStyle,
  });

  @override
  State<_BackgroundTab> createState() => _BackgroundTabState();
}

class _BackgroundTabState extends State<_BackgroundTab> {
  bool _pickingImage = false;

  List<Color> _presets() {
    final p = widget.primary;
    return [
      p,
      Color.lerp(p, Colors.black, 0.25)!,
      Color.lerp(p, Colors.black, 0.50)!,
      Color.lerp(p, Colors.black, 0.75)!,
      Color.lerp(p, Colors.white, 0.50)!,
      Colors.black, Colors.white,
      Colors.blueGrey.shade900, Colors.indigo.shade900,
      Colors.purple.shade900, Colors.teal.shade700,
      const Color(0xFF1B1B2F), const Color(0xFF2C3E50), const Color(0xFF1A1A2E),
    ];
  }

  Future<void> _pickImage() async {
    setState(() => _pickingImage = true);
    try {
      final picker = ImagePicker();
      final file   = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (file == null) return;
      String path;
      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        final b64   = base64Encode(bytes);
        final mime  = file.mimeType ?? 'image/jpeg';
        path = 'data:$mime;base64,$b64';
      } else {
        path = file.path;
      }
      widget.onStyle((s) => s.copyWith(bgImagePath: path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load image: $e'),
                backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slide = widget.slide;
    final s     = slide.style;
    final p     = widget.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('Background Colour'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _presets().map((c) {
              final sel = !s.useGradient &&
                  slide.bgColor.toARGB32() == c.toARGB32();
              return GestureDetector(
                onTap: () {
                  slide.bgColor   = c;
                  slide.textColor = contrastOn(c);
                  widget.onStyle((st) => st.copyWith(useGradient: false));
                },
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: c, shape: BoxShape.circle,
                    border: Border.all(
                        color: sel ? widget.secondary : Colors.grey.shade300,
                        width: sel ? 3 : 1),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _SectionLabel('Gradient'),
              const Spacer(),
              Switch(
                value: s.useGradient,
                onChanged: (v) => widget.onStyle((st) => st.copyWith(useGradient: v)),
                activeColor: p,
              ),
            ],
          ),
          if (s.useGradient) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('End colour:', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 10),
                Wrap(
                  spacing: 6,
                  children: [
                    Colors.black, Colors.white,
                    Colors.indigo.shade900, Colors.purple.shade900,
                    Colors.teal.shade700, Colors.orange.shade800,
                  ].map((c) {
                    final sel = s.gradientEnd.toARGB32() == c.toARGB32();
                    return GestureDetector(
                      onTap: () => widget.onStyle((st) => st.copyWith(gradientEnd: c)),
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: c, shape: BoxShape.circle,
                          border: Border.all(
                              color: sel ? widget.secondary : Colors.grey.shade300,
                              width: sel ? 2.5 : 1),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _LabeledRow(
              label: 'Direction',
              child: DropdownButton<String>(
                value: SlideStyle.alignName(s.gradientBegin),
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 'topCenter',    child: Text('Top → Bottom')),
                  DropdownMenuItem(value: 'bottomCenter', child: Text('Bottom → Top')),
                  DropdownMenuItem(value: 'centerLeft',   child: Text('Left → Right')),
                  DropdownMenuItem(value: 'centerRight',  child: Text('Right → Left')),
                  DropdownMenuItem(value: 'topLeft',      child: Text('Diagonal ↘')),
                  DropdownMenuItem(value: 'bottomRight',  child: Text('Diagonal ↖')),
                ],
                onChanged: (v) => widget.onStyle((st) => st.copyWith(
                    gradientBegin:    SlideStyle.alignFromName(v),
                    gradientEndAlign: SlideStyle.alignFromName(v,
                        fallback: Alignment.bottomCenter))),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          _SectionLabel('Background Image'),
          const SizedBox(height: 10),
          if (s.bgImagePath != null && s.bgImagePath!.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 80, width: double.infinity,
                child: _BgImagePreview(path: s.bgImagePath!),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.swap_horiz, size: 16),
                    label: const Text('Change image'),
                    style: OutlinedButton.styleFrom(foregroundColor: p),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      widget.onStyle((st) => st.copyWith(clearBgImage: true)),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Remove'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _pickingImage ? null : _pickImage,
                icon: _pickingImage
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_photo_alternate_outlined),
                label: Text(_pickingImage
                    ? 'Loading…' : 'Upload image from gallery'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: p,
                  foregroundColor: contrastOn(p),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)),
                ),
              ),
            ),
          ],
          if (s.bgImagePath != null && s.bgImagePath!.isNotEmpty) ...[
            const SizedBox(height: 14),
            _LabeledRow(
              label: 'Image fit',
              child: DropdownButton<SlideBgFit>(
                value: s.bgFit, isDense: true,
                items: const [
                  DropdownMenuItem(value: SlideBgFit.cover,   child: Text('Cover')),
                  DropdownMenuItem(value: SlideBgFit.contain, child: Text('Contain')),
                  DropdownMenuItem(value: SlideBgFit.fill,    child: Text('Stretch')),
                ],
                onChanged: (v) =>
                    widget.onStyle((st) => st.copyWith(bgFit: v)),
              ),
            ),
            _SliderRow(
              label: 'Image opacity', value: s.bgImageOpacity,
              min: 0.1, max: 1.0,
              onChanged: (v) =>
                  widget.onStyle((st) => st.copyWith(bgImageOpacity: v)),
            ),
            _SliderRow(
              label: 'Tint darkness', value: s.bgTintOpacity,
              min: 0.0, max: 0.9,
              onChanged: (v) =>
                  widget.onStyle((st) => st.copyWith(bgTintOpacity: v)),
            ),
          ],
        ],
      ),
    );
  }
}

class _BgImagePreview extends StatelessWidget {
  final String path;
  const _BgImagePreview({required this.path});

  @override
  Widget build(BuildContext context) {
    if (path.startsWith('data:')) {
      final comma = path.indexOf(',');
      if (comma >= 0) {
        try {
          final bytes = base64Decode(path.substring(comma + 1));
          return Image.memory(bytes, fit: BoxFit.cover,
              width: double.infinity, height: double.infinity);
        } catch (_) {}
      }
    }
    if (!kIsWeb) {
      return Image.file(File(path), fit: BoxFit.cover,
          width: double.infinity, height: double.infinity);
    }
    return Container(color: Colors.grey.shade200,
        child: const Icon(Icons.image, color: Colors.grey));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 3 — TEXT STYLE
// ══════════════════════════════════════════════════════════════════════════════
class _TextStyleTab extends StatelessWidget {
  final Slide slide; final Color primary;
  final VoidCallback onChanged;
  final void Function(SlideStyle Function(SlideStyle)) onStyle;

  const _TextStyleTab({
    required this.slide, required this.primary,
    required this.onChanged, required this.onStyle,
  });

  @override
  Widget build(BuildContext context) {
    final s = slide.style;
    final p = primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('Font Family'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: kSlideFonts.map((f) {
              final sel = s.fontFamily == f.fontFamily;
              return GestureDetector(
                onTap: () =>
                    onStyle((st) => st.copyWith(fontFamily: f.fontFamily)),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel
                        ? p.withValues(alpha: 0.12) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: sel ? p : Colors.transparent, width: 1.5),
                  ),
                  child: Text(f.name,
                      style: TextStyle(
                        fontFamily: f.fontFamily == 'sans-serif' ||
                                    f.fontFamily == 'serif'
                            ? null : f.fontFamily,
                        fontSize: 13,
                        color: sel ? p : null,
                        fontWeight: sel ? FontWeight.bold : null,
                      )),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _SectionLabel('Text Alignment'),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final a in SlideTextAlign.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _AlignBtn(
                    icon: _alignIcon(a), tooltip: a.name,
                    active: s.textAlign == a, color: p,
                    onTap: () => onStyle((st) => st.copyWith(textAlign: a)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionLabel('Title'),
          const SizedBox(height: 8),
          Row(
            children: [
              _ToggleBtn(label: 'B', bold: true, active: s.titleBold, color: p,
                  onTap: () => onStyle((st) => st.copyWith(titleBold: !s.titleBold))),
              const SizedBox(width: 8),
              _ToggleBtn(label: 'I', italic: true, active: s.titleItalic, color: p,
                  onTap: () => onStyle((st) => st.copyWith(titleItalic: !s.titleItalic))),
            ],
          ),
          _SliderRow(label: 'Title scale', value: s.titleScale,
              min: 0.5, max: 2.0, divisions: 15,
              onChanged: (v) => onStyle((st) => st.copyWith(titleScale: v))),
          const SizedBox(height: 12),
          _SectionLabel('Body'),
          const SizedBox(height: 8),
          Row(
            children: [
              _ToggleBtn(label: 'B', bold: true, active: s.bodyBold, color: p,
                  onTap: () => onStyle((st) => st.copyWith(bodyBold: !s.bodyBold))),
              const SizedBox(width: 8),
              _ToggleBtn(label: 'I', italic: true, active: s.bodyItalic, color: p,
                  onTap: () => onStyle((st) => st.copyWith(bodyItalic: !s.bodyItalic))),
            ],
          ),
          _SliderRow(label: 'Body scale', value: s.bodyScale,
              min: 0.5, max: 2.0, divisions: 15,
              onChanged: (v) => onStyle((st) => st.copyWith(bodyScale: v))),
          const SizedBox(height: 12),
          _SectionLabel('Text Colour'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              Colors.white, Colors.black,
              Colors.yellow.shade200, Colors.amber,
              Colors.lightBlue.shade100, Colors.grey.shade300,
              Colors.orange.shade200, const Color(0xFFD4A843),
            ].map((c) {
              final sel = slide.textColor.toARGB32() == c.toARGB32();
              return GestureDetector(
                onTap: () { slide.textColor = c; onChanged(); },
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: c, shape: BoxShape.circle,
                    border: Border.all(
                        color: sel ? p : Colors.grey.shade400,
                        width: sel ? 3 : 1),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 2)
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _SectionLabel('Spacing'),
          _SliderRow(label: 'Letter spacing', value: s.letterSpacing,
              min: -1.0, max: 6.0, divisions: 14,
              onChanged: (v) =>
                  onStyle((st) => st.copyWith(letterSpacing: v))),
          _SliderRow(label: 'Line height', value: s.lineHeight,
              min: 1.0, max: 3.0, divisions: 20,
              onChanged: (v) =>
                  onStyle((st) => st.copyWith(lineHeight: v))),
        ],
      ),
    );
  }

  static IconData _alignIcon(SlideTextAlign a) {
    switch (a) {
      case SlideTextAlign.left:   return Icons.format_align_left;
      case SlideTextAlign.center: return Icons.format_align_center;
      case SlideTextAlign.right:  return Icons.format_align_right;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 4 — EFFECTS
// ══════════════════════════════════════════════════════════════════════════════
class _EffectsTab extends StatelessWidget {
  final Slide slide; final Color primary; final Color secondary;
  final VoidCallback onChanged;
  final void Function(SlideStyle Function(SlideStyle)) onStyle;

  const _EffectsTab({
    required this.slide, required this.primary, required this.secondary,
    required this.onChanged, required this.onStyle,
  });

  @override
  Widget build(BuildContext context) {
    final s = slide.style;
    final p = primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Style Preset Picker ────────────────────────────────────────────
          _SectionLabel('Style Looks'),
          const SizedBox(height: 8),
          _StylePresetPicker(
            primary:   primary,
            secondary: secondary,
            slide:     slide,
            onStyle:   onStyle,
            onChanged: onChanged,
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          _SwitchRow(label: 'Text Shadow', value: s.textShadow, color: p,
              onChanged: (v) =>
                  onStyle((st) => st.copyWith(textShadow: v))),
          if (s.textShadow) ...[
            _SliderRow(label: 'Shadow blur', value: s.shadowBlur, min: 1, max: 20,
                onChanged: (v) =>
                    onStyle((st) => st.copyWith(shadowBlur: v))),
            _ColorRow(
              label: 'Shadow colour',
              colors: [Colors.black, Colors.white,
                       Colors.black87, Colors.blueGrey.shade900],
              current: s.shadowColor, primary: p,
              onPick: (c) =>
                  onStyle((st) => st.copyWith(shadowColor: c)),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          _SwitchRow(label: 'Text Box Background', value: s.showTextBox, color: p,
              onChanged: (v) =>
                  onStyle((st) => st.copyWith(showTextBox: v))),
          if (s.showTextBox) ...[
            _ColorRow(
              label: 'Box colour',
              colors: [Colors.black, Colors.white,
                       Colors.indigo.shade900, Colors.blueGrey.shade900,
                       Colors.brown.shade900, const Color(0xFF1A3A5C)],
              current: s.textBoxColor, primary: p,
              onPick: (c) =>
                  onStyle((st) => st.copyWith(textBoxColor: c)),
            ),
            _SliderRow(label: 'Box opacity', value: s.textBoxOpacity, min: 0.1, max: 1.0,
                onChanged: (v) =>
                    onStyle((st) => st.copyWith(textBoxOpacity: v))),
            _SliderRow(label: 'Corner radius', value: s.textBoxRadius, min: 0, max: 30,
                onChanged: (v) =>
                    onStyle((st) => st.copyWith(textBoxRadius: v))),
            _SliderRow(label: 'Horizontal padding', value: s.textBoxPaddingH,
                min: 8, max: 60,
                onChanged: (v) =>
                    onStyle((st) => st.copyWith(textBoxPaddingH: v))),
            _SliderRow(label: 'Vertical padding', value: s.textBoxPaddingV,
                min: 4, max: 40,
                onChanged: (v) =>
                    onStyle((st) => st.copyWith(textBoxPaddingV: v))),
          ],
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          _SectionLabel('Background Pattern Overlay'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: SlideOverlay.values.map((o) {
              final sel = s.overlay == o;
              return GestureDetector(
                onTap: () => onStyle((st) => st.copyWith(overlay: o)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel
                        ? p.withValues(alpha: 0.12) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: sel ? p : Colors.transparent, width: 1.5),
                  ),
                  child: Text(_overlayLabel(o),
                      style: TextStyle(
                          fontSize: 12,
                          color: sel ? p : null,
                          fontWeight: sel ? FontWeight.bold : null)),
                ),
              );
            }).toList(),
          ),
          if (s.overlay != SlideOverlay.none) ...[
            const SizedBox(height: 10),
            _SliderRow(label: 'Pattern opacity', value: s.overlayOpacity,
                min: 0.02, max: 0.35,
                onChanged: (v) =>
                    onStyle((st) => st.copyWith(overlayOpacity: v))),
          ],
        ],
      ),
    );
  }

  static String _overlayLabel(SlideOverlay o) {
    switch (o) {
      case SlideOverlay.none:       return 'None';
      case SlideOverlay.crosshatch: return 'Grid';
      case SlideOverlay.dots:       return 'Dots';
      case SlideOverlay.diagonal:   return 'Lines';
      case SlideOverlay.vignette:   return 'Vignette';
      case SlideOverlay.grain:      return 'Grain';
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// STYLE PRESET PICKER
// ══════════════════════════════════════════════════════════════════════════════
/// Horizontal chip row letting the user snap the current slide to a preset.
/// Chips show the preset swatch + name; tapping applies the preset's [SlideStyle].
// Per-slide-type style choices — 3 curated looks shown as visual cards
class SlideStyleChoice {
  final String     label;
  final String     subtitle;
  final Color      swatch;
  final Color      swatchEnd;
  final bool       useGradient;
  final bool       hasTextBox;
  final SlideStyle style;

  const SlideStyleChoice({
    required this.label,
    required this.subtitle,
    required this.swatch,
    required this.swatchEnd,
    this.useGradient = true,
    this.hasTextBox  = false,
    required this.style,
  });
}

Map<String, List<SlideStyleChoice>> slideStyleChoices(
    Color primary, Color secondary) {
  return {
    'title': [
      SlideStyleChoice(
        label: 'Bold Impact', subtitle: 'Full gradient • large type',
        swatch: primary, swatchEnd: Color.lerp(primary, Colors.black, 0.55)!,
        style: SlideStyle(
          useGradient: true, gradientEnd: Color.lerp(primary, Colors.black, 0.55)!,
          gradientBegin: Alignment.topLeft, gradientEndAlign: Alignment.bottomRight,
          overlay: SlideOverlay.vignette, overlayColor: Colors.black, overlayOpacity: 0.35,
          fontFamily: 'sans-serif', textAlign: SlideTextAlign.center,
          titleBold: true, titleScale: 1.15, bodyScale: 1.0,
          letterSpacing: 2.0, lineHeight: 1.35,
          textShadow: true, shadowColor: Colors.black, shadowBlur: 14,
          showTextBox: false,
        ),
      ),
      SlideStyleChoice(
        label: 'Clean White', subtitle: 'Light bg • dark text',
        swatch: const Color(0xFFF8F8FA),
        swatchEnd: const Color(0xFFDDDDE8),
        style: SlideStyle(
          useGradient: true, gradientEnd: const Color(0xFFDDDDE8),
          gradientBegin: Alignment.topCenter, gradientEndAlign: Alignment.bottomCenter,
          overlay: SlideOverlay.none,
          fontFamily: 'sans-serif', textAlign: SlideTextAlign.center,
          titleBold: true, titleScale: 1.1, bodyScale: 0.95,
          letterSpacing: 0.8, lineHeight: 1.4,
          textShadow: false, showTextBox: false,
        ),
      ),
      SlideStyleChoice(
        label: 'Pill Accent', subtitle: 'Dark bg • branded box',
        swatch: const Color(0xFF0A0A12),
        swatchEnd: const Color(0xFF0A0A12),
        useGradient: false, hasTextBox: true,
        style: SlideStyle(
          useGradient: false,
          overlay: SlideOverlay.dots, overlayColor: Colors.white, overlayOpacity: 0.03,
          fontFamily: 'sans-serif', textAlign: SlideTextAlign.center,
          titleBold: true, titleScale: 1.1, bodyScale: 1.0,
          letterSpacing: 1.8, lineHeight: 1.35, textShadow: false,
          showTextBox: true,
          textBoxColor: primary, textBoxOpacity: 0.88,
          textBoxRadius: 28, textBoxPaddingH: 30, textBoxPaddingV: 16,
        ),
      ),
    ],
    'lyric': [
      SlideStyleChoice(
        label: 'Worship Dark', subtitle: 'Deep navy • glow shadow',
        swatch: const Color(0xFF0D1B3E), swatchEnd: const Color(0xFF000511),
        style: SlideStyle(
          useGradient: true, gradientEnd: const Color(0xFF000511),
          gradientBegin: Alignment.topLeft, gradientEndAlign: Alignment.bottomRight,
          overlay: SlideOverlay.vignette, overlayColor: Colors.black, overlayOpacity: 0.50,
          fontFamily: 'serif', textAlign: SlideTextAlign.center,
          titleBold: false, titleItalic: true, titleScale: 0.85,
          bodyItalic: false, bodyScale: 1.1,
          letterSpacing: 0.8, lineHeight: 1.6,
          textShadow: true, shadowColor: const Color(0xFF3A6FD8), shadowBlur: 16,
          showTextBox: false,
        ),
      ),
      SlideStyleChoice(
        label: 'Warm Praise', subtitle: 'Amber gradient • bold',
        swatch: const Color(0xFFD4770A), swatchEnd: const Color(0xFF7B1A1A),
        style: SlideStyle(
          useGradient: true, gradientEnd: const Color(0xFF7B1A1A),
          gradientBegin: Alignment.topRight, gradientEndAlign: Alignment.bottomLeft,
          overlay: SlideOverlay.grain, overlayColor: Colors.white, overlayOpacity: 0.05,
          fontFamily: 'sans-serif', textAlign: SlideTextAlign.center,
          titleBold: true, titleScale: 1.0, bodyScale: 1.05,
          letterSpacing: 1.2, lineHeight: 1.5,
          textShadow: true, shadowColor: const Color(0xFF3D0000), shadowBlur: 10,
          showTextBox: false,
        ),
      ),
      SlideStyleChoice(
        label: 'Frosted Box', subtitle: 'Black bg • frosted pill',
        swatch: const Color(0xFF111111), swatchEnd: const Color(0xFF111111),
        useGradient: false, hasTextBox: true,
        style: SlideStyle(
          useGradient: false,
          overlay: SlideOverlay.none,
          fontFamily: 'sans-serif', textAlign: SlideTextAlign.center,
          titleBold: true, titleScale: 0.95, bodyScale: 1.0,
          letterSpacing: 0.5, lineHeight: 1.55, textShadow: false,
          showTextBox: true,
          textBoxColor: Colors.white, textBoxOpacity: 0.12,
          textBoxRadius: 16, textBoxPaddingH: 28, textBoxPaddingV: 18,
        ),
      ),
    ],
    'scripture': [
      SlideStyleChoice(
        label: 'Ocean Deep', subtitle: 'Navy vignette • italic serif',
        swatch: const Color(0xFF006994), swatchEnd: const Color(0xFF001A33),
        style: SlideStyle(
          useGradient: true, gradientEnd: const Color(0xFF001A33),
          gradientBegin: Alignment.topCenter, gradientEndAlign: Alignment.bottomCenter,
          overlay: SlideOverlay.vignette, overlayColor: Colors.black, overlayOpacity: 0.45,
          fontFamily: 'serif', textAlign: SlideTextAlign.center,
          titleBold: false, titleItalic: true, titleScale: 0.85,
          bodyItalic: true, bodyScale: 1.05,
          letterSpacing: 0.3, lineHeight: 1.65,
          textShadow: true, shadowColor: Colors.black, shadowBlur: 12,
          showTextBox: false,
        ),
      ),
      SlideStyleChoice(
        label: 'Stone Chapel', subtitle: 'Warm grey • classic serif',
        swatch: const Color(0xFF5A5045), swatchEnd: const Color(0xFF2A2018),
        style: SlideStyle(
          useGradient: true, gradientEnd: const Color(0xFF2A2018),
          gradientBegin: Alignment.topCenter, gradientEndAlign: Alignment.bottomCenter,
          overlay: SlideOverlay.crosshatch, overlayColor: Colors.white, overlayOpacity: 0.03,
          fontFamily: 'serif', textAlign: SlideTextAlign.center,
          titleBold: false, titleItalic: true, titleScale: 0.85,
          bodyItalic: true, bodyScale: 1.0,
          letterSpacing: 0.5, lineHeight: 1.65,
          textShadow: true, shadowColor: Colors.black, shadowBlur: 8,
          showTextBox: false,
        ),
      ),
      SlideStyleChoice(
        label: 'White Card', subtitle: 'Light bg • reference box',
        swatch: const Color(0xFFF2F2F5), swatchEnd: const Color(0xFFE0E0EC),
        hasTextBox: true,
        style: SlideStyle(
          useGradient: true, gradientEnd: const Color(0xFFE0E0EC),
          gradientBegin: Alignment.topCenter, gradientEndAlign: Alignment.bottomCenter,
          overlay: SlideOverlay.none,
          fontFamily: 'serif', textAlign: SlideTextAlign.center,
          titleBold: false, titleItalic: true, titleScale: 0.85,
          bodyItalic: true, bodyScale: 1.0,
          letterSpacing: 0.3, lineHeight: 1.6, textShadow: false,
          showTextBox: true,
          textBoxColor: const Color(0xFF1A1A2E), textBoxOpacity: 0.08,
          textBoxRadius: 12, textBoxPaddingH: 28, textBoxPaddingV: 18,
        ),
      ),
    ],
    'announcement': [
      SlideStyleChoice(
        label: 'High Contrast', subtitle: 'Dark bg • left-aligned box',
        swatch: const Color(0xFF0D0D0D), swatchEnd: const Color(0xFF0D0D0D),
        useGradient: false, hasTextBox: true,
        style: SlideStyle(
          useGradient: false,
          overlay: SlideOverlay.dots, overlayColor: Colors.white, overlayOpacity: 0.04,
          fontFamily: 'sans-serif', textAlign: SlideTextAlign.left,
          titleBold: true, titleScale: 1.1, bodyScale: 1.0,
          letterSpacing: 0.5, lineHeight: 1.4, textShadow: false,
          showTextBox: true,
          textBoxColor: Colors.black, textBoxOpacity: 0.70,
          textBoxRadius: 4, textBoxPaddingH: 28, textBoxPaddingV: 20,
        ),
      ),
      SlideStyleChoice(
        label: 'Fire & Energy', subtitle: 'Orange burst • bold',
        swatch: const Color(0xFFE63900), swatchEnd: const Color(0xFF7A0000),
        style: SlideStyle(
          useGradient: true, gradientEnd: const Color(0xFF7A0000),
          gradientBegin: Alignment.topCenter, gradientEndAlign: Alignment.bottomCenter,
          overlay: SlideOverlay.grain, overlayColor: Colors.white, overlayOpacity: 0.04,
          fontFamily: 'sans-serif', textAlign: SlideTextAlign.center,
          titleBold: true, titleScale: 1.15, bodyScale: 1.05,
          letterSpacing: 2.0, lineHeight: 1.3,
          textShadow: true, shadowColor: const Color(0xFF7A0000), shadowBlur: 16,
          showTextBox: false,
        ),
      ),
      SlideStyleChoice(
        label: 'Brand Pill', subtitle: 'Primary colour • rounded box',
        swatch: const Color(0xFF111827), swatchEnd: const Color(0xFF111827),
        useGradient: false, hasTextBox: true,
        style: SlideStyle(
          useGradient: false,
          overlay: SlideOverlay.none,
          fontFamily: 'sans-serif', textAlign: SlideTextAlign.center,
          titleBold: true, titleScale: 1.1, bodyScale: 1.0,
          letterSpacing: 1.5, lineHeight: 1.4, textShadow: false,
          showTextBox: true,
          textBoxColor: primary, textBoxOpacity: 0.85,
          textBoxRadius: 30, textBoxPaddingH: 30, textBoxPaddingV: 16,
        ),
      ),
    ],
    'blank': [
      SlideStyleChoice(
        label: 'Pure Black', subtitle: 'Solid black • no text',
        swatch: Colors.black, swatchEnd: Colors.black, useGradient: false,
        style: SlideStyle(useGradient: false, overlay: SlideOverlay.none,
            showTextBox: false),
      ),
      SlideStyleChoice(
        label: 'Deep Navy', subtitle: 'Navy gradient',
        swatch: const Color(0xFF0D1B3E), swatchEnd: const Color(0xFF000511),
        style: SlideStyle(
          useGradient: true, gradientEnd: const Color(0xFF000511),
          gradientBegin: Alignment.topLeft, gradientEndAlign: Alignment.bottomRight,
          overlay: SlideOverlay.vignette, overlayColor: Colors.black, overlayOpacity: 0.40,
          showTextBox: false,
        ),
      ),
      SlideStyleChoice(
        label: 'Brand Dark', subtitle: 'Primary colour fade',
        swatch: primary, swatchEnd: Color.lerp(primary, Colors.black, 0.60)!,
        style: SlideStyle(
          useGradient: true,
          gradientEnd: Color.lerp(primary, Colors.black, 0.60)!,
          gradientBegin: Alignment.topLeft, gradientEndAlign: Alignment.bottomRight,
          overlay: SlideOverlay.vignette, overlayColor: Colors.black, overlayOpacity: 0.30,
          showTextBox: false,
        ),
      ),
    ],
  };
}

class _StylePresetPicker extends StatelessWidget {
  final Color  primary;
  final Color  secondary;
  final Slide  slide;
  final void Function(SlideStyle Function(SlideStyle)) onStyle;
  final VoidCallback onChanged;

  const _StylePresetPicker({
    required this.primary,
    required this.secondary,
    required this.slide,
    required this.onStyle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final choices = slideStyleChoices(primary, secondary);
    final options = choices[slide.type] ?? choices['title']!;

    return Row(
      children: options.map((choice) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _StyleChoiceCard(
              choice:    choice,
              primary:   primary,
              onTap: () {
                onStyle((_) => choice.style);
                slide.styleOverridden = true;
                onChanged();
              },
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _StyleChoiceCard extends StatelessWidget {
  final SlideStyleChoice choice;
  final Color             primary;
  final VoidCallback      onTap;

  const _StyleChoiceCard({
    required this.choice, required this.primary, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          // ── Mini preview ──────────────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: CustomPaint(
                painter: SlideChoicePainter(choice: choice),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 5),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SlideCBar(w: 0.80, h: 6, color:
                          Colors.white.withValues(alpha: 0.90)),
                      const SizedBox(height: 4),
                      SlideCBar(w: 0.65, h: 6, color:
                          Colors.white.withValues(alpha: 0.90)),
                      const SizedBox(height: 5),
                      SlideCBar(w: 0.55, h: 3.5, color:
                          Colors.white.withValues(alpha: 0.50)),
                      const SizedBox(height: 3),
                      SlideCBar(w: 0.45, h: 3.5, color:
                          Colors.white.withValues(alpha: 0.50)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          // ── Label ─────────────────────────────────────────────────────
          Text(choice.label,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center),
          Text(choice.subtitle,
              style: TextStyle(
                  fontSize: 9.5, color: Colors.grey.shade500),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class SlideCBar extends StatelessWidget {
  final double w, h;
  final Color  color;
  const SlideCBar({required this.w, required this.h, required this.color});

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
        widthFactor: w,
        child: Container(
          height: h,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
        ),
      );
}

class SlideChoicePainter extends CustomPainter {
  final SlideStyleChoice choice;
  const SlideChoicePainter({required this.choice});

  @override
  void paint(Canvas canvas, Size size) {
    if (choice.useGradient) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [choice.swatch, choice.swatchEnd],
          ).createShader(Offset.zero & size),
      );
    } else {
      canvas.drawRect(Offset.zero & size, Paint()..color = choice.swatch);
    }
    // subtle vignette on all previews for depth
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent,
              Colors.black.withValues(alpha: 0.35)],
          stops: const [0.45, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  @override
  bool shouldRepaint(SlideChoicePainter old) =>
      old.choice.label != choice.label;
}

// ══════════════════════════════════════════════════════════════════════════════
// SMALL SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13));
}

class _SliderRow extends StatelessWidget {
  final String label; final double value;
  final double min; final double max; final int? divisions;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label, required this.value, required this.min,
    required this.max, required this.onChanged, this.divisions,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min, max: max,
              divisions: divisions ?? 20,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(value.toStringAsFixed(1),
                style: const TextStyle(fontSize: 11)),
          ),
        ],
      );
}

class _SwitchRow extends StatelessWidget {
  final String label; final bool value; final Color color;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.label, required this.value,
    required this.color, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(label, style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 13)),
          const Spacer(),
          Switch(value: value, onChanged: onChanged, activeColor: color),
        ],
      );
}

class _ColorRow extends StatelessWidget {
  final String label; final List<Color> colors;
  final Color current; final Color primary; final ValueChanged<Color> onPick;

  const _ColorRow({
    required this.label, required this.colors,
    required this.current, required this.primary, required this.onPick,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              child: Text(label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            ...colors.map((c) {
              final sel = current.toARGB32() == c.toARGB32();
              return GestureDetector(
                onTap: () => onPick(c),
                child: Container(
                  width: 28, height: 28,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: c, shape: BoxShape.circle,
                    border: Border.all(
                        color: sel ? primary : Colors.grey.shade400,
                        width: sel ? 2.5 : 1),
                  ),
                ),
              );
            }),
          ],
        ),
      );
}

class _LabeledRow extends StatelessWidget {
  final String label; final Widget child;
  const _LabeledRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            child,
          ],
        ),
      );
}

class _AlignBtn extends StatelessWidget {
  final IconData icon; final String tooltip; final bool active;
  final Color color; final VoidCallback onTap;

  const _AlignBtn({
    required this.icon, required this.tooltip, required this.active,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.12) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: active ? color : Colors.transparent, width: 1.5),
          ),
          child: Icon(icon, size: 18, color: active ? color : Colors.grey),
        ),
      );
}

class _ToggleBtn extends StatelessWidget {
  final String label; final bool bold; final bool italic;
  final bool active; final Color color; final VoidCallback onTap;

  const _ToggleBtn({
    required this.label, required this.active, required this.color,
    required this.onTap, this.bold = false, this.italic = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.12) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: active ? color : Colors.transparent, width: 1.5),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: bold   ? FontWeight.bold  : FontWeight.normal,
                  fontStyle:  italic ? FontStyle.italic : FontStyle.normal,
                  color: active ? color : Colors.grey,
                )),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// OVERRIDE BANNER — shown when slide has diverged from master
// ══════════════════════════════════════════════════════════════════════════════
class _OverrideBanner extends StatelessWidget {
  final Color        primary;
  final VoidCallback onReset;
  const _OverrideBanner({required this.primary, required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      color: Colors.amber.shade50,
      child: Row(
        children: [
          Icon(Icons.edit_note_rounded, size: 15, color: Colors.amber.shade800),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Custom style — different from master',
              style: TextStyle(
                fontSize: 11,
                color: Colors.amber.shade900,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: onReset,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('Reset to master',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                  )),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _dec(String hint) => InputDecoration(
      labelText: hint,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );