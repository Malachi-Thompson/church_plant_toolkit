// lib/apps/website/website_canvas_editor.dart
//
// Visual block-canvas editor — Wix-style WYSIWYG editing that preserves
// the existing WebBlock / WebPage / ChurchWebsite model layer entirely.
//
// Drop-in replacement for _BlockCanvas + _BlockCard in website_screen.dart.
// Usage:
//
//   WebsiteCanvasEditor(
//     page:          _activePage!,
//     site:          _site!,
//     selectedBlock: _selectedBlock,
//     primary:       primary,
//     secondary:     secondary,
//     onSelect:      (b) => setState(() => _selectedBlock = b),
//     onChanged:     () => _update(() {}),
//     onDelete:      _deleteBlock,
//     onReorder:     _moveBlock,
//     onToggleVisibility: (b) => _update(() => b.isVisible = !b.isVisible),
//     onAddBlock:    _addBlock,
//   )

import 'package:flutter/material.dart';
import 'website_models.dart';

// ─── Color helpers (mirrors theme.dart) ────────────────────────────────────────

Color _dim(Color c, [double alpha = 0.08]) => c.withValues(alpha: alpha);
Color _dimmed(Color c) => c.withValues(alpha: 0.55);

const _textDark = Color(0xFF1A1D23);
const _textMid  = Color(0xFF6B7280);
const _surface  = Color(0xFFF7F8FA);
const _border   = Color(0xFFEAEDF3);

// ─── Block type accent colours ─────────────────────────────────────────────────

const _blockAccent = <BlockType, Color>{
  BlockType.hero:         Color(0xFF185FA5),
  BlockType.about:        Color(0xFF3B6D11),
  BlockType.services:     Color(0xFF534AB7),
  BlockType.events:       Color(0xFFBA7517),
  BlockType.team:         Color(0xFF993556),
  BlockType.sermon:       Color(0xFF0F6E56),
  BlockType.contact:      Color(0xFF993C1D),
  BlockType.map:          Color(0xFF0F6E56),
  BlockType.gallery:      Color(0xFF185FA5),
  BlockType.announcement: Color(0xFFBA7517),
  BlockType.divider:      Color(0xFF5F5E5A),
  BlockType.richText:     Color(0xFF5F5E5A),
  BlockType.cta:          Color(0xFF185FA5),
};

Color _accentFor(BlockType t) => _blockAccent[t] ?? const Color(0xFF185FA5);

// ─── Icon map ──────────────────────────────────────────────────────────────────

const _blockIcons = <BlockType, IconData>{
  BlockType.hero:         Icons.view_agenda_outlined,
  BlockType.about:        Icons.info_outline,
  BlockType.services:     Icons.access_time,
  BlockType.events:       Icons.event_outlined,
  BlockType.team:         Icons.people_outline,
  BlockType.sermon:       Icons.menu_book_outlined,
  BlockType.contact:      Icons.mail_outline,
  BlockType.map:          Icons.map_outlined,
  BlockType.gallery:      Icons.photo_library_outlined,
  BlockType.announcement: Icons.campaign_outlined,
  BlockType.divider:      Icons.horizontal_rule,
  BlockType.richText:     Icons.article_outlined,
  BlockType.cta:          Icons.ads_click,
};

// ══════════════════════════════════════════════════════════════════════════════
// PUBLIC WIDGET
// ══════════════════════════════════════════════════════════════════════════════

class WebsiteCanvasEditor extends StatefulWidget {
  final WebPage               page;
  final ChurchWebsite         site;
  final WebBlock?             selectedBlock;
  final Color                 primary;
  final Color                 secondary;
  final ValueChanged<WebBlock> onSelect;
  final VoidCallback           onChanged;
  final ValueChanged<WebBlock> onDelete;
  final Function(int, int)     onReorder;
  final ValueChanged<WebBlock> onToggleVisibility;
  final ValueChanged<BlockType> onAddBlock;

  const WebsiteCanvasEditor({
    super.key,
    required this.page,
    required this.site,
    required this.selectedBlock,
    required this.primary,
    required this.secondary,
    required this.onSelect,
    required this.onChanged,
    required this.onDelete,
    required this.onReorder,
    required this.onToggleVisibility,
    required this.onAddBlock,
  });

