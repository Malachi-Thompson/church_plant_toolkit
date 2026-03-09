// lib/apps/presentation/presentation_screen.dart
//
// Responsive shell:
//   • Wide (≥ 600 px)  — original AppBar + two-column editor
//   • Narrow (< 600 px) — compact AppBar, overflow menu, adaptive dialogs
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_state.dart';
import '../../models/church_profile.dart';
import '../../theme.dart';

import 'models/presentation_models.dart';
import 'models/presentation_state.dart';
import 'dialogs/stream_setup_dialog.dart';
import 'dialogs/record_setup_dialog.dart';
import 'dialogs/verse_picker_dialog.dart';
import 'dialogs/deck_properties_dialog.dart';
import 'widgets/presentation_widgets.dart';
import 'views/presentations_home.dart';
import 'views/deck_editor_view.dart';
import 'views/slide_editor_view.dart' show slideStyleChoices;
import 'views/present_view.dart';

class PresentationScreen extends StatelessWidget {
  const PresentationScreen({super.key});

  // ── Dialogs ──────────────────────────────────────────────────────────────

  Future<void> _promptCreateDeck(
      BuildContext context, PresentationState ps) async {
    final ctrl   = TextEditingController(text: 'New Presentation');
    final result = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Name your presentation'),
        content: TextField(
          controller: ctrl, autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Presentation name',
              border:    OutlineInputBorder()),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(dctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx),
              child: const Text('Skip')),
          ElevatedButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    ctrl.dispose();
    if (!context.mounted) return;
    await ps.createDeck(result ?? '');
  }

  Future<void> _promptRename(
      BuildContext context, PresentationState ps, Deck deck) async {
    final newName = await showRenameDeckDialog(context, deck.name);
    if (newName == null || newName == deck.name || !context.mounted) return;
    await ps.renameDeck(deck, newName);
  }

  Future<void> _confirmDeleteDeck(
      BuildContext context, PresentationState ps, Deck deck) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Delete Presentation?'),
        content: Text('Delete "${deck.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (ok == true && context.mounted) await ps.deleteDeck(deck);
  }

  Future<void> _showProperties(
      BuildContext context, PresentationState ps, Deck deck) async {
    final state   = context.read<AppState>();
    final updated = await showDeckPropertiesDialog(context,
        deck: deck, primary: state.brandPrimary);
    if (updated == null || !context.mounted) return;
    await ps.updateDeckProperties(updated);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Properties saved'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleImportScripture(
      BuildContext context, PresentationState ps) async {
    if (ps.openDeck == null) return;
    final state = context.read<AppState>();
    final slide = await showVersePickerDialog(context,
        primary: state.brandPrimary, secondary: state.brandSecondary);
    if (slide != null && context.mounted) {
      ps.openDeck!.slides.add(slide);
      ps.selectSlide(slide);
      ps.markDirty();
    }
  }

  Future<void> _handleToggleStream(
      BuildContext context, PresentationState ps) async {
    if (ps.isStreaming) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title:   const Text('Stop Live Stream?'),
          content: const Text('This will end your live stream.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Stop Stream',
                    style: TextStyle(color: Colors.white))),
          ],
        ),
      );
      if (ok == true) {
        ps.stopStream();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Stream ended'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating));
        }
      }
    } else {
      final copy = ps.streamSettings.copyWith();
      final ok   = await showStreamSetupDialog(context, copy);
      if (ok && context.mounted) {
        await ps.saveStreamSettings(copy);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Streaming live to '
                  '${StreamSettings.platformDefaults[copy.platform]!['name']}'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating));
        }
      }
    }
  }

  Future<void> _handleToggleRecord(
      BuildContext context, PresentationState ps) async {
    if (ps.isRecording) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title:   const Text('Stop Recording?'),
          content: const Text('This will save and finalize your recording.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Stop Recording',
                    style: TextStyle(color: Colors.white))),
          ],
        ),
      );
      if (ok == true) {
        ps.stopRecord();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Recording saved'),
              backgroundColor: Colors.blueGrey,
              behavior: SnackBarBehavior.floating));
        }
      }
    } else {
      final copy = ps.recordSettings.copyWith();
      final ok   = await showRecordSetupDialog(context, copy);
      if (ok && context.mounted) {
        await ps.saveRecordSettings(copy);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Recording started'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating));
        }
      }
    }
  }

  Future<void> _promptRenameDeckInline(
      BuildContext context, PresentationState ps) async {
    if (ps.openDeck == null) return;
    final ctrl   = TextEditingController(text: ps.openDeck!.name);
    final result = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Rename presentation'),
        content: TextField(
          controller: ctrl, autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Name', border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(dctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
              child: const Text('Rename')),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result.isNotEmpty && context.mounted) {
      await ps.renameDeck(ps.openDeck!, result);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state     = context.watch<AppState>();
    final primary   = state.brandPrimary;
    final secondary = state.brandSecondary;
    final profile   = state.churchProfile;
    final ps        = context.watch<PresentationState>();
    final isWide    = MediaQuery.of(context).size.width >= 600;

    // ── Loading splash ───────────────────────────────────────────────────────
    if (ps.loading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: primary,
          foregroundColor: contrastOn(primary),
          title: const Text('Presentation Studio',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: primary),
              const SizedBox(height: 16),
              Text('Loading presentations…',
                  style: TextStyle(color: Colors.grey.shade500)),
            ],
          ),
        ),
      );
    }

    // ── Full-screen present mode ─────────────────────────────────────────────
    if (ps.presenting && ps.openDeck != null) {
      return PresentView(
        deck:           ps.openDeck!,
        primary:        primary,
        secondary:      secondary,
        onExit:         () => ps.setPresenting(false),
        isStreaming:    ps.isStreaming,
        isRecording:    ps.isRecording,
        onToggleStream: () => _handleToggleStream(context, ps),
        onToggleRecord: () => _handleToggleRecord(context, ps),
      );
    }

    // ── Build AppBar actions ─────────────────────────────────────────────────
    final List<Widget> actions = [];

    if (ps.openDeck != null) {
      // Save indicator always visible
      actions.add(_SaveIndicator(
        status:    ps.saveStatus,
        lastSaved: ps.lastSaved,
        primary:   primary,
        onSave:    ps.saveStatus == SaveStatus.unsaved ? ps.flushSave : null,
      ));

      if (isWide) {
        // Wide: show individual buttons
        actions.add(IconButton(
          icon:    const Icon(Icons.info_outline_rounded),
          tooltip: 'Presentation Properties',
          color:   contrastOn(primary).withValues(alpha: 0.80),
          onPressed: () => _showProperties(context, ps, ps.openDeck!),
        ));
        if (ps.isRecording)
          actions.add(Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: LiveBadge(label: 'REC', color: Colors.red)));
        if (ps.isStreaming)
          actions.add(Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: LiveBadge(label: 'LIVE', color: Colors.green)));
        actions.add(TextButton.icon(
          onPressed: () => ps.setPresenting(true),
          icon:  Icon(Icons.slideshow, color: contrastOn(primary)),
          label: Text('Present', style: TextStyle(color: contrastOn(primary))),
        ));
      } else {
        // Narrow: compact present button + overflow menu
        if (ps.isRecording)
          actions.add(LiveBadge(label: 'REC', color: Colors.red));
        if (ps.isStreaming)
          actions.add(LiveBadge(label: 'LIVE', color: Colors.green));
        actions.add(IconButton(
          icon:    Icon(Icons.slideshow, color: contrastOn(primary)),
          tooltip: 'Present',
          onPressed: () => ps.setPresenting(true),
        ));
        actions.add(PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: contrastOn(primary)),
          onSelected: (v) {
            switch (v) {
              case 'properties':
                _showProperties(context, ps, ps.openDeck!);
                break;
              case 'stream':
                _handleToggleStream(context, ps);
                break;
              case 'record':
                _handleToggleRecord(context, ps);
                break;
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'properties',
              child: ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Properties'),
                dense: true, contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'stream',
              child: ListTile(
                leading: Icon(Icons.wifi_tethering_rounded,
                    color: ps.isStreaming ? Colors.green : null),
                title: Text(ps.isStreaming ? 'Stop Stream' : 'Go Live'),
                dense: true, contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'record',
              child: ListTile(
                leading: Icon(Icons.fiber_manual_record,
                    color: ps.isRecording ? Colors.red : null),
                title: Text(ps.isRecording ? 'Stop Recording' : 'Record'),
                dense: true, contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ));
      }
    }

    if (ps.openDeck == null) {
      actions.add(IconButton(
        icon:    const Icon(Icons.add),
        tooltip: 'New Presentation',
        onPressed: () => _promptCreateDeck(context, ps),
      ));
    }

    // ── Title widget ─────────────────────────────────────────────────────────
    Widget titleWidget;
    if (ps.openDeck != null) {
      titleWidget = GestureDetector(
        onTap: () => _promptRenameDeckInline(context, ps),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (profile != null && isWide) ...[
              ChurchLogo(
                logoPath: profile.logoPath,
                primary: primary, secondary: secondary,
                size: 30, borderRadius: 7,
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(ps.openDeck!.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            Icon(Icons.edit_rounded, size: 13,
                color: contrastOn(primary).withValues(alpha: 0.55)),
          ],
        ),
      );
    } else {
      titleWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (profile != null) ...[
            ChurchLogo(
              logoPath: profile.logoPath,
              primary: primary, secondary: secondary,
              size: 30, borderRadius: 7,
            ),
            const SizedBox(width: 8),
          ],
          const Text('Presentation Studio',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      );
    }

    // ── Main scaffold ────────────────────────────────────────────────────────
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: contrastOn(primary),
        leading: ps.openDeck != null
            ? IconButton(
                icon:    const Icon(Icons.arrow_back),
                tooltip: 'All Presentations',
                onPressed: () async {
                  if (ps.saveStatus != SaveStatus.saved) await ps.flushSave();
                  ps.closeOpenDeck();
                },
              )
            : IconButton(
                icon:    const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () => Navigator.maybePop(context),
              ),
        title: titleWidget,
        actions: actions,
      ),
      body: ps.openDeck == null
          ? PresentationsHome(
              decks:           ps.decks,
              primary:         primary,
              secondary:       secondary,
              onOpenDeck:      ps.openDeckForEditing,
              onNewDeck:       () => _promptCreateDeck(context, ps),
              onDeleteDeck:    (d) => _confirmDeleteDeck(context, ps, d),
              onRenameDeck:    (d) => _promptRename(context, ps, d),
              onDuplicateDeck: ps.duplicateDeck,
              onProperties:    (d) => _showProperties(context, ps, d),
            )
          : DeckEditorView(
              deck:                    ps.openDeck!,
              selectedSlide:           ps.selectedSlide,
              primary:                 primary,
              secondary:               secondary,
              onSelectSlide:           ps.selectSlide,
              onAddSlide: (t) => ps.addSlide(t, primary: primary),
              onDeleteSlide:           ps.deleteSlide,
              onReorderSlides:         ps.reorderSlides,
              onSlideChanged:          ps.notifySlideChanged,
              onImportScripture: () => _handleImportScripture(context, ps),
              onCreateGroup:           ps.createGroup,
              onUpdateGroup:           ps.updateGroup,
              onDeleteGroup:           ps.deleteGroup,
              onAddSlideToGroup:       ps.addSlideToGroup,
              onRemoveSlideFromGroup:  ps.removeSlideFromGroup,
              onImportCollection:      ps.importCollection,
              onToggleCollection:      ps.toggleCollection,
              onMoveCollection:        ps.moveCollection,
              onRemoveCollection:      ps.removeCollection,
              onReorderCollectionSlide: ps.reorderCollectionSlide,
              onApplyMasterStyle: (master) => ps.applyMasterStyle(
                master, primary, secondary,
                (p, s) => slideStyleChoices(p, s).map(
                  (type, list) => MapEntry(type, list.map((c) => c.style).toList()),
                ),
              ),
              onResetSlideToMaster: ps.selectedSlide != null
                  ? () => ps.resetSlideToMaster(
                        ps.selectedSlide!, primary, secondary,
                        (p, s) => slideStyleChoices(p, s).map(
                          (type, list) => MapEntry(type, list.map((c) => c.style).toList()),
                        ),
                      )
                  : null,
            ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SAVE INDICATOR
// ══════════════════════════════════════════════════════════════════════════════
class _SaveIndicator extends StatelessWidget {
  final SaveStatus    status;
  final DateTime?     lastSaved;
  final Color         primary;
  final VoidCallback? onSave;

  const _SaveIndicator({
    required this.status, required this.primary,
    required this.lastSaved, this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final fg        = contrastOn(primary);
    final isUnsaved = status == SaveStatus.unsaved;
    final isSaving  = status == SaveStatus.saving;
    final isNarrow  = MediaQuery.of(context).size.width < 600;

    final label = switch (status) {
      SaveStatus.saved   => 'Saved',
      SaveStatus.saving  => 'Saving…',
      SaveStatus.unsaved => isNarrow ? '' : 'Unsaved',
    };

    final iconColor = switch (status) {
      SaveStatus.saved   => Colors.greenAccent.shade400,
      SaveStatus.saving  => Colors.white70,
      SaveStatus.unsaved => Colors.orangeAccent,
    };

    return Tooltip(
      message: isSaving
          ? 'Saving…'
          : isUnsaved
              ? 'Tap to save now'
              : lastSaved != null
                  ? 'Last saved ${_timeAgo(lastSaved!)}'
                  : 'Saved',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onSave,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSaving)
                SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fg.withValues(alpha: 0.70)))
              else
                Icon(
                  switch (status) {
                    SaveStatus.saved   => Icons.storage_rounded,
                    SaveStatus.saving  => Icons.sync_rounded,
                    SaveStatus.unsaved => Icons.sync_disabled_rounded,
                  },
                  size: 16, color: iconColor,
                ),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: isUnsaved
                            ? Colors.orangeAccent
                            : fg.withValues(alpha: 0.80),
                        fontWeight: isUnsaved
                            ? FontWeight.bold : FontWeight.normal)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes  < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours    < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}