/// The first-party plugins, as a project declares them in
/// `tool/flutterware.dart`:
///
/// ```dart
/// const app = Pkg('packages/app');
///
/// void main() => Flutterware.configure((fw) {
///   fw.use(Previews(packages: [.new(app, directory: 'demo')]));
/// });
/// ```
///
/// These carry identity and configuration only — the behaviour for each id is
/// compiled into the GUI. They live here, in the pure-Dart package, because the
/// config file runs under a plain `dart run` and cannot see the GUI.
library;

import 'package.dart';
import 'plugin.dart';

/// Pub dependencies, per declared package.
class Dependencies extends Plugin {
  Dependencies({this.packages = const [], String? label})
    : super('flutterware.dependencies', label: label ?? 'Dependencies');

  final List<DependenciesPackage> packages;

  @override
  Map<String, Object?> get config => {
    'packages': [for (var p in packages) p.toJson()],
  };
}

class DependenciesPackage extends PluginPackage {
  const DependenciesPackage(super.pkg);

  /// Every package — for plugins where per-package options are genuinely
  /// optional. Offered per plugin, never as a framework rule.
  static List<DependenciesPackage> each(List<Pkg> packages) => [
    for (var pkg in packages) DependenciesPackage(pkg),
  ];
}

/// Everything a package's bundle resolves to — declared assets, the density
/// variants beside them, the fonts, and whatever its dependencies contribute.
class Assets extends Plugin {
  Assets({this.packages = const [], String? label})
    : super('flutterware.assets', label: label ?? 'Assets');

  final List<AssetsPackage> packages;

  @override
  Map<String, Object?> get config => {
    'packages': [for (var p in packages) p.toJson()],
  };
}

class AssetsPackage extends PluginPackage {
  const AssetsPackage(super.pkg);

  /// Every package. Offered because there is nothing to configure per package
  /// here — the pubspec is the declaration — so naming them one at a time buys
  /// only the chance to forget one.
  static List<AssetsPackage> each(List<Pkg> packages) => [
    for (var pkg in packages) AssetsPackage(pkg),
  ];
}

/// Previews — your `@Preview`s, rendered in the embedded engine.
///
/// Wherever they are: the whole package is scanned, so a preview beside the
/// widget it shows is found without anybody declaring anything.
/// [PreviewsPackage.directory] narrows that, and is the only reason to name a
/// directory at all.
class Previews extends Plugin {
  Previews({this.packages = const [], String? label})
    : super('flutterware.previews', label: label ?? 'Previews');

  final List<PreviewsPackage> packages;

  @override
  Map<String, Object?> get config => {
    'packages': [for (var p in packages) p.toJson()],
  };
}

class PreviewsPackage extends PluginPackage {
  const PreviewsPackage(super.pkg, {this.directory, this.previewAnnotations});

  /// Narrows the scan to one directory, relative to the package.
  ///
  /// **Null scans the whole package**, which is the default and what most
  /// projects want: previews are found wherever they are written, ignored files
  /// and `build/` excluded the way git excludes them. Naming a directory is for
  /// a package that wants the scan bounded — and it moves `new` there too, so
  /// the place files are written and the place they are looked for stay the
  /// same.
  final String? directory;

  /// The annotation names that mark an entry, without their `@`.
  ///
  /// `['Preview']` when null. A project that defines its own — e.g.
  /// `base class Tablet extends Preview` — registers it here, which is what makes
  /// recognition **by registration** rather than by resolving the class
  /// hierarchy: discovery parses, and a parser cannot know what a name extends.
  /// Naming a subclass here does not drop the defaults; list them if you want
  /// them.
  final List<String>? previewAnnotations;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    if (directory != null) 'directory': directory,
    if (previewAnnotations != null) 'previewAnnotations': previewAnnotations,
  };

  static List<PreviewsPackage> each(List<Pkg> packages) => [
    for (var pkg in packages) PreviewsPackage(pkg),
  ];
}