  @override
  State<WebsiteCanvasEditor> createState() => _WebsiteCanvasEditorState();
}

class _WebsiteCanvasEditorState extends State<WebsiteCanvasEditor> {
  // Track which block the cursor is hovering over
  String? _hoveredBlockId;
  // Track whether the add-block-row below a block index is hovered
  int? _hoveredAddRow;

  void _onBlockHover(String? id) {
    if (_hoveredBlockId != id) setState(() => _hoveredBlockId = id);
  }

  void _onAddRowHover(int? idx) {
    if (_hoveredAddRow != idx) setState(() => _hoveredAddRow = idx);
  }

  @override
  Widget build(BuildContext context) {
    final blocks = widget.page.blocks;

    if (blocks.isEmpty) return _EmptyCanvas(primary: widget.primary);

    return Container(
      color: const Color(0xFFE8EAF0),
      child: ReorderableListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 24),
        proxyDecorator: (child, index, animation) => Material(
          color: Colors.transparent,
          elevation: 6,
          shadowColor: Colors.black26,
          child: child,
        ),
        onReorder: widget.onReorder,
        itemCount: blocks.length,
        itemBuilder: (ctx, i) {
          final block    = blocks[i];
          final selected = widget.selectedBlock?.id == block.id;
          final hovered  = _hoveredBlockId == block.id;

          return _CanvasBlockSlot(
            key:            ValueKey(block.id),
            block:          block,
            index:          i,
            isSelected:     selected,
            isHovered:      hovered,
            isAddRowHovered: _hoveredAddRow == i,
            primary:        widget.primary,
            secondary:      widget.secondary,
            onTap:          () => widget.onSelect(block),
            onDelete:       () => widget.onDelete(block),
            onToggle:       () => widget.onToggleVisibility(block),
            onMoveUp:       i > 0
                ? () => widget.onReorder(i, i - 1)
                : null,
            onMoveDown:     i < blocks.length - 1
                ? () => widget.onReorder(i, i + 2)
                : null,
            onHover:        _onBlockHover,
            onAddRowHover:  _onAddRowHover,
            onAddBlockBelow: () => _showAddBlockMenu(context, i + 1),
            onChanged:      widget.onChanged,
          );
        },
      ),
    );
  }

  // ── Add-block menu (shown when + is tapped) ─────────────────────────────────

  Future<void> _showAddBlockMenu(BuildContext context, int insertAt) async {
    final type = await showDialog<BlockType>(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => _AddBlockDialog(primary: widget.primary),
    );
    if (type == null) return;

    // Insert at position: add to end then move if needed
    widget.onAddBlock(type);
    final blocks = widget.page.blocks;
    if (insertAt < blocks.length - 1) {
      widget.onReorder(blocks.length - 1, insertAt);
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CANVAS BLOCK SLOT — one block row + the add-row beneath it
// ══════════════════════════════════════════════════════════════════════════════

class _CanvasBlockSlot extends StatelessWidget {
  final WebBlock          block;
  final int               index;
  final bool              isSelected;
  final bool              isHovered;
  final bool              isAddRowHovered;
  final Color             primary;
  final Color             secondary;
  final VoidCallback      onTap;
  final VoidCallback      onDelete;
  final VoidCallback      onToggle;
  final VoidCallback?     onMoveUp;
  final VoidCallback?     onMoveDown;
  final ValueChanged<String?> onHover;
  final ValueChanged<int?>    onAddRowHover;
  final VoidCallback      onAddBlockBelow;
  final VoidCallback      onChanged;

  const _CanvasBlockSlot({
    super.key,
    required this.block,          required this.index,
    required this.isSelected,     required this.isHovered,
    required this.isAddRowHovered,required this.primary,
    required this.secondary,      required this.onTap,
    required this.onDelete,       required this.onToggle,
    this.onMoveUp,                this.onMoveDown,
    required this.onHover,        required this.onAddRowHover,
    required this.onAddBlockBelow,required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── The block itself ───────────────────────────────────────────────
        MouseRegion(
          onEnter: (_) => onHover(block.id),
          onExit:  (_) => onHover(null),
          child: GestureDetector(
            onTap: onTap,
            child: _BlockShell(
              block:      block,
              isSelected: isSelected,
              isHovered:  isHovered,
              primary:    primary,
              secondary:  secondary,
              onDelete:   onDelete,
              onToggle:   onToggle,
              onMoveUp:   onMoveUp,
              onMoveDown: onMoveDown,
              onChanged:  onChanged,
            ),
          ),
        ),

        // ── Add-block insertion row ────────────────────────────────────────
        MouseRegion(
          onEnter: (_) => onAddRowHover(index),
          onExit:  (_) => onAddRowHover(null),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: isAddRowHovered || isSelected ? 1.0 : 0.0,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: _AddBlockRow(
                onTap: onAddBlockBelow,
                primary: primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BLOCK SHELL — outer chrome (selection ring, toolbar, visibility badge)
// ══════════════════════════════════════════════════════════════════════════════

class _BlockShell extends StatelessWidget {
  final WebBlock          block;
  final bool              isSelected;
  final bool              isHovered;
  final Color             primary;
  final Color             secondary;
  final VoidCallback      onDelete;
  final VoidCallback      onToggle;
  final VoidCallback?     onMoveUp;
  final VoidCallback?     onMoveDown;
  final VoidCallback      onChanged;

  const _BlockShell({
    required this.block,      required this.isSelected,
    required this.isHovered,  required this.primary,
    required this.secondary,  required this.onDelete,
    required this.onToggle,   this.onMoveUp,
    this.onMoveDown,          required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accent     = _accentFor(block.type);
    final showChrome = isSelected || isHovered;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 2, 32, 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: block.isVisible ? Colors.white : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? primary
                : showChrome
                    ? primary.withValues(alpha: 0.45)
                    : Colors.transparent,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: showChrome
              ? [BoxShadow(
                  color: primary.withValues(alpha: 0.10),
                  blurRadius: 12, offset: const Offset(0, 3))]
              : [const BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Top toolbar — animates open inside block bounds ──────────
            AnimatedSize(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: showChrome
                  ? Container(
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF3F4F8),
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFDDE1EA)),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _BlockToolbar(
                        block:      block,
                        accent:     accent,
                        primary:    primary,
                        onDelete:   onDelete,
                        onToggle:   onToggle,
                        onMoveUp:   onMoveUp,
                        onMoveDown: onMoveDown,
                      ),
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),

            // ── Block preview body ───────────────────────────────────────
            Stack(
              children: [
                Opacity(
                  opacity: block.isVisible ? 1.0 : 0.45,
                  child: _BlockPreview(
                    block:     block,
                    primary:   primary,
                    secondary: secondary,
                    onChanged: onChanged,
                  ),
                ),

                // ── Hidden badge ─────────────────────────────────────────
                if (!block.isVisible)
                  Positioned(
                    top: 8, right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.visibility_off_outlined,
                            size: 11, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text('Hidden',
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500)),
                      ]),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BLOCK TOOLBAR (floats above the selected/hovered block)
// ══════════════════════════════════════════════════════════════════════════════

class _BlockToolbar extends StatelessWidget {
  final WebBlock      block;
  final Color         accent;
  final Color         primary;
  final VoidCallback  onDelete;
  final VoidCallback  onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _BlockToolbar({
    required this.block,     required this.accent,
    required this.primary,   required this.onDelete,
    required this.onToggle,  this.onMoveUp, this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Block type label pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_blockIcons[block.type] ?? Icons.widgets,
                size: 12, color: Colors.white),
            const SizedBox(width: 5),
            Text(blockTypeLabels[block.type] ?? 'Block',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ]),
        ),

        // Action buttons
        Row(mainAxisSize: MainAxisSize.min, children: [
          _ToolbarBtn(
            icon: Icons.arrow_upward,
            tooltip: 'Move up',
            onTap: onMoveUp,
          ),
          const SizedBox(width: 3),
          _ToolbarBtn(
            icon: Icons.arrow_downward,
            tooltip: 'Move down',
            onTap: onMoveDown,
          ),
          const SizedBox(width: 3),
          _ToolbarBtn(
            icon: block.isVisible
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            tooltip: block.isVisible ? 'Hide block' : 'Show block',
            onTap: onToggle,
          ),
          const SizedBox(width: 3),
          _ToolbarBtn(
            icon: Icons.delete_outline,
            tooltip: 'Delete block',
            onTap: onDelete,
            danger: true,
          ),
        ]),
      ],
    );
  }
}

class _ToolbarBtn extends StatelessWidget {
  final IconData     icon;
  final String       tooltip;
  final VoidCallback? onTap;
  final bool         danger;

  const _ToolbarBtn({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFDDE1EA)),
          ),
          child: Icon(
            icon,
            size: 14,
            color: !enabled
                ? Colors.grey.shade300
                : danger
                    ? const Color(0xFFA32D2D)
                    : const Color(0xFF374151),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ADD BLOCK ROW (dashed separator between blocks)
// ══════════════════════════════════════════════════════════════════════════════

class _AddBlockRow extends StatelessWidget {
  final VoidCallback onTap;
  final Color primary;
  const _AddBlockRow({required this.onTap, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 28,
          decoration: BoxDecoration(
            border: Border.all(
                color: primary.withValues(alpha: 0.35), width: 1.5,
                style: BorderStyle.solid /* dashed not directly supported */),
            borderRadius: BorderRadius.circular(6),
            color: primary.withValues(alpha: 0.04),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 14, color: primary),
              const SizedBox(width: 6),
              Text('Add block here',
                  style: TextStyle(
                      fontSize: 11, color: primary,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BLOCK PREVIEW — visual representations of each BlockType
// ══════════════════════════════════════════════════════════════════════════════

class _BlockPreview extends StatelessWidget {
  final WebBlock      block;
  final Color         primary;
  final Color         secondary;
  final VoidCallback  onChanged;

  const _BlockPreview({
    required this.block,     required this.primary,
    required this.secondary, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return switch (block.type) {
      BlockType.hero         => _HeroPreview(block: block, primary: primary, secondary: secondary),
      BlockType.about        => _AboutPreview(block: block, primary: primary),
      BlockType.services     => _ServicesPreview(block: block, primary: primary, secondary: secondary),
      BlockType.events       => _EventsPreview(block: block, primary: primary),
      BlockType.team         => _TeamPreview(block: block, primary: primary),
      BlockType.sermon       => _SermonPreview(block: block, primary: primary),
      BlockType.contact      => _ContactPreview(block: block, primary: primary, secondary: secondary),
      BlockType.map          => _MapPreview(block: block, primary: primary),
      BlockType.gallery      => _GalleryPreview(block: block, primary: primary),
      BlockType.announcement => _AnnouncementPreview(block: block),
      BlockType.divider      => _DividerPreview(block: block),
      BlockType.richText     => _RichTextPreview(block: block, primary: primary),
      BlockType.cta          => _CtaPreview(block: block, primary: primary, secondary: secondary),
    };
  }
}

// ── Hero ───────────────────────────────────────────────────────────────────────

class _HeroPreview extends StatelessWidget {
  final WebBlock block;
  final Color primary, secondary;
  const _HeroPreview({required this.block, required this.primary, required this.secondary});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary,
            primary.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (block.heading.isNotEmpty)
            Text(block.heading,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold,
                    color: Colors.white, height: 1.2)),
          if (block.subheading.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(block.subheading,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: Colors.white.withValues(alpha: 0.85))),
          ],
          if (block.buttonText.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: secondary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(block.buttonText,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: _textDark)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── About ──────────────────────────────────────────────────────────────────────

class _AboutPreview extends StatelessWidget {
  final WebBlock block;
  final Color primary;
  const _AboutPreview({required this.block, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Decorative accent bar
          Container(
            width: 4, height: 80,
            decoration: BoxDecoration(
              color: primary, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 18),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (block.heading.isNotEmpty)
                Text(block.heading,
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold,
                        color: _textDark)),
              if (block.body.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(block.body,
                    style: const TextStyle(
                        fontSize: 13, color: _textMid, height: 1.6),
                    maxLines: 4, overflow: TextOverflow.ellipsis),
              ],
            ],
          )),
        ],
      ),
    );
  }
}

// ── Service Times ──────────────────────────────────────────────────────────────

class _ServicesPreview extends StatelessWidget {
  final WebBlock block;
  final Color primary, secondary;
  const _ServicesPreview({required this.block, required this.primary, required this.secondary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      color: _surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (block.heading.isNotEmpty)
          Text(block.heading,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: _textDark)),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10, runSpacing: 10,
          children: block.serviceTimes.isEmpty
              ? [_ServiceChip(day: 'Sunday', time: '10:00 AM', primary: primary)]
              : block.serviceTimes.map((st) =>
                  _ServiceChip(day: st.day, time: st.time, primary: primary)).toList(),
        ),
      ]),
    );
  }
}

class _ServiceChip extends StatelessWidget {
  final String day, time;
  final Color primary;
  const _ServiceChip({required this.day, required this.time, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primary.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(day, style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: primary, letterSpacing: 0.3)),
        const SizedBox(height: 2),
        Text(time, style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.bold, color: _textDark)),
      ]),
    );
  }
}

