import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart' show Pubspec;
import 'package:watcher/watcher.dart';
import '../package_ref.dart';
import '../utils/async_value.dart';
import '../utils/value_stream.dart';
import 'model/code_metrics.dart';

class ProjectInfoService {
  final PackageRef package;
  late final AsyncValue<Pubspec> _pubspec;
  late final AsyncValue<List<FlutterPlatform>> _platforms;
  late final AsyncValue<CodeMetrics> _codeMetrics;
  late StreamSubscription _pubspecWatcher;

  ProjectInfoService(this.package) {
    var pubspec = p.join(package.directory.path, 'pubspec.yaml');
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
  }

  ValueStream<Snapshot<Pubspec>> get pubspec => _pubspec.snapshots;

  ValueStream<Snapshot<List<FlutterPlatform>>> get platforms =>
      _platforms.snapshots;

  ValueStream<Snapshot<CodeMetrics>> get codeMetrics => _codeMetrics.snapshots;

  Future<List<FlutterPlatform>> _loadPlatforms() async {
    var result = <FlutterPlatform>[];
    for (var platform in FlutterPlatform.values) {
      var exists = await Directory(
        p.join(package.absolutePath, platform.folder),
      ).exists();
      if (exists) {
        result.add(platform);
      }
    }
    return result;
  }

  Future<CodeMetrics> _loadCodeMetrics() async {
    // The path is read out first so the closure captures a String and not
    // `this` — `Isolate.run` sends the closure, and a a `PackageRef` holds a Directory.
    var path = package.absolutePath;
    return Isolate.run(() => codeMetricsOf(path));
  }

  void dispose() {
    _pubspecWatcher.cancel();
    _pubspec.dispose();
    _platforms.dispose();
    _codeMetrics.dispose();
  }
}

enum FlutterPlatform {
  android('Android', folder: 'android'),
  ios('iOS', folder: 'ios'),
  macOS('macOS', folder: 'macos'),
  windows('Windows', folder: 'windows'),
  linux('Linux', folder: 'linux'),
  web('Web', folder: 'web');

  final String name;
  final String folder;

  const FlutterPlatform(this.name, {required this.folder});
}
