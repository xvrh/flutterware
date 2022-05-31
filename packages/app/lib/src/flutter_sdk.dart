import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:collection/collection.dart';

import 'utils/data_loader.dart';

final _logger = Logger('flutter_sdk');

class FlutterSdk {
  final String root;
  late DataLoader<Version> _version;

  FlutterSdk(String path) : root = p.canonicalize(path) {
    _version = DataLoader<Version>(
      debugName: 'Flutter SDK version',
      loader: _readVersion,
      lazy: true,
    );
  }

  factory FlutterSdk.fromJson(Map<String, dynamic> json) =>
      FlutterSdk(json['root'] as String);

  static Future<FlutterSdk?> tryFind(String path) async {
    if (await FileSystemEntity.isDirectory(path)) {
      var dir = Directory(path);
      while (await dir.exists()) {
        var sdk = FlutterSdk(dir.path);
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

  DataLoader<Version> get version => _version;

  Future<Version> _readVersion() async {
    var rawVersion = await File(p.join(root, 'version')).readAsString();
    return Version.parse(rawVersion.trim());
  }

  @override
  bool operator ==(other) => other is FlutterSdk && other.root == root;

  @override
  int get hashCode => root.hashCode;

  static Future<bool> isValid(FlutterSdk sdk) async {
    try {
      if (await sdk._readVersion() < Version(1, 0, 0)) {
        return false;
      }
    } catch (e) {
      return false;
    }
    return File(sdk.flutter).existsSync() && File(sdk.dart).existsSync();
  }

  static Future<Set<FlutterSdk>> findSdks() async {
    var sdks = <FlutterSdk?>[];

    var homeEnvironment = Platform.environment['FLUTTER_HOME'];
    if (homeEnvironment != null && homeEnvironment.isNotEmpty) {
      sdks.add(await FlutterSdk.tryFind(homeEnvironment));
    }
    await for (var sdk in _whichFlutter()) {
      sdks.add(sdk);
    }

    return sdks.whereNotNull().toSet();
  }

  static Stream<FlutterSdk> _whichFlutter() async* {
    for (var command in [
      'which',
      if (Platform.isWindows) 'where',
    ]) {
      try {
        var result = await Process.run(command, ['flutter'], runInShell: true);
        if (result.exitCode == 0) {
          var out = result.stdout;
          if (out is String && out.isNotEmpty) {
            var sdk = await FlutterSdk.tryFind(out.trim());
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
