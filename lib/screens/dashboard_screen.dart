// lib/screens/dashboard_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/church_profile.dart';
import '../theme.dart';
import '../apps/bible/bible_screen.dart';
import '../apps/notes/notes_screen.dart';
import '../apps/website/website_screen.dart';
import '../apps/presentation/presentation_screen.dart';
import '../services/bible_service.dart';
import 'setup_screen.dart';
import '../apps/media_toolkit/media_toolkit_screen.dart';
import '../apps/bulletin/bulletin_screen.dart';
import '../apps/newsletter/newsletter_screen.dart';
import '../apps/directory/directory_screen.dart';
import 'admin_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  void _openApp(BuildContext context, String appId) {
    Widget screen;
    switch (appId) {
      case 'notes':       screen = const NotesScreen(); break;
      case 'bible':       screen = const BibleScreen(); break;
      case 'website':     screen = const WebsiteScreen(); break;
      case 'presentation':screen = const PresentationScreen(); break;
      case 'media_toolkit':screen = const MediaToolkitScreen(); break;
      case 'bulletin':     screen = const BulletinScreen(); break;
      case 'newsletter':   screen = const NewsletterScreen(); break;
      case 'directory':    screen = const DirectoryScreen(); break;
      default: return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _removeApp(
      BuildContext context, String appId, String appName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove App?'),
        content: Text('Remove "$appName" from your dashboard?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<AppState>().removeApp(appId);
    }
  }

  Future<void> _showAddAppDialog(BuildContext context) async {
    final state     = context.read<AppState>();
    final primary   = state.brandPrimary;
    final installed = state.churchProfile?.installedApps ?? [];
    final available = availableApps.where((a) => !installed.contains(a.id)).toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All available apps are already installed!')));
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add App'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: available.map((app) => ListTile(
              leading: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.apps, color: primary),
              ),
              title: Text(app.title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(app.description,
                  style: const TextStyle(fontSize: 12)),
              trailing: ElevatedButton(
                onPressed: () {
                  context.read<AppState>().installApp(app.id);
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: contrastOn(primary),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('Add'),
              ),
            )).toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
        ],
      ),
    );
  }

  void _openSettings(BuildContext context, AppState state) {
    if (state.isAdminLocked) {
      // Tapping settings while locked → go straight to admin unlock
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AdminScreen()));
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SettingsSheet(state: state),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state   = context.watch<AppState>();
    final profile = state.churchProfile;
    if (profile == null) return const SizedBox();

    final primary   = state.brandPrimary;
    final secondary = state.brandSecondary;
    final installed = availableApps
        .where((a) => profile.installedApps.contains(a.id))
        .toList();
    final allInstalled = installed.length == availableApps.length;
    final locked = state.isAdminLocked;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildBanner(context, profile, state, primary, secondary),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  const Text('Your Apps',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold,
                          color: textDark)),
                  const Spacer(),
                  Text('${installed.length} installed',
                      style: const TextStyle(color: textMid, fontSize: 14)),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  // Show Add App card only if there are uninstalled apps
                  // and settings are not locked
                  if (!allInstalled && !locked && index == installed.length) {
                    return _AddAppCard(
                        color: primary,
                        onTap: () => _showAddAppDialog(context));
                  }
                  if (index >= installed.length) return null;
                  final app = installed[index];
                  return _AppCard(
                    app: app,
                    primary:   primary,
                    secondary: secondary,
                    locked:    locked,
                    onOpen:   () => _openApp(context, app.id),
                    onRemove: () => _removeApp(context, app.id, app.title),
                  );
                },
                childCount: allInstalled || locked
                    ? installed.length
                    : installed.length + 1,
              ),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 360,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.9,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildBanner(BuildContext context, ChurchProfile profile,
      AppState state, Color primary, Color secondary) {
    final onPrimary = contrastOn(primary);
    return SliverToBoxAdapter(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 36, 20, 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [primary, Color.lerp(primary, Colors.black, 0.35)!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo or icon
                _ChurchLogo(
                  logoPath: profile.logoPath,
                  primary:  primary,
                  secondary: secondary,
                  size: 64,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.name,
                          style: TextStyle(
                              color: onPrimary, fontSize: 24,
                              fontWeight: FontWeight.bold)),
                      if (profile.tagline.isNotEmpty)
                        Text(profile.tagline,
                            style: TextStyle(
                                color: onPrimary.withValues(alpha: 0.72),
                                fontSize: 13)),
                      if (profile.city.isNotEmpty)
                        Text('${profile.city}, ${profile.state}',
                            style: TextStyle(
                                color: onPrimary.withValues(alpha: 0.55),
                                fontSize: 12)),
                    ],
                  ),
                ),
                // Edit & settings icons
                _BannerIconBtn(
                  icon: Icons.edit_outlined,
                  tooltip: 'Edit Church Profile',
                  onPrimary: onPrimary,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SetupScreen(editMode: true))),
                ),
                const SizedBox(width: 4),
                _BannerIconBtn(
                  icon: Icons.settings_outlined,
                  tooltip: 'Settings',
                  onPrimary: onPrimary,
                  onTap: () => _openSettings(context, state),
                ),
              ],
            ),
            if (profile.missionStatement.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: onPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: onPrimary.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.format_quote,
                        color: secondary, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(profile.missionStatement,
                          style: TextStyle(
                              color: onPrimary.withValues(alpha: 0.88),
                              fontSize: 13,
                              fontStyle: FontStyle.italic)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                if (profile.leadPastorName.isNotEmpty)
                  _InfoChip(
                      icon: Icons.person_outline,
                      label: profile.leadPastorName,
                      onPrimary: onPrimary),
                if (profile.denomination.isNotEmpty)
                  _InfoChip(
                      icon: Icons.account_balance,
                      label: profile.denomination,
                      onPrimary: onPrimary),
                if (profile.plantingYear.isNotEmpty)
                  _InfoChip(
                      icon: Icons.calendar_today,
                      label: 'Est. ${profile.plantingYear}',
                      onPrimary: onPrimary),
                if (profile.email.isNotEmpty)
                  _InfoChip(
                      icon: Icons.email_outlined,
                      label: profile.email,
                      onPrimary: onPrimary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── CHURCH LOGO WIDGET ────────────────────────────────────────────────────────
class ChurchLogo extends StatefulWidget {
  final String logoPath;
  final Color primary;
  final Color secondary;
  final double size;
  final double borderRadius;

  const ChurchLogo({
    super.key,
    required this.logoPath,
    required this.primary,
    required this.secondary,
    this.size = 48,
    this.borderRadius = 12,
  });

  @override
  State<ChurchLogo> createState() => _ChurchLogoState();
}

class _ChurchLogoState extends State<ChurchLogo> {
  @override
  void didUpdateWidget(ChurchLogo old) {
    super.didUpdateWidget(old);
    // When the logo path changes, evict both the old and new entries from the
    // image cache so Flutter always decodes the freshly saved file.
    if (old.logoPath != widget.logoPath) {
      if (old.logoPath.isNotEmpty) {
        FileImage(File(old.logoPath)).evict();
      }
      if (widget.logoPath.isNotEmpty) {
        FileImage(File(widget.logoPath)).evict();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final logoPath     = widget.logoPath;
    final secondary    = widget.secondary;
    final size         = widget.size;
    final borderRadius = widget.borderRadius;

    return Container(
      width:  size,
      height: size,
      decoration: BoxDecoration(
        color: secondary,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
              color: secondary.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: logoPath.isNotEmpty && File(logoPath).existsSync()
          ? Image.file(
              File(logoPath),
              key: ValueKey(logoPath),
              fit: BoxFit.cover,
            )
          : Icon(Icons.church,
              color: contrastOn(secondary), size: size * 0.55),
    );
  }
}

// Private alias for use inside this file
class _ChurchLogo extends ChurchLogo {
  const _ChurchLogo({
    required super.logoPath,
    required super.primary,
    required super.secondary,
    super.size,
  });
}

// ── BANNER ICON BUTTON ────────────────────────────────────────────────────────
class _BannerIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color onPrimary;
  final VoidCallback onTap;

  const _BannerIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: onPrimary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: onPrimary.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, color: onPrimary, size: 20),
        ),
      ),
    );
  }
}

