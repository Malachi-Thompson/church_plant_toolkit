// lib/apps/notes/widgets/note_list.dart
//
// Middle-column note list and individual list tile.
// Right-click (desktop) or long-press (mobile) opens the context menu.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../theme.dart';
import '../note_constants.dart';
import '../note_model.dart';

class NoteList extends StatelessWidget {
  final List<NoteModel>         notes;
  final NoteModel?              selectedNote;
  final Color                   primary;
  final Color                   secondary;
  final bool                    showingSearch;
  final String                  activeFolder;
  final ValueChanged<NoteModel> onSelect;
  final ValueChanged<NoteModel> onArchive;
  final ValueChanged<NoteModel> onUnarchive;
  final ValueChanged<NoteModel> onDelete;
  final void Function(NoteModel, String) onExport; // format: 'docx'|'odt'|'pdf'
  final VoidCallback            onNew;

  const NoteList({
    super.key,
    required this.notes,
    required this.selectedNote,
    required this.primary,
    required this.secondary,
    required this.showingSearch,
    required this.activeFolder,
    required this.onSelect,
    required this.onArchive,
    required this.onUnarchive,
    required this.onDelete,
    required this.onExport,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFAFAFB),
      child: Column(children: [
        // Header row
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
          child: Row(children: [
            Text(
              showingSearch ? 'Search Results' : activeFolder,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: textMid),
            ),
            const Spacer(),
            Text('${notes.length}',
                style: const TextStyle(fontSize: 11, color: textMid)),
            const SizedBox(width: 4),
            if (!showingSearch)
              IconButton(
                icon: Icon(Icons.add, size: 18, color: primary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: onNew,
                tooltip: 'New note',
              ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: notes.isEmpty
              ? _emptyState()
              : ListView.separated(
                  itemCount: notes.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 14),
                  itemBuilder: (_, i) => _NoteListTile(
                    note:        notes[i],
                    selected:    selectedNote?.id == notes[i].id,
                    primary:     primary,
                    secondary:   secondary,
                    onTap:       () => onSelect(notes[i]),
                    onArchive:   () => onArchive(notes[i]),
                    onUnarchive: () => onUnarchive(notes[i]),
                    onDelete:    () => onDelete(notes[i]),
                    onExportDocx: () => onExport(notes[i], 'docx'),
                    onExportOdt:  () => onExport(notes[i], 'odt'),
                    onExportPdf:  () => onExport(notes[i], 'pdf'),
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _emptyState() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.note_add_outlined,
          size: 40, color: primary.withValues(alpha: 0.2)),
      const SizedBox(height: 10),
      Text(
        showingSearch ? 'No results' : 'No notes yet',
        style: TextStyle(color: primary.withValues(alpha: 0.4)),
      ),
    ]),
  );
}

// ── LIST TILE ─────────────────────────────────────────────────────────────────

class _NoteListTile extends StatelessWidget {
  final NoteModel  note;
  final bool       selected;
  final Color      primary;
  final Color      secondary;
  final VoidCallback onTap, onArchive, onUnarchive, onDelete;
  final VoidCallback onExportDocx, onExportOdt, onExportPdf;

  const _NoteListTile({
    required this.note,
    required this.selected,
    required this.primary,
    required this.secondary,
    required this.onTap,
    required this.onArchive,
    required this.onUnarchive,
    required this.onDelete,
    required this.onExportDocx,
    required this.onExportOdt,
    required this.onExportPdf,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = note.date != null
        ? DateFormat('MMM d, y').format(note.date!)
        : DateFormat('MMM d').format(note.updatedAt);

    return GestureDetector(
      onTap: onTap,
      onSecondaryTapUp: (d) => _showContextMenu(context, d.globalPosition),
      child: Container(
        color: selected ? primary.withValues(alpha: 0.07) : null,
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (note.isPinned)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: Icon(Icons.push_pin, size: 12, color: secondary),
            ),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(note.title,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: selected ? primary : textDark),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              if (note.subfolder.isNotEmpty)
                Text(note.subfolder,
                    style: TextStyle(
                        fontSize: 10, color: secondary,
                        fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                note.content.isEmpty
                    ? 'No content'
                    : note.content.replaceAll('\n', ' '),
                style: const TextStyle(fontSize: 11, color: textMid),
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(children: [
                // Message type badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    messageTypeLabels[note.messageType] ?? '',
                    style: TextStyle(
                        fontSize: 9, color: primary,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                // Source file type badge
                if (note.sourceFileType != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                        color: const Color(0xFFE8E8EC),
                        borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      note.sourceFileType!.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 9, color: textMid,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                const Spacer(),
                Text(dateStr,
                    style: const TextStyle(fontSize: 10, color: textMid)),
              ]),
            ],
          )),
        ]),
      ),
    );
  }

  Future<void> _showContextMenu(BuildContext ctx, Offset pos) async {
    final result = await showMenu<String>(
      context: ctx,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        const PopupMenuItem(value: 'docx', child: Row(children: [
          Icon(Icons.description_outlined, size: 16),
          SizedBox(width: 8), Text('Export as Word')])),
        const PopupMenuItem(value: 'odt', child: Row(children: [
          Icon(Icons.description_outlined, size: 16),
          SizedBox(width: 8), Text('Export as ODT')])),
        const PopupMenuItem(value: 'pdf', child: Row(children: [
          Icon(Icons.picture_as_pdf_outlined, size: 16),
          SizedBox(width: 8), Text('Export as PDF')])),
        const PopupMenuItem(value: 'archive', child: Row(children: [
          Icon(Icons.archive_outlined, size: 16),
          SizedBox(width: 8), Text('Archive')])),
        const PopupMenuItem(value: 'delete', child: Row(children: [
          Icon(Icons.delete_outline, size: 16, color: Colors.red),
          SizedBox(width: 8),
          Text('Delete', style: TextStyle(color: Colors.red))])),
      ],
    );
    switch (result) {
      case 'docx':    onExportDocx(); break;
      case 'odt':     onExportOdt();  break;
      case 'pdf':     onExportPdf();  break;
      case 'archive': note.isArchived ? onUnarchive() : onArchive(); break;
      case 'delete':  onDelete(); break;
    }
  }
}