import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'dependencies/model/service.dart';
import 'drawing/model/service.dart';
import 'icon/model/service.dart';
import 'overview/service.dart';
import 'package_ref.dart';
import 'test_runner/model/service.dart';
import 'ui_catalog/service/service.dart';
import 'utils/async_value.dart';
import 'utils/value_stream.dart';

export 'package:pubspec_parse/pubspec_parse.dart' show Pubspec;

/// **Legacy.** Every service for one package, constructed eagerly.
///
/// Nothing in the new architecture builds one of these. It survives only for
/// the pre-overhaul screens under `src/app/`, `src/drawing/` and
/// `src/test_runner/`, which are reachable from `main_dev.dart` and not from
/// `main.dart`, and which the master plan has slated for rewrite or deletion.
/// **It goes when they do.**
///
/// Why it had to stop being load-bearing: declaring a field per service means
/// importing this file pulls every service — including the two that import
/// `package:flutter/foundation.dart` — into the closure of anything that only
/// wanted a directory path. `Workspace` handed one of these to plugins, so a
/// plugin could not be linked into a pure-Dart `fw`. Services now take
/// [PackageRef]; see `2026-07-27-gui-cli-mcp-architecture.md`.
class Project extends PackageRef {
  late final tests = TestService(this);
  late final info = ProjectInfoService(this);
  late final icons = IconService(this);
  late final dependencies = DependenciesService(this);
  late final drawing = DrawingService(this);
  late final uiCatalog = UICatalogService(this);

  Project(super.context, super.path, super.flutterSdkPath);

  static Future<bool> isValid(String path) async {
    if (await FileSystemEntity.isDirectory(path)) {
      var pubspec = File(p.join(path, 'pubspec.yaml'));
      return pubspec.exists();
    }
    return false;
  }

  ValueStream<Snapshot<Pubspec>> get pubspec => info.pubspec;

  void dispose() {
    tests.dispose();
    info.dispose();
    icons.dispose();
    dependencies.dispose();
    drawing.dispose();
  }
}