// ── Events ─────────────────────────────────────────────────────────────────────

class _EventsPreview extends StatelessWidget {
  final WebBlock block;
  final Color primary;
  const _EventsPreview({required this.block, required this.primary});

  @override
  Widget build(BuildContext context) {
    final events = block.events.isEmpty
        ? [WebEvent(title: 'Sunday Service', date: 'Sun 15', time: '10:00 AM')]
        : block.events.take(3).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (block.heading.isNotEmpty)
          Text(block.heading,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: _textDark)),
        const SizedBox(height: 14),
        ...events.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (e.date.isNotEmpty)
                    Text(e.date.split(' ').last,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold,
                            color: primary))
                  else
                    Icon(Icons.event, size: 20, color: primary),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: _textDark)),
                if (e.time.isNotEmpty)
                  Text(e.time,
                      style: const TextStyle(fontSize: 12, color: _textMid)),
              ],
            )),
          ]),
        )),
      ]),
    );
  }
}

// ── Team ───────────────────────────────────────────────────────────────────────

class _TeamPreview extends StatelessWidget {
  final WebBlock block;
  final Color primary;
  const _TeamPreview({required this.block, required this.primary});

  @override
  Widget build(BuildContext context) {
    final members = block.team.isEmpty
        ? [WebTeamMember(name: 'Pastor Name', role: 'Lead Pastor')]
        : block.team.take(4).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (block.heading.isNotEmpty)
          Text(block.heading,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: _textDark)),
        const SizedBox(height: 16),
        Row(
          children: members.map((m) => Expanded(
            child: Column(children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: primary.withValues(alpha: 0.15),
                child: Text(
                  m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: primary),
                ),
              ),
              const SizedBox(height: 8),
              Text(m.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: _textDark)),
              if (m.role.isNotEmpty)
                Text(m.role,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: _textMid)),
            ]),
          )).toList(),
        ),
      ]),
    );
  }
}

