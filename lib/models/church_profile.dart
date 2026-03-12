// lib/models/church_profile.dart
import 'package:flutter/material.dart';
// Add this import at the top of church_profile.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class ChurchProfile {
  final String name;
  final String tagline;
  final String denomination;
  final String city;
  final String state;
  final String country;
  final String website;
  final String email;
  final String phone;
  final String leadPastorName;
  final String plantingYear;
  final String vision;
  final String missionStatement;
  final List<String> installedApps;

  // Branding
  final String primaryColorHex;
  final String secondaryColorHex;
  final String logoPath;

  // Bible preference — master translation used across all apps
  final String bibleTranslationId;

  ChurchProfile({
    required this.name,
    required this.tagline,
    required this.denomination,
    required this.city,
    required this.state,
    required this.country,
    required this.website,
    required this.email,
    required this.phone,
    required this.leadPastorName,
    required this.plantingYear,
    required this.vision,
    required this.missionStatement,
    required this.installedApps,
    this.primaryColorHex    = '#1A3A5C',
    this.secondaryColorHex  = '#D4A843',
    this.logoPath           = '',
    this.bibleTranslationId = 'BSB',
  });

  Color get primaryColor  => _hexToColor(primaryColorHex);
  Color get secondaryColor => _hexToColor(secondaryColorHex);

  static Color _hexToColor(String hex) {
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return const Color(0xFF1A3A5C);
  }

  ChurchProfile copyWith({
    String? name,
    String? tagline,
    String? denomination,
    String? city,
    String? state,
    String? country,
    String? website,
    String? email,
    String? phone,
    String? leadPastorName,
    String? plantingYear,
    String? vision,
    String? missionStatement,
    List<String>? installedApps,
    String? primaryColorHex,
    String? secondaryColorHex,
    String? logoPath,
    String? bibleTranslationId,
  }) {
    return ChurchProfile(
      name:               name              ?? this.name,
      tagline:            tagline           ?? this.tagline,
      denomination:       denomination      ?? this.denomination,
      city:               city              ?? this.city,
      state:              state             ?? this.state,
      country:            country           ?? this.country,
      website:            website           ?? this.website,
      email:              email             ?? this.email,
      phone:              phone             ?? this.phone,
      leadPastorName:     leadPastorName    ?? this.leadPastorName,
      plantingYear:       plantingYear      ?? this.plantingYear,
      vision:             vision            ?? this.vision,
      missionStatement:   missionStatement  ?? this.missionStatement,
      installedApps:      installedApps     ?? this.installedApps,
      primaryColorHex:    primaryColorHex   ?? this.primaryColorHex,
      secondaryColorHex:  secondaryColorHex ?? this.secondaryColorHex,
      logoPath:           logoPath          ?? this.logoPath,
      bibleTranslationId: bibleTranslationId ?? this.bibleTranslationId,
    );
  }

  Map<String, dynamic> toJson() => {
    'name':               name,
    'tagline':            tagline,
    'denomination':       denomination,
    'city':               city,
    'state':              state,
    'country':            country,
    'website':            website,
    'email':              email,
    'phone':              phone,
    'leadPastorName':     leadPastorName,
    'plantingYear':       plantingYear,
    'vision':             vision,
    'missionStatement':   missionStatement,
    'installedApps':      installedApps,
    'primaryColorHex':    primaryColorHex,
    'secondaryColorHex':  secondaryColorHex,
    'logoPath':           logoPath,
    'bibleTranslationId': bibleTranslationId,
  };

  factory ChurchProfile.fromJson(Map<String, dynamic> json) => ChurchProfile(
    name:               json['name']              ?? '',
    tagline:            json['tagline']           ?? '',
    denomination:       json['denomination']      ?? '',
    city:               json['city']              ?? '',
    state:              json['state']             ?? '',
    country:            json['country']           ?? '',
    website:            json['website']           ?? '',
    email:              json['email']             ?? '',
    phone:              json['phone']             ?? '',
    leadPastorName:     json['leadPastorName']    ?? '',
    plantingYear:       json['plantingYear']      ?? '',
    vision:             json['vision']            ?? '',
    missionStatement:   json['missionStatement']  ?? '',
    installedApps:      List<String>.from(json['installedApps'] ?? []),
    primaryColorHex:    json['primaryColorHex']   ?? '#1A3A5C',
    secondaryColorHex:  json['secondaryColorHex'] ?? '#D4A843',
    logoPath:           json['logoPath']          ?? '',
    bibleTranslationId: json['bibleTranslationId'] ?? 'BSB',
  );

  factory ChurchProfile.empty() => ChurchProfile(
    name: '', tagline: '', denomination: '', city: '', state: '',
    country: '', website: '', email: '', phone: '', leadPastorName: '',
    plantingYear: '', vision: '', missionStatement: '',
    installedApps: [],
    primaryColorHex: '#1A3A5C', secondaryColorHex: '#D4A843',
    logoPath: '', bibleTranslationId: 'BSB',
  );
}

