import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'pub_deps.dart';
import 'pubspec_lock.dart';

/// One `flutter pub deps --json` per *resolution*, rather than one per package.
///
/// [PubDeps] already says its answer is workspace-wide: run anywhere inside a
/// workspace, pub reports the whole resolution. So every member's answer is the
/// same bytes — verified on this repo, three members, one md5 — and the plugin
/// nonetheless spawned one subprocess per declared package and threw two of
/// them away.
///
/// Measured 2026-09-09 on this workspace, `fw status` as a compiled kernel,
/// five runs each: **2.33s before, 1.32s warm, 1.76s cold**. The floor under
/// all three is 0.34s of VM start and session open. Per plugin (under
/// `dart run`, so read the ratios rather than the absolute values) this one was
/// 2141ms of 3753ms — six times the next — and 1870ms of that was three
/// identical ~0.6s processes.
///
/// Two caches, because they answer different questions.
///
/// **In flight**, keyed by resolution root. Collapses one wave — the
/// `Future.wait` in `computeAll`, three panels mounting together — into one
/// process. Dropped the moment it completes, and deliberately: a memo that
/// outlived the wave would make the panel's reload button a no-op and hide a
/// `pub get` that happened while the app was open. Dropped on failure too,
/// which is what keeps a retry a retry.
///
/// **On disk**, under the resolution root's `.dart_tool/flutterware/`. That is
/// the half a cold process needs — `fw` and the MCP server are born for one
/// request and hold nothing, so an in-memory cache never sees them twice.
///
/// The disk key can be *exact* rather than a plausible guess: `pub deps` reads
/// the lockfile, the package config and the pubspecs of the workspace, and
/// reaches no network. All of them are in the stamp. The pubspecs matter
/// because a dependency between two workspace members is in neither the
/// lockfile nor the package config — a member is not locked — so an edge
/// added to one member's pubspec moved nothing the stamp used to read, and a
/// `pub get` served the answer from before it (measured: the example gaining
/// a dev dependency on the app, and the panel not seeing it).
class PubDepsStore {
  PubDepsStore({this.runProcess});

  /// Answers instead of spawning, so a test needs neither a resolved project
  /// nor an SDK.
  ///
  /// A store with one is a store answering from a fixture, and it therefore
  /// **writes nothing to disk and reads nothing from it**. The tests that
  /// inject one point at real directories inside this repo — leaving a
  /// fixture where the real `pub deps` answer is read back from would make a
  /// test run change what `fw status` reports afterwards.
  final RunProcess? runProcess;

  /// Bumped when the shape of what is cached changes, so an old file is a miss
  /// rather than a misread.
  static const _format = 2;

  final _inFlight = <String, Future<PubDeps>>{};

  /// The resolution governing [directory], as [PubDeps] would report it.
  Future<PubDeps> load({
    required String flutterExecutable,
    required String directory,
  }) {
    var root = resolutionRoot(directory);
    if (root == null) {
      // Never resolved. Ask per package and let pub say so in its own words —
      // there is no resolution to share, and [PubDepsFailure] names the
      // directory to run `pub get` in.
      return PubDeps.load(
        flutterExecutable: flutterExecutable,
        directory: directory,
        runProcess: runProcess,
      );
    }

    // The executable is in the key as well as in the stamp: two SDKs looking at
    // one checkout are two answers, and they must not share a wave either.
    var key = '$root $flutterExecutable';
    if (_inFlight[key] case var pending?) return pending;
    var shared = _loadForRoot(root, flutterExecutable).whenComplete(() {
      // A block, and it has to be one. `whenComplete` awaits whatever its
      // callback returns, and `Map.remove` returns the entry — which here is
      // this very future. An expression body made it wait on itself, and a
      // future that never completes with nothing else pending is a process
      // that exits 0 having done nothing at all.
      _inFlight.remove(key);
    });
    _inFlight[key] = shared;
    return shared;
  }

  /// The directory whose `pubspec.lock` governs [packagePath], or null when
  /// nothing above it has one.
  ///
  /// The lockfile is the resolution: a pub workspace keeps exactly one, at the
  /// root, and a standalone project's own is found on the first step up. Two
  /// declared packages that resolve separately — a nested project with its own
  /// lock — land on different roots and keep their own process, which is why
  /// this is a walk rather than "the session root".
  /// Normalised, because this string is a key. The root package is declared as
  /// `.`, and `<worktree>/.` and `<worktree>` are the same directory named two
  /// ways — sharing a process only if the two names collapse to one first.
  static String? resolutionRoot(String packagePath) {
    var file = PubspecLock.findFile(packagePath);
    return file == null ? null : p.normalize(p.dirname(file.path));
  }

