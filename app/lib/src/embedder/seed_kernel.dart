import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

import '../utils/run_dir.dart';
import 'frontend_server.dart';
import 'source_invalidator.dart';

/// A kernel of the half of a program that no checkout owns.
///
/// A warm kernel is per *worktree*, because it holds the project's own sources
/// and their absolute paths. Everything else it holds — the framework, the SDK,
/// every resolved dependency — lives outside the worktree and is byte-for-byte
/// the same for every checkout on the machine, and that is by far the larger
/// half. So the first worktree to compile leaves a kernel of only that half
/// behind, and every worktree opened afterwards starts from it instead of from
/// nothing.
///
/// Measured on this repo's catalog in a freshly created worktree: **5.5s cold
/// against 1.5s seeded**, for a 82MB seed. A consumer's numbers are larger in
/// both columns — their cold compile was measured at ~15s.
///
/// Two rules make it safe to share, and they are the whole design:
///
/// * **Only immutable roots go in.** A library is a candidate when its file
///   lives under the Flutter SDK or the pub cache — the two trees where the way
///   you change something is to resolve a different version, which moves its
///   path. A path dependency is *not* immutable, so a sibling package somebody
///   edits daily stays out and keeps being compiled per worktree.
/// * **Every package in the seed must still resolve where it did.** Recorded by
///   name and resolved directory in a manifest beside the kernel, and compared
///   against the current resolution before the seed is handed to a compiler.
///
/// The second rule is what makes a stale seed cost nothing rather than 500ms:
/// the compiler would recover from one on its own — measured, a moved package's
/// new code lands in the output either way — but it recovers by throwing the
/// whole seed away, and a seed thrown away is 82MB loaded for nothing. Better
/// not to hand it over.
///
/// Invalidation is all-or-nothing on the compiler's side, so it is worth being
/// precise about what goes in the manifest. Measured, with one dependency moved
/// to a new path: a package the program **uses** costs the entire seed (1.6s →
/// 6.1s, worse than no seed at all), and a package it does not use costs
/// nothing (1.57s). Recording only what the seed actually contains is therefore
/// not a nicety — most of a lockfile's churn is in packages the program never
/// imports, and keying on all of them would discard the seed for every one of
/// them.
class SeedStore {
  SeedStore({required this.engineRevision, required this.flavor, String? root})
    : _root = root ?? p.join(flutterwareDir(), 'kernels');

  /// The engine the seed was compiled against. A kernel from another one is not
  /// a starting point, it is a wrong answer — so it keys the directory rather
  /// than being checked inside it.
  final String engineRevision;

  /// The compiler flags the seed was produced under, as one string.
  ///
  /// A kernel compiled with creation locations is not a starting point for a
  /// compiler running without them, or the other way round, so this keys the
  /// directory rather than being checked inside it. It is the flag list itself
  /// rather than a boolean so that two lanes reach the same seed exactly when
  /// they would produce the same kernel — the catalog daemon and the scenario
  /// harness both compile with `--track-widget-creation`, and so share one.
  final String flavor;

  final String _root;

  /// How many seeds one engine keeps. Each is the size of a whole program's
  /// kernel, so this is a disk budget, not a cache-hit policy: three lets a
  /// couple of projects and a dependency bump coexist without any of them
  /// paying a cold compile, at ~250MB.
  static const keep = 3;

  /// How long an engine's seeds survive without being started from. An SDK
  /// upgrade orphans a whole directory of them, and nothing else would.
  static const forget = Duration(days: 14);

  late final String directory = p.join(
    _root,
    sha1
        .convert(utf8.encode('$engineRevision $flavor'))
        .toString()
        .substring(0, 16),
  );