class AppDefinition {
  final String id;
  final String title;
  final String description;
  final String iconPath;
  final String category;

  const AppDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.iconPath,
    required this.category,
  });
}

const List<AppDefinition> availableApps = [
  AppDefinition(
    id: 'notes',
    title: 'Master Notes',
    description: 'Organize sermons, meeting notes, prayer requests, and ministry ideas.',
    iconPath: 'notes',
    category: 'Productivity',
  ),
  AppDefinition(
    id: 'bible',
    title: 'Bible Reader',
    description: 'Read 1,000+ translations. Powered by the Free Use Bible API — no account needed.',
    iconPath: 'bible',
    category: 'Scripture',
  ),
  AppDefinition(
    id: 'website',
    title: 'Website Builder',
    description: 'Build and manage your church website with pages, events, and announcements.',
    iconPath: 'web',
    category: 'Communication',
  ),
  AppDefinition(
    id: 'presentation',
    title: 'Presentation Studio',
    description: 'Create worship slides and presentations with live streaming and recording support.',
    iconPath: 'present_to_all',
    category: 'Worship',
  ),
  AppDefinition(
    id: 'media_toolkit',
    title: 'Media Toolkit',
    description: 'Generate branded social media graphics, export your color palette, and convert images with your logo.',
    iconPath: 'palette',
    category: 'Branding',
  ),
  AppDefinition(
    id: 'bulletin',
    title: 'Bulletin Maker',
    description: 'Design and print weekly church bulletins with custom layouts, sermon notes, and announcements.',
    iconPath: 'article',
    category: 'Communication',
  ),
  AppDefinition(
    id: 'newsletter',
    title: 'Newsletter Builder',
    description: 'Compose church newsletters with announcements, sermon recaps, events, and scripture. Export as PDF or email-ready HTML.',
    iconPath: 'newspaper',
    category: 'Communication',
  ),
  AppDefinition(
    id: 'directory',
    title: 'Member Directory',
    description: 'Track members, visitors, and families. Record contact info, baptism dates, join dates, and export a printable directory.',
    iconPath: 'people',
    category: 'Pastoral',
  ),
];
// ── CHURCH LOGO WIDGET ────────────────────────────────────────────────────────
class ChurchLogo extends StatelessWidget {
  final String logoPath;
  final Color  primary;
  final Color  secondary;
  final double size;
  final double borderRadius;

  const ChurchLogo({
    super.key,
    required this.logoPath,
    required this.primary,
    required this.secondary,
    this.size         = 40,
    this.borderRadius = 10,
  });

  @override
  Widget build(BuildContext context) {
    final hasLogo = logoPath.isNotEmpty;

    return Container(
      width:  size,
      height: size,
      decoration: BoxDecoration(
        color:        secondary.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(borderRadius),
        border:       Border.all(
          color: secondary.withValues(alpha: 0.50),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasLogo
          ? _logoImage()
          : Icon(Icons.church, color: secondary, size: size * 0.55),
    );
  }

  Widget _logoImage() {
    if (kIsWeb) {
      return Image.network(
        logoPath,
        fit:         BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.church, color: secondary, size: size * 0.55),
      );
    }
    return Image.file(
      File(logoPath),
      fit:         BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.church, color: secondary, size: size * 0.55),
    );
  }
}