/// Scenarios — app tests with per-step screenshots, run under FakeAsync in a
/// directly-spawned `flutter_tester`. See
/// `docs/superpowers/specs/2026-07-30-scenarios-design.md`.
class Scenarios extends Plugin {
  Scenarios({this.packages = const [], String? label})
    : super('flutterware.scenarios', label: label ?? 'Scenarios');

  final List<ScenariosPackage> packages;

  @override
  Map<String, Object?> get config => {
    'packages': [for (var p in packages) p.toJson()],
  };
}

class ScenariosPackage extends PluginPackage {
  const ScenariosPackage(
    super.pkg, {
    this.directory,
    this.languages,
    this.captureScale,
  });

  /// Where this package keeps its scenarios, relative to the package;
  /// `test/scenarios` when null.
  final String? directory;

  /// The locale tags this app supports — `['en', 'fr']` — offered by the
  /// language axis. Null means the axis offers no list and runs stay on the
  /// platform default.
  final List<String>? languages;

  /// Screenshot pixels per logical pixel for every run of this package —
  /// `3` renders retina captures, at roughly the device ratio's cost in
  /// time and bytes. Null means 1, the measured sweet spot; a run's own
  /// `capture-scale` argument still wins.
  final double? captureScale;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    if (directory != null) 'directory': directory,
    if (languages != null) 'languages': languages,
    if (captureScale != null) 'captureScale': captureScale,
  };

  static List<ScenariosPackage> each(List<Pkg> packages) => [
    for (var pkg in packages) ScenariosPackage(pkg),
  ];
}

/// Motion — timelines scrubbed against a live screen, with the tuned numbers in
/// a file no human writes. See
/// `docs/superpowers/specs/2026-07-31-motion-design.md`.
class Motion extends Plugin {
  Motion({this.packages = const [], String? label})
    : super('flutterware.motion', label: label ?? 'Motion');

  final List<MotionPackage> packages;

  @override
  Map<String, Object?> get config => {
    'packages': [for (var p in packages) p.toJson()],
  };
}

class MotionPackage extends PluginPackage {
  const MotionPackage(super.pkg, {this.directory});

  /// Where this package's screens are, relative to the package; `lib` when
  /// null.
  ///
  /// A directory rather than a convention of ours, because a motion is not a
  /// thing you keep somewhere — it is a screen that happens to move, and it
  /// lives wherever the screens live.
  final String? directory;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    if (directory != null) 'directory': directory,
  };

  static List<MotionPackage> each(List<Pkg> packages) => [
    for (var pkg in packages) MotionPackage(pkg),
  ];
}

/// The native splash screen: what `flutter_native_splash` will produce, on
/// every surface and in both themes.
///
/// Like [LauncherIcon] it offers no `each`: a splash config only means anything
/// in a package that is an app, and quietly declaring one for a pure Dart
/// library would report "no splash configured" forever.
class NativeSplash extends Plugin {
  NativeSplash({this.packages = const [], String? label})
    : super('flutterware.splash', label: label ?? 'Splash screen');

  final List<NativeSplashPackage> packages;

  @override
  Map<String, Object?> get config => {
    'packages': [for (var p in packages) p.toJson()],
  };
}

class NativeSplashPackage extends PluginPackage {
  const NativeSplashPackage(super.pkg);
}

/// Live inspection of the project's Dart servers: HTTP requests, SQL queries
/// and logs, reported from inside the running process by
/// `package:flutterware/server.dart`.
///
/// Deliberately declares no `packages:` — a server announces *itself* at
/// runtime with a handle under `~/.flutterware/run`, however it was launched,
/// so there is nothing to configure but the wish to see them. See
/// `docs/superpowers/specs/2026-07-30-server-inspection-design.md`.
class ServerInspection extends Plugin {
  ServerInspection({String? label})
    : super('flutterware.server', label: label ?? 'Server');
}