// ── Sermon ─────────────────────────────────────────────────────────────────────

class _SermonPreview extends StatelessWidget {
  final WebBlock block;
  final Color primary;
  const _SermonPreview({required this.block, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      color: _surface,
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: primary, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.menu_book, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (block.heading.isNotEmpty)
              Text(block.heading,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold,
                      color: _textDark)),
            if (block.subheading.isNotEmpty)
              Text(block.subheading,
                  style: TextStyle(
                      fontSize: 12, color: primary,
                      fontWeight: FontWeight.w500)),
            if (block.body.isNotEmpty)
              Text(block.body,
                  style: const TextStyle(
                      fontSize: 12, color: _textMid,
                      fontStyle: FontStyle.italic),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        )),
      ]),
    );
  }
}

// ── Contact ────────────────────────────────────────────────────────────────────

class _ContactPreview extends StatelessWidget {
  final WebBlock block;
  final Color primary, secondary;
  const _ContactPreview({required this.block, required this.primary, required this.secondary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      color: primary,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (block.heading.isNotEmpty)
          Text(block.heading,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold,
                  color: Colors.white)),
        if (block.subheading.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(block.subheading,
              style: TextStyle(
                  fontSize: 13, color: Colors.white.withValues(alpha: 0.8))),
        ],
        const SizedBox(height: 16),
        // Mock form fields
        _MockInput(label: 'Your name'),
        const SizedBox(height: 8),
        _MockInput(label: 'Email address'),
        const SizedBox(height: 8),
        _MockInput(label: 'Message', tall: true),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: secondary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(block.buttonText.isNotEmpty ? block.buttonText : 'Send Message',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: _textDark)),
        ),
      ]),
    );
  }
}

