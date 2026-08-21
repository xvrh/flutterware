import 'dart:convert';
import 'dart:io';

/// The resolution pub actually performed, read from `flutter pub deps --json`.
///
/// Replaces reconstructing the graph from the pubspecs of whatever happened to
/// be in `package_config.json`, which was wrong twice over: it re-derived edges
/// pub had already resolved, and in a workspace it saw every member's packages
/// as one undifferentiated pile.
///
/// This object is workspace-wide, and deliberately so. Run from anywhere
/// inside a workspace, pub reports the whole resolution — 174 packages and
/// three `kind: root` entries for this repo — and [root] names the *workspace
/// root package*, not the directory you ran in. Scoping to one member is
/// [PubDepsPackage.devDependencies]'s job, and belongs to the caller: see
/// `DependencyResolution` in `service.dart`.
class PubDeps {
  PubDeps({required this.root, required List<PubDepsPackage> packages})
    : _packages = {for (var package in packages) package.name: package};

  /// Name of the workspace root package. **Not** the package the command ran
  /// in — in a workspace those differ, which is the trap this whole file
  /// exists to route around.
  final String root;

  final Map<String, PubDepsPackage> _packages;

  PubDepsPackage? operator [](String name) => _packages[name];

  Iterable<PubDepsPackage> get packages => _packages.values;

  /// The workspace members. In a single-package project there is exactly one,
  /// and it is the project.
  Iterable<PubDepsPackage> get members =>
      _packages.values.where((e) => e.kind == PubDepsKind.root);

  /// The member named [packageName], or null when no member goes by that name.
  PubDepsPackage? memberNamed(String packageName) {
    var package = _packages[packageName];
    return package != null && package.kind == PubDepsKind.root ? package : null;
  }

  factory PubDeps.parse(String json) {
    var map = jsonDecode(json) as Map<String, dynamic>;
    return PubDeps(
      root: map['root'] as String,
      packages: [
        for (var package in map['packages'] as List)
          PubDepsPackage.fromJson(package as Map<String, dynamic>),
      ],
    );
  }

  /// Runs `pub deps --json` in [directory], **through the Flutter SDK's
  /// `flutter`** rather than its `dart`.
  ///
  /// Not a preference. Whenever pub has to re-resolve — a touched pubspec, a
  /// moved SDK, a fresh checkout — `dart pub` refuses a package that depends on
  /// the Flutter SDK and says so itself: *"Flutter users should use `flutter
  /// pub` instead of `dart pub`"*. It appeared to work only because the `dart`
  /// being run sits inside a Flutter SDK, which lets pub infer `FLUTTER_ROOT`
  /// from its own location; an inherited-but-wrong `FLUTTER_ROOT` breaks that
  /// inference and the Dependencies panel fails to load against this very repo.
  ///
  /// Asking whether *this* package depends on Flutter would not be enough: pub
  /// resolves the whole workspace, so a pure-Dart member fails on a *sibling's*
  /// Flutter dependency. `flutter pub` is right for every package and costs
  /// ~0.13s more (measured 2026-08-13: 0.37s against 0.50s on this workspace).
  ///
  /// Fast either way, because it reads the lockfile and the package config
  /// rather than resolving anything. It does *not* reach the network, and it
  /// does not run `pub get`: an unresolved project is an error here, and says
  /// so.
  static Future<PubDeps> load({
    required String flutterExecutable,
    required String directory,
    RunProcess? runProcess,
  }) async {
    var run = runProcess ?? Process.run;
    var result = await run(flutterExecutable, const [
      'pub',
      'deps',
      '--json',
    ], workingDirectory: directory);

    if (result.exitCode != 0) {
      throw PubDepsFailure(
        directory: directory,
        exitCode: result.exitCode,
        stderr: '${result.stderr}'.trim(),
      );
    }
    return PubDeps.parse('${result.stdout}');
  }
}

typedef RunProcess =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// `pub deps` refused. Almost always an unresolved project, so the message says
/// what to run rather than only what failed.
class PubDepsFailure implements Exception {
  PubDepsFailure({
    required this.directory,
    required this.exitCode,
    required this.stderr,
  });

  final String directory;
  final int exitCode;
  final String stderr;

  @override
  String toString() =>
      'flutter pub deps failed in $directory (exit $exitCode). '
      'Run `flutter pub get` there first.'
      '${stderr.isEmpty ? '' : '\n$stderr'}';
}

/// How a package entered the resolution.
///
/// Workspace-wide, and therefore not what to show a user. Every member's
/// classification is folded into one value, so a package that is direct for
/// `app` reads as `direct` even while you are looking at `examples/example`,
/// which does not depend on it at all. Per-member direct/dev/transitive is
/// computed from the member's own [PubDepsPackage.directDependencies], not read
/// off here.
enum PubDepsKind {
  /// A workspace member. Three of them in this repo.
  root,
  direct,
  dev,
  transitive;

  static PubDepsKind byName(String name) => switch (name) {
    'root' => root,
    'direct' => direct,
    'dev' => dev,
    _ => transitive,
  };
}

class PubDepsPackage {
  PubDepsPackage({
    required this.name,
    required this.version,
    required this.kind,
    required this.source,
    required this.dependencies,
    required this.directDependencies,
    required this.devDependencies,
    required this.dependencyConstraints,
  });

  final String name;

  /// The resolved version. `0.0.0` for anything from the SDK, which is why the
  /// UI keys off [source] before printing this.
  final String version;

  final PubDepsKind kind;

  /// `hosted`, `git`, `path`, `sdk`, or `root` for a workspace member.
  ///
  /// The *kind* of origin only — the URL, the git ref and the relative path are
  /// not in this output and come from the lockfile. See `PackageOrigin`.
  final String source;

  /// Everything this package depends on: [directDependencies] plus, for a
  /// member, [devDependencies].
  final List<String> dependencies;

  final List<String> directDependencies;

  /// Only ever populated for a [PubDepsKind.root] member — pub does not resolve
  /// a dependency's dev_dependencies, so for everything else this is empty
  /// because it is genuinely empty, not because it was dropped.
  final List<String> devDependencies;

  /// What each entry of [dependencies] was constrained to, as written in this
  /// package's pubspec. `any` for a bare `foo:` declaration.
  final Map<String, String> dependencyConstraints;

  factory PubDepsPackage.fromJson(Map<String, dynamic> json) => PubDepsPackage(
    name: json['name'] as String,
    version: json['version'] as String,
    kind: PubDepsKind.byName(json['kind'] as String),
    source: json['source'] as String,
    dependencies: _strings(json['dependencies']),
    directDependencies: _strings(json['directDependencies']),
    devDependencies: _strings(json['devDependencies']),
    dependencyConstraints: {
      for (var entry
          in (json['dependencyConstraints'] as Map<String, dynamic>? ?? {})
              .entries)
        entry.key: '${entry.value}',
    },
  );

  @override
  String toString() => 'PubDepsPackage($name $version, ${kind.name})';
}

List<String> _strings(Object? value) => [
  for (var entry in value as List? ?? const []) entry as String,
];