  /// A seed every one of whose packages still resolves where it did, or null.
  ///
  /// Also the moment the store tidies up — a daemon start is rare, and it is
  /// the only caller that comes through here.
  SeedKernel? find(PackageConfig resolution) {
    var found = <SeedKernel>[];
    for (var manifest in _manifests()) {
      var seed = SeedKernel._read(manifest);
      if (seed == null) continue;
      if (!seed.matches(resolution)) continue;
      found.add(seed);
    }
    // The one that holds the most, when a resolution validates more than one —
    // a seed built before a dependency was added is still valid and still
    // smaller than the one built after it.
    found.sort((a, b) => b.packages.length.compareTo(a.packages.length));
    var seed = found.firstOrNull;
    if (seed != null) {
      // Touched so [_sweep] evicts what nobody starts from, rather than what
      // happened to be built first.
      try {
        File(seed.kernelPath).setLastModifiedSync(DateTime.now());
      } catch (_) {
        // An unwritable cache is still a readable one.
      }
    }
    // **After the choice, never before.** Sweeping first lets a lookup evict
    // the very seed it was about to return: [keep] is 3, so a machine holding
    // four resolutions would delete the oldest — which on the day you come back
    // to a project you have not opened in a while is *that project's* — then
    // find nothing, compile cold, and write the seed again, evicting the next
    // one. Four projects would round-robin at zero hits, each start slower than
    // if there were no cache at all.
    _sweep();
    return seed;
  }

  /// Writes the root a seed for [plan] is compiled from, and says where its
  /// kernel and manifest will go.
  ///
  /// **The root lives here rather than in the checkout that compiles it.** A
  /// kernel records the file uri of every library in it, its root included, so
  /// a root under a worktree is the one thing that would make an otherwise
  /// worktree-independent seed name a directory nobody else has. Written where
  /// it is named — by a hash of the manifest — two checkouts building the same
  /// seed write the same bytes to the same path, and the kernels they produce
  /// are identical.
  SeedDraft draft(SeedPlan plan) {
    var (manifest, name) = _identify(plan);
    Directory(directory).createSync(recursive: true);
    var entrypoint = p.join(directory, '$name.dart');
    // **Atomically, and only when it would change anything.** Naming the root
    // by its manifest is what makes two checkouts produce the same kernel, and
    // it also aims them at one path: a plain write truncates the file another
    // checkout's compiler is that moment reading, and a half-read root is not a
    // failure — it is a *smaller seed* that looks like a whole one.
    writeFileAtomically(File(entrypoint), plan.source);
    return SeedDraft._(this, name, manifest, entrypoint);
  }

  /// The manifest [plan] is recorded under, and the name that hashes to.
  ///
  /// Split out of [draft] because deciding whether a seed is worth writing has
  /// to be able to ask whether this exact one is already here, and [draft]
  /// writes a file on its way to answering.
  (String, String) _identify(SeedPlan plan) {
    var manifest = jsonEncode({
      'engine': engineRevision,
      'flavor': flavor,
      'packages': {
        for (var name in plan.packages.keys.toList()..sort())
          name: plan.packages[name],
      },
    });
    return (
      manifest,
      sha1.convert(utf8.encode(manifest)).toString().substring(0, 16),
    );
  }

  /// Whether this store already holds the seed [plan] would produce.
  ///
  /// Exact rather than approximate — a name is the hash of the manifest, so
  /// this answers about the artifact itself and not about anything resembling
  /// it. That is what makes [writeSeedKernel] safe to *decide* from the cheaper
  /// estimate in [reachedPackages]: an estimate that came out a package too
  /// high stops here, once, instead of compiling the same seed again on every
  /// start for ever.
  bool holds(SeedPlan plan) =>
      File(p.join(directory, '${_identify(plan).$2}.dill')).existsSync();

  List<File> _manifests() {
    try {
      return [
        for (var entity in Directory(directory).listSync())
          if (entity is File && entity.path.endsWith('.json')) entity,
      ];
    } on FileSystemException {
      return const [];
    }
  }