class _MockInput extends StatelessWidget {
  final String label;
  final bool tall;
  const _MockInput({required this.label, this.tall = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: tall ? 64 : 36,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      alignment: Alignment.centerLeft,
      child: Text(label,
          style: TextStyle(
              fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
    );
  }
}

// ── Map ────────────────────────────────────────────────────────────────────────

class _MapPreview extends StatelessWidget {
  final WebBlock block;
  final Color primary;
  const _MapPreview({required this.block, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      width: double.infinity,
      color: const Color(0xFFE8F0E4),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Stylised map grid
          CustomPaint(size: Size.infinite, painter: _MapGridPainter()),
          // Pin
          Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Text(
                block.mapAddress.isNotEmpty
                    ? block.mapAddress
                    : block.heading.isNotEmpty ? block.heading : 'Church Location',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: _textDark),
              ),
            ),
            const SizedBox(height: 4),
            Icon(Icons.location_on, size: 28, color: primary),
          ]),
          // Provider badge
          Positioned(
            bottom: 8, right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _border),
              ),
              child: Text(mapProviderLabels[block.mapProvider] ?? 'Map',
                  style: const TextStyle(fontSize: 9, color: _textMid)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCDD8C6)
      ..strokeWidth = 1;
    // Horizontal roads
    for (double y = 20; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // Vertical roads
    for (double x = 40; x < size.width; x += 50) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // Block fills
    final blockPaint = Paint()..color = const Color(0xFFD9E4D4);
    canvas.drawRect(const Rect.fromLTWH(50, 30, 80, 40), blockPaint);
    canvas.drawRect(const Rect.fromLTWH(150, 55, 60, 35), blockPaint);
    canvas.drawRect(const Rect.fromLTWH(220, 20, 90, 50), blockPaint);
  }

  @override bool shouldRepaint(_) => false;
}

