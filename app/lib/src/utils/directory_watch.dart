/// One directory, watched recursively, coalesced — and nothing above that.
///
/// Extracted from `worktrees/watchers.dart`, which built it for the explorer
/// and the changes screen and measured it there. What made it worth pulling out
/// is a third caller with the same shape and a different filter: the scenario
/// list, which has to notice a `_test.dart` appearing under `test/` while
/// somebody watches the panel.
///
/// The timing rules are the part worth having once. A debounce alone is not
/// enough — an agent writing steadily never offers the quiet moment a debounce
/// waits for, so the screen would update either never or on every write — and a
/// floor alone fires on the first event of a burst, before the burst is over.
/// [Coalescer] is both, and it is the reason this file exists rather than three
/// classes each with their own timer.
library;

import 'dart:async';
import 'dart:io';

/// How a directory is watched: a stream of **paths that changed**, nothing more.
///
/// Injectable, so the timing rules can be tested without a filesystem. Paths
/// rather than `FileSystemEvent` for two reasons: it is all any of this uses
/// (any event means "look again"), and dart:io's event classes have private
/// constructors, so a test could not have made one.
typedef WatchDirectory =
    Stream<String> Function(String path, {required bool recursive});

/// Whether a changed path is worth waking anything for.
typedef WatchFilter = bool Function(String path);

/// The default [WatchDirectory] — `dart:io`, projected down to paths.
Stream<String> watchDirectoryPaths(String path, {required bool recursive}) =>
    Directory(path).watch(recursive: recursive).map((event) => event.path);

/// A recursive watch on [directory], reported as a coalesced "something moved".
///
/// **Never throws, and never guesses.** A directory that is not there, a
/// platform that refuses, a system out of watches: each costs one live signal
/// and nothing else, reported through [onFailure] and visible as
/// [isWatching] — so a surface that has silently stopped being live can say so
/// rather than looking fine.
class DirectoryWatch {
  DirectoryWatch({
    required this.directory,
    this.accept,
    this.debounce = const Duration(milliseconds: 300),
    this.minInterval = const Duration(seconds: 1),
    WatchDirectory? watch,
    DateTime Function()? now,
    this.onFailure,
  }) : _watch = watch ?? watchDirectoryPaths,
       _now = now ?? DateTime.now;

  final String directory;

  /// Which changed paths count. Null accepts everything.
  ///
  /// The filter is where callers differ, and it is usually the whole reason a
  /// watch is affordable: the run dir keeps `stack-*` out of a server's log
  /// lines, the changes screen keeps `.git/objects` out of a fetch, the
  /// scenario list keeps everything that is not Dart out of a build directory.
  final WatchFilter? accept;

  /// How long a burst is allowed to settle. One save is several writes.
  final Duration debounce;

  /// The floor between two fires. See the library comment.
  final Duration minInterval;

  final WatchDirectory _watch;
  final DateTime Function() _now;

  /// Told when the watch could not be established. Liveness, never correctness.
  final void Function(Object error)? onFailure;

  Stream<void> get changes => _changes.stream;
  final _changes = StreamController<void>.broadcast();

  /// Whether a watch is actually established. False before [start], and after
  /// a [start] that could not.
  bool get isWatching => _subscription != null;

  StreamSubscription<String>? _subscription;
  late final _coalescer = Coalescer(
    debounce: debounce,
    minInterval: minInterval,
    now: _now,
    fire: () {
      if (!_changes.isClosed) _changes.add(null);
    },
  );

  /// Begins watching. Idempotent, and never throws.
  void start() {
    if (_started) return;
    _started = true;
    try {
      if (!Directory(directory).existsSync()) return;
      _subscription = _watch(directory, recursive: true).listen(
        (changed) {
          if (accept != null && !accept!(changed)) return;
          _coalescer.poke();
        },
        onError: (Object error) => onFailure?.call(error),
        cancelOnError: true,
      );
    } catch (e) {
      onFailure?.call(e);
    }
  }

  var _started = false;

  Future<void> dispose() async {
    _coalescer.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    await _changes.close();
  }
}

/// Debounce with a floor: settles a burst, and never fires faster than
/// [minInterval] however hard it is poked.
class Coalescer {
  Coalescer({
    required this.debounce,
    required this.minInterval,
    required this.fire,
    required this.now,
  });

  final Duration debounce;
  final Duration minInterval;
  final void Function() fire;
  final DateTime Function() now;

  var _pending = false;
  Timer? _timer;
  DateTime? _firedAt;

  void poke() {
    _pending = true;
    if (_timer != null) return;

    var wait = debounce;
    if (_firedAt case var at?) {
      var remaining = minInterval - now().difference(at);
      if (remaining > wait) wait = remaining;
    }
    _timer = Timer(wait, () {
      _timer = null;
      if (!_pending) return;
      _pending = false;
      _firedAt = now();
      fire();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
