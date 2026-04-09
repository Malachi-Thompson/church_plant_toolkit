// lib/screens/church_profile_screen.dart
//
// Full-page church profile viewer.
// • Opens as a regular route (Navigator.push) from the dashboard banner button.
// • Top-right "Edit" button navigates to SetupScreen(editMode: true).
// • All fields are read-only here — editing happens entirely in SetupScreen.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/church_profile.dart';
import '../theme.dart';
import 'setup_screen.dart';

class ChurchProfileScreen extends StatelessWidget {
  const ChurchProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state     = context.watch<AppState>();
    final profile   = state.churchProfile;
    if (profile == null) return const SizedBox.shrink();

    final primary   = state.brandPrimary;
    final secondary = state.brandSecondary;
    final onPrimary = contrastOn(primary);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: primary,
            foregroundColor: onPrimary,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: onPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              // Edit button — top right
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const SetupScreen(editMode: true))),
                  icon: Icon(Icons.edit_outlined, size: 16, color: onPrimary),
                  label: Text('Edit',
                      style: TextStyle(
                          color: onPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  style: TextButton.styleFrom(
                    backgroundColor: onPrimary.withValues(alpha: 0.12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primary,
                      Color.lerp(primary, Colors.black, 0.40)!,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Logo
                        _ProfileLogo(
                          logoPath:  profile.logoPath,
                          primary:   primary,
                          secondary: secondary,
                          size:      72,
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.name.isNotEmpty
                                    ? profile.name
                                    : 'Church Name',
                                style: TextStyle(
                                    color: onPrimary,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    height: 1.2),
                              ),
                              if (profile.tagline.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(profile.tagline,
                                    style: TextStyle(
                                        color: onPrimary.withValues(alpha: 0.75),
                                        fontSize: 13,
                                        fontStyle: FontStyle.italic)),
                              ],
                              if (profile.city.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(children: [
                                  Icon(Icons.location_on_outlined,
                                      size: 12,
                                      color: onPrimary.withValues(alpha: 0.6)),
                                  const SizedBox(width: 4),
                                  Text(
                                    [
                                      profile.city,
                                      if (profile.state.isNotEmpty) profile.state,
                                      if (profile.country.isNotEmpty &&
                                          profile.country != 'United States')
                                        profile.country,
                                    ].join(', '),
                                    style: TextStyle(
                                        color: onPrimary.withValues(alpha: 0.6),
                                        fontSize: 12),
                                  ),
                                ]),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Body ────────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  // ── At-a-glance chips ──────────────────────────────────────
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (profile.leadPastorName.isNotEmpty)
                      _Chip(
                          icon: Icons.person_outline,
                          label: profile.leadPastorName,
                          color: primary),
                    if (profile.denomination.isNotEmpty)
                      _Chip(
                          icon: Icons.account_balance_outlined,
                          label: profile.denomination,
                          color: primary),
                    if (profile.plantingYear.isNotEmpty)
                      _Chip(
                          icon: Icons.calendar_today_outlined,
                          label: 'Est. ${profile.plantingYear}',
                          color: primary),
                  ]),

                  // ── Mission statement ──────────────────────────────────────
                  if (profile.missionStatement.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _Section(
                      title: 'Mission Statement',
                      icon: Icons.format_quote_rounded,
                      color: primary,
                      child: Text(
                        profile.missionStatement,
                        style: const TextStyle(
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            height: 1.6,
                            color: textDark),
                      ),
                    ),
                  ],

                  // ── Vision ────────────────────────────────────────────────
                  if (profile.vision.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _Section(
                      title: 'Vision',
                      icon: Icons.visibility_outlined,
                      color: primary,
                      child: Text(
                        profile.vision,
                        style: const TextStyle(
                            fontSize: 14, height: 1.6, color: textDark),
                      ),
                    ),
                  ],

                  // ── Contact info ──────────────────────────────────────────
                  if (profile.email.isNotEmpty ||
                      profile.phone.isNotEmpty ||
                      profile.website.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _Section(
                      title: 'Contact',
                      icon: Icons.contact_mail_outlined,
                      color: primary,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (profile.email.isNotEmpty)
                            _ContactRow(
                                icon: Icons.email_outlined,
                                text: profile.email,
                                color: primary),
                          if (profile.phone.isNotEmpty)
                            _ContactRow(
                                icon: Icons.phone_outlined,
                                text: profile.phone,
                                color: primary),
                          if (profile.website.isNotEmpty)
                            _ContactRow(
                                icon: Icons.language_outlined,
                                text: profile.website,
                                color: primary),
                        ],
                      ),
                    ),
                  ],

                  // ── Branding preview ──────────────────────────────────────
                  const SizedBox(height: 16),
                  _Section(
                    title: 'Branding',
                    icon: Icons.palette_outlined,
                    color: primary,
                    child: Row(children: [
                      _ColorSwatch(
                          label: 'Primary',
                          color: primary),
                      const SizedBox(width: 16),
                      _ColorSwatch(
                          label: 'Accent',
                          color: secondary),
                    ]),
                  ),

                  // ── Installed apps ────────────────────────────────────────
                  if (profile.installedApps.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _Section(
                      title: 'Installed Apps',
                      icon: Icons.apps_outlined,
                      color: primary,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: profile.installedApps.map((id) {
                          final def = availableApps
                              .where((a) => a.id == id)
                              .firstOrNull;
                          return _Chip(
                            icon: _AppCard._appIconFor(id),
                            label: def?.title ?? id,
                            color: secondary,
                          );
                        }).toList(),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── LOGO ─────────────────────────────────────────────────────────────────────

class _ProfileLogo extends StatelessWidget {
  final String logoPath;
  final Color  primary;
  final Color  secondary;
  final double size;

  const _ProfileLogo({
    required this.logoPath,
    required this.primary,
    required this.secondary,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final hasLogo = logoPath.isNotEmpty && File(logoPath).existsSync();
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: secondary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: hasLogo
          ? Image.file(File(logoPath), fit: BoxFit.cover)
          : Icon(Icons.church, color: contrastOn(secondary), size: size * 0.5),
    );
  }
}

// ── SECTION CARD ─────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String  title;
  final IconData icon;
  final Color   color;
  final Widget  child;

  const _Section({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 7),
            Text(title,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                    letterSpacing: 0.8)),
          ]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── CONTACT ROW ──────────────────────────────────────────────────────────────

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String   text;
  final Color    color;

  const _ContactRow({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 16, color: color.withValues(alpha: 0.6)),
      const SizedBox(width: 10),
      Expanded(
        child: Text(text,
            style: const TextStyle(fontSize: 13, color: textDark),
            overflow: TextOverflow.ellipsis),
      ),
    ]),
  );
}

