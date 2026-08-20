/// A comparison stopped because somebody asked it to.
///
/// Its own type rather than a generic exception so every layer between the
/// Stop button and a render loop can tell "the user is done" from "something
/// broke": the first keeps the rows it has, the second is a refusal.
class ComparisonCancelled implements Exception {
  const ComparisonCancelled();

  @override
  String toString() => 'the comparison was stopped';
}

/// One run's stop signal.
///
/// Checked at every seam the run passes through — between stages, between
/// frames, between scenario replays — because the work underneath is a process
/// rendering a batch and there is no killing it mid-frame. Stopping takes
/// effect at the next boundary, which is at worst one frame away.
class CancelToken {
  var _cancelled = false;

  bool get cancelled => _cancelled;

  void cancel() => _cancelled = true;

  /// Throws [ComparisonCancelled] once [cancel] has been called.
  void check() {
    if (_cancelled) throw const ComparisonCancelled();
  }
}
