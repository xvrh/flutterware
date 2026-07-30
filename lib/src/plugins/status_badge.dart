import 'tone.dart';

/// How a badge renders: nothing, a coloured dot, or a small count.
enum StatusBadgeKind { none, dot, count }

/// A per-plugin or per-worktree glyph small enough for a tab or a switcher row.
///
/// Distinct from [Status]: a status is a sentence, a badge is a mark. The
/// worktree switcher shows badges for worktrees that are not open, so a badge
/// must be cheap to compute.
class StatusBadge {
  const StatusBadge(
    this.kind, {
    this.tone = Tone.neutral,
    this.count,
    this.pulsing = false,
  });

  static const none = StatusBadge(StatusBadgeKind.none);

  const StatusBadge.dot(Tone tone, {bool pulsing = false})
    : this(StatusBadgeKind.dot, tone: tone, pulsing: pulsing);

  const StatusBadge.count(int count, {Tone tone = Tone.neutral})
    : this(StatusBadgeKind.count, tone: tone, count: count);

  final StatusBadgeKind kind;
  final Tone tone;
  final int? count;

  /// A hint that the badge wants attention — Claude parked waiting on you, a
  /// build that just went red. Renderers may ignore it.
  final bool pulsing;

  bool get isEmpty => kind == StatusBadgeKind.none;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'tone': tone.name,
    if (count != null) 'count': count,
    if (pulsing) 'pulsing': true,
  };

  static StatusBadge fromJson(Map<String, Object?> json) => StatusBadge(
    StatusBadgeKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => StatusBadgeKind.none,
    ),
    tone: Tone.byName(json['tone']! as String),
    count: json['count'] as int?,
    pulsing: json['pulsing'] == true,
  );

  @override
  String toString() => switch (kind) {
    StatusBadgeKind.none => '',
    StatusBadgeKind.dot => '●',
    StatusBadgeKind.count => '${count ?? 0}',
  };

  @override
  bool operator ==(Object other) =>
      other is StatusBadge &&
      other.kind == kind &&
      other.tone == tone &&
      other.count == count &&
      other.pulsing == pulsing;

  @override
  int get hashCode => Object.hash(kind, tone, count, pulsing);
}
