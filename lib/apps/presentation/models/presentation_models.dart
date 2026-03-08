// lib/apps/presentation/models/presentation_models.dart
//
// Core models for Presentation Studio.
// Deck  — a named collection of Slides with metadata.
// Slide — a single presentation slide with full style support.
// Data is persisted in a normalized SQLite DB (one row per slide).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'slide_group.dart';

// ── SLIDE STYLE ───────────────────────────────────────────────────────────────

enum SlideTextAlign { left, center, right }
enum SlideBgFit     { cover, contain, fill }
enum SlideOverlay   { none, crosshatch, dots, diagonal, vignette, grain }

class SlideFont {
  final String name;
  final String fontFamily;
  const SlideFont(this.name, this.fontFamily);
}

const List<SlideFont> kSlideFonts = [
  SlideFont('Default',        'sans-serif'),
  SlideFont('Serif',          'serif'),
  SlideFont('Montserrat',     'Montserrat'),
  SlideFont('Playfair',       'Playfair Display'),
  SlideFont('Lato',           'Lato'),
  SlideFont('Oswald',         'Oswald'),
  SlideFont('Roboto Slab',    'Roboto Slab'),
  SlideFont('Dancing Script', 'Dancing Script'),
];

class SlideStyle {
  String?           bgImagePath;
  SlideBgFit        bgFit;
  double            bgImageOpacity;
  Color             bgTint;
  double            bgTintOpacity;
  SlideOverlay      overlay;
  Color             overlayColor;
  double            overlayOpacity;
  String            fontFamily;
  SlideTextAlign    textAlign;
  double            titleScale;
  double            bodyScale;
  bool              titleBold;
  bool              titleItalic;
  bool              bodyBold;
  bool              bodyItalic;
  double            letterSpacing;
  double            lineHeight;
  bool              textShadow;
  Color             shadowColor;
  double            shadowBlur;
  bool              showTextBox;
  Color             textBoxColor;
  double            textBoxOpacity;
  double            textBoxRadius;
  double            textBoxPaddingH;
  double            textBoxPaddingV;
  bool              useGradient;
  Color             gradientEnd;
  AlignmentGeometry gradientBegin;
  AlignmentGeometry gradientEndAlign;

  SlideStyle({
    this.bgImagePath,
    this.bgFit            = SlideBgFit.cover,
    this.bgImageOpacity   = 1.0,
    this.bgTint           = Colors.black,
    this.bgTintOpacity    = 0.0,
    this.overlay          = SlideOverlay.none,
    this.overlayColor     = Colors.white,
    this.overlayOpacity   = 0.08,
    this.fontFamily       = 'sans-serif',
    this.textAlign        = SlideTextAlign.center,
    this.titleScale       = 1.0,
    this.bodyScale        = 1.0,
    this.titleBold        = true,
    this.titleItalic      = false,
    this.bodyBold         = false,
    this.bodyItalic       = false,
    this.letterSpacing    = 0.0,
    this.lineHeight       = 1.5,
    this.textShadow       = false,
    this.shadowColor      = Colors.black,
    this.shadowBlur       = 4.0,
    this.showTextBox      = false,
    this.textBoxColor     = Colors.black,
    this.textBoxOpacity   = 0.45,
    this.textBoxRadius    = 10.0,
    this.textBoxPaddingH  = 24.0,
    this.textBoxPaddingV  = 16.0,
    this.useGradient      = false,
    this.gradientEnd      = Colors.black,
    this.gradientBegin    = Alignment.topCenter,
    this.gradientEndAlign = Alignment.bottomCenter,
  });

