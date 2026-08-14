import 'dart:io';

import 'package:path/path.dart' as p;

import '../constants.dart';

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

  /// The SDK this project runs under: **the one that started us**.
  ///
  /// Not discovered, and that is the whole rule. `dart run flutterware` arrives
  /// through the user's own `dart` — fvm, mise, asdf, or a path they typed —
  /// and choosing it is how they say which SDK this project uses. Reading a pin
  /// file, a version manager's cache or `FLUTTER_HOME` would be flutterware
  /// answering that question on their behalf, and every one of those answers
  /// can disagree with the interpreter that is actually running.
  ///
  /// Two spellings of the one signal:
  ///
  /// 1. [dartExecutableEnvironmentKey], recorded by the launcher when it spawns
  ///    the CLI — the only one that survives the hop into a compiled binary.
  /// 2. [Platform.resolvedExecutable], when this process *is* running under the
  ///    dart in question: `dart run flutterware_app:fw`, and the test harness.
  ///
  /// Null when neither answers, which is a compiled Flutter app: there
  /// `resolvedExecutable` is the app binary and no SDK sits above it. Those
  /// entry points are *told* instead, through [flutterSdkDefineKey] — see
  /// `main.dart`. Nothing here guesses on their behalf.
  ///
  /// [environment] exists so a test can ask about an environment it built
  /// rather than the one it happens to run in.
  static Future<FlutterSdkPath?> findSdk({
    Map<String, String>? environment,
  }) async {
    var env = environment ?? Platform.environment;

    var recorded = env[dartExecutableEnvironmentKey];
    if (recorded != null && recorded.isNotEmpty) {
      var sdk = await tryFind(recorded);
      if (sdk != null) return sdk;
    }

    return tryFind(Platform.resolvedExecutable);
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