// ── Gallery ────────────────────────────────────────────────────────────────────

class _GalleryPreview extends StatelessWidget {
  final WebBlock block;
  final Color primary;
  const _GalleryPreview({required this.block, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (block.heading.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(block.heading,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: _textDark)),
          ),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 6, mainAxisSpacing: 6,
          children: List.generate(6, (i) => Container(
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.08 + (i * 0.03)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(Icons.image_outlined,
                size: 24, color: primary.withValues(alpha: 0.4)),
          )),
        ),
      ]),
    );
  }
}

// ── Announcement ───────────────────────────────────────────────────────────────

class _AnnouncementPreview extends StatelessWidget {
  final WebBlock block;
  const _AnnouncementPreview({required this.block});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    try {
      final hex = block.announcementColor.replaceFirst('#', '');
      bgColor = Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      bgColor = const Color(0xFFD4A843);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: bgColor,
      child: Row(children: [
        const Icon(Icons.campaign, color: Colors.white, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (block.heading.isNotEmpty)
              Text(block.heading,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold,
                      color: Colors.white)),
            if (block.body.isNotEmpty)
              Text(block.body,
                  style: TextStyle(
                      fontSize: 12, color: Colors.white.withValues(alpha: 0.9)),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        )),
      ]),
    );
  }
}

// ── Divider ────────────────────────────────────────────────────────────────────

class _DividerPreview extends StatelessWidget {
  final WebBlock block;
  const _DividerPreview({required this.block});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      child: switch (block.dividerStyle) {
        'wave' => CustomPaint(
            size: const Size(double.infinity, 24),
            painter: _WavePainter(),
          ),
        'cross' => const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.add, size: 18, color: _textMid),
              ),
              Expanded(child: Divider()),
            ],
          ),
        _ => const Divider(color: _border, thickness: 1),
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path();
    path.moveTo(0, size.height / 2);
    for (double x = 0; x < size.width; x += 20) {
      path.quadraticBezierTo(x + 5, 0, x + 10, size.height / 2);
      path.quadraticBezierTo(x + 15, size.height, x + 20, size.height / 2);
    }
    canvas.drawPath(path, paint);
  }

  @override bool shouldRepaint(_) => false;
}

