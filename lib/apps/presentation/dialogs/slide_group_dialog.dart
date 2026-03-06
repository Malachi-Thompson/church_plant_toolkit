// lib/apps/presentation/dialogs/slide_group_dialog.dart
//
// showSlideGroupDialog — create or edit a SlideGroup.
// Returns the updated/new SlideGroup or null if cancelled.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/slide_group.dart';

Future<SlideGroup?> showSlideGroupDialog(
  BuildContext context, {
  required Color primary,
  SlideGroup?   existing,
}) {
  return showDialog<SlideGroup>(
    context: context,
    builder: (_) => _SlideGroupDialog(primary: primary, existing: existing),
  );
}

class _SlideGroupDialog extends StatefulWidget {
  final Color       primary;
  final SlideGroup? existing;
  const _SlideGroupDialog({required this.primary, this.existing});

  @override
  State<_SlideGroupDialog> createState() => _SlideGroupDialogState();
}

class _SlideGroupDialogState extends State<_SlideGroupDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _secsCtrl;
  bool _autoEnabled = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl    = TextEditingController(text: e?.name ?? '');
    _autoEnabled = e?.hasAutoAdvance ?? false;
    _secsCtrl    = TextEditingController(
        text: (e?.autoAdvanceSeconds ?? 5).toString());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _secsCtrl.dispose();
    super.dispose();
  }

  Color get p => widget.primary;

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final secs = _autoEnabled
        ? int.tryParse(_secsCtrl.text.trim()) ?? 5
        : null;

    final group = widget.existing != null
        ? widget.existing!.copyWith(
            name:                 name,
            autoAdvanceSeconds:   secs,
            clearAuto:            !_autoEnabled,
          )
        : SlideGroup(
            name:               name,
            autoAdvanceSeconds: secs,
          );

    Navigator.pop(context, group);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:        p.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.collections_bookmark_rounded,
                        color: p, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(isEdit ? 'Edit Group' : 'New Slide Group',
                      style: TextStyle(
                          fontSize:   17,
                          fontWeight: FontWeight.bold,
                          color:      p)),
                ],
              ),
              const SizedBox(height: 20),

              // ── Name field ──────────────────────────────────────────────
              TextField(
                controller:  _nameCtrl,
                autofocus:   true,
                decoration:  InputDecoration(
                  labelText:     'Group name',
                  hintText:      'e.g. Opening Worship, Announcements',
                  border:        OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  prefixIcon:    const Icon(Icons.label_outline_rounded),
                ),
                textCapitalization: TextCapitalization.words,
                onSubmitted:   (_) => _submit(),
              ),
              const SizedBox(height: 20),

              // ── Auto-advance toggle ─────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:        p.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border:       Border.all(
                      color: p.withValues(alpha: 0.18)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.timer_rounded, color: p, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Auto-advance slides',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color:      p)),
                        ),
                        Switch(
                          value:         _autoEnabled,
                          activeColor:   p,
                          onChanged: (v) =>
                              setState(() => _autoEnabled = v),
                        ),
                      ],
                    ),
                    if (_autoEnabled) ...[
                      const SizedBox(height: 12),
                      Text('Advance every:',
                          style: TextStyle(
                              fontSize: 12,
                              color:    Colors.grey.shade600)),
                      const SizedBox(height: 8),
                      _TimerPicker(
                        primary:  p,
                        ctrl:     _secsCtrl,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Each slide in this group will automatically '
                        'advance after ${_secsCtrl.text.trim().isEmpty ? '?' : _secsCtrl.text.trim()} seconds '
                        'during presentation.',
                        style: TextStyle(
                            fontSize: 11,
                            color:    Colors.grey.shade500,
                            fontStyle: FontStyle.italic),
                      ),
                    ] else ...[
                      const SizedBox(height: 6),
                      Text('Slides advance manually (tap/key)',
                          style: TextStyle(
                              fontSize: 12,
                              color:    Colors.grey.shade500)),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Actions ─────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.grey),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _submit,
                    icon:  Icon(isEdit ? Icons.check_rounded : Icons.add_rounded,
                        size: 18),
                    label: Text(isEdit ? 'Save' : 'Create Group'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p,
                      foregroundColor: _contrastOn(p),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Quick-pick chip row + manual text field ───────────────────────────────────
class _TimerPicker extends StatelessWidget {
  final Color                  primary;
  final TextEditingController  ctrl;
  final ValueChanged<String>   onChanged;

  const _TimerPicker({
    required this.primary,
    required this.ctrl,
    required this.onChanged,
  });

  static const _presets = [3, 5, 10, 15, 30, 60];

  @override
  Widget build(BuildContext context) {
    final current = int.tryParse(ctrl.text.trim());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6, runSpacing: 6,
          children: _presets.map((s) {
            final selected = current == s;
            return GestureDetector(
              onTap: () {
                ctrl.text = s.toString();
                onChanged(s.toString());
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: selected
                      ? primary
                      : primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? primary
                        : primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  s < 60 ? '${s}s' : '1 min',
                  style: TextStyle(
                    fontSize:   12,
                    fontWeight: FontWeight.w600,
                    color:      selected ? _contrastOn(primary) : primary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 120,
          child: TextField(
            controller:    ctrl,
            keyboardType:  TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText:     'Custom (s)',
              border:        OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              suffixText: 'sec',
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

Color _contrastOn(Color bg) {
  final l = bg.computeLuminance();
  return l > 0.35 ? Colors.black87 : Colors.white;
}