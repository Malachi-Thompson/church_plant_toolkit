// lib/apps/presentation/models/slide_group.dart
//
// A SlideGroup is a named, ordered subset of slides within a Deck that can
// optionally auto-advance on a timer during presentation, and optionally
// loop back to the first slide instead of exiting the group.
//
// Groups are stored directly on the Deck (deck.groups) and reference slides
// by their id so that standard slide editing remains unchanged.

import 'package:uuid/uuid.dart';

class SlideGroup {
  String        id;
  String        name;
  /// Seconds between auto-advances. null = manual only.
  int?          autoAdvanceSeconds;
  /// When true, reaching the last slide loops back to the first instead of
  /// advancing out of the group.
  bool          loop;
  /// Ordered list of slide IDs belonging to this group.
  List<String>  slideIds;

  SlideGroup({
    String?      id,
    required this.name,
    this.autoAdvanceSeconds,
    this.loop     = false,
    List<String>? slideIds,
  })  : id       = id       ?? const Uuid().v4(),
        slideIds = slideIds ?? [];

  bool get hasAutoAdvance => autoAdvanceSeconds != null && autoAdvanceSeconds! > 0;

  SlideGroup copyWith({
    String?       name,
    int?          autoAdvanceSeconds,
    bool          clearAuto = false,
    bool?         loop,
    List<String>? slideIds,
  }) =>
      SlideGroup(
        id:                 id,
        name:               name               ?? this.name,
        autoAdvanceSeconds: clearAuto ? null   : (autoAdvanceSeconds ?? this.autoAdvanceSeconds),
        loop:               loop               ?? this.loop,
        slideIds:           slideIds           ?? List.of(this.slideIds),
      );

  // ── JSON ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id':                 id,
        'name':               name,
        'autoAdvanceSeconds': autoAdvanceSeconds,
        'loop':               loop,
        'slideIds':           slideIds,
      };

  factory SlideGroup.fromJson(Map<String, dynamic> j) => SlideGroup(
        id:                 (j['id']   as String?)  ?? const Uuid().v4(),
        name:               (j['name'] as String?)  ?? 'Group',
        autoAdvanceSeconds: (j['autoAdvanceSeconds'] as num?)?.toInt(),
        loop:               (j['loop'] as bool?)    ?? false,
        slideIds: (j['slideIds'] as List?)
                ?.whereType<String>()
                .toList() ??
            [],
      );

  @override
  String toString() => 'SlideGroup($name, ${slideIds.length} slides, '
      'auto=${autoAdvanceSeconds ?? "off"}s, loop=$loop)';
}