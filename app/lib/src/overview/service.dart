import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_studio_app/src/dependencies/pubspec_lock.dart';
import 'package:flutter_studio_app/src/utils/async_value.dart';
import 'package:watcher/watcher.dart';
import 'package:yaml/yaml.dart';

import '../icon/icons.dart';
import '../project.dart';
import '../utils/cloc/cloc.dart';
import 'package:path/path.dart' as p;

class ProjectInfoService {
  final Project project;
  late final AsyncValue<Pubspec> _pubspec;
  late StreamSubscription _pubspecWatcher;

  ProjectInfoService(this.project) {
    var pubspec = p.join(project.directory.path, 'pubspec.yaml');
    _pubspec = AsyncValue(
      debugName: 'Pubspec',
      lazy: true,
      loader: () async {
        var content = await File(pubspec).readAsString();
        return Pubspec.parse(content);
      },
    );
    _pubspecWatcher = FileWatcher(pubspec).events.listen((change) {
      _pubspec.refresh(mode: LoadingMode.none);
    });
  }

  ValueListenable<Snapshot<Pubspec>> get pubspec => _pubspec;

  void dispose() {
    _pubspecWatcher.cancel();
    _pubspec.dispose();
  }
}

class CodeMetrics {
  final ClocResult lib, tests;

  CodeMetrics({required this.lib, required this.tests});

  ClocResult get sum => lib + tests;
}
