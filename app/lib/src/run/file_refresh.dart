import 'dart:async';
import 'dart:io';

/// Calls back when a file changes, so that a panel showing one does not have to
/// read it from `build`.
///
/// The panels that show a run's log and a run's journal both need this, and
/// both need it for the reason `RunCore.logOf` gives at length: a panel
/// rebuilds on every probe and on every frame of any animation above it, and a
/// file read from `build` is a file read hundreds of times for every time it
/// changed.
///
/// A watch *and* a poll. The watch is what makes a change land in 50ms; the
/// poll is there because a directory watch is not offered everywhere and does
/// not survive every kind of write, and a log that stopped updating is worse
/// than a log that updates a little late. When the watch is up the poll drops
/// to a backstop interval.
class FileRefresh {
  FileRefresh(String? path, this.onChanged) {
    if (path != null) {
      var directory = File(path).parent;
      if (directory.existsSync()) {
        _watch = directory.watch().listen((event) {
          if (!event.path.startsWith(path)) return;
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 50), onChanged);
        }, onError: (_) {});
      }
    }
    _poll = Timer.periodic(
      _watch != null
          ? const Duration(seconds: 2)
          : const Duration(milliseconds: 700),
      (_) => onChanged(),
    );
  }

  final void Function() onChanged;
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _debounce;
  Timer? _poll;

  void dispose() {
    _debounce?.cancel();
    _poll?.cancel();
    unawaited(_watch?.cancel());
  }
}
