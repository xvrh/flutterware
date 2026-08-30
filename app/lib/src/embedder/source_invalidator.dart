import 'dart:io';

import 'package:path/path.dart' as p;

/// Which of a compile's sources have been edited since the last look.
///
/// `frontend_server` invalidates nothing on its own. Its `recompile` request
/// *is* the invalidation — the compiler drops exactly the libraries named in it
/// and serves every other one from the state it already has — so a caller that
/// names nothing gets its previous program back, however much the files on disk
/// have moved. Somebody has to stat the world and say what changed; in
/// `flutter run` that is `ProjectFileInvalidator`
/// (`packages/flutter_tools/lib/src/run_hot.dart`), and this is ours.
///
/// It keeps a modification time per file rather than one `lastCompiled` stamp
/// for the whole set, because a change is a change in either direction: a
/// branch switch or a `git stash` can hand a file back an *older* mtime, which
/// an `isAfter(lastCompiled)` test reads as untouched.
class SourceInvalidator {
  SourceInvalidator({Iterable<String> ignoredRoots = const []})
    : _ignored = [
        for (var root in ignoredRoots)
          if (root.isNotEmpty) p.normalize(root),
      ];

  /// Directory trees never worth statting: the SDK and the pub cache hold most
  /// of a compile's sources and none of the files anyone is editing.
  final List<String> _ignored;

  /// The last modification time seen per file, or null for one that was not
  /// there. Both are answers — a source that disappears has changed.
  final _seen = <Uri, DateTime?>{};

  /// How many files the last [sweep] statted.
  int get watched => _watched;
  var _watched = 0;

  Duration get lastSweep => _lastSweep;
  var _lastSweep = Duration.zero;

  /// The subset of [sources] whose file changed since the previous sweep.
  ///
  /// A file seen for the first time is recorded and *not* reported: the first
  /// sweep establishes the baseline that later ones are read against, which is
  /// why the daemon takes one as soon as the cold compile lands rather than
  /// waiting for the first request.
  ///
  /// [compiledAt] is the exception, and it exists because that baseline rule
  /// assumes the compile it follows was made *from these files*. A compiler
  /// started with `--initialize-from-dill` holds libraries somebody else
  /// compiled, possibly before the files on disk were edited — and it will
  /// serve them forever, because `recompile` only drops what it is told to
  /// drop and the baseline told it nothing. Pass when that kernel was written
  /// and a first sighting newer than it is reported rather than recorded, so
  /// exactly the files the kernel cannot reflect get recompiled.
  List<Uri> sweep(Iterable<Uri> sources, {DateTime? compiledAt}) {
    var watch = Stopwatch()..start();
    var invalidated = <Uri>[];
    var watched = 0;
    for (var uri in sources) {
      // `package:` and `dart:` sources arrive resolved; anything that is still
      // a scheme is not a path we can stat.
      if (uri.scheme != 'file') continue;
      var path = uri.toFilePath();
      if (_isIgnored(path)) continue;
      watched++;

      var stat = FileStat.statSync(path);
      var modified = stat.type == FileSystemEntityType.notFound
          ? null
          : stat.modified;
      var known = _seen.containsKey(uri);
      var previous = _seen[uri];
      _seen[uri] = modified;
      if (known) {
        if (modified != previous) invalidated.add(uri);
      } else if (compiledAt != null &&
          modified != null &&
          modified.isAfter(compiledAt)) {
        invalidated.add(uri);
      }
    }
    _watched = watched;
    _lastSweep = watch.elapsed;
    return invalidated;
  }

  bool _isIgnored(String path) =>
      _ignored.any((root) => p.isWithin(root, path));
}
