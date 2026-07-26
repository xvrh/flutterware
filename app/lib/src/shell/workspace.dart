import 'dart:io';

import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../context.dart';
import '../project.dart';
import '../utils/flutter_sdk.dart';

export 'repo_layout.dart';

/// The packages of one worktree, and the [Project] services for each.
///
/// Carries **identity only** until something asks: `projectFor` builds a
/// [Project] on first use and caches it, so opening a worktree with twelve
/// declared packages does not construct twelve service graphs nobody looked at.
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

  /// Packages the config declared. Only these are addressable by plugins.
  final List<Pkg> declared;

  /// Packages found on disk (from `workspace:`, else a scan). Reference data:
  /// used to validate declarations and warn on a typo, never to activate
  /// anything.
  final List<String> discovered;

  final AppContext appContext;
  final FlutterSdkPath flutterSdk;
  final _projects = <String, Project>{};

  /// Declared paths that are not on disk — almost always a typo, and worth
  /// saying out loud rather than silently doing nothing.
  List<String> get unknownDeclarations => [
    for (var pkg in declared)
      // '.' is the worktree root — it exists by construction.
      if (pkg.path != '.' &&
          !discovered.contains(pkg.path) &&
          !Directory(absolutePathOf(pkg.path)).existsSync())
        pkg.path,
  ];

  String absolutePathOf(String relative) =>
      relative == '.' ? root : p.normalize(p.join(root, relative));

  Pkg? declaredAt(String path) =>
      declared.where((pkg) => pkg.path == path).firstOrNull;

  /// The services for one package, built on first request and reused after.
  Project projectFor(String path) => _projects.putIfAbsent(
    path,
    () => Project(appContext, absolutePathOf(path), flutterSdk),
  );

  /// True once [projectFor] has actually built this package's services — lets a
  /// report distinguish "nothing yet" from "nothing there".
  bool isRealised(String path) => _projects.containsKey(path);

  void dispose() {
    for (var project in _projects.values) {
      project.dispose();
    }
    _projects.clear();
  }
}
