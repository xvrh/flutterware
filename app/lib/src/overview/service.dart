import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutterware_app/src/overview/model/assets.dart';
import 'package:flutterware_app/src/overview/model/code_metrics.dart';
import 'package:flutterware_app/src/utils/async_value.dart';
import 'package:watcher/watcher.dart';
import '../project.dart';
import 'package:path/path.dart' as p;

class ProjectInfoService {
  final Project project;
  late final AsyncValue<Pubspec> _pubspec;
  late final AsyncValue<List<FlutterPlatform>> _platforms;
  late final AsyncValue<CodeMetrics> _codeMetrics;
  late final AsyncValue<AssetsReport> _assetsMetrics;
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
    _codeMetrics = AsyncValue(loader: _loadCodeMetrics);
    _assetsMetrics = AsyncValue(loader: _loadAssetsMetrics);
  }

  ValueListenable<Snapshot<Pubspec>> get pubspec => _pubspec;

  ValueListenable<Snapshot<List<FlutterPlatform>>> get platforms => _platforms;

  ValueListenable<Snapshot<CodeMetrics>> get codeMetrics => _codeMetrics;

  ValueListenable<Snapshot<AssetsReport>> get assetsMetrics => _assetsMetrics;

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

  Future<CodeMetrics> _loadCodeMetrics() async {
    return compute<String, CodeMetrics>(codeMetricsOf, project.absolutePath);
  }

  Future<AssetsReport> _loadAssetsMetrics() async {
    return compute<String, AssetsReport>(
        createAssetReport, project.absolutePath);
  }

  void dispose() {
    _pubspecWatcher.cancel();
    _pubspec.dispose();
    _platforms.dispose();
    _codeMetrics.dispose();
    _assetsMetrics.dispose();
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