// ── INFO CHIP ─────────────────────────────────────────────────────────────────
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color onPrimary;
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: onPrimary.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: onPrimary.withValues(alpha: 0.75)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(color: onPrimary, fontSize: 12)),
        ],
      ),
    );
  }
}

// ── SETTINGS BOTTOM SHEET ─────────────────────────────────────────────────────
class _SettingsSheet extends StatelessWidget {
  final AppState state;
  const _SettingsSheet({required this.state});

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Fixed header (never scrolls) ───────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                        color: const Color(0xFFDDDDDD),
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const Text('Settings',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold,
                        color: textDark)),
                const SizedBox(height: 20),
              ],
            ),
          ),
          // ── Scrollable tiles ───────────────────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
          _SettingsTile(
            icon: Icons.edit_outlined,
            iconColor: state.brandPrimary,
            title: 'Edit Church Profile',
            subtitle: 'Update name, logo, colors, contact info, and more',
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SetupScreen(editMode: true)));
            },
          ),
          const Divider(height: 1),
          _BibleTranslationTile(state: state),
          const Divider(height: 1),
          _SettingsTile(
            icon: Icons.admin_panel_settings_outlined,
            iconColor: const Color(0xFF6A1B9A),
            title: 'Admin & Master Account',
            subtitle: state.hasAdminPin
                ? 'Manage PIN, settings lock, export/import profile'
                : 'Set up a PIN to protect church settings',
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminScreen()));
            },
          ),
          const Divider(height: 1),
          _SettingsTile(
            icon: Icons.info_outline,
            iconColor: const Color(0xFF1565C0),
            title: 'About Church Plant Toolkit',
            subtitle: 'Version 1.0.0 MVP',
            onTap: () {
              Navigator.pop(context);
              showAboutDialog(
                context: context,
                applicationName: 'Church Plant Toolkit',
                applicationVersion: '1.0.0',
                applicationIcon: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                      color: state.brandPrimary,
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.church,
                      color: contrastOn(state.brandPrimary), size: 28),
                ),
                children: const [
                  Text('A suite of tools built to help church planters manage ministry.'),
                ],
              );
            },
          ),
          const Divider(height: 1),
          _SettingsTile(
            icon: Icons.refresh,
            iconColor: Colors.orange.shade700,
            title: 'Reset All Data',
            subtitle: 'Clear everything and restart setup',
            onTap: () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: const Text('Reset All Data?'),
                  content: const Text(
                      'This will permanently delete your church profile, logo, and all app data.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        state.resetSetup();
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700),
                      child: const Text('Reset Everything'),
                    ),
                  ],
                ),
              );
            },
          ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── BIBLE TRANSLATION SETTINGS TILE ──────────────────────────────────────────