// ── CHIP ─────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;

  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color.withValues(alpha: 0.8)),
      const SizedBox(width: 6),
      Text(label,
          style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600)),
    ]),
  );
}

// ── COLOR SWATCH ─────────────────────────────────────────────────────────────

class _ColorSwatch extends StatelessWidget {
  final String label;
  final Color  color;

  const _ColorSwatch({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 2)),
            ]),
      ),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: textMid, fontWeight: FontWeight.w600)),
        Text(
          '#${color.r.round().toRadixString(16).padLeft(2, '0')}'
          '${color.g.round().toRadixString(16).padLeft(2, '0')}'
          '${color.b.round().toRadixString(16).padLeft(2, '0')}'
              .toUpperCase(),
          style: const TextStyle(fontSize: 11, color: textDark,
              fontWeight: FontWeight.bold),
        ),
      ]),
    ],
  );
}

// ── APP ICON HELPER (duplicated minimally to avoid cross-file private access) ─

class _AppCard {
  static IconData _appIconFor(String id) {
    const icons = <String, IconData>{
      'notes':         Icons.note_alt_rounded,
      'bible':         Icons.menu_book_rounded,
      'website':       Icons.language_rounded,
      'presentation':  Icons.present_to_all_rounded,
      'media_toolkit': Icons.perm_media_rounded,
      'bulletin':      Icons.article_rounded,
      'newsletter':    Icons.newspaper_rounded,
      'directory':     Icons.people_rounded,
    };
    return icons[id] ?? Icons.apps;
  }
}