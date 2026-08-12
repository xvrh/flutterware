import 'dart:convert';
import 'dart:io';

// The frozen name of the link `init` writes and the test for a committed
// wrapper, taken from the walker rather than spelled a second time here.
// ignore: implementation_imports
import 'package:flutterware/src/walker.dart' show findWrapper, sdkLinkPath;
import 'package:path/path.dart' as p;

import '../constants.dart';

class FlutterSdkPath {
  final String root;

  FlutterSdkPath(String path) : root = p.canonicalize(path);

  factory FlutterSdkPath.fromJson(Map<String, dynamic> json) =>
      FlutterSdkPath(json['root'] as String);

  static Future<FlutterSdkPath?> tryFind(String path) async {
    if (await FileSystemEntity.isDirectory(path)) {
      var dir = Directory(path);
      while (await dir.exists()) {
        var sdk = FlutterSdkPath(dir.path);
        if (await isValid(sdk)) {
          return sdk;
        } else {
          var parent = dir.parent;
          if (parent.path == dir.path) return null;
          dir = parent;
        }
      }
    } else if (await FileSystemEntity.isFile(path)) {
      return tryFind(File(path).parent.path);
    }
    return null;
  }

  Map<String, dynamic> toJson() => {'root': root};

  String get binDir => p.join(root, 'bin');

  String get flutter =>
      p.join(binDir, 'flutter${Platform.isWindows ? '.bat' : ''}');

  String get dart => p.join(binDir, 'dart${Platform.isWindows ? '.bat' : ''}');

  @override
  bool operator ==(other) => other is FlutterSdkPath && other.root == root;

  @override
  int get hashCode => root.hashCode;

  @override
  String toString() => 'Flutter SDK ($root)';

  static Future<bool> isValid(FlutterSdkPath sdk) async {
    return File(sdk.flutter).existsSync() && File(sdk.dart).existsSync();
  }

  /// Every SDK this project could run under, best answer first: callers that
  /// need one take it, and the GUI offers the set.
  ///
  /// **Recorded before discovered, and the project before the machine.** A
  /// recorded answer was written by something that was already running under
  /// the right SDK; everything below it is a convention that may not hold.
  /// Between two recorded answers the committed one wins: `flutter_version` is
  /// versioned and moves with the repo, where `.flutterware/sdk` is gitignored
  /// and can go on naming a version manager the repo has left.
  ///
  /// 1. [dartExecutableEnvironmentKey], set by the launcher — the same "record,
  ///    do not discover" rule `.flutterware/sdk` follows, and the only source
  ///    that survives `fw` being an AOT binary.
  /// 2. The version `flutter_version` pins, read from the `fw` wrapper's
  ///    cache — the committed pin of a repo whose toolchain is the wrapper,
  ///    resolved exactly the way the wrapper resolves it. Above the fvm
  ///    sources: a repo carrying both pins is one the wrapper runs. Above the
  ///    recorded link too, but only where a committed wrapper is found.
  /// 3. `.flutterware/sdk`, what `init` wrote down — first when the repo
  ///    commits no wrapper.
  /// 4. `.fvm/flutter_sdk`, for a project that pins with fvm and has not run
  ///    flutterware yet.
  /// 5. The version `.fvmrc` pins, read from fvm's cache — for a *fresh
  ///    worktree* of such a project, where the pin is versioned but the
  ///    symlink `fvm use` writes is not. Without this, `fw mcp` in a worktree
  ///    nobody has set up answers "No Flutter SDK found" about a project that
  ///    says, in a committed file, exactly which SDK it wants.
  /// 6. The SDK running us: `fvm dart app/bin/fw.dart` resolves to
  ///    `<flutter>/bin/cache/dart-sdk/bin/dart`, and walking up from it finds
  ///    the Flutter root three levels above. Null when the running executable
  ///    is not inside an SDK — the AOT `fw` and the GUI, where it is the app.
  /// 7. `FLUTTER_HOME`, which describes the machine rather than this project,
  ///    so it answers only when nothing above it did.
  ///
  /// Both [from] and [environment] exist so a test can ask about a directory
  /// and an environment it built, rather than the one it happens to run in.
  static Future<Set<FlutterSdkPath>> findSdks({
    Directory? from,
    Map<String, String>? environment,
  }) async {
    var env = environment ?? Platform.environment;
    var start = from ?? Directory.current;
    var sdks = <FlutterSdkPath?>[];

    var launcherDart = env[dartExecutableEnvironmentKey];
    if (launcherDart != null && launcherDart.isNotEmpty) {
      sdks.add(await tryFind(launcherDart));
    }

    // A repo that commits the wrapper has pinned its whole toolchain, so its
    // pin outranks the link `init` recorded — the precedence [findWrapper]
    // already gives the wrapper one level up. It matters because the link can
    // name the SDK of a version manager the repo has since left, and `init`
    // leaves an unchanged link alone: read back as the best answer, it feeds
    // itself and never disagrees.
    var recorded = await _findAbove(start, sdkLinkPath);
    var pinned = await _findFwPinned(start, env);
    sdks.addAll(
      findWrapper(start) != null ? [pinned, recorded] : [recorded, pinned],
    );
    sdks.add(await _findAbove(start, p.join('.fvm', 'flutter_sdk')));
    sdks.add(await _findPinned(start, env));

    sdks.add(await tryFind(Platform.resolvedExecutable));

    var homeEnvironment = env['FLUTTER_HOME'];
    if (homeEnvironment != null && homeEnvironment.isNotEmpty) {
      sdks.add(await tryFind(homeEnvironment));
    }

    return sdks.nonNulls.toSet();
  }