  /// Drops other engines' seeds once nothing has started from them, and keeps
  /// this engine's down to [keep].
  void _sweep() {
    var cutoff = DateTime.now().subtract(forget);
    try {
      for (var entity in Directory(_root).listSync()) {
        if (entity is! Directory || entity.path == directory) continue;
        var kernels = <DateTime>[
          for (var file in entity.listSync())
            if (file is File && file.path.endsWith('.dill'))
              file.statSync().modified,
        ];
        // **A directory holding no kernel is not therefore an old one.**
        // [draft] creates the directory and writes the root before anything
        // else, and the kernel arrives as a `.dill.<pid>.tmp` that is renamed
        // into place at the end — so for the whole of another process's
        // excursion, its directory contains no `.dill` at all. Read as expired
        // it would be deleted recursively, taking the root that process's
        // compiler is that moment reading. Its own timestamp is what tells a
        // directory being built in from one a previous sweep emptied.
        var newest = kernels.isEmpty
            ? entity.statSync().modified
            : kernels.reduce((a, b) => a.isAfter(b) ? a : b);
        if (newest.isAfter(cutoff)) continue;
        entity.deleteSync(recursive: true);
      }
    } on FileSystemException {
      // Housekeeping. Another process winning the race is the expected case.
    }

    var kernels = <File>[];
    try {
      for (var entity in Directory(directory).listSync()) {
        if (entity is File && entity.path.endsWith('.dill')) {
          kernels.add(entity);
        }
      }
    } on FileSystemException {
      return;
    }
    if (kernels.length <= keep) return;
    kernels.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    for (var stale in kernels.skip(keep)) {
      for (var file in [
        stale,
        File(p.setExtension(stale.path, '.json')),
        File(p.setExtension(stale.path, '.dart')),
      ]) {
        try {
          if (file.existsSync()) file.deleteSync();
        } catch (_) {
          // Left for the next sweep.
        }
      }
    }
  }
}

/// Where pub keeps its packages.
///
/// A dependency is immutable by construction — the way you change one is to
/// resolve a different version, which rewrites the package config and
/// recompiles anyway. That is what makes this tree both skippable by a
/// [SourceInvalidator] and shareable by a [SeedStore].
List<String> pubCacheRoots() {
  var env = Platform.environment;
  var home = env[Platform.isWindows ? 'LOCALAPPDATA' : 'HOME'];
  return [
    ?env['PUB_CACHE'],
    if (home != null)
      Platform.isWindows
          ? p.join(home, 'Pub', 'Cache')
          : p.join(home, '.pub-cache'),
  ];
}

/// How a compile's extra flags name themselves to a [SeedStore].
///
/// Sorted, so two lanes passing the same flags in a different order reach the
/// same seed. Two lanes passing *different* flags must not, which is the whole
/// reason this is the flag list rather than a version number.
String seedFlavor(List<String> arguments) =>
    (arguments.toList()..sort()).join(' ');

/// A seed being written: its root is on disk, its kernel is not yet.
class SeedDraft {
  SeedDraft._(this._store, this._name, this._manifest, this.entrypoint);

  final SeedStore _store;
  final String _name;
  final String _manifest;

  /// The root to compile. Holds an empty `main` and an import of every library
  /// the seed is to contain.
  final String entrypoint;

  /// Publishes the kernel [writeKernel] leaves at the seed's path, and returns
  /// that path — or null if nothing could be written.
  ///
  /// Best effort: this is a cache, and a machine that cannot write it pays the
  /// cold compile it was already paying.
  String? commit(void Function(String destination) writeKernel) {
    try {
      var kernel = p.join(_store.directory, '$_name.dill');
      writeKernel(kernel);
      if (!File(kernel).existsSync()) return null;
      // After the kernel, never before: a manifest is a promise that the file
      // beside it is loadable, and a reader that finds one without the other
      // would hand a compiler a path that is not there.
      writeFileAtomically(
        File(p.join(_store.directory, '$_name.json')),
        _manifest,
      );
      _store._sweep();
      return kernel;
    } catch (e) {
      stderr.writeln('[catalog] could not record a seed kernel: $e');
      return null;
    }
  }
}

/// One seed on disk: a kernel and the resolution it was compiled against.
class SeedKernel {
  SeedKernel({required this.kernelPath, required this.packages});