/// Running the app on a device: what is connected, what is free, what is
/// already running where — across every worktree of the repo, not just this
/// one — and launching an entry point onto it.
///
/// ```dart
/// fw.use(Run(packages: [
///   RunPackage(app, entrypoints: [
///     Entrypoint('lib/main.dart', name: 'App'),
///     Entrypoint('lib/main_staging.dart', name: 'Staging', defines: [
///       DartDefine('API_HOST', from: DefineSource.hostAddresses),
///       DartDefine('API_PORT',
///           from: DefineSource.script('tool/local_env.dart',
///               args: ['port', 'server'])),
///     ]),
///   ]),
/// ]));
/// ```
///
/// See `docs/superpowers/specs/2026-07-31-app-launcher-cockpit-brainstorm.md`,
/// and `2026-08-11-computed-define-sources.md` for what a define's `from:` can
/// work out for itself.
///
/// Offers no `each`, like [LauncherIcon] and for the same reason: only a
/// package that is an app can be run onto a phone.
class Run extends Plugin {
  Run({this.packages = const [], String? label})
    : super('flutterware.run', label: label ?? 'Run');

  final List<RunPackage> packages;

  @override
  Map<String, Object?> get config => {
    'packages': [for (var p in packages) p.toJson()],
  };
}

class RunPackage extends PluginPackage {
  const RunPackage(super.pkg, {this.entrypoints = const []});

  /// The `main()`s worth launching, named.
  ///
  /// Empty means "scan for them": every `lib/*.dart` with a `main()` is
  /// offered, under its file name. The scan is provisional and this list is
  /// authority — the rule discovery already has everywhere else.
  ///
  /// Naming them is worth more than it looks. An agent picks an entry point
  /// off a list, and `Staging` tells it what the thing is where
  /// `main_staging.dart` only tells it where the thing lives.
  final List<Entrypoint> entrypoints;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    if (entrypoints.isNotEmpty)
      'entrypoints': [for (var e in entrypoints) e.toJson()],
  };
}

/// One `main()` a package can be launched from.
class Entrypoint {
  const Entrypoint(
    this.path, {
    this.name,
    this.description,
    this.flavor,
    this.platforms = const [],
    this.defines = const [],
  });

  /// Package-relative, `/`-separated — `lib/main_staging.dart`.
  final String path;

  /// What a human and an agent call it. The file's name when null.
  final String? name;

  /// What this entry point *is*, in a line.
  ///
  /// `Kiosk` and `Onboarding` are unguessable from their file names, and the
  /// picker is where that costs you. An agent choosing between entry points
  /// reads the same field, so it pays twice.
  final String? description;

  /// The `--flavor` this entry point is built with — `dev`, `staging`.
  ///
  /// **A flavoured project cannot be run without one at all.** Where a missing
  /// `--dart-define` merely gives you the fallback value, a missing `--flavor`
  /// on a project that declares product flavors is a hard failure before
  /// anything is compiled: Gradle has no such variant, and Xcode has no such
  /// scheme. So this is not a convenience — for those projects it is the
  /// difference between an entry point that launches and one that cannot.
  ///
  /// Declared per entry point because that is how the pairing actually works:
  /// `main_dev.dart` goes with `dev`, and it is the same fact twice. To run one
  /// entry point under several flavors, declare it several times with different
  /// [name]s, or pass `flavor` to the launch action.
  ///
  /// Android and Apple platforms only — `flutter run` rejects `--flavor` for
  /// web, Linux and Windows, so leave it null for an entry point that targets
  /// those.
  final String? flavor;

  /// What this entry point can actually run on. Everything, when empty.
  ///
  /// Some `main()`s are only meant for one kind of machine: a kiosk build for
  /// tablets, an operator console for the desktop, a web-only embed. Declaring
  /// it turns a wrong device from a build failure minutes later into a device
  /// the picker never offers.
  ///
  /// [RunPlatform.mobile] and [RunPlatform.desktop] are shorthands and expand,
  /// so the coarse case stays one word:
  ///
  /// ```dart
  /// Entrypoint('lib/main_kiosk.dart', name: 'Kiosk',
  ///     platforms: [RunPlatform.ios, RunPlatform.android]),
  /// Entrypoint('lib/main_admin.dart', name: 'Admin',
  ///     platforms: [RunPlatform.desktop]),
  /// ```
  ///
  /// This says what the *entry point* is for, not what the package can build.
  /// A package with no `web/` directory cannot run on Chrome either, and that
  /// is not declared here — it is a fact about the package, and one nothing
  /// should have to write down twice.
  final List<RunPlatform> platforms;

