import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

class FlutterSdk {
  final String root;

  FlutterSdk(String root) : root = p.canonicalize(root);

  factory FlutterSdk.fromJson(Map<String, dynamic> json) =>
      FlutterSdk(json['root'] as String);

  Map<String, dynamic> toJson() => {'root': root};

  String get flutter =>
      p.join(root, 'bin', 'flutter${Platform.isWindows ? '.bat' : ''}');

  String get dart =>
      p.join(root, 'bin', 'dart${Platform.isWindows ? '.bat' : ''}');

  Future<Version> get version async {
    var rawVersion = await File(p.join(root, 'version')).readAsString();
    return Version.parse(rawVersion.trim());
  }

  @override
  bool operator ==(other) => other is FlutterSdk && other.root == root;

  @override
  int get hashCode => root.hashCode;

  static Future<bool> isValid(FlutterSdk sdk) async {
    try {
      if (await sdk.version < Version(1, 0, 0)) {
        return false;
      }
    } catch (e) {
      return false;
    }
    return File(sdk.flutter).existsSync() && File(sdk.dart).existsSync();
  }

  static Future<Set<FlutterSdk>> findSdks() async {
    var toTry = <FlutterSdk>[];

    var homeEnvironment = Platform.environment['FLUTTER_HOME'];
    if (homeEnvironment != null && homeEnvironment.isNotEmpty) {
      toTry.add(FlutterSdk(homeEnvironment));
    }
    await for (var sdk in _whichFlutter()) {
      toTry.add(sdk);
    }

    var result = <FlutterSdk>{};
    for (var sdk in toTry) {
      if (await isValid(sdk)) {
        result.add(sdk);
      }
    }
    return result;
  }

  static Stream<FlutterSdk> _whichFlutter() async* {
    for (var command in ['which', 'where']) {
      try {
        var result = await Process.run(command, ['flutter'], runInShell: true);
        print(
            "Out ${result.exitCode} ${result.stderr} ${result.stdout} ${result.stdout.runtimeType}");
        if (result.exitCode == 0) {
          var out = result.stdout;
          if (out is String && out.isNotEmpty) {
            yield FlutterSdk(out.trim());
          }
        }
      } catch (e) {
        print("Error $e");
        // Skip error
      }
    }
  }
}
