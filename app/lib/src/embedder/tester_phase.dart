/// What a [TesterHost] is doing, in the handful of phases a wait can be.
///
/// The host narrates itself for a log file, and a log file's voice is the
/// wrong one on a status row or under a spinner. Worse, its `onLog` carries
/// the **guest's whole console** — every `print` a preview or a scenario makes
/// on the way up — so anything that forwards those lines verbatim shows
/// whatever the app last said. This is the vocabulary in between: the host's
/// own lines, read back as phases; everything else discarded.
enum TesterPhase {
  /// The cold start's long pole: the kernel is being built.
  compiling,

  /// An asset changed, so the bundle is being rebuilt — which also means a
  /// restart, because a guest registers its manifest once.
  bundling,

  /// The process is up and the harness has not answered yet.
  starting,

  /// The harness answered. Nothing is waiting on the host any more.
  ready,

  /// Back to a fresh process, whatever sent it there.
  restarting,

  /// An incremental compile pushed into the live guest.
  reloading,
}

/// [TesterPhase.reloading] knows how many files; every other phase carries
/// nothing.
typedef TesterPhaseReading = ({TesterPhase phase, int? files});

/// Reads one line of a [TesterHost]'s narration, or null for a line that means
/// nothing to a reader watching it work.
///
/// Unknown lines return null rather than a fallback, and that is the whole
/// point: `[tester] flutterware previews harness ready — 133 entries, fonts:
/// MaterialIcons` is a long, bracketed, lower-case line naming three things —
/// a process, a count and a font list — that the person waiting did not ask
/// about, and the line after it may be the app greeting its own console. A
/// caption that changes to whatever the guest last printed is unreadable.
TesterPhaseReading? readTesterPhase(String line) {
  var text = line.replaceFirst(RegExp(r'^\[[^\]]*\]\s*'), '');
  if (RegExp(r'^reloading (\d+) edited').firstMatch(text) case var m?) {
    return (phase: TesterPhase.reloading, files: int.parse(m.group(1)!));
  }
  if (text.startsWith('compiling the harness')) {
    return (phase: TesterPhase.compiling, files: null);
  }
  if (text.startsWith('the asset bundle changed')) {
    return (phase: TesterPhase.bundling, files: null);
  }
  // Both ways back to a fresh process: the reload the VM refused, and the
  // guest that left on its own.
  if (text.contains('restarting the harness') ||
      text.startsWith('the harness exited')) {
    return (phase: TesterPhase.restarting, files: null);
  }
  if (text.startsWith('The Dart VM service is listening')) {
    return (phase: TesterPhase.starting, files: null);
  }
  if (text.contains('harness ready')) {
    return (phase: TesterPhase.ready, files: null);
  }
  return null;
}