  /// The nearest `<ancestor>/[relative]` that is an SDK, walking up from
  /// [start].
  ///
  /// Walking rather than testing one directory because neither pointer is
  /// written where a command is typed: both sit at the repo root, and `fw` in
  /// `app/` or in `examples/example` has to find them from there.
  ///
  /// Unlike [tryFind] this does not walk up *from the pointer*. A pointer
  /// either leads to an SDK or it does not; climbing out of a stale one until
  /// some ancestor happens to look like an SDK answers a question nobody asked.
  /// The link is resolved, so the same SDK reached through here and through
  /// `FLUTTER_HOME` is one entry rather than two.
  static Future<FlutterSdkPath?> _findAbove(
    Directory start,
    String relative,
  ) async {
    var dir = start.absolute;
    while (true) {
      var candidate = FlutterSdkPath(_resolve(p.join(dir.path, relative)));
      if (await isValid(candidate)) return candidate;
      var parent = dir.parent;
      if (parent.path == dir.path) return null;
      dir = parent;
    }
  }

  /// The SDK `flutter_version` pins, resolved through the `fw` wrapper's
  /// cache — the same lookup the committed wrapper script performs, done
  /// passively: no download is started, an uncached pin simply does not
  /// answer.
  ///
  /// The cache roots are `FW_SDK_CACHE` then `~/.flutterware/sdks`, from
  /// [env] rather than the process — so a caller that asks with an empty
  /// environment (the comparison does, on purpose) keeps this source silent.
  static Future<FlutterSdkPath?> _findFwPinned(
    Directory start,
    Map<String, String> env,
  ) async {
    var pin = _pinFileAbove(start, 'flutter_version');
    if (pin == null) return null;
    String version;
    try {
      version = pin.readAsStringSync().trim();
    } on Object {
      return null;
    }
    if (version.isEmpty) return null;
    for (var base in [
      env['FW_SDK_CACHE'],
      if (env['HOME'] case var home?) p.join(home, '.flutterware', 'sdks'),
    ]) {
      if (base == null || base.isEmpty) continue;
      var candidate = FlutterSdkPath(p.join(base, version));
      if (await isValid(candidate)) return candidate;
    }
    return null;
  }

  /// The SDK `.fvmrc` pins, resolved through fvm's cache rather than the
  /// `.fvm/flutter_sdk` symlink — which does not exist until someone runs
  /// `fvm use`, and a fresh worktree is exactly the place nobody has.
  ///
  /// This serves *user projects* pinned with fvm (flutterware's own repo pins
  /// with `flutter_version` and the committed `fw` wrapper instead). Two
  /// rules: the cache roots are `FVM_CACHE_PATH`, `FVM_HOME`, then `~/fvm`,
  /// and the fvm CLI is never invoked — it can prompt, and on the MCP surface
  /// stdin is the protocol stream.
  static Future<FlutterSdkPath?> _findPinned(
    Directory start,
    Map<String, String> env,
  ) async {
    var pin = _pinFileAbove(start, '.fvmrc');
    if (pin == null) return null;
    String version;
    try {
      if (jsonDecode(pin.readAsStringSync()) case {'flutter': String pinned}) {
        version = pinned;
      } else {
        return null;
      }
    } on Object {
      // An unreadable pin names nothing — the sources below still answer.
      return null;
    }
    for (var base in [
      env['FVM_CACHE_PATH'],
      env['FVM_HOME'],
      if (env['HOME'] case var home?) p.join(home, 'fvm'),
    ]) {
      if (base == null || base.isEmpty) continue;
      var candidate = FlutterSdkPath(p.join(base, 'versions', version));
      if (await isValid(candidate)) return candidate;
    }
    return null;
  }

  /// The nearest `<ancestor>/[name]` that is a file, walked up like
  /// [_findAbove]'s pointers: a pin sits at the repo root and a command may
  /// be typed anywhere inside the project.
  static File? _pinFileAbove(Directory start, String name) {
    var dir = start.absolute;
    while (true) {
      var candidate = File(p.join(dir.path, name));
      if (candidate.existsSync()) return candidate;
      var parent = dir.parent;
      if (parent.path == dir.path) return null;
      dir = parent;
    }
  }

  static String _resolve(String path) {
    try {
      return Directory(path).resolveSymbolicLinksSync();
    } on FileSystemException {
      return path;
    }
  }
}

class FlutterSdk {
  final FlutterSdkPath path;

  FlutterSdk(this.path);

  factory FlutterSdk.fromJson(Map<String, dynamic> json) =>
      FlutterSdk(FlutterSdkPath.fromJson(json));

  Map<String, dynamic> toJson() => path.toJson();

  String get flutter => path.flutter;

  String get dart => path.dart;

  @override
  bool operator ==(other) => other is FlutterSdk && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
