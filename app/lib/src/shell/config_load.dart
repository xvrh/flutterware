/// What one run of `tool/flutterware.dart` did.
enum ConfigLoadOutcome {
  /// The worktree was opened, so the graph was built rather than changed.
  built,

  /// It ran, and declared exactly what was already there.
  ///
  /// **The case the whole feature turns on.** A reload that rebuilds everything
  /// is fine — losing a compiled catalog to a config change is the price of
  /// having changed the config. Paying it for a comment is not, so "nothing
  /// moved" has to be exact.
  ///
  /// It also has to be *reported*, not inferred from silence: a no-op reload and
  /// a watcher that is not working look identical otherwise.
  unchanged,

  /// The config declared something different, so the graph was rebuilt.
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
    this.plugins = 0,
    this.error,
  });

  final DateTime at;

  /// How long the whole load took — running the config, comparing, and
  /// rebuilding if it moved.
  ///
  /// Surfaced so a drift from ~300ms to seconds is visible without anyone
  /// instrumenting anything.
  final Duration duration;

  final ConfigLoadOutcome outcome;

  /// How many plugins the graph ended up with.
  final int plugins;

  /// The load failure, when [outcome] is [ConfigLoadOutcome.failed].
  final String? error;

  bool get succeeded => outcome != ConfigLoadOutcome.failed;

  /// A phrase for one line of UI — no timing, no prefix.
  String get summary => switch (outcome) {
    ConfigLoadOutcome.built => 'opened, ${_plural(plugins)}',
    ConfigLoadOutcome.unchanged => 'no changes',
    ConfigLoadOutcome.rebuilt => 'rebuilt, ${_plural(plugins)}',
    ConfigLoadOutcome.failed => 'failed',
  };

  static String _plural(int n) => n == 1 ? '1 plugin' : '$n plugins';
}
