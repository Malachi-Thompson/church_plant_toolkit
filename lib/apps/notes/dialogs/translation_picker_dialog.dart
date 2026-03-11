// lib/apps/notes/dialogs/translation_picker_dialog.dart
//
// Dialog for selecting a Bible translation per note.

import 'package:flutter/material.dart';
import '../../../services/bible_service.dart';
import '../../../theme.dart';

const popularTranslationIds = <String>[
  'KJV','NKJV','ESV','NASB1995','NIV','NLT','CSB','BSB',
  'ASV','WEB','YLT','DARBY','HCSB','AMP','MSG',
];

class TranslationPickerDialog extends StatefulWidget {
  final List<BibleTranslation> translations;
  final String current;
  final Color  primary;

  const TranslationPickerDialog({
    super.key,
    required this.translations,
    required this.current,
    required this.primary,
  });

  @override
  State<TranslationPickerDialog> createState() =>
      _TranslationPickerDialogState();
}

class _TranslationPickerDialogState
    extends State<TranslationPickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.translations
        .where((t) =>
            t.id.toLowerCase().contains(_q.toLowerCase()) ||
            t.name.toLowerCase().contains(_q.toLowerCase()))
        .toList();

    final popular =
        filtered.where((t) => popularTranslationIds.contains(t.id)).toList();
    final others =
        filtered.where((t) => !popularTranslationIds.contains(t.id)).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 420,
        height: 540,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Choose Translation',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: widget.primary)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'Search translations…',
                prefixIcon: Icon(Icons.search, color: widget.primary),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: ListView(children: [
            if (popular.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('POPULAR',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: textMid,
                        letterSpacing: 1.2)),
              ),
              ...popular.map((t) => _TransTile(
                  t: t, current: widget.current, primary: widget.primary)),
            ],
            if (others.isNotEmpty && _q.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('ALL',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: textMid,
                        letterSpacing: 1.2)),
              ),
              ...others.map((t) => _TransTile(
                  t: t, current: widget.current, primary: widget.primary)),
            ],
          ])),
        ]),
      ),
    );
  }
}

class _TransTile extends StatelessWidget {
  final BibleTranslation t;
  final String current;
  final Color  primary;
  const _TransTile(
      {required this.t, required this.current, required this.primary});

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    selected: t.id == current,
    selectedTileColor: primary.withValues(alpha: 0.07),
    leading: Container(
      width: 44, height: 28,
      decoration: BoxDecoration(
          color: t.id == current ? primary : const Color(0xFFEEEEEE),
          borderRadius: BorderRadius.circular(4)),
      alignment: Alignment.center,
      child: Text(t.shortName,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: t.id == current ? contrastOn(primary) : textMid)),
    ),
    title: Text(t.name,
        style: const TextStyle(fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis),
    trailing: t.id == current
        ? Icon(Icons.check, color: primary, size: 16)
        : null,
    onTap: () => Navigator.pop(context, t.id),
  );
}