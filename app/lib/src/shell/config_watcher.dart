import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../plugins/manifest_loader.dart';

/// Fires when a worktree's `tool/flutterware.dart` changes on disk.
///
/// **Small on purpose.** It is the last piece of the reload work and the least
/// of it: everything that makes an automatic reload safe — a failed load
/// changing nothing, an unchanged manifest costing nothing, only the plugins
/// whose declaration moved being rebuilt — is in the reload itself, and was
/// built and driven by hand before this existed. What is left here is deciding
/// *when* to call it.
///
/// Three things it has to get right, and each one is a way file watching
/// normally feels broken:
///
/// - **Watch the directory, not the file.** Editors save atomically — write a
///   temporary file, rename it over the target — which replaces the inode. A
///   watch on the file itself survives exactly one save and then goes quiet
///   forever, with nothing to say it has.
/// - **Debounce, then re-read.** One save can produce several events, and a
///   truncate-then-write editor can be observed mid-write.
/// - **Compare content, not events.** A save-all, or a formatter that produces
///   the bytes that were already there, must cost nothing at all — not even the
///   ~45ms of re-running the config and the log row that would come with it.
///
/// What it does *not* watch is the config's import closure. Once a callback body
/// can live in `tool/plugins/thing.dart`, a change there has to count, and the
/// authoritative closure is the source list `frontend_server` reports from each
/// compile — which arrives with the resident compiler in phase 3. Until then the
/// config's own directory is the floor, and it covers the case that exists.
class ConfigWatcher {
  ConfigWatcher({
    required this.worktreePath,
    required this.onChanged,
    this.debounce = const Duration(milliseconds: 250),
    this.onError,
    Stream<WatchEvent> Function(String directory)? watch,
  }) : _watch = watch ?? ((dir) => DirectoryWatcher(dir).events);

  final String worktreePath;

  /// Called after [debounce] has settled and the file's bytes really moved.
  ///
  /// Awaited: events that arrive while a reload is running are coalesced into
  /// one follow-up rather than starting a second cycle underneath it.
  final Future<void> Function() onChanged;

  final Duration debounce;

  /// Reports a reload that threw. There is nobody to rethrow *to* — [_fire]
  /// runs from a timer — so an unreported failure here would be genuinely
  /// silent, which is the one outcome this class must not produce.
  final void Function(Object error)? onError;

  final Stream<WatchEvent> Function(String directory) _watch;

  // Cancelled in [dispose], which the shell calls when a tab closes.
  // ignore: cancel_subscriptions
  StreamSubscription<WatchEvent>? _events;
  Timer? _settle;

  /// The hash of the content the last fire was for — *not* of the content the
  /// running manifest came from.
  ///
  /// The distinction matters on the error path. A file that goes good → broken
  /// → broken-again must fire once: the second save changed nothing, and
  /// re-running would reproduce the same error. Keying on the last fire gets
  /// that; keying on the last *successful* load would fire again and again while
  /// the file stayed broken.
  String? _lastFired;

  String get configPath => p.join(worktreePath, configFilePath);

  /// The directory being watched, or null when there is nothing to watch.
  String? get watching {
    var dir = p.dirname(configPath);
    return Directory(dir).existsSync() ? dir : null;
  }

  bool get isWatching => _events != null;

  /// Begins watching, or does nothing when the worktree has no config directory.
  ///
  /// A project that grows a `tool/flutterware.dart` mid-session is not picked up
  /// — watching the worktree root to catch it would mean a recursive watch over
  /// `.git` and every build directory, which is a real cost for a rare moment.
  /// The Reload button covers it.
  /// Throws if the config cannot be read at all. The caller must not leave a
  /// watcher in place that failed here: [watching] answers from the filesystem,
  /// so it would keep naming a directory nothing is listening to — the "looks
  /// armed and is not" state the enable switch exists to make visible.
  Future<void> start() async {
    if (_events != null || _disposed) return;
    var dir = watching;
    if (dir == null) return;

    // Before the subscription, so a failure leaves nothing half-started.
    _lastFired = _hash();
    _events = _watch(dir).listen(_onEvent, onError: (Object _) {});
  }

  void _onEvent(WatchEvent event) {
    if (!p.equals(event.path, configPath)) return;
    _arm();
  }

  void _arm() {
    _settle?.cancel();
    _settle = Timer(debounce, _fire);
  }

  /// True while [onChanged] is running, so a save landing mid-reload becomes one
  /// follow-up instead of a second reload racing the first.
  var _running = false;
  var _againWhenDone = false;

  var _disposed = false;

  Future<void> _fire() async {
    if (_disposed) return;
    if (_running) {
      _againWhenDone = true;
      return;
    }

    // **A file passing through nothing is not a file with nothing in it.** An
    // editor that truncates before writing, and `git checkout`, both leave the
    // config momentarily empty — and acting on that produces "it printed
    // nothing", which is a red banner for a file that is fine. Give it one more
    // settle before believing it. A config that really was emptied or deleted
    // still lands, 250ms later.
    var file = File(configPath);
    if (!file.existsSync() || file.lengthSync() == 0) {
      if (!_confirmingEmpty) {
        _confirmingEmpty = true;
        _arm();
        return;
      }
    }
    _confirmingEmpty = false;

    String? hash;
    try {
      hash = _hash();
    } on FileSystemException {
      // Being written right now, despite the debounce. Try again rather than
      // guess, and never just drop it.
      _arm();
      return;
    }
    if (hash == _lastFired) return;
    _lastFired = hash;

    _running = true;
    try {
      await onChanged();
    } catch (e) {
      // Rewound, so the *same* bytes can fire again — otherwise a save that
      // blew up leaves the file looking already-handled and re-saving it does
      // nothing at all.
      _lastFired = null;
      onError?.call(e);
    } finally {
      _running = false;
      // Disposed while the reload ran: `dispose` cannot cancel an awaited call,
      // so the follow-up has to check. Without this, switching the watch off
      // mid-reload still landed one more reload afterwards.
      if (_againWhenDone && !_disposed) {
        _againWhenDone = false;
        // Straight to the check: the debounce already elapsed for that event.
        unawaited(_fire());
      }
    }
  }

  var _confirmingEmpty = false;

  /// Null when the file is absent — which is itself a change worth firing for,
  /// since a config that disappears means a worktree with no plugins.
  ///
  /// Throws [FileSystemException] when it cannot be read, which [_fire] answers
  /// by waiting another cycle. Returning the previous hash instead would have
  /// been quieter and wrong: with no further event to come, the save would be
  /// dropped without a word, which is the one thing this whole surface exists
  /// to avoid.
  String? _hash() {
    var file = File(configPath);
    if (!file.existsSync()) return null;
    return '${sha1.convert(file.readAsBytesSync())}';
  }

  Future<void> dispose() async {
    _disposed = true;
    _againWhenDone = false;
    _settle?.cancel();
    var events = _events;
    _events = null;
    await events?.cancel();
  }
}
