// lib/apps/bulletin/widgets/bulletin_list.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../theme.dart';
import '../bulletin_model.dart';

class BulletinList extends StatelessWidget {
  final List<BulletinModel>         bulletins;
  final BulletinModel?              selected;
  final Color                       primary;
  final ValueChanged<BulletinModel> onSelect;
  final ValueChanged<BulletinModel> onDelete;
  final ValueChanged<BulletinModel> onDuplicate;
  final VoidCallback                onNew;

  const BulletinList({
    super.key,
    required this.bulletins,
    required this.selected,
    required this.primary,
    required this.onSelect,
    required this.onDelete,
    required this.onDuplicate,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F9FA),
      child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
          child: Row(children: [
            const Text('Bulletins',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: textMid)),
            const Spacer(),
            Text('${bulletins.length}',
                style: const TextStyle(fontSize: 11, color: textMid)),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.add, size: 18, color: primary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'New bulletin',
              onPressed: onNew,
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: bulletins.isEmpty
              ? _emptyState()
              : ListView.separated(
                  itemCount: bulletins.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 14),
                  itemBuilder: (_, i) => _BulletinTile(
                    bulletin:    bulletins[i],
                    selected:    selected?.id == bulletins[i].id,
                    primary:     primary,
                    onTap:       () => onSelect(bulletins[i]),
                    onDelete:    () => onDelete(bulletins[i]),
                    onDuplicate: () => onDuplicate(bulletins[i]),
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _emptyState() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.article_outlined,
          size: 40, color: primary.withValues(alpha: 0.2)),
      const SizedBox(height: 10),
      Text('No bulletins yet',
          style: TextStyle(color: primary.withValues(alpha: 0.4))),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: onNew,
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Create first bulletin'),
      ),
    ]),
  );
}

class _BulletinTile extends StatelessWidget {
  final BulletinModel bulletin;
  final bool          selected;
  final Color         primary;
  final VoidCallback  onTap, onDelete, onDuplicate;

  const _BulletinTile({
    required this.bulletin,
    required this.selected,
    required this.primary,
    required this.onTap,
    required this.onDelete,
    required this.onDuplicate,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = bulletin.serviceDate != null
        ? DateFormat('MMM d, y').format(bulletin.serviceDate!)
        : DateFormat('MMM d').format(bulletin.updatedAt);

    return GestureDetector(
      onTap: onTap,
      onSecondaryTapUp: (d) => _showContextMenu(context, d.globalPosition),
      child: Container(
        color: selected ? primary.withValues(alpha: 0.07) : null,
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(children: [
          // Layout icon
          Container(
            width: 32, height: 40,
            decoration: BoxDecoration(
              color: selected
                  ? primary.withValues(alpha: 0.12)
                  : const Color(0xFFEEEFF3),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Icon(_layoutIcon(bulletin.layout),
                size: 16,
                color: selected ? primary : textMid),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(bulletin.title,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: selected ? primary : textDark),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              if (bulletin.sermonTitle.isNotEmpty)
                Text(bulletin.sermonTitle,
                    style: TextStyle(
                        fontSize: 11,
                        color: selected ? primary.withValues(alpha: 0.7) : textMid,
                        fontStyle: FontStyle.italic),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Row(children: [
                _LayoutBadge(
                    label: bulletinLayoutLabels[bulletin.layout] ?? '',
                    primary: primary,
                    selected: selected),
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

  IconData _layoutIcon(BulletinLayout l) {
    switch (l) {
      case BulletinLayout.singlePage: return Icons.article_outlined;
      case BulletinLayout.bifold:     return Icons.menu_book_outlined;
      case BulletinLayout.halfSheet:  return Icons.view_agenda_outlined;
      case BulletinLayout.trifold:    return Icons.view_column_outlined;
    }
  }

  Future<void> _showContextMenu(BuildContext ctx, Offset pos) async {
    final result = await showMenu<String>(
      context: ctx,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        const PopupMenuItem(value: 'duplicate', child: Row(children: [
          Icon(Icons.copy_outlined, size: 16),
          SizedBox(width: 8), Text('Duplicate for next week')])),
        const PopupMenuItem(value: 'delete', child: Row(children: [
          Icon(Icons.delete_outline, size: 16, color: Colors.red),
          SizedBox(width: 8),
          Text('Delete', style: TextStyle(color: Colors.red))])),
      ],
    );
    switch (result) {
      case 'duplicate': onDuplicate(); break;
      case 'delete':    onDelete();    break;
    }
  }
}

class _LayoutBadge extends StatelessWidget {
  final String label; final Color primary; final bool selected;
  const _LayoutBadge({required this.label, required this.primary, required this.selected});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
        color: selected
            ? primary.withValues(alpha: 0.1)
            : const Color(0xFFE8E8EC),
        borderRadius: BorderRadius.circular(4)),
    child: Text(label,
        style: TextStyle(
            fontSize: 9,
            color: selected ? primary : textMid,
            fontWeight: FontWeight.bold)),
  );
}