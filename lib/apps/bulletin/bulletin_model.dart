// lib/apps/bulletin/bulletin_model.dart
//
// Data model for church bulletins.
// Add new fields here and surface them in the editor / exporter.

import 'package:uuid/uuid.dart';

// ── LAYOUT TYPE ───────────────────────────────────────────────────────────────

enum BulletinLayout {
  singlePage,   // One full page — front only
  bifold,       // Letter folded in half → 4 panels
  halfSheet,    // Two half-pages on one letter sheet (2-up)
  trifold,      // Letter folded in thirds → 6 panels
}

const bulletinLayoutLabels = <BulletinLayout, String>{
  BulletinLayout.singlePage: 'Single Page',
  BulletinLayout.bifold:     'Bi-fold (4 panels)',
  BulletinLayout.halfSheet:  'Half-Sheet (2-up)',
  BulletinLayout.trifold:    'Tri-fold (6 panels)',
};

const bulletinLayoutDescriptions = <BulletinLayout, String>{
  BulletinLayout.singlePage: 'One full letter-size page',
  BulletinLayout.bifold:     'Letter folded in half — 4 panels front & back',
  BulletinLayout.halfSheet:  'Two half-sheets printed on one page, cut apart',
  BulletinLayout.trifold:    'Letter folded in thirds — 6 panels',
};

// ── ORDER OF SERVICE ITEM ─────────────────────────────────────────────────────

class ServiceItem {
  String time;    // optional — e.g. "10:15"
  String label;  // e.g. "Worship", "Scripture Reading"
  String detail; // optional — e.g. song title, reader name

  ServiceItem({this.time = '', required this.label, this.detail = ''});

  Map<String, dynamic> toJson() =>
      {'time': time, 'label': label, 'detail': detail};

  factory ServiceItem.fromJson(Map<String, dynamic> j) => ServiceItem(
        time:   j['time']   ?? '',
        label:  j['label']  ?? '',
        detail: j['detail'] ?? '',
      );

  ServiceItem copy() =>
      ServiceItem(time: time, label: label, detail: detail);
}

// ── ANNOUNCEMENT ──────────────────────────────────────────────────────────────

class Announcement {
  String title;
  String body;

  Announcement({required this.title, this.body = ''});

  Map<String, dynamic> toJson() => {'title': title, 'body': body};

  factory Announcement.fromJson(Map<String, dynamic> j) =>
      Announcement(title: j['title'] ?? '', body: j['body'] ?? '');

  Announcement copy() => Announcement(title: title, body: body);
}

// ── BULLETIN MODEL ────────────────────────────────────────────────────────────

class BulletinModel {
  final String id;
  String       title;          // internal name, e.g. "March 16 Bulletin"
  DateTime?    serviceDate;

  // ── Church info (pre-filled from church profile, editable per bulletin)
  String churchName;
  String churchAddress;
  String churchPhone;
  String churchWebsite;
  String churchEmail;
  String logoPath;             // optional — path to church logo

  // ── Sermon / message
  String sermonTitle;
  String speakerName;
  String sermonScripture;
  String sermonSeriesName;

  // ── Sections
  List<ServiceItem>  orderOfService;
  List<Announcement> announcements;
  String             prayerRequests;  // free-form text
  String             sermonNotesPrompt; // printed as lined note-taking area heading
  bool               includeSermonNotes;
  bool               includeContactCard;

  // ── Contact / visitor card (printed at bottom or back)
  String contactCardHeading;  // e.g. "We'd love to connect with you!"

  // ── Layout
  BulletinLayout layout;
  String         accentColor; // hex, e.g. '#1A3A5C' — matches brand

  // ── Metadata
  final DateTime createdAt;
  DateTime       updatedAt;

  BulletinModel({
    required this.id,
    required this.title,
    this.serviceDate,
    this.churchName          = '',
    this.churchAddress       = '',
    this.churchPhone         = '',
    this.churchWebsite       = '',
    this.churchEmail         = '',
    this.logoPath            = '',
    this.sermonTitle         = '',
    this.speakerName         = '',
    this.sermonScripture     = '',
    this.sermonSeriesName    = '',
    List<ServiceItem>?  orderOfService,
    List<Announcement>? announcements,
    this.prayerRequests      = '',
    this.sermonNotesPrompt   = 'Sermon Notes',
    this.includeSermonNotes  = true,
    this.includeContactCard  = true,
    this.contactCardHeading  = "We'd love to connect with you!",
    this.layout              = BulletinLayout.bifold,
    this.accentColor         = '#1A3A5C',
    required this.createdAt,
    required this.updatedAt,
  })  : orderOfService = orderOfService ?? _defaultOrder(),
        announcements  = announcements  ?? [];

