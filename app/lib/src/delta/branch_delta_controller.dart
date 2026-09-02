/// One worktree's [BranchDelta], loaded off the UI isolate and reloadable —
/// the changes screen's controller, for a delta two plugins read.
///
/// Stale-then-fresh: [value] keeps the last answer while the next one is
/// computed, so a tree painted from it never blanks. The first load is the
/// only one with nothing to show, and the tree is simply untinted until it
/// lands — the delta enhances a list, it never gates one.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'branch_delta.dart';
import 'branch_delta_probe.dart';

/// What one load is asked for.
class BranchDeltaRequest {
  const BranchDeltaRequest({
    required this.worktreePath,
    required this.files,
    required this.packageConfigs,
    this.previous,
  });

  final String worktreePath;
  final Set<String> files;
  final List<String> packageConfigs;

  /// The last answer, so a load whose git half comes back identical can keep
  /// its reach rather than re-parse the import graph for it.
  final BranchDelta? previous;
}

class BranchDeltaController {
  BranchDeltaController({
    required this.worktreePath,
    this.packages = const ['.'],
    Future<BranchDelta> Function(BranchDeltaRequest request)? load,
    this.tick = const Duration(seconds: 20),
    this.staleAfter = const Duration(seconds: 10),
  }) : _load = load ?? _probe;

  final String worktreePath;

  /// The worktree's packages, worktree-relative — where a `package_config`
  /// may live besides the checkout's own.
  final List<String> packages;

  final Future<BranchDelta> Function(BranchDeltaRequest request) _load;

  /// How often an attached panel re-reads without being told to — the
  /// backstop for a save nothing else noticed. Affordable because a read
  /// whose git half comes back unchanged skips the import graph, so an idle
  /// checkout costs a few git processes per tick and no parsing.
  final Duration tick;

  /// How old an answer may be before a panel arriving asks again.
  final Duration staleAfter;

  static Future<BranchDelta> _probe(BranchDeltaRequest request) => Isolate.run(
    () => BranchDeltaProbe().probe(
      request.worktreePath,
      files: request.files,
      packageConfigs: request.packageConfigs,
      previous: request.previous,
    ),
  );

  BranchDelta? get value => _value;
  BranchDelta? _value;

  /// When the last load finished, whatever it found. On the controller
  /// rather than on the delta: an unchanged answer keeps its object (see
  /// [_run]) but is still freshly read.
  DateTime? _readAt;

  bool get isLoading => _inFlight != null;

  /// The load in flight, or null.
  Future<void>? get pending => _inFlight;
  Future<void>? _inFlight;
  var _again = false;

  Object? get failure => _failure;
  Object? _failure;

  /// Files (worktree-relative) each owner wants reach computed for. The
  /// previews and scenarios cores each register theirs per package, and one
  /// load answers for the union.
  final _tracked = <String, Set<String>>{};

  final _listeners = <void Function()>[];

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (var listener in [..._listeners]) {
      listener();
    }
  }

  /// Registers the entry files [owner]'s scan found, and looks again.
  ///
  /// Always looks, whether or not the set moved: a scan lands because a file
  /// was saved, and the save is exactly what the tint is behind on. An edit
  /// inside an existing entry changes no set at all. The read is cheap when
  /// nothing changed (see [tick]) and coalesced when one is running.
  void track(String owner, Iterable<String> files) {
    _tracked[owner] = files.toSet();
    unawaited(refresh());
  }

  /// Idempotent, and a call that arrives mid-load is remembered rather than
  /// joined: the save that fired it landed after the running load read the
  /// disk. Same rule as the changes controller, for the same reason.
  Future<void> refresh() {
    if (_disposed) return Future.value();
    if (_inFlight case var running?) {
      _again = true;
      return running;
    }
    // Registered before the work starts, and cleared only if it is still
    // this load's future: a loader that failed synchronously would otherwise
    // clear the slot first and leave it pinned to a finished future.
    var done = Completer<void>();
    var running = done.future;
    _inFlight = running;
    unawaited(
      _run().whenComplete(() {
        if (identical(_inFlight, running)) _inFlight = null;
        // The remembered call starts before any awaiter of this one resumes,
        // which is what lets [whenSettled] follow the chain.
        if (!_disposed && _again) {
          _again = false;
          unawaited(refresh());
        }
        done.complete();
      }),
    );
    return running;
  }

  /// Resolves once no load is running or queued — the read a caller wants
  /// after registering files, since a load already in flight when they
  /// arrived was asked about the files before them. Starts one if none is.
  Future<void> whenSettled() async {
    if (_inFlight == null) unawaited(refresh());
    while (true) {
      var running = _inFlight;
      if (running == null) return;
      await running;
    }
  }

  /// [refresh], unless the last answer is younger than [staleAfter] — what a
  /// panel arriving or the window regaining focus asks.
  Future<void> refreshIfStale() {
    // Nothing registered yet means the scans have not landed: the load they
    // start on landing is the first one worth paying for, since reach is
    // computed for exactly the files they register. A read now would answer
    // for no file and be replaced a second later.
    if (_value == null && _tracked.values.every((set) => set.isEmpty)) {
      return _inFlight ?? Future.value();
    }
    var readAt = _readAt;
    if (readAt != null &&
        DateTime.now().difference(readAt) < staleAfter &&
        _failure == null) {
      return _inFlight ?? Future.value();
    }
    return refresh();
  }

  Future<void> _run() async {
    var changed = false;
    try {
      var files = {for (var set in _tracked.values) ...set};
      var delta = await _load(
        BranchDeltaRequest(
          worktreePath: worktreePath,
          files: files,
          packageConfigs: [
            p.join(worktreePath, '.dart_tool', 'package_config.json'),
            for (var package in packages)
              if (package != '.')
                p.join(
                  worktreePath,
                  package,
                  '.dart_tool',
                  'package_config.json',
                ),
          ],
          previous: _value,
        ),
      );
      if (_disposed) return;
      // **The previous object survives an unchanged answer.** Everything
      // painted from it is memoised on its identity, and most ticks on a
      // checkout nobody is typing in produce this exact answer again.
      var previous = _value;
      if (previous == null || !previous.sameAnswerAs(delta)) {
        _value = delta;
        changed = true;
      }
      if (_failure != null) changed = true;
      _failure = null;
      _readAt = DateTime.now();
    } on Object catch (error) {
      if (_disposed) return;
      // The last good answer survives a failed reload.
      _failure = error;
      changed = true;
    } finally {
      if (!_disposed && changed) _notify();
    }
  }

  /// A panel that paints from this is on screen. While any is, the delta is
  /// re-read every [tick]; arriving asks for a fresh one if what is held is
  /// stale.
  void attach() {
    _attached++;
    unawaited(refreshIfStale());
    _timer ??= Timer.periodic(tick, (_) => refresh());
  }

  void detach() {
    _attached--;
    if (_attached <= 0) {
      _attached = 0;
      _timer?.cancel();
      _timer = null;
    }
  }

  var _attached = 0;
  Timer? _timer;

  bool get isAttached => _attached > 0;

  var _disposed = false;

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _listeners.clear();
  }
}