  /// What has to be decided before this can be built.
  final List<DartDefine> defines;

  Map<String, Object?> toJson() => {
    'path': path,
    'name': ?name,
    'description': ?description,
    'flavor': ?flavor,
    // As written, shorthands and all. The tool expands them where it matches
    // devices; the manifest keeps the author's word so a picker can say
    // `desktop` rather than reciting three platforms back at them.
    if (platforms.isNotEmpty) 'platforms': [for (var p in platforms) p.name],
    if (defines.isNotEmpty) 'defines': [for (var d in defines) d.toJson()],
  };
}

/// What an [Entrypoint] can run on — one of Flutter's platforms, or a
/// shorthand for a group of them.
///
/// The concrete members are `flutter run`'s own platform names, which is what
/// makes them checkable: the device list reports the same vocabulary, so a
/// declaration and a device either match or visibly do not. The two shorthands
/// are the daemon's device *categories*, and exist because "this is a phone
/// thing" is the restriction people actually mean most of the time.
enum RunPlatform {
  ios,
  android,
  macos,
  linux,
  windows,
  web,

  /// [ios] and [android].
  mobile,

  /// [macos], [linux] and [windows].
  desktop;

  /// The concrete platforms this stands for — itself, unless it is a shorthand.
  Set<RunPlatform> get expanded => switch (this) {
    mobile => const {ios, android},
    desktop => const {macos, linux, windows},
    _ => {this},
  };