// ── Rich Text ──────────────────────────────────────────────────────────────────

class _RichTextPreview extends StatelessWidget {
  final WebBlock block;
  final Color primary;
  const _RichTextPreview({required this.block, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (block.heading.isNotEmpty) ...[
          Text(block.heading,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: _textDark)),
          const SizedBox(height: 8),
        ],
        if (block.body.isNotEmpty)
          Text(block.body,
              style: const TextStyle(
                  fontSize: 13, color: _textMid, height: 1.7),
              maxLines: 5, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

// ── CTA ────────────────────────────────────────────────────────────────────────

class _CtaPreview extends StatelessWidget {
  final WebBlock block;
  final Color primary, secondary;
  const _CtaPreview({required this.block, required this.primary, required this.secondary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      color: _surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (block.heading.isNotEmpty)
            Text(block.heading,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold,
                    color: _textDark)),
          if (block.subheading.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(block.subheading,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: _textMid)),
          ],
          if (block.buttonText.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(block.buttonText,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ADD BLOCK DIALOG
// ══════════════════════════════════════════════════════════════════════════════

class _AddBlockDialog extends StatefulWidget {
  final Color primary;
  const _AddBlockDialog({required this.primary});

  @override
  State<_AddBlockDialog> createState() => _AddBlockDialogState();
}

class _AddBlockDialogState extends State<_AddBlockDialog> {
  static const _groups = [
    ('Layout',  [BlockType.hero, BlockType.cta, BlockType.divider]),
    ('Content', [BlockType.about, BlockType.richText, BlockType.announcement]),
    ('Church',  [BlockType.services, BlockType.events, BlockType.sermon,
                 BlockType.team, BlockType.contact, BlockType.map, BlockType.gallery]),
  ];

  BlockType? _hovered;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(children: [
                Icon(Icons.add_box_outlined, size: 20, color: widget.primary),
                const SizedBox(width: 8),
                Text('Add a block',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold,
                        color: widget.primary)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  color: _textMid,
                ),
              ]),
            ),
            const Divider(height: 1, color: _border),
            // Groups
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _groups.map((g) {
                    final (label, types) = g;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 8),
                          child: Text(label,
                              style: const TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w700,
                                  color: _textMid, letterSpacing: 0.8)),
                        ),
                        GridView.count(
                          crossAxisCount: 3,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 8, mainAxisSpacing: 8,
                          childAspectRatio: 2.6,
                          children: types.map((t) => _BlockTypeChip(
                            type:      t,
                            primary:   widget.primary,
                            isHovered: _hovered == t,
                            onHover:   (h) => setState(() => _hovered = h ? t : null),
                            onTap:     () => Navigator.pop(context, t),
                          )).toList(),
                        ),
                        const SizedBox(height: 8),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockTypeChip extends StatelessWidget {
  final BlockType type;
  final Color primary;
  final bool isHovered;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  const _BlockTypeChip({
    required this.type, required this.primary, required this.isHovered,
    required this.onHover, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(type);
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit:  (_) => onHover(false),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: isHovered
                ? accent.withValues(alpha: 0.08)
                : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isHovered ? accent : _border,
              width: isHovered ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(children: [
              Icon(_blockIcons[type] ?? Icons.widgets,
                  size: 14, color: isHovered ? accent : _textMid),
              const SizedBox(width: 6),
              Expanded(
                child: Text(blockTypeLabels[type] ?? '',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w500,
                        color: isHovered ? accent : _textDark),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// EMPTY CANVAS
// ══════════════════════════════════════════════════════════════════════════════

class _EmptyCanvas extends StatelessWidget {
  final Color primary;
  const _EmptyCanvas({required this.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE8EAF0),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: primary.withValues(alpha: 0.25), width: 2,
                  style: BorderStyle.solid),
            ),
            child: Icon(Icons.add_box_outlined,
                size: 36, color: primary.withValues(alpha: 0.4)),
          ),
          const SizedBox(height: 16),
          Text('This page is empty',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold,
                  color: primary.withValues(alpha: 0.6))),
          const SizedBox(height: 6),
          const Text('Add your first block from the panel on the left',
              style: TextStyle(fontSize: 13, color: _textMid)),
        ]),
      ),
    );
  }
}