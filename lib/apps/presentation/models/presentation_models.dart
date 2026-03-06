// lib/apps/presentation/models/presentation_models.dart
import 'package:flutter/material.dart';
import 'slide_group.dart';

// ── SLIDE STYLE ───────────────────────────────────────────────────────────────

/// Text alignment inside a slide.
enum SlideTextAlign { left, center, right }

/// How a background image is scaled.
enum SlideBgFit { cover, contain, fill }

/// Decorative overlay pattern drawn on top of the bg colour / image.
enum SlideOverlay { none, crosshatch, dots, diagonal, vignette, grain }

/// Font family preset available in the editor.
class SlideFont {
  final String name;
  final String fontFamily;
  const SlideFont(this.name, this.fontFamily);
}

const List<SlideFont> kSlideFonts = [
  SlideFont('Default',       'sans-serif'),
  SlideFont('Serif',         'serif'),
  SlideFont('Montserrat',    'Montserrat'),
  SlideFont('Playfair',      'Playfair Display'),
  SlideFont('Lato',          'Lato'),
  SlideFont('Oswald',        'Oswald'),
  SlideFont('Roboto Slab',   'Roboto Slab'),
  SlideFont('Dancing Script','Dancing Script'),
];

/// All presentational properties for a single slide.
class SlideStyle {
  // ── background ──────────────────────────────────────────────────────────
  /// Absolute path (mobile/desktop) or data-URI (web) of a custom bg image.
  String?       bgImagePath;
  SlideBgFit    bgFit;
  /// 0.0 = fully transparent image (solid colour), 1.0 = fully opaque image.
  double        bgImageOpacity;
  /// Dark/light tint overlaid on the bg image to keep text readable.
  Color         bgTint;
  double        bgTintOpacity; // 0.0 → 1.0

  // ── overlay ─────────────────────────────────────────────────────────────
  SlideOverlay  overlay;
  Color         overlayColor;
  double        overlayOpacity;

  // ── text ────────────────────────────────────────────────────────────────
  String        fontFamily;
  SlideTextAlign textAlign;
  double        titleScale;   // multiplier on top of slide.fontSize
  double        bodyScale;
  bool          titleBold;
  bool          titleItalic;
  bool          bodyBold;
  bool          bodyItalic;
  double        letterSpacing;
  double        lineHeight;

  // ── text shadow ──────────────────────────────────────────────────────────
  bool          textShadow;
  Color         shadowColor;
  double        shadowBlur;

  // ── text box ─────────────────────────────────────────────────────────────
  bool          showTextBox;
  Color         textBoxColor;
  double        textBoxOpacity;
  double        textBoxRadius;
  double        textBoxPaddingH;
  double        textBoxPaddingV;

