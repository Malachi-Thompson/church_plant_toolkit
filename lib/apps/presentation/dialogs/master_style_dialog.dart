// lib/apps/presentation/dialogs/master_style_dialog.dart
//
// Two-panel Master Style dialog:
//   Left  — 12 layout templates (Canva-style visual cards)
//   Right — colour customiser (bg, accent, text) — defaults to brand colours
//
// Returns MasterStyleResult? with the chosen template id + colour overrides.
// Colours stored as ARGB int; 0 means "use the app's brand colour at runtime".

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/presentation_models.dart';

// ══════════════════════════════════════════════════════════════════════════════
// PUBLIC RESULT TYPE
// ══════════════════════════════════════════════════════════════════════════════

class MasterStyleResult {
  final String styleId;
  final int    bgColor;      // 0 = brand primary
  final int    accentColor;  // 0 = brand secondary
  final int    textColor;    // 0 = white

  const MasterStyleResult({
    required this.styleId,
    required this.bgColor,
    required this.accentColor,
    required this.textColor,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// LAYOUT TEMPLATE MODEL
// ══════════════════════════════════════════════════════════════════════════════

class StylePreset {
  final String   id;
  final String   name;
  final String   category;
  final String   tagline;
  // These describe the *shape* of the style — colours come from MasterStyleResult
  final bool     darkBg;       // does this template suit dark backgrounds?
  final bool     useGradient;
  final Alignment gradFrom;
  final Alignment gradTo;
  final SlideOverlay overlay;
  final double   overlayOpacity;
  final String   fontFamily;
  final SlideTextAlign textAlign;
  final bool     titleBold;
  final bool     titleItalic;
  final double   titleScale;
  final bool     bodyItalic;
  final double   bodyScale;
  final double   letterSpacing;
  final double   lineHeight;
  final bool     textShadow;
  final double   shadowBlur;
  final bool     showTextBox;
  final double   textBoxOpacity;
  final double   textBoxRadius;
  final double   textBoxPaddingH;
  final double   textBoxPaddingV;

  const StylePreset({
    required this.id, required this.name, required this.category,
    required this.tagline,
    this.darkBg        = true,
    this.useGradient   = true,
    this.gradFrom      = Alignment.topLeft,
    this.gradTo        = Alignment.bottomRight,
    this.overlay       = SlideOverlay.none,
    this.overlayOpacity = 0.0,
    this.fontFamily    = 'sans-serif',
    this.textAlign     = SlideTextAlign.center,
    this.titleBold     = true,
    this.titleItalic   = false,
    this.titleScale    = 1.0,
    this.bodyItalic    = false,
    this.bodyScale     = 1.0,
    this.letterSpacing = 1.0,
    this.lineHeight    = 1.45,
    this.textShadow    = true,
    this.shadowBlur    = 12.0,
    this.showTextBox   = false,
    this.textBoxOpacity = 0.70,
    this.textBoxRadius  = 8.0,
    this.textBoxPaddingH = 28.0,
    this.textBoxPaddingV = 18.0,
  });

  // Build a concrete SlideStyle from this template + resolved colours
  SlideStyle toSlideStyle({
    required Color bgColor,
    required Color accentColor,
    required Color textColor,
  }) {
    final gradEnd = useGradient
        ? Color.lerp(bgColor, Colors.black, darkBg ? 0.60 : 0.15)!
        : bgColor;

    return SlideStyle(
      useGradient:      useGradient,
      gradientEnd:      gradEnd,
      gradientBegin:    gradFrom,
      gradientEndAlign: gradTo,
      overlay:          overlay,
      overlayColor:     darkBg ? Colors.black : Colors.white,
      overlayOpacity:   overlayOpacity,
      fontFamily:       fontFamily,
      textAlign:        textAlign,
      titleBold:        titleBold,
      titleItalic:      titleItalic,
      titleScale:       titleScale,
      bodyItalic:       bodyItalic,
      bodyScale:        bodyScale,
      letterSpacing:    letterSpacing,
      lineHeight:       lineHeight,
      textShadow:       textShadow,
      shadowColor:      darkBg ? Colors.black : Colors.grey.shade600,
      shadowBlur:       shadowBlur,
      showTextBox:      showTextBox,
      textBoxColor:     showTextBox ? accentColor : Colors.black,
      textBoxOpacity:   textBoxOpacity,
      textBoxRadius:    textBoxRadius,
      textBoxPaddingH:  textBoxPaddingH,
      textBoxPaddingV:  textBoxPaddingV,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TEMPLATE CATALOGUE
// ══════════════════════════════════════════════════════════════════════════════

const List<StylePreset> kLayoutTemplates = [
  StylePreset(
    id: 'your_brand', name: 'Your Brand', category: 'Brand',
    tagline: 'Diagonal gradient from your brand colour',
    darkBg: true, useGradient: true,
    gradFrom: Alignment.topLeft, gradTo: Alignment.bottomRight,
    overlay: SlideOverlay.vignette, overlayOpacity: 0.32,
    textShadow: true, shadowBlur: 12,
    letterSpacing: 1.0, lineHeight: 1.45,
  ),
  StylePreset(
    id: 'midnight_worship', name: 'Midnight Worship', category: 'Modern Dark',
    tagline: 'Top-left fade • vignette • glow shadow • serif',
    darkBg: true, useGradient: true,
    gradFrom: Alignment.topLeft, gradTo: Alignment.bottomRight,
    overlay: SlideOverlay.vignette, overlayOpacity: 0.55,
    fontFamily: 'serif', bodyItalic: true,
    letterSpacing: 1.2, lineHeight: 1.55,
    textShadow: true, shadowBlur: 22,
  ),
  StylePreset(
    id: 'golden_hour', name: 'Golden Hour', category: 'Warm',
    tagline: 'Diagonal top-right • grain texture • warm tracking',
    darkBg: true, useGradient: true,
    gradFrom: Alignment.topRight, gradTo: Alignment.bottomLeft,
    overlay: SlideOverlay.grain, overlayOpacity: 0.06,
    letterSpacing: 1.6, lineHeight: 1.45,
    textShadow: true, shadowBlur: 14,
  ),
  StylePreset(
    id: 'fresh_light', name: 'Fresh Light', category: 'Clean',
    tagline: 'Light background • top-to-bottom fade • no shadow',
    darkBg: false, useGradient: true,
    gradFrom: Alignment.topCenter, gradTo: Alignment.bottomCenter,
    overlay: SlideOverlay.none,
    letterSpacing: 0.8, lineHeight: 1.4,
    textShadow: false, shadowBlur: 0,
  ),
  StylePreset(
    id: 'emerald_forest', name: 'Emerald Forest', category: 'Nature',
    tagline: 'Top-centre fade • diagonal line overlay',
    darkBg: true, useGradient: true,
    gradFrom: Alignment.topCenter, gradTo: Alignment.bottomRight,
    overlay: SlideOverlay.diagonal, overlayOpacity: 0.04,
    letterSpacing: 0.8, lineHeight: 1.5,
    textShadow: true, shadowBlur: 10,
  ),
  StylePreset(
    id: 'royal_purple', name: 'Royal Purple', category: 'Bold',
    tagline: 'Top-to-bottom • dot grid • wide tracking • glow',
    darkBg: true, useGradient: true,
    gradFrom: Alignment.topCenter, gradTo: Alignment.bottomCenter,
    overlay: SlideOverlay.dots, overlayOpacity: 0.06,
    letterSpacing: 2.0, lineHeight: 1.4,
    textShadow: true, shadowBlur: 18,
  ),
  StylePreset(
    id: 'slate_editorial', name: 'Slate Editorial', category: 'Editorial',
    tagline: 'Left-to-right • frosted text box • left-aligned',
    darkBg: true, useGradient: true,
    gradFrom: Alignment.centerLeft, gradTo: Alignment.centerRight,
    overlay: SlideOverlay.none,
    textAlign: SlideTextAlign.left,
    letterSpacing: 0.5, lineHeight: 1.5,
    textShadow: false, shadowBlur: 0,
    showTextBox: true, textBoxOpacity: 0.14,
    textBoxRadius: 8, textBoxPaddingH: 28, textBoxPaddingV: 22,
  ),
  StylePreset(
    id: 'sunrise_praise', name: 'Sunrise Praise', category: 'Soft',
    tagline: 'Diagonal • grain • warm and joyful',
    darkBg: false, useGradient: true,
    gradFrom: Alignment.topLeft, gradTo: Alignment.bottomRight,
    overlay: SlideOverlay.grain, overlayOpacity: 0.07,
    letterSpacing: 0.8, lineHeight: 1.5,
    textShadow: true, shadowBlur: 10,
  ),
  StylePreset(
    id: 'ocean_deep', name: 'Ocean Deep', category: 'Scripture',
    tagline: 'Vignette • italic serif • meditative body text',
    darkBg: true, useGradient: true,
    gradFrom: Alignment.topCenter, gradTo: Alignment.bottomCenter,
    overlay: SlideOverlay.vignette, overlayOpacity: 0.48,
    fontFamily: 'serif', titleItalic: true, titleScale: 0.88,
    bodyItalic: true, bodyScale: 1.05,
    letterSpacing: 0.3, lineHeight: 1.7,
    textShadow: true, shadowBlur: 14,
  ),
  StylePreset(
    id: 'fire_faith', name: 'Fire & Faith', category: 'High Energy',
    tagline: 'Full gradient • wide tracking • maximum impact',
    darkBg: true, useGradient: true,
    gradFrom: Alignment.topCenter, gradTo: Alignment.bottomCenter,
    overlay: SlideOverlay.grain, overlayOpacity: 0.05,
    titleScale: 1.15, bodyScale: 1.05,
    letterSpacing: 2.5, lineHeight: 1.3,
    textShadow: true, shadowBlur: 20,
  ),
  StylePreset(
    id: 'stone_chapel', name: 'Stone Chapel', category: 'Classic',
    tagline: 'Crosshatch • serif • traditional and dignified',
    darkBg: true, useGradient: true,
    gradFrom: Alignment.topCenter, gradTo: Alignment.bottomCenter,
    overlay: SlideOverlay.crosshatch, overlayOpacity: 0.03,
    fontFamily: 'serif', bodyItalic: true,
    letterSpacing: 0.5, lineHeight: 1.6,
    textShadow: true, shadowBlur: 8,
  ),
  StylePreset(
    id: 'neon_metro', name: 'Neon Metro', category: 'Contemporary',
    tagline: 'Solid dark • dot grid • accent pill box',
    darkBg: true, useGradient: false,
    overlay: SlideOverlay.dots, overlayOpacity: 0.04,
    letterSpacing: 2.2, lineHeight: 1.4,
    textShadow: false, shadowBlur: 0,
    showTextBox: true, textBoxOpacity: 0.88,
    textBoxRadius: 32, textBoxPaddingH: 32, textBoxPaddingV: 18,
  ),
];

// ══════════════════════════════════════════════════════════════════════════════
// buildPresets — legacy helper still used by _StylePresetPicker in slide editor
// ══════════════════════════════════════════════════════════════════════════════

class StylePresetLegacy {
  final String   id;
  final String   name;
  final String   description;
  final IconData icon;
  final Color    swatch;
  final SlideStyle style;
  const StylePresetLegacy({
    required this.id, required this.name, required this.description,
    required this.icon, required this.swatch, required this.style,
  });
}

List<StylePresetLegacy> buildPresets({
  required Color primaryAccent,
  required Color secondaryAccent,
}) {
  return kLayoutTemplates.map((t) {
    final bg     = primaryAccent;
    final accent = secondaryAccent;
    final text   = Colors.white;
    return StylePresetLegacy(
      id:          t.id,
      name:        t.name,
      description: t.tagline,
      icon:        Icons.style_rounded,
      swatch:      bg,
      style:       t.toSlideStyle(bgColor: bg, accentColor: accent, textColor: text),
    );
  }).toList();
}

// ══════════════════════════════════════════════════════════════════════════════
// PUBLIC API
// ══════════════════════════════════════════════════════════════════════════════

Future<MasterStyleResult?> showMasterStyleDialog(
  BuildContext context, {
  required Color  primary,     // brand primary (default bg)
  required Color  secondary,   // brand secondary (default accent)
  required String currentStyleId,
  required int    currentBgColor,
  required int    currentAccentColor,
  required int    currentTextColor,
}) =>
    showDialog<MasterStyleResult>(
      context: context,
      builder: (_) => _MasterStyleDialog(
        brandPrimary:       primary,
        brandSecondary:     secondary,
        currentStyleId:     currentStyleId,
        currentBgColor:     currentBgColor,
        currentAccentColor: currentAccentColor,
        currentTextColor:   currentTextColor,
      ),
    );

// ══════════════════════════════════════════════════════════════════════════════
// DIALOG
// ══════════════════════════════════════════════════════════════════════════════

class _MasterStyleDialog extends StatefulWidget {
  final Color  brandPrimary;
  final Color  brandSecondary;
  final String currentStyleId;
  final int    currentBgColor;
  final int    currentAccentColor;
  final int    currentTextColor;

  const _MasterStyleDialog({
    required this.brandPrimary,   required this.brandSecondary,
    required this.currentStyleId, required this.currentBgColor,
    required this.currentAccentColor, required this.currentTextColor,
  });

  @override
  State<_MasterStyleDialog> createState() => _MasterStyleDialogState();
}

class _MasterStyleDialogState extends State<_MasterStyleDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late String        _styleId;
  late Color         _bg;
  late Color         _accent;
  late Color         _text;
  bool               _bgIsDefault     = true;
  bool               _accentIsDefault = true;
  bool               _textIsDefault   = true;

  String _catFilter = 'All';

  static const _categories = [
    'All','Brand','Modern Dark','Warm','Clean','Nature','Bold',
    'Editorial','Soft','Scripture','High Energy','Classic','Contemporary',
  ];

  @override
  void initState() {
    super.initState();
    _tabs    = TabController(length: 2, vsync: this);
    _styleId = widget.currentStyleId;

    // Resolve stored ints → Colors; 0 means "use brand default"
    _bgIsDefault     = widget.currentBgColor     == 0;
    _accentIsDefault = widget.currentAccentColor == 0;
    _textIsDefault   = widget.currentTextColor   == 0;
    _bg     = _bgIsDefault     ? widget.brandPrimary   : Color(widget.currentBgColor);
    _accent = _accentIsDefault ? widget.brandSecondary : Color(widget.currentAccentColor);
    _text   = _textIsDefault   ? Colors.white          : Color(widget.currentTextColor);
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  StylePreset get _selectedTemplate =>
      kLayoutTemplates.firstWhere((t) => t.id == _styleId,
          orElse: () => kLayoutTemplates.first);

  List<StylePreset> get _filtered => _catFilter == 'All'
      ? kLayoutTemplates
      : kLayoutTemplates.where((t) => t.category == _catFilter).toList();

  void _apply() {
    Navigator.pop(context, MasterStyleResult(
      styleId:     _styleId,
      bgColor:     _bgIsDefault     ? 0 : _bg.toARGB32(),
      accentColor: _accentIsDefault ? 0 : _accent.toARGB32(),
      textColor:   _textIsDefault   ? 0 : _text.toARGB32(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p      = widget.brandPrimary;
    final narrow = MediaQuery.of(context).size.width < 660;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
          horizontal: narrow ? 8 : 24, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth:  760,
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        child: Column(children: [
          // ── Header ────────────────────────────────────────────────────────
          _Header(primary: p, onClose: () => Navigator.pop(context)),

          // ── Tab bar ───────────────────────────────────────────────────────
          Container(
            color: p.withValues(alpha: 0.04),
            child: TabBar(
              controller:       _tabs,
              labelColor:       p,
              unselectedLabelColor: Colors.grey.shade500,
              indicatorColor:   p,
              indicatorWeight:  2.5,
              tabs: const [
                Tab(text: 'Layout',  icon: Icon(Icons.dashboard_customize_rounded, size: 16)),
                Tab(text: 'Colours', icon: Icon(Icons.palette_rounded, size: 16)),
              ],
            ),
          ),

          // ── Tab views ─────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(controller: _tabs, children: [
              _LayoutTab(
                templates:  _filtered,
                allTemplates: kLayoutTemplates,
                selectedId: _styleId,
                catFilter:  _catFilter,
                categories: _categories,
                primary:    p,
                bgColor:    _bg,
                accentColor: _accent,
                textColor:  _text,
                onSelectTemplate: (id) => setState(() => _styleId = id),
                onFilterChange:   (c)  => setState(() => _catFilter = c),
              ),
              _ColourTab(
                brandPrimary:    widget.brandPrimary,
                brandSecondary:  widget.brandSecondary,
                bg:              _bg,
                accent:          _accent,
                text:            _text,
                bgIsDefault:     _bgIsDefault,
                accentIsDefault: _accentIsDefault,
                textIsDefault:   _textIsDefault,
                template:        _selectedTemplate,
                primary:         p,
                onBgChanged:     (c, isDefault) => setState(() { _bg = c; _bgIsDefault = isDefault; }),
                onAccentChanged: (c, isDefault) => setState(() { _accent = c; _accentIsDefault = isDefault; }),
                onTextChanged:   (c, isDefault) => setState(() { _text = c; _textIsDefault = isDefault; }),
              ),
            ]),
          ),

          // ── Footer ────────────────────────────────────────────────────────
          _Footer(primary: p, onCancel: () => Navigator.pop(context), onApply: _apply),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 1: LAYOUT PICKER
// ══════════════════════════════════════════════════════════════════════════════

class _LayoutTab extends StatelessWidget {
  final List<StylePreset>   templates;
  final List<StylePreset>   allTemplates;
  final String              selectedId;
  final String              catFilter;
  final List<String>        categories;
  final Color               primary;
  final Color               bgColor;
  final Color               accentColor;
  final Color               textColor;
  final ValueChanged<String> onSelectTemplate;
  final ValueChanged<String> onFilterChange;

  const _LayoutTab({
    required this.templates, required this.allTemplates,
    required this.selectedId, required this.catFilter,
    required this.categories, required this.primary,
    required this.bgColor, required this.accentColor, required this.textColor,
    required this.onSelectTemplate, required this.onFilterChange,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 660;
    return Column(children: [
      // Category filter
      SizedBox(
        height: 42,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          scrollDirection: Axis.horizontal,
          itemCount: categories.length,
          separatorBuilder: (_, __) => const SizedBox(width: 5),
          itemBuilder: (_, i) {
            final cat = categories[i];
            final sel = cat == catFilter;
            return GestureDetector(
              onTap: () => onFilterChange(cat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color:        sel ? primary : primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: sel ? primary : primary.withValues(alpha: 0.18)),
                ),
                child: Text(cat,
                    style: TextStyle(
                      fontSize:   11, fontWeight: FontWeight.w600,
                      color: sel ? _contrast(primary)
                                 : primary.withValues(alpha: 0.75),
                    )),
              ),
            );
          },
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.all(14),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:   narrow ? 1 : 2,
            crossAxisSpacing: 12, mainAxisSpacing: 12,
            childAspectRatio: narrow ? 2.6 : 1.75,
          ),
          itemCount: templates.length,
          itemBuilder: (_, i) {
            final t   = templates[i];
            final sel = t.id == selectedId;
            return _TemplateCard(
              template:   t,
              selected:   sel,
              primary:    primary,
              bgColor:    bgColor,
              accentColor: accentColor,
              textColor:  textColor,
              onTap:      () => onSelectTemplate(t.id),
            );
          },
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 2: COLOUR CUSTOMISER
// ══════════════════════════════════════════════════════════════════════════════

class _ColourTab extends StatelessWidget {
  final Color    brandPrimary;
  final Color    brandSecondary;
  final Color    bg;
  final Color    accent;
  final Color    text;
  final bool     bgIsDefault;
  final bool     accentIsDefault;
  final bool     textIsDefault;
  final StylePreset template;
  final Color    primary;
  final void Function(Color, bool) onBgChanged;
  final void Function(Color, bool) onAccentChanged;
  final void Function(Color, bool) onTextChanged;

  const _ColourTab({
    required this.brandPrimary, required this.brandSecondary,
    required this.bg,            required this.accent,
    required this.text,          required this.bgIsDefault,
    required this.accentIsDefault, required this.textIsDefault,
    required this.template,      required this.primary,
    required this.onBgChanged,   required this.onAccentChanged,
    required this.onTextChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Live preview ──────────────────────────────────────────────────
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _LivePreview(
              template:   template,
              bgColor:    bg,
              accentColor: accent,
              textColor:  text,
            ),
          ),
        ),
        const SizedBox(height: 24),

        Text('Colours', style: TextStyle(
            fontWeight: FontWeight.bold, fontSize: 15, color: primary)),
        const SizedBox(height: 4),
        Text('Tap a colour to change it. "Use brand" resets to your church settings.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 18),

        // Background colour
        _ColourRow(
          label:        'Background',
          sublabel:     'Main slide background / gradient start',
          color:        bg,
          isDefault:    bgIsDefault,
          brandColor:   brandPrimary,
          brandLabel:   'Brand Primary',
          onChanged:    onBgChanged,
          swatches: [
            brandPrimary,
            const Color(0xFF0D1B3E), const Color(0xFF000511),
            const Color(0xFF0D4F3C), const Color(0xFF3D0066),
            const Color(0xFF1C1C2E), const Color(0xFF5A5045),
            const Color(0xFFCF6A0A), const Color(0xFFE63900),
            const Color(0xFFFFFFFF), Colors.black,
          ],
        ),
        const SizedBox(height: 18),

        // Accent colour
        _ColourRow(
          label:     'Accent',
          sublabel:  'Text box colour, gradient tint, shadow glow',
          color:     accent,
          isDefault: accentIsDefault,
          brandColor: brandSecondary,
          brandLabel: 'Brand Secondary',
          onChanged: onAccentChanged,
          swatches: [
            brandSecondary,
            const Color(0xFF4A90D9), const Color(0xFF2ECC71),
            const Color(0xFFBB86FC), const Color(0xFFF5C842),
            const Color(0xFFFF9500), const Color(0xFF00D4FF),
            const Color(0xFFE8A87C), Colors.white,
            Colors.deepOrange, Colors.teal,
          ],
        ),
        const SizedBox(height: 18),

        // Text colour
        _ColourRow(
          label:     'Text',
          sublabel:  'Title, body and reference colour',
          color:     text,
          isDefault: textIsDefault,
          brandColor: Colors.white,
          brandLabel: 'White (default)',
          onChanged: onTextChanged,
          swatches: [
            Colors.white,
            const Color(0xFFF0F0F0), const Color(0xFFD4C5A9),
            const Color(0xFFF5C842), const Color(0xFFBB86FC),
            const Color(0xFF90CAF9), Colors.black87,
            const Color(0xFF1A1A2E),
          ],
        ),
        const SizedBox(height: 12),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// LIVE PREVIEW
// ══════════════════════════════════════════════════════════════════════════════

class _LivePreview extends StatelessWidget {
  final StylePreset template;
  final Color       bgColor;
  final Color       accentColor;
  final Color       textColor;
  const _LivePreview({
    required this.template, required this.bgColor,
    required this.accentColor, required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final gradEnd = template.useGradient
        ? Color.lerp(bgColor, Colors.black, template.darkBg ? 0.58 : 0.12)!
        : bgColor;

    return CustomPaint(
      painter: _BgPainter(
        bgA:        bgColor,
        bgB:        gradEnd,
        useGrad:    template.useGradient,
        gradFrom:   template.gradFrom,
        gradTo:     template.gradTo,
        overlay:    template.overlay,
        overlayC:   template.darkBg ? Colors.black : Colors.white,
        overlayOp:  template.overlayOpacity,
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          child: _PreviewText(
            template:    template,
            textColor:   textColor,
            accentColor: accentColor,
          ),
        ),
      ),
    );
  }
}

class _PreviewText extends StatelessWidget {
  final StylePreset template;
  final Color       textColor;
  final Color       accentColor;
  const _PreviewText({
    required this.template, required this.textColor, required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final shadows = template.textShadow
        ? [Shadow(
            color:      Colors.black.withValues(alpha: 0.65),
            blurRadius: template.shadowBlur,
            offset:     const Offset(1, 2))]
        : null;

    final align = template.textAlign == SlideTextAlign.left
        ? TextAlign.left : TextAlign.center;
    final crossAlign = template.textAlign == SlideTextAlign.left
        ? CrossAxisAlignment.start : CrossAxisAlignment.center;

    Widget content = Column(
      mainAxisSize:       MainAxisSize.min,
      crossAxisAlignment: crossAlign,
      children: [
        Text('Slide Title Here',
            textAlign: align,
            style: TextStyle(
              color:      textColor,
              fontSize:   28 * template.titleScale,
              fontWeight: template.titleBold ? FontWeight.bold : FontWeight.normal,
              fontStyle:  template.titleItalic ? FontStyle.italic : FontStyle.normal,
              letterSpacing: template.letterSpacing,
              height:     template.lineHeight,
              shadows:    shadows,
            )),
        const SizedBox(height: 8),
        Text('Body text and verse content appears here',
            textAlign: align,
            style: TextStyle(
              color:      textColor.withValues(alpha: 0.78),
              fontSize:   18 * template.bodyScale,
              fontStyle:  template.bodyItalic ? FontStyle.italic : FontStyle.normal,
              letterSpacing: template.letterSpacing * 0.7,
              height:     template.lineHeight,
              shadows:    shadows,
            )),
      ],
    );

    if (template.showTextBox) {
      content = Container(
        padding: EdgeInsets.symmetric(
            horizontal: template.textBoxPaddingH * 0.5,
            vertical:   template.textBoxPaddingV * 0.5),
        decoration: BoxDecoration(
          color:        accentColor.withValues(alpha: template.textBoxOpacity),
          borderRadius: BorderRadius.circular(template.textBoxRadius),
        ),
        child: content,
      );
    }

    return content;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// COLOUR ROW  — swatch strip + "Use brand default" reset
// ══════════════════════════════════════════════════════════════════════════════

class _ColourRow extends StatelessWidget {
  final String   label;
  final String   sublabel;
  final Color    color;
  final bool     isDefault;
  final Color    brandColor;
  final String   brandLabel;
  final List<Color> swatches;
  final void Function(Color, bool) onChanged;

  const _ColourRow({
    required this.label,     required this.sublabel,
    required this.color,     required this.isDefault,
    required this.brandColor, required this.brandLabel,
    required this.swatches,  required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
            Text(sublabel, style: TextStyle(
                fontSize: 11, color: Colors.grey.shade500)),
          ]),
        ),
        // Current colour chip
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color:        color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [BoxShadow(
                color: color.withValues(alpha: 0.35), blurRadius: 6)],
          ),
        ),
      ]),
      const SizedBox(height: 10),
      // Swatch strip
      SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: swatches.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final sw  = swatches[i];
            final sel = !isDefault && _colorClose(sw, color);
            return GestureDetector(
              onTap: () {
                final usingBrand = _colorClose(sw, brandColor);
                onChanged(sw, usingBrand);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color:        sw,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: sel ? Colors.black87 : Colors.grey.shade300,
                    width: sel ? 2.5 : 1,
                  ),
                  boxShadow: [BoxShadow(
                      color: sw.withValues(alpha: 0.30), blurRadius: 4)],
                ),
                child: i == 0
                    ? Center(child: Icon(Icons.auto_awesome_rounded,
                          size: 14,
                          color: _contrast(sw).withValues(alpha: 0.70)))
                    : null,
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
      // Brand default button
      GestureDetector(
        onTap: () => onChanged(brandColor, true),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color:        isDefault
                ? brandColor.withValues(alpha: 0.12)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDefault
                  ? brandColor.withValues(alpha: 0.50)
                  : Colors.grey.shade300,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(isDefault ? Icons.check_circle_rounded : Icons.refresh_rounded,
                size: 14,
                color: isDefault ? brandColor : Colors.grey.shade500),
            const SizedBox(width: 6),
            Text(
              isDefault ? '$brandLabel (active)' : 'Use $brandLabel',
              style: TextStyle(
                fontSize:   11, fontWeight: FontWeight.w600,
                color: isDefault ? brandColor : Colors.grey.shade500,
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  bool _colorClose(Color a, Color b) =>
      (a.r - b.r).abs() < 8 &&
      (a.g - b.g).abs() < 8 &&
      (a.b - b.b).abs() < 8;
}

// ══════════════════════════════════════════════════════════════════════════════
// TEMPLATE CARD — small rendered preview + info
// ══════════════════════════════════════════════════════════════════════════════

class _TemplateCard extends StatelessWidget {
  final StylePreset  template;
  final bool         selected;
  final Color        primary;
  final Color        bgColor;
  final Color        accentColor;
  final Color        textColor;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.template, required this.selected, required this.primary,
    required this.bgColor, required this.accentColor, required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? primary : Colors.grey.shade200,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: [BoxShadow(
            color: selected
                ? primary.withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: selected ? 14 : 5,
            offset: const Offset(0, 3),
          )],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Row(children: [
            // ── Rendered preview ─────────────────────────────────────────
            SizedBox(
              width: 120,
              child: _CardPreview(
                template:    template,
                bgColor:     bgColor,
                accentColor: accentColor,
                textColor:   textColor,
              ),
            ),
            // ── Info ─────────────────────────────────────────────────────
            Expanded(
              child: Container(
                color: selected
                    ? primary.withValues(alpha: 0.045)
                    : Colors.white,
                padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment:  MainAxisAlignment.center,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(template.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14,
                              color: selected ? primary : Colors.black87),
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (selected)
                        Icon(Icons.check_circle_rounded,
                            color: primary, size: 18),
                    ]),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(template.category,
                          style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w600,
                            color: primary)),
                    ),
                    const SizedBox(height: 6),
                    Text(template.tagline,
                        style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500,
                          height:   1.35),
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                    if (selected) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color:        primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('ACTIVE',
                            style: TextStyle(
                              color:         _contrast(primary),
                              fontSize:      9,
                              fontWeight:    FontWeight.bold,
                              letterSpacing: 0.8)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CardPreview extends StatelessWidget {
  final StylePreset template;
  final Color bgColor, accentColor, textColor;
  const _CardPreview({
    required this.template, required this.bgColor,
    required this.accentColor, required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final gradEnd = template.useGradient
        ? Color.lerp(bgColor, Colors.black, template.darkBg ? 0.58 : 0.12)!
        : bgColor;
    final barC = textColor.withValues(alpha: 0.88);
    final subC = textColor.withValues(alpha: 0.50);
    final align = template.textAlign == SlideTextAlign.left
        ? CrossAxisAlignment.start : CrossAxisAlignment.center;

    Widget bars = Column(
      mainAxisAlignment:  MainAxisAlignment.center,
      crossAxisAlignment: align,
      children: [
        _Bar(w: 0.82, h: 8, color: barC),
        const SizedBox(height: 5),
        _Bar(w: 0.68, h: 8, color: barC),
        const SizedBox(height: 8),
        _Bar(w: 0.58, h: 4.5, color: subC),
        const SizedBox(height: 4),
        _Bar(w: 0.46, h: 4.5, color: subC),
        const SizedBox(height: 4),
        _Bar(w: 0.36, h: 4.5, color: subC),
      ],
    );

    if (template.showTextBox) {
      bars = Container(
        margin:  const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color:        accentColor.withValues(alpha: template.textBoxOpacity),
          borderRadius: BorderRadius.circular(
              (template.textBoxRadius / 2).clamp(0, 16)),
        ),
        child: bars,
      );
    }

    return CustomPaint(
      painter: _BgPainter(
        bgA: bgColor, bgB: gradEnd,
        useGrad: template.useGradient,
        gradFrom: template.gradFrom, gradTo: template.gradTo,
        overlay: template.overlay,
        overlayC: template.darkBg ? Colors.black : Colors.white,
        overlayOp: template.overlayOpacity,
      ),
      child: SizedBox.expand(child: Center(child: bars)),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BACKGROUND PAINTER
// ══════════════════════════════════════════════════════════════════════════════

class _BgPainter extends CustomPainter {
  final Color        bgA, bgB, overlayC;
  final bool         useGrad;
  final Alignment    gradFrom, gradTo;
  final SlideOverlay overlay;
  final double       overlayOp;

  const _BgPainter({
    required this.bgA, required this.bgB, required this.overlayC,
    required this.useGrad, required this.gradFrom, required this.gradTo,
    required this.overlay, required this.overlayOp,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (useGrad && bgA != bgB) {
      canvas.drawRect(Offset.zero & size, Paint()
        ..shader = LinearGradient(
          begin: gradFrom, end: gradTo, colors: [bgA, bgB],
        ).createShader(Offset.zero & size));
    } else {
      canvas.drawRect(Offset.zero & size, Paint()..color = bgA);
    }

    final op = overlayOp.clamp(0.0, 1.0);
    final oc = overlayC.withValues(alpha: op);
    switch (overlay) {
      case SlideOverlay.vignette:
        canvas.drawRect(Offset.zero & size, Paint()
          ..shader = RadialGradient(
            colors: [Colors.transparent, oc.withValues(alpha: oc.a)],
            stops: const [0.38, 1.0],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
        break;
      case SlideOverlay.dots:
        final p = Paint()..color = oc;
        for (double x = 0; x < size.width;  x += 8)
          for (double y = 0; y < size.height; y += 8)
            canvas.drawCircle(Offset(x, y), 0.8, p);
        break;
      case SlideOverlay.diagonal:
        final p = Paint()..color = oc..strokeWidth = 0.6
            ..style = PaintingStyle.stroke;
        for (double i = -size.height; i < size.width + size.height; i += 9)
          canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), p);
        break;
      case SlideOverlay.crosshatch:
        final p = Paint()..color = oc..strokeWidth = 0.45
            ..style = PaintingStyle.stroke;
        for (double x = 0; x < size.width;  x += 10)
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        for (double y = 0; y < size.height; y += 10)
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        break;
      case SlideOverlay.grain:
        final rng = math.Random(7);
        final p   = Paint()..color = oc;
        for (var i = 0; i < 500; i++)
          canvas.drawCircle(Offset(
              rng.nextDouble() * size.width,
              rng.nextDouble() * size.height), 0.8, p);
        break;
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(_BgPainter o) =>
      o.bgA != bgA || o.bgB != bgB || o.overlay != overlay || o.overlayOp != overlayOp;
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED SMALL WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _Bar extends StatelessWidget {
  final double w, h;
  final Color  color;
  const _Bar({required this.w, required this.h, required this.color});
  @override
  Widget build(BuildContext context) => FractionallySizedBox(
        widthFactor: w,
        child: Container(
          height: h,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2.5)),
        ),
      );
}

class _Header extends StatelessWidget {
  final Color primary;
  final VoidCallback onClose;
  const _Header({required this.primary, required this.onClose});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.055),
          border: Border(bottom: BorderSide(color: primary.withValues(alpha: 0.10))),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.style_rounded, color: primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Master Style',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 17, color: primary)),
              Text('Choose a layout template and customise colours.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded), color: Colors.grey,
            onPressed: onClose,
          ),
        ]),
      );
}

class _Footer extends StatelessWidget {
  final Color primary;
  final VoidCallback onCancel, onApply;
  const _Footer({required this.primary, required this.onCancel, required this.onApply});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Colors.grey.shade200))),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: onApply,
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: _contrast(primary),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon:  const Icon(Icons.check_rounded, size: 18),
            label: const Text('Apply',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ]),
      );
}

Color _contrast(Color bg) =>
    bg.computeLuminance() > 0.35 ? Colors.black87 : Colors.white;