  static RunPlatform? byName(String name) {
    for (var value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// Every concrete platform [platforms] allows, shorthands expanded.
  ///
  /// Empty in and empty out, and the caller has to read that as "no
  /// restriction" rather than "nothing is allowed" — the difference between an
  /// entry point that runs anywhere and one that runs nowhere.
  static Set<RunPlatform> expandAll(Iterable<RunPlatform> platforms) => {
    for (var platform in platforms) ...platform.expanded,
  };
}

/// A `--dart-define` this entry point wants, offered as a control rather than
/// as something to remember.
///
/// **Named for what it is, because that is what says what it costs.** This was
/// `LaunchKnob`, which put it in the same word as a preview's knobs — and those
/// are the opposite kind of thing: a knob is read while a widget builds and
/// changing one costs a frame, while a define is compiled in and changing one
/// costs a full rebuild and reinstall. Nothing in the old name said so, and
/// both were `--knobs=` on the same CLI.
///
/// Prefer a runtime control where one will do — a devbar variable, pushed into
/// a running app for nothing — and reach for this only when the value has to be
/// baked in.
class DartDefine {
  const DartDefine(
    this.name, {
    this.label,
    this.description,
    this.defaultValue,
    this.options = const [],
    this.from,
  });

  /// The name `String.fromEnvironment` reads — `API_BASE_URL`.
  final String name;

  /// What a human sees; [name] when absent.
  final String? label;

  final String? description;

  /// Used when nobody says otherwise.
  final String? defaultValue;

  /// Values worth offering, when they are known in advance and few.
  final List<String> options;

  /// Values the tool can work out for itself, added to [options].
  ///
  /// This is what turns "point the app at this machine" from typing into
  /// picking: the tool already knows what this machine is reachable at, so the
  /// value should not have to be looked up by hand.
  final DefineSource? from;

  Map<String, Object?> toJson() => {
    'define': name,
    if (label != null) 'label': label,
    if (description != null) 'description': description,
    if (defaultValue != null) 'default': defaultValue,
    if (options.isNotEmpty) 'options': options,
    if (from != null) 'from': from!.toJson(),
  };
}

/// Where a [DartDefine]'s offered values are found.
///
/// Two of them, and they are not the same kind of thing: [hostAddresses] is
/// something the tool knows, while [DefineSource.script] is something the
/// project knows and the tool goes and asks. Only the second can answer "what
/// port did this worktree get", because only the project allocated it.
///
/// There was a third, `servers`, offering the base URLs of dev servers
/// announcing themselves through `package:flutterware/server.dart`. It was
/// deleted: the offered values are a `List<String>`, so two servers arrived as
/// two bare URLs with nothing to tell them apart — and the scan was not even
/// scoped to this worktree, so they came from every project on the machine.
/// A source whose answer you cannot identify is worse than no source.
sealed class DefineSource {
  const DefineSource();

  /// This machine's addresses on the local network. What a phone has to be
  /// told, since `localhost` on a phone is the phone.
  static const DefineSource hostAddresses = HostAddressesSource();

  /// A Dart script in this worktree that prints the value, or a JSON array of
  /// values to choose from.
  ///
  /// ```dart
  /// DartDefine('LOCALDEV_SERVER_PORT',
  ///     from: DefineSource.script('tool/local_env.dart',
  ///         args: ['port', 'server'])),
  /// ```
  ///
  /// **A script, not a command, because a command would have to name an
  /// executable and no config file can know which one.** A `dart` on PATH is
  /// routinely older than the SDK the project pins — this repo's own is — so a
  /// config saying `dart` would be saying "whichever SDK happens to be first",
  /// which is not a thing anybody means. Run with the same `dart` that compiles
  /// and runs this config file, from the worktree root.
  ///
  /// **Selection belongs in [args], not here.** An earlier draft had a `pick:`
  /// naming a key in a JSON object the script printed; it would have grown a
  /// path syntax the first time somebody's output was nested. Passing the
  /// selection as an argument puts it in the tool that owns the data, where it
  /// can be a real function of that tool's model.
  ///
  /// Run when the values are needed, not when the config is read: the answer to
  /// "which port is this worktree on" changes when the stack goes up or down,
  /// which is not a moment the config file knows about.
  const factory DefineSource.script(String path, {List<String> args}) =
      ScriptSource;

  Map<String, Object?> toJson();

  /// Reads back what [toJson] wrote, or null for a shape this build has no
  /// member for.
  ///
  /// Null rather than a throw, for the reason `_platformsOf` gives on the app
  /// side: the config imports the `flutterware` version the *project* pins,
  /// which can run ahead of the GUI reading its manifest. A source we cannot
  /// resolve has to mean a define with fewer suggestions, never a define that
  /// disappears.
  static DefineSource? fromJson(Object? raw) {
    if (raw is! Map) return null;
    if (raw['source'] == 'hostAddresses') return hostAddresses;
    if (raw['script'] case String path) {
      return ScriptSource(
        path,
        args: [
          for (var arg in (raw['args'] as List? ?? const []))
            if (arg is String) arg,
        ],
      );
    }
    return null;
  }
}

/// See [DefineSource.hostAddresses].
final class HostAddressesSource extends DefineSource {
  const HostAddressesSource();

  @override
  Map<String, Object?> toJson() => {'source': 'hostAddresses'};
}

/// See [DefineSource.script].
final class ScriptSource extends DefineSource {
  const ScriptSource(this.path, {this.args = const []});

  /// Worktree-relative, `/`-separated — `tool/local_env.dart`.
  final String path;

  final List<String> args;

  @override
  Map<String, Object?> toJson() => {
    'script': path,
    if (args.isNotEmpty) 'args': args,
  };
}

/// The launcher-icon editor. Only meaningful for packages that are apps, so it
/// deliberately offers no `each` — naming them is the point.
class LauncherIcon extends Plugin {
  LauncherIcon({this.packages = const [], String? label})
    : super('flutterware.launcher_icon', label: label ?? 'Launcher icon');

  final List<LauncherIconPackage> packages;

  @override
  Map<String, Object?> get config => {
    'packages': [for (var p in packages) p.toJson()],
  };
}

class LauncherIconPackage extends PluginPackage {
  const LauncherIconPackage(super.pkg);
}
