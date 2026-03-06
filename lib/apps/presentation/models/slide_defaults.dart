// lib/apps/presentation/models/slide_defaults.dart
import 'package:flutter/material.dart';

/// Pure helper functions for generating default slide content.
class SlideDefaults {
  SlideDefaults._();

  static Color background(String type, Color primary) {
    switch (type) {
      case 'title':        return primary;
      case 'scripture':    return Color.lerp(primary, Colors.black, 0.25)!;
      case 'lyric':        return Color.lerp(primary, Colors.black, 0.45)!;
      case 'announcement': return Color.lerp(primary, Colors.purple, 0.4)!;
      case 'blank':        return Colors.black;
      default:             return primary;
    }
  }

  static String title(String type) {
    switch (type) {
      case 'title':        return 'Service Title';
      case 'scripture':    return 'Scripture';
      case 'lyric':        return 'Verse 1';
      case 'announcement': return 'Announcement';
      default:             return '';
    }
  }

  static String body(String type) {
    switch (type) {
      case 'title':        return 'Welcome!';
      case 'scripture':    return 'For God so loved the world...';
      case 'lyric':        return 'Type your lyrics here';
      case 'announcement': return 'Details here';
      default:             return '';
    }
  }

  static const List<String> slideTypes = [
    'title',
    'scripture',
    'lyric',
    'announcement',
    'blank',
  ];

  static String typeLabel(String type) {
    switch (type) {
      case 'title':        return 'Title Slide';
      case 'scripture':    return 'Scripture';
      case 'lyric':        return 'Lyrics';
      case 'announcement': return 'Announcement';
      case 'blank':        return 'Blank';
      default:             return type;
    }
  }
}