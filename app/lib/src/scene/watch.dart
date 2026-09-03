import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

/// Fires when a scene file under a directory moves on disk — an agent
/// writing one, a branch switch, an editor saving one by hand.
///
/// Small on purpose, and deliberately the same shape as the shell's config
/// watcher, because file watching goes wrong the same three ways every time:
///
/// - **Watch the directory, not the file.** A save is usually a write to a
///   temporary file and a rename over the target, which replaces the inode. A
///   watch on the file itself survives exactly one save and then goes quiet
///   with nothing to say it has.
/// - **Debounce.** One save is several events, and a writer that truncates
///   first can be read halfway through.
/// - **Compare content, not events, and do it in the caller.** Our own
///   automatic write comes back as an event indistinguishable from anybody
///   else's, and only the caller holds the bytes it last wrote.
class SceneWatcher {
  SceneWatcher({
    required this.directory,
    required this.onChanged,
    this.debounce = const Duration(milliseconds: 250),
    Stream<WatchEvent> Function(String directory)? watch,
  }) : _watch = watch ?? ((dir) => DirectoryWatcher(dir).events);

  final String directory;

  /// The scene files that saw an event since the last fire, canonicalized.
  final void Function(Set<String> paths) onChanged;

  final Duration debounce;
  final Stream<WatchEvent> Function(String directory) _watch;

  // Cancelled in [dispose], which the panel calls when it closes.
  // ignore: cancel_subscriptions
  StreamSubscription<WatchEvent>? _events;
  Timer? _settle;
  final _pending = <String>{};
  var _disposed = false;

  bool get isWatching => _events != null;

  /// Begins watching, or does nothing when the directory is not there. A
  /// project that grows its scene directory mid-session is picked up by the
  /// listing's own rescan rather than here.
  void start() {
    if (_events != null || _disposed) return;
    if (!Directory(directory).existsSync()) return;
    _events = _watch(directory).listen(_onEvent, onError: (Object _) {});
  }

  void _onEvent(WatchEvent event) {
    if (!event.path.endsWith('.scene.dart')) return;
    _pending.add(p.canonicalize(event.path));
    _settle?.cancel();
    _settle = Timer(debounce, _fire);
  }

  void _fire() {
    _settle = null;
    if (_disposed || _pending.isEmpty) return;
    var paths = Set<String>.from(_pending);
    _pending.clear();
    onChanged(paths);
  }

  void dispose() {
    _disposed = true;
    _settle?.cancel();
    unawaited(_events?.cancel());
    _events = null;
  }
}
