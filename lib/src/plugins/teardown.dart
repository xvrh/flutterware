/// When a teardown step runs relative to the others. Steps run in phase order;
/// the built-in "remove the git worktree" step always runs last.
enum TeardownPhase { apps, infra, cleanup }

/// One checkable step in the "close this worktree" checklist.
///
/// [enabled], [checked] and [detail] are resolved against live plugin state
/// when the dialog opens, so the checklist reflects reality rather than
/// registration time — which is why they are values here, not closures: the
/// plugin runtime evaluates them and hands over the result.
class TeardownStep {
  const TeardownStep(
    this.id,
    this.label, {
    this.detail,
    this.enabled = true,
    this.checked = false,
    this.danger = false,
    this.phase = TeardownPhase.cleanup,
  });

  final String id;
  final String label;

  /// What this will actually do, given current state — "3 containers, 2 named
  /// volumes". Shown under the label.
  final String? detail;

  /// False when there is nothing to do; renderers grey the row out.
  final bool enabled;

  /// Default tick state.
  final bool checked;

  /// Destroys data.
  final bool danger;

  final TeardownPhase phase;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    if (detail != null) 'detail': detail,
    'enabled': enabled,
    'checked': checked,
    if (danger) 'danger': true,
    'phase': phase.name,
  };

  static TeardownStep fromJson(Map<String, Object?> json) => TeardownStep(
    json['id']! as String,
    json['label']! as String,
    detail: json['detail'] as String?,
    enabled: json['enabled'] != false,
    checked: json['checked'] == true,
    danger: json['danger'] == true,
    phase: TeardownPhase.values.firstWhere(
      (p) => p.name == json['phase'],
      orElse: () => TeardownPhase.cleanup,
    ),
  );
}