  Future<PubDeps> _loadForRoot(String root, String flutterExecutable) async {
    var stamp = runProcess == null ? stampFor(root, flutterExecutable) : null;

    if (stamp != null) {
      var cached = _read(cacheFileFor(root, stamp));
      if (cached != null) return cached;
    }

    var json = await PubDeps.loadJson(
      flutterExecutable: flutterExecutable,
      directory: root,
      runProcess: runProcess,
    );
    // Parsed before it is written, so a cache entry is never something that
    // will not read back.
    var deps = PubDeps.parse(json);
    if (stamp != null) _write(root, stamp, json);
    return deps;
  }

  /// The cache file *is* the key: its name carries the stamp, so a file that
  /// exists is a file that matches. The alternative — a payload beside a stamp
  /// file — has a window where the two disagree, and two flutterware processes
  /// on one checkout (the studio open while an agent runs `fw status`) is the
  /// ordinary case rather than the exotic one.
  @visibleForTesting
  static File cacheFileFor(String root, String stamp) =>
      File(p.join(root, '.dart_tool', 'flutterware', 'pub_deps-$stamp.json'));

  static PubDeps? _read(File file) {
    try {
      if (!file.existsSync()) return null;
      return PubDeps.parse(file.readAsStringSync());
    } on FileSystemException {
      return null;
    } on FormatException {
      // A truncated entry is not something to report; it is something to
      // replace.
      return null;
    }
  }

  static void _write(String root, String stamp, String json) {
    var file = cacheFileFor(root, stamp);
    try {
      file.parent.createSync(recursive: true);
      // Written aside and renamed, so a reader never opens a half-written file.
      File('${file.path}.$pid.tmp')
        ..writeAsStringSync(json)
        ..renameSync(file.path);
      _sweep(file);
    } on FileSystemException {
      // A checkout nothing may write to still works; it just pays pub every
      // time.
    }
  }

  /// Drops what earlier resolutions left behind. Best effort — another process
  /// may be reading one, and on Windows that makes the delete fail.
  static void _sweep(File current) {
    for (var entry in current.parent.listSync()) {
      if (!p.basename(entry.path).startsWith('pub_deps-')) continue;
      if (entry.path == current.path) continue;
      try {
        entry.deleteSync();
      } on FileSystemException {
        // Someone else's, or in use. It goes on the next write.
      }
    }
  }

  /// Everything the answer depends on, hashed.
  ///
  /// Null when the resolution is not on disk to be hashed, which means *do not
  /// trust a cache* rather than *the cache is fine*.
  @visibleForTesting
  static String? stampFor(String root, String flutterExecutable) {
    var lock = File(p.join(root, 'pubspec.lock'));
    var packageConfig = File(p.join(root, '.dart_tool', 'package_config.json'));
    try {
      if (!lock.existsSync() || !packageConfig.existsSync()) return null;
      var parts = [
        '$_format',
        flutterExecutable,
        '${sha1.convert(lock.readAsBytesSync())}',
        '${sha1.convert(packageConfig.readAsBytesSync())}',
        for (var pubspec in _workspacePubspecs(root))
          '${sha1.convert(pubspec.readAsBytesSync())}',
      ];
      return '${sha1.convert(utf8.encode(parts.join('\n')))}';
    } on FileSystemException {
      return null;
    }
  }

  /// The root's pubspec and every workspace member's, in the root's order —
  /// the files whose edges the lockfile does not carry.
  static List<File> _workspacePubspecs(String root) {
    var rootPubspec = File(p.join(root, 'pubspec.yaml'));
    if (!rootPubspec.existsSync()) return const [];
    var files = [rootPubspec];
    if (loadYaml(rootPubspec.readAsStringSync()) case YamlMap yaml) {
      if (yaml['workspace'] case YamlList members) {
        for (var member in members) {
          var pubspec = File(p.join(root, '$member', 'pubspec.yaml'));
          if (pubspec.existsSync()) files.add(pubspec);
        }
      }
    }
    return files;
  }
}
