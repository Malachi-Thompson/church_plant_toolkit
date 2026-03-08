// lib/apps/presentation/presentation_screen.dart
//
// This screen is now STATELESS with respect to presentation data.
// All deck/slide/save state lives in PresentationState (a ChangeNotifier
// provided above the navigator), so it survives every navigation hop.
//
// The screen only owns:
//   • UI-only timers (none needed now)
//   • Dialogs / snackbars

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_state.dart';
import '../../models/church_profile.dart';
import '../../theme.dart';

import 'models/presentation_models.dart';       // ← Deck, StreamSettings, etc.
import 'models/presentation_state.dart';
import 'dialogs/stream_setup_dialog.dart';
import 'dialogs/record_setup_dialog.dart';
import 'dialogs/verse_picker_dialog.dart';
import 'dialogs/deck_properties_dialog.dart';
import 'widgets/presentation_widgets.dart';
import 'views/presentations_home.dart';
import 'views/deck_editor_view.dart';
import 'views/present_view.dart';

class PresentationScreen extends StatelessWidget {
  const PresentationScreen({super.key});

  // ── Dialogs / actions that need a BuildContext ─────────────────────────────

  Future<void> _promptCreateDeck(
      BuildContext context, PresentationState ps) async {
    final ctrl   = TextEditingController(text: 'New Presentation');
    final result = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Name your presentation'),
        content: TextField(
          controller:         ctrl,
          autofocus:          true,
          decoration: const InputDecoration(
            labelText: 'Presentation name',
            border:    OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(dctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
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
    final updated = await showDeckPropertiesDialog(
      context,
      deck:    deck,
      primary: state.brandPrimary,
    );
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
    final slide = await showVersePickerDialog(
      context,
      primary:   state.brandPrimary,
      secondary: state.brandSecondary,
    );
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
          controller: ctrl,
          autofocus:  true,
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state     = context.watch<AppState>();
    final primary   = state.brandPrimary;
    final secondary = state.brandSecondary;
    final profile   = state.churchProfile;

    final ps = context.watch<PresentationState>();

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
                  if (ps.saveStatus != SaveStatus.saved) {
                    await ps.flushSave();
                  }
                  ps.closeOpenDeck();
                },
              )
            : null,
        title: Row(
          children: [
            if (profile != null) ...[
              ChurchLogo(
                logoPath:     profile.logoPath,
                primary:      primary,
                secondary:    secondary,
                size:         32,
                borderRadius: 8,
              ),
              const SizedBox(width: 10),
            ],
            if (ps.openDeck != null)
              Flexible(
                child: GestureDetector(
                  onTap: () => _promptRenameDeckInline(context, ps),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(ps.openDeck!.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.edit_rounded,
                          size: 15,
                          color: contrastOn(primary).withValues(alpha: 0.55)),
                    ],
                  ),
                ),
              )
            else
              const Text('Presentation Studio',
                  style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          if (ps.openDeck != null)
            _SaveIndicator(
              status:    ps.saveStatus,
              lastSaved: ps.lastSaved,
              primary:   primary,
              onSave:    ps.saveStatus == SaveStatus.unsaved
                  ? ps.flushSave : null,
            ),
          if (ps.openDeck != null)
            IconButton(
              icon:    const Icon(Icons.info_outline_rounded),
              tooltip: 'Presentation Properties',
              color:   contrastOn(primary).withValues(alpha: 0.80),
              onPressed: () => _showProperties(context, ps, ps.openDeck!),
            ),
          if (ps.isRecording)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                child: LiveBadge(label: 'REC', color: Colors.red)),
          if (ps.isStreaming)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                child: LiveBadge(label: 'LIVE', color: Colors.green)),
          if (ps.openDeck != null)
            TextButton.icon(
              onPressed: () => ps.setPresenting(true),
              icon:  Icon(Icons.slideshow, color: contrastOn(primary)),
              label: Text('Present',
                  style: TextStyle(color: contrastOn(primary))),
            ),
          if (ps.openDeck == null)
            IconButton(
              icon:    const Icon(Icons.add),
              tooltip: 'New Presentation',
              onPressed: () => _promptCreateDeck(context, ps),
            ),
        ],
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
            ),
    );
  }
}

// ── Save indicator widget ──────────────────────────────────────────────────────
class _SaveIndicator extends StatelessWidget {
  final SaveStatus    status;
  final DateTime?     lastSaved;
  final Color         primary;
  final VoidCallback? onSave;

  const _SaveIndicator({
    required this.status,
    required this.primary,
    required this.lastSaved,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final fg        = contrastOn(primary);
    final isUnsaved = status == SaveStatus.unsaved;
    final isSaving  = status == SaveStatus.saving;

    final label = switch (status) {
      SaveStatus.saved   => 'Saved',
      SaveStatus.saving  => 'Saving…',
      SaveStatus.unsaved => 'Unsaved',
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSaving)
                SizedBox(width: 14, height: 14,
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
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize:   11,
                      color:      isUnsaved
                          ? Colors.orangeAccent
                          : fg.withValues(alpha: 0.80),
                      fontWeight: isUnsaved
                          ? FontWeight.bold : FontWeight.normal)),
              if (isUnsaved) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color:        Colors.orangeAccent.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(5),
                    border:       Border.all(
                        color: Colors.orangeAccent.withValues(alpha: 0.55)),
                  ),
                  child: const Text('Save now',
                      style: TextStyle(
                          fontSize: 9, color: Colors.orangeAccent,
                          fontWeight: FontWeight.bold)),
                ),
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
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}