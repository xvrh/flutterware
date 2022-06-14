import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:collection/collection.dart';

import 'utils/async_value.dart';

final _logger = Logger('flutter_sdk');

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

  String get flutter =>
      p.join(root, 'bin', 'flutter${Platform.isWindows ? '.bat' : ''}');

  String get dart =>
      p.join(root, 'bin', 'dart${Platform.isWindows ? '.bat' : ''}');

  Future<Version> _readVersion() async {
    var rawVersion = await File(p.join(root, 'version')).readAsString();
    return Version.parse(rawVersion.trim());
  }

  @override
  bool operator ==(other) => other is FlutterSdkPath && other.root == root;

  @override
  int get hashCode => root.hashCode;

  @override
  String toString() => 'Flutter SDK ($root)';

  static Future<bool> isValid(FlutterSdkPath sdk) async {
    try {
      if (await sdk._readVersion() < Version(1, 0, 0)) {
        return false;
      }
    } catch (e) {
      return false;
    }
    return File(sdk.flutter).existsSync() && File(sdk.dart).existsSync();
  }

  static Future<Set<FlutterSdkPath>> findSdks() async {
    var sdks = <FlutterSdkPath?>[];

    var homeEnvironment = Platform.environment['FLUTTER_HOME'];
    if (homeEnvironment != null && homeEnvironment.isNotEmpty) {
      sdks.add(await FlutterSdkPath.tryFind(homeEnvironment));
    }
    await for (var sdk in _whichFlutter()) {
      sdks.add(sdk);
    }

    return sdks.whereNotNull().toSet();
  }

  static Stream<FlutterSdkPath> _whichFlutter() async* {
    for (var command in [
      'which',
      if (Platform.isWindows) 'where',
    ]) {
      try {
        var result = await Process.run(command, ['flutter'], runInShell: true);
        if (result.exitCode == 0) {
          var out = result.stdout;
          if (out is String && out.isNotEmpty) {
            var sdk = await FlutterSdkPath.tryFind(out.trim());
            if (sdk != null) {
              yield sdk;
            }
          }
        }
      } catch (e) {
        _logger.fine('Error which flutter: $e');
        // Skip error
      }
    }
  }
}

class FlutterSdk {
  final FlutterSdkPath path;
  late AsyncValue<Version> _version;

  FlutterSdk(this.path) {
    _version = AsyncValue<Version>(
      debugName: 'Flutter SDK version',
      loader: path._readVersion,
      lazy: true,
    );
  }

  factory FlutterSdk.fromJson(Map<String, dynamic> json) =>
      FlutterSdk(FlutterSdkPath.fromJson(json));

  Map<String, dynamic> toJson() => path.toJson();

  String get flutter => path.flutter;

  String get dart => path.dart;

  AsyncValue<Version> get version => _version;

  @override
  bool operator ==(other) => other is FlutterSdk && other.path == path;

  @override
  int get hashCode => path.hashCode;

  void dispose() {
    _version.dispose();
  }
}
