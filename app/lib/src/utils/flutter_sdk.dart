import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'async_value.dart';

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
    sdks.add(await _whichFlutter());

    return sdks.nonNulls.toSet();
  }

  static Future<FlutterSdkPath?> _whichFlutter() async {
    var uri = await _which('flutter');
    if (uri != null) {
      return FlutterSdkPath.tryFind(uri.toFilePath());
    }
    return null;
  }

  static Future<Uri?> _which(String executableName) async {
    final whichOrWhere = Platform.isWindows ? 'where' : 'which';
    final fileExtension = Platform.isWindows ? '.exe' : '';
    final process =
        await Process.run(whichOrWhere, ['$executableName$fileExtension']);
    if (process.exitCode == 0) {
      final file = File(LineSplitter.split(process.stdout.toString()).first);
      final uri = File(await file.resolveSymbolicLinks()).uri;
      return uri;
    }
    if (process.exitCode == 1) {
      // The exit code for executable not being on the `PATH`.
      return null;
    }
    throw Exception(
        '`$whichOrWhere $executableName` returned unexpected exit code: '
        '${process.exitCode}.');
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