class _BibleTranslationTile extends StatelessWidget {
  final AppState state;
  const _BibleTranslationTile({required this.state});

  @override
  Widget build(BuildContext context) {
    final svc     = context.watch<BibleService>();
    final primary = state.brandPrimary;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      leading: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.menu_book_outlined,
            color: Color(0xFF2E7D32), size: 22),
      ),
      title: const Text('Bible Translation',
          style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 15, color: textDark)),
      subtitle: Text(
        svc.availableTranslations.isNotEmpty
            ? svc.availableTranslations
                .firstWhere((t) => t.id == svc.translationId,
                    orElse: () => svc.availableTranslations.first)
                .name
            : svc.translationId,
        style: const TextStyle(fontSize: 12, color: textMid),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(svc.translationId,
                style: const TextStyle(
                    color: Color(0xFF2E7D32),
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: textMid),
        ],
      ),
      onTap: () async {
        Navigator.pop(context);
        // Load translations in background while sheet opens
        svc.fetchTranslations();
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => ChangeNotifierProvider<BibleService>.value(
            value: svc,
            child: TranslationPickerSheet(
              service: svc,
              primary: primary,
              onPicked: (id) async {
                await state.updateBibleTranslation(id);
              },
            ),
          ),
        );
      },
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon, required this.iconColor,
    required this.title, required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
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
              fontWeight: FontWeight.w600, fontSize: 15, color: textDark)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: textMid)),
      trailing: const Icon(Icons.chevron_right, color: textMid),
      onTap: onTap,
    );
  }
}

// ── APP CARD ──────────────────────────────────────────────────────────────────
class _AppCard extends StatelessWidget {
  final AppDefinition app;
  final Color primary;
  final Color secondary;
  final bool  locked;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _AppCard({
    required this.app,
    required this.primary,
    required this.secondary,
    required this.locked,
    required this.onOpen,
    required this.onRemove,
  });

  static const _appIcons = {
    'notes':         Icons.note_alt_rounded,
    'bible':         Icons.menu_book_rounded,
    'website':       Icons.language_rounded,
    'presentation':  Icons.present_to_all_rounded,
    'media_toolkit': Icons.perm_media_rounded,
    'bulletin':      Icons.article_rounded,
    'newsletter':    Icons.newspaper_rounded,
    'directory':     Icons.people_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final icon    = _appIcons[app.id] ?? Icons.apps;
    final bgColor = Color.lerp(primary, Colors.white, 0.88)!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: primary, size: 30),
                ),
                const Spacer(),
                if (!locked)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert,
                        color: Colors.grey.shade400, size: 20),
                    onSelected: (v) { if (v == 'remove') onRemove(); },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'remove',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Text('Remove App',
                                style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(app.title,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold, color: textDark)),
            const SizedBox(height: 6),
            Expanded(
              child: Text(app.description,
                  style: const TextStyle(
                      fontSize: 13, color: textMid, height: 1.5),
                  maxLines: 3, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open App'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: contrastOn(primary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── ADD APP CARD ──────────────────────────────────────────────────────────────
class _AddAppCard extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  const _AddAppCard({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: color.withValues(alpha: 0.1),
                child: Icon(Icons.add_rounded, size: 32, color: color),
              ),
              const SizedBox(height: 16),
              Text('Add App',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold,
                      color: color)),
              const SizedBox(height: 6),
              const Text('Browse available tools',
                  style: TextStyle(fontSize: 13, color: textMid)),
            ],
          ),
        ),
      ),
    );
  }
}