  SlideStyle copyWith({
    String?            bgImagePath,
    bool               clearBgImage = false,
    SlideBgFit?        bgFit,
    double?            bgImageOpacity,
    Color?             bgTint,
    double?            bgTintOpacity,
    SlideOverlay?      overlay,
    Color?             overlayColor,
    double?            overlayOpacity,
    String?            fontFamily,
    SlideTextAlign?    textAlign,
    double?            titleScale,
    double?            bodyScale,
    bool?              titleBold,
    bool?              titleItalic,
    bool?              bodyBold,
    bool?              bodyItalic,
    double?            letterSpacing,
    double?            lineHeight,
    bool?              textShadow,
    Color?             shadowColor,
    double?            shadowBlur,
    bool?              showTextBox,
    Color?             textBoxColor,
    double?            textBoxOpacity,
    double?            textBoxRadius,
    double?            textBoxPaddingH,
    double?            textBoxPaddingV,
    bool?              useGradient,
    Color?             gradientEnd,
    AlignmentGeometry? gradientBegin,
    AlignmentGeometry? gradientEndAlign,
  }) =>
      SlideStyle(
        bgImagePath:      clearBgImage ? null : (bgImagePath ?? this.bgImagePath),
        bgFit:            bgFit            ?? this.bgFit,
        bgImageOpacity:   bgImageOpacity   ?? this.bgImageOpacity,
        bgTint:           bgTint           ?? this.bgTint,
        bgTintOpacity:    bgTintOpacity    ?? this.bgTintOpacity,
        overlay:          overlay          ?? this.overlay,
        overlayColor:     overlayColor     ?? this.overlayColor,
        overlayOpacity:   overlayOpacity   ?? this.overlayOpacity,
        fontFamily:       fontFamily       ?? this.fontFamily,
        textAlign:        textAlign        ?? this.textAlign,
        titleScale:       titleScale       ?? this.titleScale,
        bodyScale:        bodyScale        ?? this.bodyScale,
        titleBold:        titleBold        ?? this.titleBold,
        titleItalic:      titleItalic      ?? this.titleItalic,
        bodyBold:         bodyBold         ?? this.bodyBold,
        bodyItalic:       bodyItalic       ?? this.bodyItalic,
        letterSpacing:    letterSpacing    ?? this.letterSpacing,
        lineHeight:       lineHeight       ?? this.lineHeight,
        textShadow:       textShadow       ?? this.textShadow,
        shadowColor:      shadowColor      ?? this.shadowColor,
        shadowBlur:       shadowBlur       ?? this.shadowBlur,
        showTextBox:      showTextBox      ?? this.showTextBox,
        textBoxColor:     textBoxColor     ?? this.textBoxColor,
        textBoxOpacity:   textBoxOpacity   ?? this.textBoxOpacity,
        textBoxRadius:    textBoxRadius    ?? this.textBoxRadius,
        textBoxPaddingH:  textBoxPaddingH  ?? this.textBoxPaddingH,
        textBoxPaddingV:  textBoxPaddingV  ?? this.textBoxPaddingV,
        useGradient:      useGradient      ?? this.useGradient,
        gradientEnd:      gradientEnd      ?? this.gradientEnd,
        gradientBegin:    gradientBegin    ?? this.gradientBegin,
        gradientEndAlign: gradientEndAlign ?? this.gradientEndAlign,
      );

  // ── serialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'bgImagePath':      bgImagePath,
        'bgFit':            bgFit.name,
        'bgImageOpacity':   bgImageOpacity,
        'bgTint':           bgTint.toARGB32(),
        'bgTintOpacity':    bgTintOpacity,
        'overlay':          overlay.name,
        'overlayColor':     overlayColor.toARGB32(),
        'overlayOpacity':   overlayOpacity,
        'fontFamily':       fontFamily,
        'textAlign':        textAlign.name,
        'titleScale':       titleScale,
        'bodyScale':        bodyScale,
        'titleBold':        titleBold,
        'titleItalic':      titleItalic,
        'bodyBold':         bodyBold,
        'bodyItalic':       bodyItalic,
        'letterSpacing':    letterSpacing,
        'lineHeight':       lineHeight,
        'textShadow':       textShadow,
        'shadowColor':      shadowColor.toARGB32(),
        'shadowBlur':       shadowBlur,
        'showTextBox':      showTextBox,
        'textBoxColor':     textBoxColor.toARGB32(),
        'textBoxOpacity':   textBoxOpacity,
        'textBoxRadius':    textBoxRadius,
        'textBoxPaddingH':  textBoxPaddingH,
        'textBoxPaddingV':  textBoxPaddingV,
        'useGradient':      useGradient,
        'gradientEnd':      gradientEnd.toARGB32(),
        'gradientBegin':    SlideStyle.alignName(gradientBegin),
        'gradientEndAlign': SlideStyle.alignName(gradientEndAlign),
      };

  factory SlideStyle.fromJson(Map<String, dynamic> j) {
    T en<T>(List<T> vals, String? name, T def) =>
        vals.firstWhere((v) => (v as dynamic).name == name, orElse: () => def);

    Color col(String key, int fallback) {
      final v = j[key];
      if (v == null) return Color(fallback);
      return Color((v as num).toInt());
    }

    return SlideStyle(
      bgImagePath:      j['bgImagePath'] as String?,
      bgFit:            en(SlideBgFit.values,     j['bgFit'],     SlideBgFit.cover),
      bgImageOpacity:   ((j['bgImageOpacity']  as num?) ?? 1.0).toDouble(),
      bgTint:           col('bgTint',             0xFF000000),
      bgTintOpacity:    ((j['bgTintOpacity']   as num?) ?? 0.0).toDouble(),
      overlay:          en(SlideOverlay.values,   j['overlay'],   SlideOverlay.none),
      overlayColor:     col('overlayColor',       0xFFFFFFFF),
      overlayOpacity:   ((j['overlayOpacity']  as num?) ?? 0.08).toDouble(),
      fontFamily:       (j['fontFamily']  as String?) ?? 'sans-serif',
      textAlign:        en(SlideTextAlign.values, j['textAlign'], SlideTextAlign.center),
      titleScale:       ((j['titleScale']      as num?) ?? 1.0).toDouble(),
      bodyScale:        ((j['bodyScale']       as num?) ?? 1.0).toDouble(),
      titleBold:        (j['titleBold']   as bool?) ?? true,
      titleItalic:      (j['titleItalic'] as bool?) ?? false,
      bodyBold:         (j['bodyBold']    as bool?) ?? false,
      bodyItalic:       (j['bodyItalic']  as bool?) ?? false,
      letterSpacing:    ((j['letterSpacing']   as num?) ?? 0.0).toDouble(),
      lineHeight:       ((j['lineHeight']      as num?) ?? 1.5).toDouble(),
      textShadow:       (j['textShadow']  as bool?) ?? false,
      shadowColor:      col('shadowColor',        0xFF000000),
      shadowBlur:       ((j['shadowBlur']      as num?) ?? 4.0).toDouble(),
      showTextBox:      (j['showTextBox']  as bool?) ?? false,
      textBoxColor:     col('textBoxColor',       0xFF000000),
      textBoxOpacity:   ((j['textBoxOpacity']  as num?) ?? 0.45).toDouble(),
      textBoxRadius:    ((j['textBoxRadius']   as num?) ?? 10.0).toDouble(),
      textBoxPaddingH:  ((j['textBoxPaddingH'] as num?) ?? 24.0).toDouble(),
      textBoxPaddingV:  ((j['textBoxPaddingV'] as num?) ?? 16.0).toDouble(),
      useGradient:      (j['useGradient']  as bool?) ?? false,
      gradientEnd:      col('gradientEnd',        0xFF000000),
      gradientBegin:    SlideStyle.alignFromName(j['gradientBegin']),
      gradientEndAlign: SlideStyle.alignFromName(j['gradientEndAlign'],
          fallback: Alignment.bottomCenter),
    );
  }

  static String alignName(AlignmentGeometry a) {
    if (a == Alignment.topCenter)    return 'topCenter';
    if (a == Alignment.bottomCenter) return 'bottomCenter';
    if (a == Alignment.centerLeft)   return 'centerLeft';
    if (a == Alignment.centerRight)  return 'centerRight';
    if (a == Alignment.topLeft)      return 'topLeft';
    if (a == Alignment.bottomRight)  return 'bottomRight';
    return 'topCenter';
  }

  static Alignment alignFromName(dynamic name,
      {Alignment fallback = Alignment.topCenter}) {
    switch (name) {
      case 'topCenter':    return Alignment.topCenter;
      case 'bottomCenter': return Alignment.bottomCenter;
      case 'centerLeft':   return Alignment.centerLeft;
      case 'centerRight':  return Alignment.centerRight;
      case 'topLeft':      return Alignment.topLeft;
      case 'bottomRight':  return Alignment.bottomRight;
      default:             return fallback;
    }
  }
}

// ── SLIDE ─────────────────────────────────────────────────────────────────────

class Slide {
  final String id;
  String type;
  String title;
  String body;
  String reference;
  Color  bgColor;
  Color  textColor;
  double fontSize;
  SlideStyle style;

  Slide({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.reference = '',
    this.bgColor   = const Color(0xFF1A3A5C),
    this.textColor = Colors.white,
    this.fontSize  = 36,
    SlideStyle? style,
  }) : style = style ?? SlideStyle();

