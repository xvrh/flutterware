import 'tone.dart';

/// How a badge renders: nothing, a coloured dot, or a small count.
enum BadgeKind { none, dot, count }

/// A per-plugin or per-worktree glyph small enough for a tab or a switcher row.
///
/// Distinct from [Status]: a status is a sentence, a badge is a mark. The
/// worktree switcher shows badges for worktrees that are not open, so a badge
/// must be cheap to compute.
class Badge {
  const Badge(
    this.kind, {
    this.tone = Tone.neutral,
    this.count,
    this.pulsing = false,
  });

  static const none = Badge(BadgeKind.none);

  const Badge.dot(Tone tone, {bool pulsing = false})
    : this(BadgeKind.dot, tone: tone, pulsing: pulsing);

  const Badge.count(int count, {Tone tone = Tone.neutral})
    : this(BadgeKind.count, tone: tone, count: count);

  final BadgeKind kind;
  final Tone tone;
  final int? count;

  /// A hint that the badge wants attention — Claude parked waiting on you, a
  /// build that just went red. Renderers may ignore it.
  final bool pulsing;

  bool get isEmpty => kind == BadgeKind.none;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'tone': tone.name,
    if (count != null) 'count': count,
    if (pulsing) 'pulsing': true,
  };

  static Badge fromJson(Map<String, Object?> json) => Badge(
    BadgeKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => BadgeKind.none,
    ),
    tone: Tone.byName(json['tone']! as String),
    count: json['count'] as int?,
    pulsing: json['pulsing'] == true,
  );

  @override
  String toString() => switch (kind) {
    BadgeKind.none => '',
    BadgeKind.dot => '●',
    BadgeKind.count => '${count ?? 0}',
  };

  @override
  bool operator ==(Object other) =>
      other is Badge &&
      other.kind == kind &&
      other.tone == tone &&
      other.count == count &&
      other.pulsing == pulsing;

  @override
  int get hashCode => Object.hash(kind, tone, count, pulsing);
}
