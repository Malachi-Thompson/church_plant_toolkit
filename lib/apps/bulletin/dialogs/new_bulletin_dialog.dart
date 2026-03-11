// lib/apps/bulletin/dialogs/new_bulletin_dialog.dart
//
// Shown when creating a new bulletin — lets the user pick a layout template.

import 'package:flutter/material.dart';
import '../../../theme.dart';
import '../bulletin_model.dart';

class NewBulletinDialog extends StatefulWidget {
  final Color primary;
  const NewBulletinDialog({super.key, required this.primary});

  @override
  State<NewBulletinDialog> createState() => _NewBulletinDialogState();
}

class _NewBulletinDialogState extends State<NewBulletinDialog> {
  BulletinLayout _selected = BulletinLayout.bifold;

  static const _previews = <BulletinLayout, _LayoutPreview>{
    BulletinLayout.singlePage: _LayoutPreview(
      icon: Icons.article_outlined,
      panels: 1,
      description:
          'One full letter-size page, portrait. Great for simple services '
          'or when you want everything in one view.',
      printNote: 'Print: portrait, one-sided',
    ),
    BulletinLayout.bifold: _LayoutPreview(
      icon: Icons.menu_book_outlined,
      panels: 4,
      description:
          'The classic church bulletin. Print landscape on letter paper, '
          'fold down the middle to get a 4-panel booklet.',
      printNote: 'Print: landscape, two-sided, fold in half',
    ),
    BulletinLayout.halfSheet: _LayoutPreview(
      icon: Icons.view_agenda_outlined,
      panels: 2,
      description:
          'Two identical half-pages on one letter sheet. Cut apart and '
          'hand out — cost-effective for small congregations.',
      printNote: 'Print: portrait, one-sided, cut horizontally',
    ),
    BulletinLayout.trifold: _LayoutPreview(
      icon: Icons.view_column_outlined,
      panels: 6,
      description:
          'Six panels for maximum content. Print landscape, fold in thirds. '
          'Ideal for larger services with lots of announcements.',
      printNote: 'Print: landscape, two-sided, fold in thirds',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary;
    final preview = _previews[_selected]!;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(children: [
              Icon(Icons.article_outlined, color: primary),
              const SizedBox(width: 10),
              Text('New Bulletin',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: primary)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 6, 20, 12),
            child: Text('Choose a layout template to get started.',
                style: TextStyle(fontSize: 13, color: textMid)),
          ),
          const Divider(height: 1),

          // Layout grid
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Left: layout picker
              SizedBox(
                width: 220,
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: BulletinLayout.values.map((l) {
                    final p       = _previews[l]!;
                    final sel     = l == _selected;
                    return InkWell(
                      onTap: () => setState(() => _selected = l),
                      child: Container(
                        color: sel ? primary.withValues(alpha: 0.07) : null,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(children: [
                          Container(
                            width: 40, height: 50,
                            decoration: BoxDecoration(
                              color: sel
                                  ? primary.withValues(alpha: 0.1)
                                  : const Color(0xFFEEEFF3),
                              borderRadius: BorderRadius.circular(6),
                              border: sel
                                  ? Border.all(color: primary, width: 1.5)
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Icon(p.icon,
                                size: 20,
                                color: sel ? primary : textMid),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(bulletinLayoutLabels[l] ?? '',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: sel ? primary : textDark)),
                              Text('${p.panels} panels',
                                  style: const TextStyle(
                                      fontSize: 10, color: textMid)),
                            ],
                          )),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const VerticalDivider(width: 1),
              // Right: preview description
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Icon(preview.icon, size: 36, color: primary),
                    const SizedBox(height: 12),
                    Text(bulletinLayoutLabels[_selected] ?? '',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: primary)),
                    const SizedBox(height: 8),
                    Text(preview.description,
                        style: const TextStyle(
                            fontSize: 13, color: textDark, height: 1.5)),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: const Color(0xFFF0F4FF),
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        Icon(Icons.print_outlined, size: 14, color: primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(preview.printNote,
                              style: TextStyle(
                                  fontSize: 11, color: primary)),
                        ),
                      ]),
                    ),
                    // Panel diagram
                    const SizedBox(height: 20),
                    _PanelDiagram(
                        layout: _selected, primary: primary),
                  ]),
                ),
              ),
            ]),
          ),

          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, _selected),
                style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: contrastOn(primary)),
                child: const Text('Create Bulletin'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// Simple visual panel diagram
class _PanelDiagram extends StatelessWidget {
  final BulletinLayout layout;
  final Color          primary;
  const _PanelDiagram({required this.layout, required this.primary});

  @override
  Widget build(BuildContext context) {
    final panels = _panelConfig[layout]!;
    final total  = panels.fold<int>(0, (s, p) => s + p);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Layout diagram',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: primary.withValues(alpha: 0.6),
              letterSpacing: .06)),
      const SizedBox(height: 6),
      for (final rowCount in panels) ...[
        Row(
          children: List.generate(rowCount, (i) => Expanded(
            child: Container(
              height: 36,
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.08),
                  border: Border.all(color: primary.withValues(alpha: 0.25)),
                  borderRadius: BorderRadius.circular(4)),
              alignment: Alignment.center,
              child: Text('${i + 1}',
                  style: TextStyle(
                      fontSize: 10,
                      color: primary.withValues(alpha: 0.6))),
            ),
          )),
        ),
      ],
      const SizedBox(height: 4),
      Text('$total panels total',
          style: const TextStyle(fontSize: 10, color: textMid)),
    ]);
  }

  // rows of panel counts
  static const _panelConfig = <BulletinLayout, List<int>>{
    BulletinLayout.singlePage: [1],
    BulletinLayout.bifold:     [2, 2],
    BulletinLayout.halfSheet:  [1, 1],
    BulletinLayout.trifold:    [3, 3],
  };
}

class _LayoutPreview {
  final IconData icon;
  final int      panels;
  final String   description;
  final String   printNote;
  const _LayoutPreview({
    required this.icon,
    required this.panels,
    required this.description,
    required this.printNote,
  });
}