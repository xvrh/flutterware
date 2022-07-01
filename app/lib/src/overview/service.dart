import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutterware_app/src/dependencies/model/pubspec_lock.dart';
import 'package:flutterware_app/src/utils/async_value.dart';
import 'package:watcher/watcher.dart';
import 'package:yaml/yaml.dart';

import '../icon/model/icons.dart';
import '../project.dart';
import '../utils/cloc/cloc.dart';
import 'package:path/path.dart' as p;

class ProjectInfoService {
  final Project project;
  late final AsyncValue<Pubspec> _pubspec;
  late final AsyncValue<List<FlutterPlatform>> _platforms;
  late StreamSubscription _pubspecWatcher;

  ProjectInfoService(this.project) {
    var pubspec = p.join(project.directory.path, 'pubspec.yaml');
    _pubspec = AsyncValue(
      debugName: 'Pubspec',
      loader: () async {
        var content = await File(pubspec).readAsString();
        return Pubspec.parse(content);
      },
    );
    _pubspecWatcher = FileWatcher(pubspec).events.listen((change) {
      _pubspec.refresh(mode: LoadingMode.none);
    });

    _platforms = AsyncValue(loader: _loadPlatforms);
  }

  ValueListenable<Snapshot<Pubspec>> get pubspec => _pubspec;

  ValueListenable<Snapshot<List<FlutterPlatform>>> get platforms => _platforms;

  Future<List<FlutterPlatform>> _loadPlatforms() async {
    var result = <FlutterPlatform>[];
    for (var platform in FlutterPlatform.values) {
      var exists =
          await Directory(p.join(project.absolutePath, platform.folder))
              .exists();
      if (exists) {
        result.add(platform);
      }
    }
    return result;
  }

  void dispose() {
    _pubspecWatcher.cancel();
    _pubspec.dispose();
    _platforms.dispose();
  }
}

enum FlutterPlatform {
  android('Android', folder: 'android'),
  ios('iOS', folder: 'ios'),
  macOS('macOS', folder: 'macos'),
  windows('Windows', folder: 'windows'),
  linux('Linux', folder: 'linux'),
  web('Web', folder: 'web'),
  ;

  final String name;
  final String folder;

  const FlutterPlatform(this.name, {required this.folder});
}

class CodeMetrics {
  final ClocResult lib, tests;

  CodeMetrics({required this.lib, required this.tests});

  ClocResult get sum => lib + tests;
}
