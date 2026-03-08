// lib/apps/presentation/dialogs/master_style_dialog.dart
//
// Master Style Settings dialog.
//
// Contains:
//   • A set of named "slide style presets" (church-logo dark, church-logo light,
//     accent primary, accent secondary, minimal, scripture, announcement)
//   • Each preset is a full SlideStyle with colours, fonts, gradients, overlays
//   • The deck stores a `masterStyleId` string; slides can override with their own
//     `stylePresetId` (or null = "use master").
//
// Usage:
//   final updated = await showMasterStyleDialog(context, deck: deck, primary: p);
//   if (updated != null) onDeckUpdated(updated);
import 'package:flutter/material.dart';
import '../models/presentation_models.dart';

// ══════════════════════════════════════════════════════════════════════════════
// PRESET DEFINITIONS
// ══════════════════════════════════════════════════════════════════════════════

/// A named style preset that can be applied to a slide or set as master.
class StylePreset {
  final String   id;
  final String   name;
  final String   description;
  final IconData icon;
  final Color    swatch;       // preview swatch colour
  final SlideStyle style;

  const StylePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.swatch,
    required this.style,
  });
}

/// All built-in presets.  Add or customise here to suit your church's brand.
List<StylePreset> buildPresets({
  required Color primaryAccent,
  required Color secondaryAccent,
}) {
  return [
    // ── Church branding: dark ─────────────────────────────────────────────────
    StylePreset(
      id:          'church_dark',
      name:        'Church Dark',
      description: 'Dark background with church accent colour — ideal for main slides',
      icon:        Icons.church_rounded,
      swatch:      primaryAccent,
      style: SlideStyle(
        useGradient:    true,
        gradientEnd:    primaryAccent,
        gradientBegin:  Alignment.topLeft,
        gradientEndAlign: Alignment.bottomRight,
        overlay:        SlideOverlay.vignette,
        overlayOpacity: 0.35,
        overlayColor:   Colors.black,
        titleBold:      true,
        titleScale:     1.0,
        bodyScale:      1.0,
        textAlign:      SlideTextAlign.center,
        textShadow:     true,
        shadowBlur:     8,
        shadowColor:    Colors.black,
        fontFamily:     'sans-serif',
        lineHeight:     1.35,
        letterSpacing:  0.5,
        showTextBox:    false,
      ),
    ),

    // ── Church branding: light ────────────────────────────────────────────────
    StylePreset(
      id:          'church_light',
      name:        'Church Light',
      description: 'Light/white background with church accent — clean, readable',
      icon:        Icons.wb_sunny_rounded,
      swatch:      secondaryAccent,
      style: SlideStyle(
        useGradient:    true,
        gradientEnd:    secondaryAccent.withValues(alpha: 0.25),
        gradientBegin:  Alignment.topCenter,
        gradientEndAlign: Alignment.bottomCenter,
        overlay:        SlideOverlay.none,
        titleBold:      true,
        titleScale:     1.0,
        bodyScale:      1.0,
        textAlign:      SlideTextAlign.center,
        textShadow:     false,
        fontFamily:     'sans-serif',
        lineHeight:     1.35,
        letterSpacing:  0.3,
        showTextBox:    false,
      ),
    ),

    // ── Accent primary ────────────────────────────────────────────────────────
    StylePreset(
      id:          'accent_primary',
      name:        'Accent Primary',
      description: 'Bold use of the primary accent colour as background',
      icon:        Icons.format_color_fill_rounded,
      swatch:      primaryAccent,
      style: SlideStyle(
        useGradient:    false,
        overlay:        SlideOverlay.crosshatch,
        overlayOpacity: 0.10,
        overlayColor:   Colors.white,
        titleBold:      true,
        titleScale:     1.1,
        bodyScale:      0.95,
        textAlign:      SlideTextAlign.center,
        textShadow:     false,
        fontFamily:     'sans-serif',
        lineHeight:     1.3,
        letterSpacing:  0.8,
        showTextBox:    false,
      ),
    ),

    // ── Accent secondary ──────────────────────────────────────────────────────
    StylePreset(
      id:          'accent_secondary',
      name:        'Accent Secondary',
      description: 'Secondary accent colour — great for announcements',
      icon:        Icons.color_lens_rounded,
      swatch:      secondaryAccent,
      style: SlideStyle(
        useGradient:    true,
        gradientEnd:    secondaryAccent.withValues(alpha: 0.70),
        gradientBegin:  Alignment.centerLeft,
        gradientEndAlign: Alignment.centerRight,
        overlay:        SlideOverlay.diagonal,
        overlayOpacity: 0.08,
        overlayColor:   Colors.white,
        titleBold:      true,
        titleItalic:    false,
        titleScale:     1.0,
        bodyScale:      1.0,
        textAlign:      SlideTextAlign.center,
        textShadow:     true,
        shadowBlur:     6,
        shadowColor:    Colors.black,
        fontFamily:     'sans-serif',
        showTextBox:    false,
      ),
    ),

    // ── Scripture ─────────────────────────────────────────────────────────────
    StylePreset(
      id:          'scripture',
      name:        'Scripture',
      description: 'Clean dark backdrop — body italic for verse text, reference small',
      icon:        Icons.menu_book_rounded,
      swatch:      const Color(0xFF1A2540),
      style: SlideStyle(
        useGradient:    true,
        gradientEnd:    const Color(0xFF2C3E6B),
        gradientBegin:  Alignment.topCenter,
        gradientEndAlign: Alignment.bottomCenter,
        overlay:        SlideOverlay.vignette,
        overlayOpacity: 0.40,
        overlayColor:   Colors.black,
        titleBold:      false,
        titleItalic:    true,
        titleScale:     0.85,
        bodyItalic:     true,
        bodyScale:      1.05,
        textAlign:      SlideTextAlign.center,
        textShadow:     true,
        shadowBlur:     10,
        shadowColor:    Colors.black,
        fontFamily:     'serif',
        lineHeight:     1.5,
        letterSpacing:  0.2,
        showTextBox:    false,
      ),
    ),

    // ── Announcement ──────────────────────────────────────────────────────────
    StylePreset(
      id:          'announcement',
      name:        'Announcement',
      description: 'High contrast with text box — great for notices',
      icon:        Icons.campaign_rounded,
      swatch:      const Color(0xFF0D1117),
      style: SlideStyle(
        useGradient:    false,
        overlay:        SlideOverlay.dots,
        overlayOpacity: 0.08,
        overlayColor:   Colors.white,
        titleBold:      true,
        titleScale:     1.1,
        bodyScale:      1.0,
        textAlign:      SlideTextAlign.left,
        textShadow:     false,
        fontFamily:     'sans-serif',
        lineHeight:     1.4,
        letterSpacing:  0.5,
        showTextBox:    true,
        textBoxOpacity: 0.75,
        textBoxPaddingH: 24,
        textBoxPaddingV: 16,
        textBoxRadius:   12,
      ),
    ),

    // ── Minimal ───────────────────────────────────────────────────────────────
    StylePreset(
      id:          'minimal',
      name:        'Minimal',
      description: 'Black slide, white text — nothing in the way',
      icon:        Icons.circle_outlined,
      swatch:      Colors.black,
      style: SlideStyle(
        useGradient:  false,
        overlay:      SlideOverlay.none,
        titleBold:    true,
        titleScale:   1.0,
        bodyScale:    1.0,
        textAlign:    SlideTextAlign.center,
        textShadow:   false,
        fontFamily:   'sans-serif',
        lineHeight:   1.4,
        letterSpacing: 0.5,
        showTextBox:  false,
      ),
    ),
  ];
}