  // ── JSON (for legacy data migration only) ─────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id':        id,
        'type':      type,
        'title':     title,
        'body':      body,
        'reference': reference,
        'bgColor':   bgColor.toARGB32(),
        'textColor': textColor.toARGB32(),
        'fontSize':  fontSize,
        'style':     style.toJson(),
      };

  factory Slide.fromJson(Map<String, dynamic> j) {
    Color col(String key, int fallback) {
      final v = j[key];
      if (v == null) return Color(fallback);
      return Color((v as num).toInt());
    }

    return Slide(
      id:        (j['id']        as String?) ?? '',
      type:      (j['type']      as String?) ?? 'blank',
      title:     (j['title']     as String?) ?? '',
      body:      (j['body']      as String?) ?? '',
      reference: (j['reference'] as String?) ?? '',
      bgColor:   col('bgColor',   0xFF1A3A5C),
      textColor: col('textColor', 0xFFFFFFFF),
      fontSize:  ((j['fontSize'] as num?) ?? 36).toDouble(),
      style: j['style'] is Map
          ? SlideStyle.fromJson(
              Map<String, dynamic>.from(j['style'] as Map))
          : SlideStyle(),
    );
  }

  // ── DB row (normalized slides table) ─────────────────────────────────────

  /// Convert to a DB row for the `slides` table.
  /// [deckId] and [order] are supplied by the caller.
  Map<String, dynamic> toRow(String deckId, int order) => {
        'id':            id,
        'deck_id':       deckId,
        'slide_order':   order,
        'type':          type,
        'title':         title,
        'body':          body,
        'reference':     reference,
        'bg_color':      bgColor.toARGB32(),
        'text_color':    textColor.toARGB32(),
        'font_size':     fontSize,
        'style_json':    jsonEncode(style.toJson()),
      };

  /// Reconstruct a Slide from a DB row.
  factory Slide.fromRow(Map<String, dynamic> row) {
    Color col(String key, int fallback) {
      final v = row[key];
      if (v == null) return Color(fallback);
      return Color((v as num).toInt());
    }

    SlideStyle parseStyle() {
      try {
        final raw = row['style_json'];
        if (raw == null || (raw as String).isEmpty) return SlideStyle();
        final decoded = jsonDecode(raw);
        if (decoded is! Map) return SlideStyle();
        return SlideStyle.fromJson(Map<String, dynamic>.from(decoded));
      } catch (_) {
        return SlideStyle();
      }
    }

    return Slide(
      id:        (row['id']        as String?) ?? '',
      type:      (row['type']      as String?) ?? 'blank',
      title:     (row['title']     as String?) ?? '',
      body:      (row['body']      as String?) ?? '',
      reference: (row['reference'] as String?) ?? '',
      bgColor:   col('bg_color',   0xFF1A3A5C),
      textColor: col('text_color', 0xFFFFFFFF),
      fontSize:  ((row['font_size'] as num?) ?? 36).toDouble(),
      style:     parseStyle(),
    );
  }
}

// ── DECK ──────────────────────────────────────────────────────────────────────

class Deck {
  final String     id;
  String           name;
  String           description;
  String           author;
  String           notes;
  DateTime?        serviceDate;
  List<String>     tags;
  bool             isTemplate;
  bool             isPinned;
  int              sortOrder;
  List<Slide>      slides;
  List<SlideGroup> groups;
  DateTime         createdAt;
  DateTime?        lastUsedAt;
  DateTime?        lastModifiedAt;
  String?          filePath;
  String           masterStyleId;   // layout template id (e.g. 'midnight_worship')
  int              masterBgColor;   // ARGB stored as int; 0 = use brand primary
  int              masterAccentColor; // 0 = use brand secondary
  int              masterTextColor;   // 0 = use default (white)

  Deck({
    required this.id,
    required this.name,
    required this.slides,
    required this.createdAt,
    this.description    = '',
    this.author         = '',
    this.notes          = '',
    this.serviceDate,
    List<String>?     tags,
    this.isTemplate     = false,
    this.isPinned       = false,
    this.sortOrder      = 0,
    this.lastUsedAt,
    this.lastModifiedAt,
    this.filePath,
    this.masterStyleId      = 'your_brand',
    this.masterBgColor      = 0,
    this.masterAccentColor  = 0,
    this.masterTextColor    = 0,
    List<SlideGroup>? groups,
  })  : tags   = tags   ?? [],
        groups = groups ?? [];

  int get slideCount => slides.length;

  static String safeFileName(String name) =>
      name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();

  // ── DB row (decks table — no slides blob) ─────────────────────────────────

