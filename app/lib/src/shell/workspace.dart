import 'dart:io';

import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../context.dart';
import '../package_ref.dart';
import '../utils/flutter_sdk.dart';

export 'repo_layout.dart';

/// The packages of one worktree.
///
/// Identity and paths only — deliberately **no services**. It used to hand out
/// a `Project`, which declared a field per service and so dragged every one of
/// them (and `package:flutter` with them) into the closure of any plugin that
/// touched a workspace. A plugin has to be linkable into a pure-Dart `fw`, so a
/// plugin now builds the one service it needs from a [PackageRef] and owns its
/// lifetime.
class Workspace {
  Workspace({
    required this.root,
    required this.declared,
    required this.discovered,
    required this.appContext,
    required this.flutterSdk,
  });

  /// Absolute path to the worktree root — where `tool/flutterware.dart` lives.
  final String root;

  /// Every package the config's plugins name, in declaration order,
  /// deduplicated — see [PluginManifest.packages].
  final List<Pkg> declared;

  /// Packages found on disk (from `workspace:`, else a scan). Reference data:
  /// used to validate declarations and warn on a typo, never to activate
  /// anything.
  final List<String> discovered;

  final AppContext appContext;
  final FlutterSdkPath flutterSdk;
  final _packages = <String, PackageRef>{};

  /// Whether [path] is a directory that is actually there.
  ///
  /// This is what a plugin filters its declared packages on. It used to filter
  /// on membership of a separate `fw.packages([...])` list, which could only
  /// ever subtract a package the config had explicitly handed the plugin — and
  /// did it silently. Existence is the question that was worth asking.
  bool exists(String path) =>
      // '.' is the worktree root, which is there by construction.
      path == '.' ||
      discovered.contains(path) ||
      Directory(absolutePathOf(path)).existsSync();

  /// Named paths that are not on disk — almost always a typo, and worth saying
  /// out loud rather than silently doing nothing.
  List<String> get unknownDeclarations => [
    for (var pkg in declared)
      if (!exists(pkg.path)) pkg.path,
  ];

  String absolutePathOf(String relative) =>
      relative == '.' ? root : p.normalize(p.join(root, relative));

  /// The handle for one package, interned so callers can compare identity.
  ///
  /// Cheap and service-free, so unlike the `Project` it replaces, asking for
  /// one starts no work — which is what lets a plugin resolve a path without
  /// deciding to compute anything.
  PackageRef packageFor(String path) => _packages.putIfAbsent(
    path,
    () => PackageRef(appContext, absolutePathOf(path), flutterSdk),
  );

  void dispose() => _packages.clear();
}
