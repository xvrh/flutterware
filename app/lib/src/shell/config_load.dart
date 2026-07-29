/// What one run of `tool/flutterware.dart` did.
enum ConfigLoadOutcome {
  /// The worktree was opened, so the graph was built rather than changed.
  ///
  /// Distinct from [rebuilt] because nothing was lost: there was nothing there
  /// to lose. A surface reporting reloads should stay quiet for this one — the
  /// tab appearing is already the feedback — while the log still keeps the row.
  built,

  /// It ran, and matched what was already there.
  ///
  /// **This has to be reported rather than inferred from silence.** A reload
  /// that changed nothing and a reload that never fired look identical
  /// otherwise, and that ambiguity is what makes a file-watching feature feel
  /// broken. Every surface that renders a load must render this case.
  unchanged,

  /// Some plugins were rebuilt; the rest were left alone, still holding
  /// whatever they held.
  reconciled,

  /// The `packages:` list moved, so the workspace and every core went with it.
  rebuilt,

  /// The config did not produce a manifest. **Nothing was torn down** — the
  /// plugins that were running before are still running.
  failed,
}

/// One row of a worktree's reload history.
class ConfigLoad {
  const ConfigLoad({
    required this.at,
    required this.duration,
    required this.outcome,
    this.rebuilt = const [],
    this.reasons = const {},
    this.error,
  });

  final DateTime at;

  /// How long the whole load took — running the config, comparing, and
  /// rebuilding whatever moved.
  ///
  /// Surfaced so a drift from ~100ms to seconds is visible without anyone
  /// instrumenting anything.
  final Duration duration;

  final ConfigLoadOutcome outcome;

  /// Plugin ids that were disposed and rebuilt.
  final List<String> rebuilt;

  /// Why each id in [rebuilt] moved — `'packages changed'`, `'newly
  /// declared'`. Keyed by plugin id.
  final Map<String, String> reasons;

  /// The load failure, when [outcome] is [ConfigLoadOutcome.failed].
  final String? error;

  bool get succeeded => outcome != ConfigLoadOutcome.failed;

  /// A phrase for one line of UI — no timing, no prefix.
  String get summary => switch (outcome) {
    ConfigLoadOutcome.built => switch (rebuilt.length) {
      1 => 'opened, 1 plugin',
      var n => 'opened, $n plugins',
    },
    ConfigLoadOutcome.unchanged => 'no changes',
    ConfigLoadOutcome.reconciled => switch (rebuilt.length) {
      0 => 'reordered',
      1 => '${_short(rebuilt.single)} rebuilt',
      var n => '$n plugins rebuilt',
    },
    ConfigLoadOutcome.rebuilt => 'workspace rebuilt, ${rebuilt.length} plugins',
    ConfigLoadOutcome.failed => 'failed',
  };

  /// The last dotted segment, which is what a person calls a plugin —
  /// `ui_catalog`, not `flutterware.ui_catalog`.
  static String _short(String id) => id.split('.').last;
}
