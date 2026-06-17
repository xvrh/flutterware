import 'dart:io';
import 'package:path/path.dart' as p;

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

  String get binDir => p.join(root, 'bin');

  String get flutter =>
      p.join(binDir, 'flutter${Platform.isWindows ? '.bat' : ''}');

  String get dart => p.join(binDir, 'dart${Platform.isWindows ? '.bat' : ''}');

  @override
  bool operator ==(other) => other is FlutterSdkPath && other.root == root;

  @override
  int get hashCode => root.hashCode;

  @override
  String toString() => 'Flutter SDK ($root)';

  static Future<bool> isValid(FlutterSdkPath sdk) async {
    return File(sdk.flutter).existsSync() && File(sdk.dart).existsSync();
  }

  static Future<Set<FlutterSdkPath>> findSdks() async {
    var sdks = <FlutterSdkPath?>[];

    var homeEnvironment = Platform.environment['FLUTTER_HOME'];
    if (homeEnvironment != null && homeEnvironment.isNotEmpty) {
      sdks.add(await tryFind(homeEnvironment));
    }

    var projectRoot = _findProjectRoot();
    if (projectRoot != null) {
      sdks.add(await tryFind(p.join(projectRoot.path, '.fvm/flutter_sdk')));
    }

    return sdks.nonNulls.toSet();
  }

  static Directory? _findProjectRoot() {
    var dir = Directory.current;
    while (dir.parent.path != dir.path) {
      var rootFile = File(p.join(dir.path, 'flutter_version'));
      if (rootFile.existsSync()) {
        return dir;
      }

      dir = dir.parent;
    }
    return null;
  }
}

class FlutterSdk {
  final FlutterSdkPath path;

  FlutterSdk(this.path);

  factory FlutterSdk.fromJson(Map<String, dynamic> json) =>
      FlutterSdk(FlutterSdkPath.fromJson(json));

  Map<String, dynamic> toJson() => path.toJson();

  String get flutter => path.flutter;

  String get dart => path.dart;

  @override
  bool operator ==(other) => other is FlutterSdk && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
