// lib/apps/notes/note_model.dart
//
// Core data model for the Notes feature.
// Add new fields here when you need to track more metadata per note.

import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'note_constants.dart';

// ══════════════════════════════════════════════════════════════════════════════
// MESSAGE TYPE
// ══════════════════════════════════════════════════════════════════════════════

enum MessageType {
  sermon, teaching, devotional, bibleStudy, smallGroup, prayer, meeting, other
}

const messageTypeLabels = <MessageType, String>{
  MessageType.sermon:     'Sermon',
  MessageType.teaching:   'Teaching',
  MessageType.devotional: 'Devotional',
  MessageType.bibleStudy: 'Bible Study',
  MessageType.smallGroup: 'Small Group',
  MessageType.prayer:     'Prayer',
  MessageType.meeting:    'Meeting',
  MessageType.other:      'Other',
};

// ══════════════════════════════════════════════════════════════════════════════
// NOTE MODEL
// ══════════════════════════════════════════════════════════════════════════════

class NoteModel {
  final String id;
  String title;
  String content;
  String folder;         // kFolderTopical / kFolderExpositional / etc.
  String subfolder;      // topic name or book of Bible for expositional
  String seriesName;     // Expositional series / message title
  MessageType messageType;
  DateTime?   date;
  bool        isPinned;
  bool        isArchived;
  List<String> tags;
  String?     sourceFilePath;  // path of the original imported file
  String?     sourceFileType;  // 'docx' | 'pdf' | 'txt' | 'md'
  Uint8List?  sourceFileBytes; // raw bytes (runtime only — not persisted)
  String?     translation;     // Bible translation used for this note
  final DateTime createdAt;
  DateTime       updatedAt;

  NoteModel({
    required this.id,
    required this.title,
    required this.content,
    required this.folder,
    this.subfolder       = '',
    this.seriesName      = '',
    this.messageType     = MessageType.sermon,
    this.date,
    this.isPinned        = false,
    this.isArchived      = false,
    this.tags            = const [],
    this.sourceFilePath,
    this.sourceFileType,
    this.sourceFileBytes,
    this.translation,
    required this.createdAt,
    required this.updatedAt,
  });

  // ── SERIALISATION ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'id':           id,
    'title':        title,
    'content':      content,
    'folder':       folder,
    'subfolder':    subfolder,
    'seriesName':   seriesName,
    'messageType':  messageType.name,
    'date':         date?.toIso8601String(),
    'isPinned':     isPinned,
    'isArchived':   isArchived,
    'tags':         tags,
    'sourceFilePath': sourceFilePath,
    'sourceFileType': sourceFileType,
    // sourceFileBytes intentionally omitted — too large to persist
    'translation':  translation,
    'createdAt':    createdAt.toIso8601String(),
    'updatedAt':    updatedAt.toIso8601String(),
  };

  factory NoteModel.fromJson(Map<String, dynamic> j) => NoteModel(
    id:          j['id']      ?? const Uuid().v4(),
    title:       j['title']   ?? 'Untitled',
    content:     j['content'] ?? '',
    folder:      j['folder']  ?? kFolderGeneral,
    subfolder:   j['subfolder']  ?? '',
    seriesName:  j['seriesName'] ?? '',
    messageType: MessageType.values.firstWhere(
        (t) => t.name == j['messageType'],
        orElse: () => MessageType.sermon),
    date:       j['date'] != null ? DateTime.tryParse(j['date']) : null,
    isPinned:   j['isPinned']   ?? false,
    isArchived: j['isArchived'] ?? false,
    tags:       List<String>.from(j['tags'] ?? []),
    sourceFilePath: j['sourceFilePath'],
    sourceFileType: j['sourceFileType'],
    translation: j['translation'],
    createdAt:   DateTime.parse(j['createdAt']),
    updatedAt:   DateTime.parse(j['updatedAt']),
  );
}