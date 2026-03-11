// lib/apps/notes/widgets/shared_widgets.dart
//
// Small reusable widgets used across the notes feature.
// Add other lightweight, stateless note widgets here.

import 'package:flutter/material.dart';
import '../../../theme.dart';

// ── META CHIP ─────────────────────────────────────────────────────────────────
// Tappable pill badge used in the editor toolbar for message type, date, etc.

class MetaChip extends StatelessWidget {
  final String     label;
  final IconData   icon;
  final Color      color;
  final VoidCallback onTap;

  const MetaChip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ── EMPTY EDITOR ──────────────────────────────────────────────────────────────
// Shown in the right pane when no note is selected (desktop layout).

class EmptyEditor extends StatelessWidget {
  final Color primary;
  const EmptyEditor({super.key, required this.primary});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.edit_note_outlined,
          size: 56, color: primary.withValues(alpha: 0.15)),
      const SizedBox(height: 16),
      Text('Select a note or create a new one',
          style: TextStyle(
              color: primary.withValues(alpha: 0.35), fontSize: 14)),
    ]),
  );
}