// ══════════════════════════════════════════════════════════════════════════════
// SHOW HELPER
// ══════════════════════════════════════════════════════════════════════════════
Future<String?> showMasterStyleDialog(
  BuildContext context, {
  required Color  primary,
  required Color  secondary,
  required String currentMasterPresetId,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _MasterStyleDialog(
      primary:               primary,
      secondary:             secondary,
      currentMasterPresetId: currentMasterPresetId,
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// DIALOG
// ══════════════════════════════════════════════════════════════════════════════
class _MasterStyleDialog extends StatefulWidget {
  final Color  primary;
  final Color  secondary;
  final String currentMasterPresetId;

  const _MasterStyleDialog({
    required this.primary,
    required this.secondary,
    required this.currentMasterPresetId,
  });

  @override
  State<_MasterStyleDialog> createState() => _MasterStyleDialogState();
}

class _MasterStyleDialogState extends State<_MasterStyleDialog> {
  late String _selected;
  late List<StylePreset> _presets;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentMasterPresetId;
    _presets = buildPresets(
        primaryAccent: widget.primary,
        secondaryAccent: widget.secondary);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.primary;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              decoration: BoxDecoration(
                color: p.withValues(alpha: 0.08),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(
                    bottom: BorderSide(color: p.withValues(alpha: 0.12))),
              ),
              child: Row(
                children: [
                  Icon(Icons.style_rounded, color: p, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Master Style',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                                color: p)),
                        const SizedBox(height: 2),
                        Text(
                          'Sets the default look for all slides. '
                          'Individual slides can override this.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.grey,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // ── Preset grid ─────────────────────────────────────────────────
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _presets.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final preset  = _presets[i];
                  final isSel   = preset.id == _selected;
                  return _PresetTile(
                    preset:   preset,
                    selected: isSel,
                    primary:  p,
                    onTap:    () => setState(() => _selected = preset.id),
                  );
                },
              ),
            ),

            // ── Footer ───────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, _selected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Apply Master Style',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Single preset tile ────────────────────────────────────────────────────────
class _PresetTile extends StatelessWidget {
  final StylePreset preset;
  final bool        selected;
  final Color       primary;
  final VoidCallback onTap;

  const _PresetTile({
    required this.preset,
    required this.selected,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.10)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? primary : Colors.grey.shade200,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Colour swatch
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: preset.swatch,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                      color: preset.swatch.withValues(alpha: 0.30),
                      blurRadius: 6)
                ],
              ),
              child: Icon(preset.icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(preset.name,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: selected ? primary : null)),
                      if (selected) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('MASTER',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(preset.description,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: primary, size: 22)
            else
              Icon(Icons.radio_button_unchecked_rounded,
                  color: Colors.grey.shade300, size: 22),
          ],
        ),
      ),
    );
  }
}