  // ── gradient ─────────────────────────────────────────────────────────────
  bool          useGradient;
  Color         gradientEnd;
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
        bgImagePath:     clearBgImage ? null : (bgImagePath ?? this.bgImagePath),
        bgFit:           bgFit           ?? this.bgFit,
        bgImageOpacity:  bgImageOpacity  ?? this.bgImageOpacity,
        bgTint:          bgTint          ?? this.bgTint,
        bgTintOpacity:   bgTintOpacity   ?? this.bgTintOpacity,
        overlay:         overlay         ?? this.overlay,
        overlayColor:    overlayColor    ?? this.overlayColor,
        overlayOpacity:  overlayOpacity  ?? this.overlayOpacity,
        fontFamily:      fontFamily      ?? this.fontFamily,
        textAlign:       textAlign       ?? this.textAlign,
        titleScale:      titleScale      ?? this.titleScale,
        bodyScale:       bodyScale       ?? this.bodyScale,
        titleBold:       titleBold       ?? this.titleBold,
        titleItalic:     titleItalic     ?? this.titleItalic,
        bodyBold:        bodyBold        ?? this.bodyBold,
        bodyItalic:      bodyItalic      ?? this.bodyItalic,
        letterSpacing:   letterSpacing   ?? this.letterSpacing,
        lineHeight:      lineHeight      ?? this.lineHeight,
        textShadow:      textShadow      ?? this.textShadow,
        shadowColor:     shadowColor     ?? this.shadowColor,
        shadowBlur:      shadowBlur      ?? this.shadowBlur,
        showTextBox:     showTextBox     ?? this.showTextBox,
        textBoxColor:    textBoxColor    ?? this.textBoxColor,
        textBoxOpacity:  textBoxOpacity  ?? this.textBoxOpacity,
        textBoxRadius:   textBoxRadius   ?? this.textBoxRadius,
        textBoxPaddingH: textBoxPaddingH ?? this.textBoxPaddingH,
        textBoxPaddingV: textBoxPaddingV ?? this.textBoxPaddingV,
        useGradient:     useGradient     ?? this.useGradient,
        gradientEnd:     gradientEnd     ?? this.gradientEnd,
        gradientBegin:   gradientBegin   ?? this.gradientBegin,
        gradientEndAlign:gradientEndAlign?? this.gradientEndAlign,
      );

  // ── serialisation ──────────────────────────────────────────────────────────
  Map<String, dynamic> toJson() => {
        'bgImagePath':     bgImagePath,
        'bgFit':           bgFit.name,
        'bgImageOpacity':  bgImageOpacity,
        'bgTint':          bgTint.toARGB32(),
        'bgTintOpacity':   bgTintOpacity,
        'overlay':         overlay.name,
        'overlayColor':    overlayColor.toARGB32(),
        'overlayOpacity':  overlayOpacity,
        'fontFamily':      fontFamily,
        'textAlign':       textAlign.name,
        'titleScale':      titleScale,
        'bodyScale':       bodyScale,
        'titleBold':       titleBold,
        'titleItalic':     titleItalic,
        'bodyBold':        bodyBold,
        'bodyItalic':      bodyItalic,
        'letterSpacing':   letterSpacing,
        'lineHeight':      lineHeight,
        'textShadow':      textShadow,
        'shadowColor':     shadowColor.toARGB32(),
        'shadowBlur':      shadowBlur,
        'showTextBox':     showTextBox,
        'textBoxColor':    textBoxColor.toARGB32(),
        'textBoxOpacity':  textBoxOpacity,
        'textBoxRadius':   textBoxRadius,
        'textBoxPaddingH': textBoxPaddingH,
        'textBoxPaddingV': textBoxPaddingV,
        'useGradient':     useGradient,
        'gradientEnd':     gradientEnd.toARGB32(),
        'gradientBegin':   SlideStyle.alignName(gradientBegin),
        'gradientEndAlign':SlideStyle.alignName(gradientEndAlign),
      };

  factory SlideStyle.fromJson(Map<String, dynamic> j) {
    T en<T>(List<T> vals, String? name, T def) =>
        vals.firstWhere(
            (v) => (v as dynamic).name == name,
            orElse: () => def);
    return SlideStyle(
      bgImagePath:     j['bgImagePath'],
      bgFit:           en(SlideBgFit.values,    j['bgFit'],    SlideBgFit.cover),
      bgImageOpacity:  (j['bgImageOpacity']  ?? 1.0).toDouble(),
      bgTint:          Color(j['bgTint']       ?? 0xFF000000),
      bgTintOpacity:   (j['bgTintOpacity']   ?? 0.0).toDouble(),
      overlay:         en(SlideOverlay.values,  j['overlay'],  SlideOverlay.none),
      overlayColor:    Color(j['overlayColor']  ?? 0xFFFFFFFF),
      overlayOpacity:  (j['overlayOpacity']  ?? 0.08).toDouble(),
      fontFamily:      j['fontFamily']         ?? 'sans-serif',
      textAlign:       en(SlideTextAlign.values,j['textAlign'],SlideTextAlign.center),
      titleScale:      (j['titleScale']      ?? 1.0).toDouble(),
      bodyScale:       (j['bodyScale']       ?? 1.0).toDouble(),
      titleBold:       j['titleBold']          ?? true,
      titleItalic:     j['titleItalic']        ?? false,
      bodyBold:        j['bodyBold']           ?? false,
      bodyItalic:      j['bodyItalic']         ?? false,
      letterSpacing:   (j['letterSpacing']   ?? 0.0).toDouble(),
      lineHeight:      (j['lineHeight']      ?? 1.5).toDouble(),
      textShadow:      j['textShadow']         ?? false,
      shadowColor:     Color(j['shadowColor']   ?? 0xFF000000),
      shadowBlur:      (j['shadowBlur']      ?? 4.0).toDouble(),
      showTextBox:     j['showTextBox']        ?? false,
      textBoxColor:    Color(j['textBoxColor']  ?? 0xFF000000),
      textBoxOpacity:  (j['textBoxOpacity']  ?? 0.45).toDouble(),
      textBoxRadius:   (j['textBoxRadius']   ?? 10.0).toDouble(),
      textBoxPaddingH: (j['textBoxPaddingH'] ?? 24.0).toDouble(),
      textBoxPaddingV: (j['textBoxPaddingV'] ?? 16.0).toDouble(),
      useGradient:     j['useGradient']        ?? false,
      gradientEnd:     Color(j['gradientEnd']   ?? 0xFF000000),
      gradientBegin:   SlideStyle.alignFromName(j['gradientBegin']),
      gradientEndAlign:SlideStyle.alignFromName(j['gradientEndAlign'],
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

  factory Slide.fromJson(Map<String, dynamic> j) => Slide(
        id:        j['id'],
        type:      j['type'],
        title:     j['title'],
        body:      j['body'],
        reference: j['reference'] ?? '',
        bgColor:   Color(j['bgColor']   ?? 0xFF1A3A5C),
        textColor: Color(j['textColor'] ?? 0xFFFFFFFF),
        fontSize:  (j['fontSize'] ?? 36).toDouble(),
        style:     j['style'] != null
            ? SlideStyle.fromJson(j['style'])
            : SlideStyle(),
      );
}

// ── DECK ──────────────────────────────────────────────────────────────────────
class Deck {
  final String     id;
  String           name;
  String           description;
  List<String>     tags;
  bool             isTemplate;
  bool             isPinned;
  int              sortOrder;
  List<Slide>      slides;
  List<SlideGroup> groups;        // ← named collections with optional auto-advance
  DateTime         createdAt;
  DateTime?        lastUsedAt;

  Deck({
    required this.id,
    required this.name,
    required this.slides,
    required this.createdAt,
    this.description = '',
    this.tags        = const [],
    this.isTemplate  = false,
    this.isPinned    = false,
    this.sortOrder   = 0,
    this.lastUsedAt,
    List<SlideGroup>? groups,
  }) : groups = groups ?? [];

  int get slideCount => slides.length;

  Map<String, dynamic> toJson() => {
        'id':          id,
        'name':        name,
        'description': description,
        'tags':        tags,
        'isTemplate':  isTemplate,
        'isPinned':    isPinned,
        'sortOrder':   sortOrder,
        'slides':      slides.map((s) => s.toJson()).toList(),
        'groups':      groups.map((g) => g.toJson()).toList(),
        'createdAt':   createdAt.toIso8601String(),
        'lastUsedAt':  lastUsedAt?.toIso8601String(),
      };

  factory Deck.fromJson(Map<String, dynamic> j) => Deck(
        id:          j['id'],
        name:        j['name'],
        description: j['description'] ?? '',
        tags:        List<String>.from(j['tags'] ?? []),
        isTemplate:  j['isTemplate']  ?? false,
        isPinned:    j['isPinned']    ?? false,
        sortOrder:   j['sortOrder']   ?? 0,
        slides:      (j['slides'] as List).map((s) => Slide.fromJson(s)).toList(),
        groups:      (j['groups'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(SlideGroup.fromJson)
            .toList() ?? [],
        createdAt:   DateTime.parse(j['createdAt']),
        lastUsedAt:  j['lastUsedAt'] != null
            ? DateTime.tryParse(j['lastUsedAt'])
            : null,
      );
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

  StreamSettings copyWith({String? rtmpUrl, String? streamKey, String? platform}) =>
      StreamSettings(
        rtmpUrl:   rtmpUrl   ?? this.rtmpUrl,
        streamKey: streamKey ?? this.streamKey,
        platform:  platform  ?? this.platform,
      );

  Map<String, dynamic> toJson() =>
      {'rtmpUrl': rtmpUrl, 'streamKey': streamKey, 'platform': platform};

  factory StreamSettings.fromJson(Map<String, dynamic> j) => StreamSettings(
        rtmpUrl:   j['rtmpUrl']   ?? '',
        streamKey: j['streamKey'] ?? '',
        platform:  j['platform']  ?? 'youtube',
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

  RecordSettings copyWith({String? savePath, String? quality, String? format}) =>
      RecordSettings(
        savePath: savePath ?? this.savePath,
        quality:  quality  ?? this.quality,
        format:   format   ?? this.format,
      );

  Map<String, dynamic> toJson() =>
      {'savePath': savePath, 'quality': quality, 'format': format};

  factory RecordSettings.fromJson(Map<String, dynamic> j) => RecordSettings(
        savePath: j['savePath'] ?? '',
        quality:  j['quality']  ?? 'high',
        format:   j['format']   ?? 'mp4',
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