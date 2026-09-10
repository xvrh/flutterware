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

  /// When the previous [sweep] began, or null before the first.
  DateTime? _sweptAt;

  /// The subset of [sources] whose file changed since the compiler read it.
  ///
  /// A file already seen is compared against the modification time the last
  /// sweep recorded for it. A file seen for the first time has no record: it
  /// entered the program in a compile that ran *after* the previous sweep, so
  /// it is compared against that sweep's start — no compile since can have
  /// read it earlier — and reported when it moved later.
  ///
  /// Recording a first sighting as the baseline, which is what this used to
  /// do, lost exactly one edit: a new file compiled, edited, and only then
  /// swept had its edit taken for the version the compiler held. The catalog
  /// served that file's first version until something else touched it.
  ///
  /// The bound is early rather than exact — a file written between a sweep and
  /// the compile after it is recompiled for nothing — and it rests on nobody
  /// sweeping while a compile is in flight, which both callers guarantee by
  /// doing the two in turn.
  ///
  /// [compiledAt] replaces that bound, and the first sweep has no other: pass
  /// when the compile it follows began, or — for a compiler started with
  /// `--initialize-from-dill` — when that kernel was written. Such a compiler
  /// holds libraries somebody else compiled, possibly before the files on disk
  /// were edited, and serves them forever, because `recompile` only drops what
  /// it is told to drop. Without either, the first sweep records everything it
  /// sees as the baseline.
  List<Uri> sweep(Iterable<Uri> sources, {DateTime? compiledAt}) {
    var watch = Stopwatch()..start();
    var readSince = compiledAt ?? _sweptAt;
    _sweptAt = DateTime.now();
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
      } else if (readSince != null &&
          modified != null &&
          modified.isAfter(readSince)) {
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