  static List<ServiceItem> _defaultOrder() => [
    ServiceItem(label: 'Welcome & Greeting'),
    ServiceItem(label: 'Worship'),
    ServiceItem(label: 'Scripture Reading'),
    ServiceItem(label: 'Message'),
    ServiceItem(label: 'Response / Prayer'),
    ServiceItem(label: 'Offering'),
    ServiceItem(label: 'Closing Song'),
    ServiceItem(label: 'Benediction'),
  ];

  // ── SERIALISATION ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'id':                  id,
    'title':               title,
    'serviceDate':         serviceDate?.toIso8601String(),
    'churchName':          churchName,
    'churchAddress':       churchAddress,
    'churchPhone':         churchPhone,
    'churchWebsite':       churchWebsite,
    'churchEmail':         churchEmail,
    'logoPath':            logoPath,
    'sermonTitle':         sermonTitle,
    'speakerName':         speakerName,
    'sermonScripture':     sermonScripture,
    'sermonSeriesName':    sermonSeriesName,
    'orderOfService':      orderOfService.map((i) => i.toJson()).toList(),
    'announcements':       announcements.map((a) => a.toJson()).toList(),
    'prayerRequests':      prayerRequests,
    'sermonNotesPrompt':   sermonNotesPrompt,
    'includeSermonNotes':  includeSermonNotes,
    'includeContactCard':  includeContactCard,
    'contactCardHeading':  contactCardHeading,
    'layout':              layout.name,
    'accentColor':         accentColor,
    'createdAt':           createdAt.toIso8601String(),
    'updatedAt':           updatedAt.toIso8601String(),
  };

  factory BulletinModel.fromJson(Map<String, dynamic> j) => BulletinModel(
    id:          j['id'] ?? const Uuid().v4(),
    title:       j['title'] ?? 'Untitled Bulletin',
    serviceDate: j['serviceDate'] != null
        ? DateTime.tryParse(j['serviceDate'])
        : null,
    churchName:       j['churchName']       ?? '',
    churchAddress:    j['churchAddress']    ?? '',
    churchPhone:      j['churchPhone']      ?? '',
    churchWebsite:    j['churchWebsite']    ?? '',
    churchEmail:      j['churchEmail']      ?? '',
    logoPath:         j['logoPath']         ?? '',
    sermonTitle:      j['sermonTitle']      ?? '',
    speakerName:      j['speakerName']      ?? '',
    sermonScripture:  j['sermonScripture']  ?? '',
    sermonSeriesName: j['sermonSeriesName'] ?? '',
    orderOfService:   (j['orderOfService'] as List? ?? [])
        .map((e) => ServiceItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    announcements: (j['announcements'] as List? ?? [])
        .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
        .toList(),
    prayerRequests:     j['prayerRequests']     ?? '',
    sermonNotesPrompt:  j['sermonNotesPrompt']  ?? 'Sermon Notes',
    includeSermonNotes: j['includeSermonNotes'] ?? true,
    includeContactCard: j['includeContactCard'] ?? true,
    contactCardHeading: j['contactCardHeading'] ?? "We'd love to connect with you!",
    layout: BulletinLayout.values.firstWhere(
        (l) => l.name == j['layout'],
        orElse: () => BulletinLayout.bifold),
    accentColor: j['accentColor'] ?? '#1A3A5C',
    createdAt:   DateTime.parse(j['createdAt']),
    updatedAt:   DateTime.parse(j['updatedAt']),
  );

  /// Duplicate this bulletin (for "copy last week's" workflow)
  BulletinModel copyForNewWeek() {
    final now  = DateTime.now();
    final next = serviceDate?.add(const Duration(days: 7)) ?? now;
    return BulletinModel(
      id:                  const Uuid().v4(),
      title:               'Bulletin – ${_fmtDate(next)}',
      serviceDate:         next,
      churchName:          churchName,
      churchAddress:       churchAddress,
      churchPhone:         churchPhone,
      churchWebsite:       churchWebsite,
      churchEmail:         churchEmail,
      logoPath:            logoPath,
      sermonTitle:         '',         // clear for new week
      speakerName:         speakerName,
      sermonScripture:     '',
      sermonSeriesName:    sermonSeriesName,
      orderOfService:      orderOfService.map((i) => i.copy()).toList(),
      announcements:       [],          // clear for new week
      prayerRequests:      '',
      sermonNotesPrompt:   sermonNotesPrompt,
      includeSermonNotes:  includeSermonNotes,
      includeContactCard:  includeContactCard,
      contactCardHeading:  contactCardHeading,
      layout:              layout,
      accentColor:         accentColor,
      createdAt:           now,
      updatedAt:           now,
    );
  }

  static String _fmtDate(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}, ${d.year}';
  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];
}