  Map<String, dynamic> toRow() => {
        'id':               id,
        'name':             name,
        'description':      description,
        'author':           author,
        'notes':            notes,
        'service_date':     serviceDate?.toIso8601String(),
        'tags_json':        jsonEncode(tags),
        'is_template':      isTemplate  ? 1 : 0,
        'is_pinned':        isPinned    ? 1 : 0,
        'sort_order':       sortOrder,
        'groups_json':      jsonEncode(groups.map((g) => g.toJson()).toList()),
        'master_style_id':    masterStyleId,
        'master_bg_color':    masterBgColor,
        'master_accent_color': masterAccentColor,
        'master_text_color':  masterTextColor,
        'created_at':       createdAt.toIso8601String(),
        'last_used_at':     lastUsedAt?.toIso8601String(),
        'last_modified_at': lastModifiedAt?.toIso8601String(),
      };

  /// Reconstruct a Deck (without slides) from a DB row.
  /// Call [db.loadSlidesForDeck] separately and assign to [slides].
  factory Deck.fromRow(Map<String, dynamic> row) {
    DateTime? dt(String key) {
      final v = row[key] as String?;
      if (v == null || v.isEmpty) return null;
      return DateTime.tryParse(v);
    }

    List<String> parseTags() {
      try {
        final raw = row['tags_json'];
        if (raw == null || (raw as String).isEmpty) return [];
        final list = jsonDecode(raw);
        if (list is! List) return [];
        return list.whereType<String>().toList();
      } catch (_) { return []; }
    }

    List<SlideGroup> parseGroups() {
      try {
        final raw = row['groups_json'];
        if (raw == null || (raw as String).isEmpty) return [];
        final list = jsonDecode(raw);
        if (list is! List) return [];
        return list
            .where((e) => e is Map)
            .map((e) {
              try {
                return SlideGroup.fromJson(Map<String, dynamic>.from(e as Map));
              } catch (_) { return null; }
            })
            .whereType<SlideGroup>()
            .toList();
      } catch (_) { return []; }
    }

    return Deck(
      id:             (row['id']   as String?) ?? '',
      name:           (row['name'] as String?) ?? 'Untitled',
      description:    (row['description'] as String?) ?? '',
      author:         (row['author']      as String?) ?? '',
      notes:          (row['notes']       as String?) ?? '',
      serviceDate:    dt('service_date'),
      tags:           parseTags(),
      isTemplate:     (row['is_template'] as int?) == 1,
      isPinned:       (row['is_pinned']   as int?) == 1,
      sortOrder:      ((row['sort_order'] as num?) ?? 0).toInt(),
      groups:         parseGroups(),
      createdAt:      dt('created_at')    ?? DateTime.now(),
      lastUsedAt:     dt('last_used_at'),
      lastModifiedAt: dt('last_modified_at'),
      masterStyleId:     (row['master_style_id']    as String?) ?? 'your_brand',
      masterBgColor:     ((row['master_bg_color']    as num?) ?? 0).toInt(),
      masterAccentColor: ((row['master_accent_color'] as num?) ?? 0).toInt(),
      masterTextColor:   ((row['master_text_color']  as num?) ?? 0).toInt(),
      slides:         [], // populated by DB after this call
    );
  }

  // ── Legacy JSON (used only for migration of old blob data) ────────────────

  Map<String, dynamic> toJson() => {
        'id':             id,
        'name':           name,
        'description':    description,
        'author':         author,
        'notes':          notes,
        'serviceDate':    serviceDate?.toIso8601String(),
        'tags':           tags,
        'isTemplate':     isTemplate,
        'isPinned':       isPinned,
        'sortOrder':      sortOrder,
        'slides':         slides.map((s) => s.toJson()).toList(),
        'groups':         groups.map((g) => g.toJson()).toList(),
        'createdAt':      createdAt.toIso8601String(),
        'lastUsedAt':     lastUsedAt?.toIso8601String(),
        'lastModifiedAt': lastModifiedAt?.toIso8601String(),
      };