  static SeedKernel? _read(File manifest) {
    try {
      var json = jsonDecode(manifest.readAsStringSync());
      if (json is! Map) return null;
      var packages = json['packages'];
      if (packages is! Map) return null;
      var kernel = p.setExtension(manifest.path, '.dill');
      if (!File(kernel).existsSync()) return null;
      return SeedKernel(
        kernelPath: kernel,
        packages: {
          for (var entry in packages.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
        },
      );
    } catch (_) {
      return null;
    }
  }

  final String kernelPath;

  /// Package name to the directory it resolved to when the seed was compiled.
  final Map<String, String> packages;

  /// Whether every package this seed holds still resolves where it did.
  ///
  /// A package that has *gone* fails too: the seed's libraries name files that
  /// are no longer anybody's, and the compiler would load them only to discard
  /// the lot.
  bool matches(PackageConfig resolution) {
    for (var entry in packages.entries) {
      var package = resolution[entry.key];
      if (package == null) return false;
      if (packageDirectory(package) != entry.value) return false;
    }
    return true;
  }
}

/// Where a package resolved to, as a comparable string.
///
/// The `lib/` directory rather than the package root, because that is the part
/// the compiler reads and the part a version bump moves.
String packageDirectory(Package package) =>
    p.normalize(package.packageUriRoot.toFilePath());

/// What a seed for [sources] would be built from.
///
/// Null when there is nothing worth sharing — a project with no resolved
/// dependencies compiled against a Flutter SDK that is somehow not an immutable
/// root, which is to say a test.
SeedPlan? planSeed({
  required Iterable<Uri> sources,
  required PackageConfig resolution,
  required List<String> immutableRoots,
}) {
  var candidates = [
    for (var (uri, _) in _shared(sources, resolution, immutableRoots)) uri,
  ];
  if (candidates.isEmpty) return null;

  // A part cannot be imported, and one that slips in fails the whole seed
  // compile rather than its own line — so both halves of the relationship are
  // read, not just the `part of` a file declares about itself. The read is the
  // same one either way, and it is paid once per resolution per machine.
  var parts = <Uri>{};
  for (var uri in candidates) {
    String text;
    try {
      text = File.fromUri(uri).readAsStringSync();
    } catch (_) {
      parts.add(uri);
      continue;
    }
    if (_partOf.hasMatch(text)) {
      parts.add(uri);
      continue;
    }
    for (var match in _partDirective.allMatches(text)) {
      parts.add(uri.resolve(match.group(1)!));
    }
  }

  var imports = <String>[];
  var packages = <String, String>{};
  for (var uri in candidates) {
    if (parts.contains(uri)) continue;
    var packageUri = resolution.toPackageUri(uri)!;
    var package = resolution[packageUri.pathSegments.first];
    if (package == null) continue;
    imports.add('$packageUri');
    packages[package.name] = packageDirectory(package);
  }
  if (imports.isEmpty) return null;
  imports.sort();
  return SeedPlan(imports: imports, packages: packages);
}

/// The libraries under an immutable root that [sources] reached, each with the
/// `package:` uri it answers to.
///
/// The one walk both [planSeed] and [reachedPackages] read, so the exact
/// question and the cheap one cannot come to disagree about what a seed would
/// contain.
Iterable<(Uri, Uri)> _shared(
  Iterable<Uri> sources,
  PackageConfig resolution,
  List<String> immutableRoots,
) sync* {
  var roots = [
    for (var root in immutableRoots)
      if (root.isNotEmpty) p.normalize(root),
  ];
  for (var uri in sources) {
    if (uri.scheme != 'file') continue;
    if (!uri.path.endsWith('.dart')) continue;
    if (!roots.any((root) => p.isWithin(root, uri.toFilePath()))) continue;
    var packageUri = resolution.toPackageUri(uri);
    if (packageUri == null) continue;
    yield (uri, packageUri);
  }
}

/// Which packages a seed for [sources] would hold, without reading one of them.
///
/// [planSeed] answers the same question exactly, and to do it reads every
/// candidate file to find the parts — thousands of small reads. That is worth
/// paying to *write* a seed and not worth paying on a start that is only asking
/// whether writing one would gain anything, which is every start.
///
/// The two agree wherever it matters. The only file the exact answer drops that
/// this one keeps is a part, and a part lives in the package of the library
/// declaring it — which is imported, and so contributes the same name. A start
/// that estimates one package too many writes nothing anyway: [SeedStore.holds]
/// recognises the seed it would have produced.
Set<String> reachedPackages({
  required Iterable<Uri> sources,
  required PackageConfig resolution,
  required List<String> immutableRoots,
}) => {
  for (var (_, packageUri) in _shared(sources, resolution, immutableRoots))
    if (resolution[packageUri.pathSegments.first] case var package?)
      package.name,
};

/// Whether a program reaching [reached] would leave behind a better seed than
/// [improving], which is the one it started from.
///
/// **The same preference [SeedStore.find] reads by**, deliberately: the store
/// hands a program the largest seed its resolution validates, so the question
/// of whether to write one has to be asked in the same currency. A write rule
/// stricter than the read rule leaves seeds nothing will ever produce.
///
/// A strict superset was tried here first and is wrong, which only a
/// measurement showed: this repo's catalog reaches **62** packages against the
/// 20 in the seed a sample project had left — and **3 of those 20 the catalog
/// does not reach**, because a sample app uses localisations and an http client
/// that a widget gallery does not. Nested resolutions are the exception; two
/// programs sharing one workspace normally overlap and neither contains the
/// other. Under a superset rule the seed stays stunted for ever, which is the
/// bug this exists to fix.
///
/// Nothing is displaced by saying yes — a seed is written under its own
/// manifest hash and lands *beside* the one it grew from, so the project that
/// wrote the smaller one still finds it while its resolution validates it.
/// Growth is also monotone, so two projects cannot take turns: whoever reaches
/// more writes, and the one reaching less is then handed the bigger seed and
/// has nothing to write.
bool seedWouldGrow(SeedKernel improving, Set<String> reached) =>
    reached.length > improving.packages.length;

/// A `part of` directive, which is what makes a file unimportable. Anchored to
/// a line so the word in prose above it does not count.
final _partOf = RegExp(r'^\s*part\s+of[\s;]', multiLine: true);

/// A `part '…';` directive, naming a file relative to the one declaring it.
final _partDirective = RegExp(
  r"""^\s*part\s+['"]([^'"]+)['"]\s*;""",
  multiLine: true,
);

/// The entrypoint a seed is compiled from, and what it will contain.
class SeedPlan {
  SeedPlan({required this.imports, required this.packages});

