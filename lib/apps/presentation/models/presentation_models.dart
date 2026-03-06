// lib/apps/presentation/models/presentation_models.dart
import 'package:flutter/material.dart';

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

  Slide({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.reference = '',
    this.bgColor   = const Color(0xFF1A3A5C),
    this.textColor = Colors.white,
    this.fontSize  = 36,
  });

  Map<String, dynamic> toJson() => {
    'id':        id,
    'type':      type,
    'title':     title,
    'body':      body,
    'reference': reference,
    'bgColor':   bgColor.toARGB32(),
    'textColor': textColor.toARGB32(),
    'fontSize':  fontSize,
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
  );
}

// ── DECK ──────────────────────────────────────────────────────────────────────
class Deck {
  final String id;
  String      name;
  List<Slide> slides;
  DateTime    createdAt;
  DateTime?   lastUsedAt;

  Deck({
    required this.id,
    required this.name,
    required this.slides,
    required this.createdAt,
    this.lastUsedAt,
  });

  int get slideCount => slides.length;

  Map<String, dynamic> toJson() => {
    'id':         id,
    'name':       name,
    'slides':     slides.map((s) => s.toJson()).toList(),
    'createdAt':  createdAt.toIso8601String(),
    'lastUsedAt': lastUsedAt?.toIso8601String(),
  };

  factory Deck.fromJson(Map<String, dynamic> j) => Deck(
    id:         j['id'],
    name:       j['name'],
    slides:     (j['slides'] as List).map((s) => Slide.fromJson(s)).toList(),
    createdAt:  DateTime.parse(j['createdAt']),
    lastUsedAt: j['lastUsedAt'] != null
        ? DateTime.tryParse(j['lastUsedAt'])
        : null,
  );
}

// ── STREAM SETTINGS ───────────────────────────────────────────────────────────
class StreamSettings {
  String rtmpUrl;
  String streamKey;
  String platform; // 'youtube' | 'facebook' | 'twitch' | 'custom'

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

  Map<String, dynamic> toJson() => {
    'rtmpUrl':   rtmpUrl,
    'streamKey': streamKey,
    'platform':  platform,
  };

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
  String quality; // 'high' | 'medium' | 'low'
  String format;  // 'mp4' | 'mkv' | 'mov'

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

  Map<String, dynamic> toJson() => {
    'savePath': savePath,
    'quality':  quality,
    'format':   format,
  };

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