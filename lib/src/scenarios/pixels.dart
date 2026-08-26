/// Which of a run's steps are worth rasterizing.
///
/// It lives in its own file for the reason `Shots` does: the CLI half of the
/// app names it, and nothing on that side may reach Flutter —
/// `run_args.dart` imports `widgets.dart` for a `Size` and would drag the
/// framework into a pure entry point.
library;

/// Which of a run's steps are worth rasterizing.
///
/// Rasterizing and encoding is the one part of a step that scales with the
/// screen: measured on the example suite at 1x it is 27% of the run, and at 2x
/// half of it. Every step that nobody will look at is that cost spent twice —
/// once to make the bytes and again to write them.
enum ScenarioPixels {
  /// Every step. What a run means unless it says otherwise.
  all,

  /// Only steps whose read found a translation key — and any step that failed,
  /// because a red step's picture is the first thing anybody opens.
  ///
  /// The translation export's pass: it files a screenshot against a *string
  /// id*, so a screen showing no key can contribute no shot. Measured on the
  /// example suite, 23 of 62 steps showed no key. Text belonging to no catalog
  /// is not enough — the export's `unkeyed` finding carries the words and the
  /// step, never a picture.
  keyed,

  /// Only the steps a `Shot` named — and any step that failed.
  ///
  /// The store lane's pass. `scenarios shots` keeps the named shots and
  /// deletes everything else, at the device's own ratio, which is where this
  /// costs the most: an automatic step on a 1320×2868 canvas is rasterized and
  /// encoded at eleven times the pixels of a 1× run, written to disk, and then
  /// thrown away unopened.
  ///
  /// The one mode whose decision is not a property of the *screen*. That
  /// matters where a name adopts the capture before it — see
  /// `_adoptablePending`, which refuses under this mode alone, because the
  /// automatic capture a shot would land on is exactly the one this skipped.
  named,

  /// None of them. A probe pass reads its answers off the walk
  /// (`didExceedMaxLines`, the keys artifact) and looks at no frame. The step
  /// still emits: tree, keys and texts are written as ever.
  none,
}
