// lib/screens/admin_screen.dart
//
// Master Account & Settings Lock
//
// Three modes depending on state:
//   1. No PIN set       → "Set up Master Account" wizard
//   2. PIN set, locked  → PIN entry unlock screen
//   3. PIN set, unlocked → Full admin panel
//
// Admin panel sections:
//   • Lock / Unlock settings toggle
//   • Change / Remove PIN
//   • Export church profile (JSON)
//   • Import church profile (JSON)
//   • Reset all data (danger zone)

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../theme.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (!state.hasAdminPin) {
      return const _SetupPinScreen();
    }
    if (state.isAdminLocked) {
      return const _UnlockScreen();
    }
    return const _AdminPanel();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 1. SET UP PIN SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class _SetupPinScreen extends StatefulWidget {
  const _SetupPinScreen();

  @override
  State<_SetupPinScreen> createState() => _SetupPinScreenState();
}

class _SetupPinScreenState extends State<_SetupPinScreen> {
  final _pinCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;
  String _error  = '';

  @override
  void dispose() {
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin     = _pinCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'PIN must be at least 4 characters.');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'PINs do not match.');
      return;
    }
    await context.read<AppState>().setAdminPin(pin);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Master account created!')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = context.watch<AppState>().brandPrimary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Up Master Account'),
        backgroundColor: primary,
        foregroundColor: contrastOn(primary),
      ),
      body: Center(
        child: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon + title
                Center(
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.admin_panel_settings_outlined,
                        color: primary, size: 36),
                  ),
                ),
                const SizedBox(height: 20),
                Center(child: Text('Create a Master Account',
                    style: TextStyle(fontSize: 20,
                        fontWeight: FontWeight.bold, color: primary))),
                const SizedBox(height: 8),
                const Center(child: Text(
                  'Set a PIN to protect church settings.\nOthers can still use the apps normally.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: textMid),
                )),
                const SizedBox(height: 32),

                // What gets locked info box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: primary.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('What the lock protects:',
                          style: TextStyle(fontSize: 12,
                              fontWeight: FontWeight.bold, color: primary)),
                      const SizedBox(height: 8),
                      ...[
                        'Edit Church Profile',
                        'Add / Remove Apps',
                        'Reset All Data',
                        'Bible Translation Setting',
                        'Admin & Export Settings',
                      ].map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(children: [
                          Icon(Icons.lock_outline,
                              size: 13, color: primary),
                          const SizedBox(width: 6),
                          Text(item, style: const TextStyle(
                              fontSize: 12, color: textDark)),
                        ]),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // PIN fields
                TextField(
                  controller: _pinCtrl,
                  obscureText: _obscure1,
                  keyboardType: TextInputType.number,
                  inputFormatters: [LengthLimitingTextInputFormatter(12)],
                  decoration: InputDecoration(
                    labelText: 'Create PIN',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure1
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscure1 = !_obscure1),
                    ),
                  ),
                  onChanged: (_) => setState(() => _error = ''),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmCtrl,
                  obscureText: _obscure2,
                  keyboardType: TextInputType.number,
                  inputFormatters: [LengthLimitingTextInputFormatter(12)],
                  decoration: InputDecoration(
                    labelText: 'Confirm PIN',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure2
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscure2 = !_obscure2),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_error,
                      style: const TextStyle(
                          color: Colors.red, fontSize: 12)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: contrastOn(primary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Create Master Account'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 2. UNLOCK SCREEN (PIN entry)
// ══════════════════════════════════════════════════════════════════════════════

class _UnlockScreen extends StatefulWidget {
  const _UnlockScreen();

  @override
  State<_UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<_UnlockScreen> {
  final _pinCtrl = TextEditingController();
  bool  _obscure = true;
  String _error  = '';
  int   _attempts = 0;

  @override
  void dispose() { _pinCtrl.dispose(); super.dispose(); }

  void _tryUnlock() {
    final state = context.read<AppState>();
    if (state.verifyPin(_pinCtrl.text.trim())) {
      state.unlockAdmin();
      // Stay on screen — AdminScreen will rebuild to AdminPanel
    } else {
      _attempts++;
      setState(() {
        _error = _attempts >= 3
            ? 'Incorrect PIN. $_attempts failed attempts.'
            : 'Incorrect PIN. Please try again.';
        _pinCtrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = context.watch<AppState>().brandPrimary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Settings'),
        backgroundColor: primary,
        foregroundColor: contrastOn(primary),
      ),
      body: Center(
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outlined,
                    color: primary, size: 36),
              ),
              const SizedBox(height: 20),
              Text('Settings are locked',
                  style: TextStyle(fontSize: 20,
                      fontWeight: FontWeight.bold, color: primary)),
              const SizedBox(height: 8),
              const Text('Enter the admin PIN to access settings.',
                  style: TextStyle(fontSize: 13, color: textMid)),
              const SizedBox(height: 28),
              TextField(
                controller: _pinCtrl,
                obscureText: _obscure,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Admin PIN',
                  border: const OutlineInputBorder(),
                  errorText: _error.isNotEmpty ? _error : null,
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscure = !_obscure),
                  ),
                ),
                onSubmitted: (_) => _tryUnlock(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _tryUnlock,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: contrastOn(primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Unlock'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 3. ADMIN PANEL (unlocked)
// ══════════════════════════════════════════════════════════════════════════════

class _AdminPanel extends StatelessWidget {
  const _AdminPanel();

  @override
  Widget build(BuildContext context) {
    final state     = context.watch<AppState>();
    final primary   = state.brandPrimary;
    final secondary = state.brandSecondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Settings'),
        backgroundColor: primary,
        foregroundColor: contrastOn(primary),
        actions: [
          // Quick lock button in app bar
          if (state.hasAdminPin && state.isAdminUnlocked)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () {
                  state.lockAdmin();
                  Navigator.pop(context);
                },
                icon: Icon(Icons.lock_outline,
                    color: contrastOn(primary), size: 18),
                label: Text('Lock Now',
                    style: TextStyle(color: contrastOn(primary))),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [

          // ── Status banner ────────────────────────────────────────────────
          _StatusBanner(state: state, primary: primary, secondary: secondary),
          const SizedBox(height: 24),

          // ── Lock Settings section ────────────────────────────────────────
          _SectionHeader(title: 'Settings Lock', primary: primary),
          _AdminTile(
            icon: state.isAdminLocked
                ? Icons.lock_outlined
                : Icons.lock_open_outlined,
            iconColor: state.isAdminLocked
                ? Colors.red.shade700
                : Colors.green.shade700,
            title: state.isAdminLocked
                ? 'Settings are Locked'
                : 'Settings are Unlocked',
            subtitle: state.isAdminLocked
                ? 'Users cannot access church settings or manage apps.'
                : 'Turn on to prevent others from changing church settings.',
            trailing: Switch(
              value: state.adminLockEnabled,
              activeColor: primary,
              onChanged: (v) => state.setAdminLockEnabled(v),
            ),
          ),
          const SizedBox(height: 8),
          _AdminTile(
            icon: Icons.pin_outlined,
            iconColor: primary,
            title: 'Change PIN',
            subtitle: 'Update the master account PIN.',
            onTap: () => _showChangePinDialog(context, state, primary),
          ),
          _AdminTile(
            icon: Icons.no_encryption_gmailerrorred_outlined,
            iconColor: Colors.orange.shade700,
            title: 'Remove PIN',
            subtitle: 'Disables the master account and unlocks all settings permanently.',
            onTap: () => _confirmRemovePin(context, state, primary),
          ),
          const SizedBox(height: 24),

          // ── Profile Export/Import section ────────────────────────────────
          _SectionHeader(title: 'Profile Export & Import', primary: primary),
          _AdminTile(
            icon: Icons.upload_file_outlined,
            iconColor: const Color(0xFF1565C0),
            title: 'Export Church Profile',
            subtitle: 'Save your church settings as a .json file to share or back up.',
            onTap: () => _exportProfile(context, state),
          ),
          _AdminTile(
            icon: Icons.download_outlined,
            iconColor: const Color(0xFF2E7D32),
            title: 'Import Church Profile',
            subtitle: 'Load a previously exported .json profile on this device.',
            onTap: () => _importProfile(context, state),
          ),
          const SizedBox(height: 24),

          // ── Danger zone ──────────────────────────────────────────────────
          _SectionHeader(title: 'Danger Zone', primary: Colors.red.shade700),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.red.shade200),
              borderRadius: BorderRadius.circular(10),
            ),
            child: _AdminTile(
              icon: Icons.delete_forever_outlined,
              iconColor: Colors.red.shade700,
              title: 'Reset All Data',
              subtitle: 'Permanently deletes church profile, logo, and all app data.',
              onTap: () => _confirmReset(context, state),
            ),
          ),
        ],
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _exportProfile(
      BuildContext context, AppState state) async {
    final path = await state.exportProfile();
    if (!context.mounted) return;
    if (path != null) {
      _showInfo(context, 'Profile Exported',
          'Saved to:\n$path\n\nShare this file to set up another device.');
    } else {
      _showError(context, 'Export failed. No profile found.');
    }
  }

  Future<void> _importProfile(
      BuildContext context, AppState state) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import Church Profile',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return;
    final error = await state.importProfile(result.files.single.path!);
    if (!context.mounted) return;
    if (error == null) {
      _showInfo(context, 'Profile Imported',
          'Church profile loaded successfully.');
    } else {
      _showError(context, error);
    }
  }

  Future<void> _showChangePinDialog(
      BuildContext context, AppState state, Color primary) async {
    final oldCtrl  = TextEditingController();
    final newCtrl  = TextEditingController();
    final confCtrl = TextEditingController();
    String error   = '';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Text('Change PIN',
              style: TextStyle(color: primary)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: oldCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Current PIN',
                  border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: newCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'New PIN (min 4 digits)',
                  border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Confirm New PIN',
                  border: OutlineInputBorder(), isDense: true),
            ),
            if (error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(error,
                  style: const TextStyle(
                      color: Colors.red, fontSize: 12)),
            ],
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (!state.verifyPin(oldCtrl.text.trim())) {
                  setS(() => error = 'Current PIN is incorrect.');
                  return;
                }
                if (newCtrl.text.trim().length < 4) {
                  setS(() => error = 'New PIN must be at least 4 digits.');
                  return;
                }
                if (newCtrl.text.trim() != confCtrl.text.trim()) {
                  setS(() => error = 'New PINs do not match.');
                  return;
                }
                state.setAdminPin(newCtrl.text.trim());
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN updated.')));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: contrastOn(primary),
              ),
              child: const Text('Update PIN'),
            ),
          ],
        ),
      ),
    );
    oldCtrl.dispose();
    newCtrl.dispose();
    confCtrl.dispose();
  }

  Future<void> _confirmRemovePin(
      BuildContext context, AppState state, Color primary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove PIN?'),
        content: const Text(
          'This will disable the master account and allow anyone to '
          'change church settings. Are you sure?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700),
            child: const Text('Remove PIN'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await state.removeAdminPin();
      if (context.mounted) Navigator.pop(context);
    }
  }

  Future<void> _confirmReset(
      BuildContext context, AppState state) async {
    final pinCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Reset All Data?',
            style: TextStyle(color: Colors.red)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'This permanently deletes ALL data including the church '
            'profile, logo, and all app data. This cannot be undone.\n\n'
            'Enter your admin PIN to confirm.'),
          const SizedBox(height: 12),
          TextField(
            controller: pinCtrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Admin PIN',
                border: OutlineInputBorder(), isDense: true),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (state.verifyPin(pinCtrl.text.trim())) {
                Navigator.pop(ctx, true);
              } else {
                Navigator.pop(ctx, false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Incorrect PIN. Reset cancelled.')));
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700),
            child: const Text('Reset Everything'),
          ),
        ],
      ),
    );
    pinCtrl.dispose();
    if (confirmed == true && context.mounted) {
      await state.resetSetup();
    }
  }

  void _showInfo(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK')),
        ],
      ),
    );
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _StatusBanner extends StatelessWidget {
  final AppState state;
  final Color    primary;
  final Color    secondary;
  const _StatusBanner({
    required this.state,
    required this.primary,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final locked = state.adminLockEnabled;
    final color  = locked ? Colors.red.shade700 : Colors.green.shade700;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(locked ? Icons.lock_outlined : Icons.lock_open_outlined,
            color: color, size: 28),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              locked ? 'Settings Lock is ON' : 'Settings Lock is OFF',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: color),
            ),
            Text(
              locked
                  ? 'Users cannot edit settings or manage apps without the PIN.'
                  : 'Anyone can edit church settings. Enable the lock to protect them.',
              style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8)),
            ),
          ],
        )),
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color  primary;
  const _SectionHeader({required this.title, required this.primary});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title.toUpperCase(),
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: primary,
            letterSpacing: 1.2)),
  );
}

class _AdminTile extends StatelessWidget {
  final IconData    icon;
  final Color       iconColor;
  final String      title;
  final String      subtitle;
  final VoidCallback? onTap;
  final Widget?     trailing;

  const _AdminTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(
        horizontal: 12, vertical: 4),
    leading: Container(
      width: 42, height: 42,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: iconColor, size: 22),
    ),
    title: Text(title,
        style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: textDark)),
    subtitle: Text(subtitle,
        style: const TextStyle(fontSize: 12, color: textMid)),
    trailing: trailing ??
        (onTap != null
            ? const Icon(Icons.chevron_right, color: textMid)
            : null),
    onTap: onTap,
  );
}