  factory Deck.fromJson(Map<String, dynamic> j) {
    List<Slide> parseSlides() {
      final raw = j['slides'];
      if (raw == null || raw is! List) return [];
      return raw
          .where((e) => e is Map)
          .map((e) {
            try {
              return Slide.fromJson(Map<String, dynamic>.from(e as Map));
            } catch (_) { return null; }
          })
          .whereType<Slide>()
          .toList();
    }

    List<SlideGroup> parseGroups() {
      final raw = j['groups'];
      if (raw == null || raw is! List) return [];
      return raw
          .where((e) => e is Map)
          .map((e) {
            try {
              return SlideGroup.fromJson(Map<String, dynamic>.from(e as Map));
            } catch (_) { return null; }
          })
          .whereType<SlideGroup>()
          .toList();
    }

    List<String> parseTags() {
      final raw = j['tags'];
      if (raw == null || raw is! List) return [];
      return raw.whereType<String>().toList();
    }

    DateTime? dt(String key) {
      final v = j[key] as String?;
      if (v == null || v.isEmpty) return null;
      return DateTime.tryParse(v);
    }

    return Deck(
      id:             (j['id']   as String?) ?? '',
      name:           (j['name'] as String?) ?? 'Untitled',
      description:    (j['description'] as String?) ?? '',
      author:         (j['author']      as String?) ?? '',
      notes:          (j['notes']       as String?) ?? '',
      serviceDate:    dt('serviceDate'),
      tags:           parseTags(),
      isTemplate:     (j['isTemplate'] as bool?) ?? false,
      isPinned:       (j['isPinned']   as bool?) ?? false,
      sortOrder:      ((j['sortOrder'] as num?) ?? 0).toInt(),
      slides:         parseSlides(),
      groups:         parseGroups(),
      createdAt:      dt('createdAt') ?? DateTime.now(),
      lastUsedAt:     dt('lastUsedAt'),
      lastModifiedAt: dt('lastModifiedAt'),
    );
  }
}

// ── STREAM SETTINGS ───────────────────────────────────────────────────────────

class StreamSettings {
  String rtmpUrl;
  String streamKey;
  String platform;

  StreamSettings({
    this.rtmpUrl   = '',
    this.streamKey = '',
    this.platform  = 'youtube',
  });

  String get fullRtmpUrl {
    if (platform != 'custom' && rtmpUrl.isNotEmpty && streamKey.isNotEmpty) {
      return '$rtmpUrl/$streamKey';
    }
    return rtmpUrl;
  }

  StreamSettings copyWith({
    String? rtmpUrl,
    String? streamKey,
    String? platform,
  }) =>
      StreamSettings(
        rtmpUrl:   rtmpUrl   ?? this.rtmpUrl,
        streamKey: streamKey ?? this.streamKey,
        platform:  platform  ?? this.platform,
      );

  Map<String, dynamic> toJson() =>
      {'rtmpUrl': rtmpUrl, 'streamKey': streamKey, 'platform': platform};

  factory StreamSettings.fromJson(Map<String, dynamic> j) => StreamSettings(
        rtmpUrl:   (j['rtmpUrl']   as String?) ?? '',
        streamKey: (j['streamKey'] as String?) ?? '',
        platform:  (j['platform']  as String?) ?? 'youtube',
      );

  static const Map<String, Map<String, String>> platformDefaults = {
    'youtube':  {'name': 'YouTube Live',  'url': 'rtmp://a.rtmp.youtube.com/live2'},
    'facebook': {'name': 'Facebook Live', 'url': 'rtmps://live-api-s.facebook.com:443/rtmp'},
    'twitch':   {'name': 'Twitch',        'url': 'rtmp://live.twitch.tv/app'},
    'custom':   {'name': 'Custom RTMP',   'url': ''},
  };
}

// ── RECORD SETTINGS ───────────────────────────────────────────────────────────

class RecordSettings {
  String savePath;
  String quality;
  String format;

  RecordSettings({
    this.savePath = '',
    this.quality  = 'high',
    this.format   = 'mp4',
  });

  RecordSettings copyWith({
    String? savePath,
    String? quality,
    String? format,
  }) =>
      RecordSettings(
        savePath: savePath ?? this.savePath,
        quality:  quality  ?? this.quality,
        format:   format   ?? this.format,
      );

  Map<String, dynamic> toJson() =>
      {'savePath': savePath, 'quality': quality, 'format': format};

  factory RecordSettings.fromJson(Map<String, dynamic> j) => RecordSettings(
        savePath: (j['savePath'] as String?) ?? '',
        quality:  (j['quality']  as String?) ?? 'high',
        format:   (j['format']   as String?) ?? 'mp4',
      );

  String get estimatedStorage {
    switch (quality) {
      case 'high':   return '~4 GB/hr';
      case 'medium': return '~2 GB/hr';
      case 'low':    return '~700 MB/hr';
      default:       return '~2 GB/hr';
    }
  }
}