  /// Every shared library the program reached, as a `package:` uri.
  final List<String> imports;

  /// Package name to resolved directory, for the manifest.
  final Map<String, String> packages;

  /// The source of the entrypoint to compile.
  ///
  /// Prefixed imports, so that two libraries declaring the same name cannot
  /// turn a seed into a compile error over a name nothing here uses.
  String get source => [
    '// Generated by flutterware. A root that reaches every library this',
    '// machine shares with every other checkout of this project, and nothing',
    '// that belongs to any one of them. See `SeedStore`.',
    for (var (index, uri) in imports.indexed) "import '$uri' as _i$index;",
    '',
    'void main() {}',
    '',
  ].join('\n');
}

/// Compiles the shared half of whatever [compiler] is holding, and records it
/// as a seed for the next checkout that has none — **or a better one than the
/// next checkout would otherwise get**.
///
/// Costs the emit of a program the compiler already has — see
/// [FrontendServer.asideAt]. Measured on this repo's catalog: **~800ms
/// including the 82MB copy**, once per resolution per machine, against the 4.4s
/// it takes off every checkout opened afterwards.
///
/// **A seed that exists is not therefore the seed to have.** [SeedStore.find]
/// already prefers the largest match and the store already keeps three, so a
/// machine is built to hold and pick the biggest seed it has — but for as long
/// as this ran only on an empty store, nothing ever wrote a second one. First
/// writer won, permanently: measured, a 20-package seed left by a sample
/// project served this repo's catalog — which reaches 62 packages — at 3877ms
/// against 1671ms for one of its own, and no start was ever going to replace
/// it. So [improving] asks the other half of the question, and
/// [seedWouldGrow] answers it in the same currency [SeedStore.find] chooses by.
///
/// Returns where the seed landed, or null when there was nothing to write or
/// nothing could be written. Nothing here is worth failing a start over: the
/// worst outcome is the cold compile that was already the status quo.
Future<String?> writeSeedKernel({
  required FrontendServer compiler,
  required String outputDill,
  required SeedStore store,
  required PackageConfig resolution,
  required List<String> immutableRoots,

  /// The seed this start actually used, when it found one. Null asks for the
  /// first seed this resolution has ever had.
  SeedKernel? improving,
  void Function(String)? log,
}) async {
  if (improving != null) {
    var reached = reachedPackages(
      sources: compiler.sources,
      resolution: resolution,
      immutableRoots: immutableRoots,
    );
    // Said either way, and in one line, because this is the fact a slow start
    // raises and nothing else records: a seed holding a fraction of what the
    // program reaches is a seed that saved a fraction of the compile.
    var missing = reached.difference(improving.packages.keys.toSet());
    log?.call(
      'the seed this start used holds ${improving.packages.length} packages; '
      'this program reaches ${reached.length}, '
      'of which ${missing.length} are not in it',
    );
    // Answered before [planSeed] reads a file, because this is the branch every
    // ordinary start takes: the seed on disk is this project's own, the counts
    // agree, and there is nothing here to do.
    if (!seedWouldGrow(improving, reached)) return null;
  }
  var plan = planSeed(
    sources: compiler.sources,
    resolution: resolution,
    immutableRoots: immutableRoots,
  );
  if (plan == null) return null;
  // The exact form of the question the estimate above answered approximately.
  // An estimate one package high would otherwise send every start of this
  // project on the same excursion to write a seed that is already here.
  if (store.holds(plan)) return null;
  SeedDraft draft;
  try {
    draft = store.draft(plan);
  } catch (e) {
    log?.call('could not write a seed root: $e');
    return null;
  }
  return compiler.asideAt(draft.entrypoint, (result) async {
    if (!result.ok) {
      // Nothing here is the project's fault and nothing is worth failing over:
      // the next checkout compiles cold, exactly as it does today.
      log?.call(
        'the shared half did not compile on its own; no seed written:\n'
        '${result.output.take(5).join('\n')}',
      );
      return null;
    }
    var at = draft.commit((to) => copyKernelAtomically(outputDill, to));
    if (at != null) {
      log?.call(
        '${improving == null ? 'seeded' : 'reseeded'} ${plan.imports.length} '
        'shared libraries from ${plan.packages.length} packages at $at',
      );
    }
    return at;
  });
}

/// Writes [contents] beside [file] and renames it into place, skipping the
/// write when the file already says exactly that.
///
/// Everything in a seed directory is shared by processes that are not each
/// other's, so a reader can arrive mid-write. A rename is the only write that
/// has no middle — and on POSIX it leaves a reader that already opened the old
/// file reading it to the end, rather than under it.
void writeFileAtomically(File file, String contents) {
  try {
    if (file.existsSync() && file.readAsStringSync() == contents) return;
  } catch (_) {
    // Unreadable is a reason to write, not a reason to stop.
  }
  var staged = File('${file.path}.$pid.tmp');
  try {
    staged.writeAsStringSync(contents);
    staged.renameSync(file.path);
  } catch (_) {
    if (staged.existsSync()) {
      try {
        staged.deleteSync();
      } catch (_) {
        // Nothing left to try; the next write overwrites it.
      }
    }
    rethrow;
  }
}

/// Copies the kernel at [from] to [to], beside itself and then renamed.
///
/// Best effort, and silent: everything written this way is a cache, and a
/// destination that cannot be written costs the next start its head start
/// rather than costing this one anything. The rename is what makes it safe to
/// share — a reader arriving mid-write must see a whole kernel or none, and a
/// copy straight onto the path lets it see half of one.
void copyKernelAtomically(String from, String to) {
  if (!File(from).existsSync()) return;
  Directory(p.dirname(to)).createSync(recursive: true);
  var staged = File('$to.$pid.tmp');
  try {
    File(from).copySync(staged.path);
    staged.renameSync(to);
  } catch (_) {
    if (staged.existsSync()) {
      try {
        staged.deleteSync();
      } catch (_) {
        // Nothing left to try; the next save overwrites it.
      }
    }
  }
}
