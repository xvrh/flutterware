/// When a teardown step runs relative to the others. Steps run in phase order;
/// the built-in "remove the git worktree" step always runs last.
enum TeardownPhase { apps, infra, cleanup }

/// One checkable step in the "close this worktree" checklist.
///
/// [enabled], [checked] and [detail] are resolved against live plugin state
/// when the dialog opens, so the checklist reflects the current state rather
/// than registration time. That is why they are values here rather than
/// closures: the plugin runtime evaluates them and hands over the result.
class TeardownStep {
  const TeardownStep(
    this.id,
    this.label, {
    this.detail,
    this.arguments = const {},
    this.enabled = true,
    this.checked = false,
    this.danger = false,
    this.phase = TeardownPhase.cleanup,
  });

  /// An action id on the same plugin — this is what makes a step
  /// executable while staying pure data.
  ///
  /// The design this came from held a closure (`teardown('…', () => sh(…))`),
  /// which a serialisable contract cannot. Naming an action instead costs
  /// nothing and buys the property every other surface already has: the
  /// checklist runs a step by the same call `fw run <plugin> <action>` makes,
  /// so a step can never do something the CLI and an agent cannot also do — and
  /// there is no second code path to keep in step with the first.
  ///
  /// A plugin may emit several steps naming one action, told apart by
  /// [arguments]: the run plugin emits one per running app, all of them `stop`.
  final String id;
  final String label;

  /// What this will actually do, given current state — "3 containers, 2 named
  /// volumes". Shown under the label.
  final String? detail;

  /// False when there is nothing to do; renderers grey the row out.
  final bool enabled;

  /// Default tick state.
  final bool checked;

  /// What to pass the action, keyed by `ActionParameter.id`.
  ///
  /// This is what lets one action back several rows. A step per running app
  /// gives each its own [detail] — *which* device, running *how* long — and
  /// lets one be unticked, where a single "stop 3 apps" row can only be taken
  /// or left whole.
  final Map<String, Object?> arguments;

  /// Destroys data.
  final bool danger;

  final TeardownPhase phase;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    if (detail != null) 'detail': detail,
    if (arguments.isNotEmpty) 'arguments': arguments,
    'enabled': enabled,
    'checked': checked,
    if (danger) 'danger': true,
    'phase': phase.name,
  };

  static TeardownStep fromJson(Map<String, Object?> json) => TeardownStep(
    json['id']! as String,
    json['label']! as String,
    detail: json['detail'] as String?,
    arguments: (json['arguments'] as Map? ?? const {}).cast<String, Object?>(),
    enabled: json['enabled'] != false,
    checked: json['checked'] == true,
    danger: json['danger'] == true,
    phase: TeardownPhase.values.firstWhere(
      (p) => p.name == json['phase'],
      orElse: () => TeardownPhase.cleanup,
    ),
  );
}
