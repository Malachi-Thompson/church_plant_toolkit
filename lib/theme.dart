// lib/theme.dart
// Static fallback constants used in widgets before a profile is loaded,
// and for any widget that needs a hardcoded reference color.
// The live dynamic theme is built by buildChurchTheme() in app_state.dart.

import 'package:flutter/material.dart';

// Default brand colors (used only as fallback if no profile loaded)
const Color primaryColor   = Color(0xFF1A3A5C);
const Color accentColor    = Color(0xFFD4A843);
const Color lightBg        = Color(0xFFF5F7FA);
const Color cardColor      = Colors.white;
const Color textDark       = Color(0xFF1C1C2E);
const Color textMid        = Color(0xFF5A6175);
const Color borderColor    = Color(0xFFEAEDF3);

/// Returns white or black depending on which has better contrast on [bg].
Color contrastOn(Color bg) =>
    bg.computeLuminance() > 0.4 ? Colors.black87 : Colors.white;

/// Lightens a color by mixing it with white at [amount] (0.0–1.0).
Color lighten(Color color, [double amount = 0.15]) {
  return Color.lerp(color, Colors.white, amount)!;
}

/// Darkens a color by mixing it with black at [amount] (0.0–1.0).
Color darken(Color color, [double amount = 0.15]) {
  return Color.lerp(color, Colors.black, amount)!;
}

/// Creates a subtle tinted background from a brand color.
Color tintedBg(Color color) => Color.lerp(color, Colors.white, 0.92)!;