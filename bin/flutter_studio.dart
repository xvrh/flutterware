import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;
import 'package:io/io.dart';
import 'package:args/args.dart';

void main() async {
  var packageUri =
      await Isolate.resolvePackageUri(Uri.parse('package:flutter_studio/lib'));
  var packageRoot = packageUri!.resolve('..').toFilePath();
  var appPath = p.join(packageRoot, 'app');
  assert(Directory(appPath).existsSync());

  var flutterSdk = FlutterSdk.tryFind(Platform.resolvedExecutable);
  if (flutterSdk == null) {
    throw Exception('Flutter command not found. '
        'Make sure you are using the dart command from a Flutter SDK (instead of a standalone Dart SDK).\nSearched ${Platform.resolvedExecutable}');
  }

  var argParser = ArgParser()..addFlag('verbose');
  var appCommand = argParser.addCommand('app');

  print('''Flutter Studio
Commands:
- app: start the graphic user interface
- screenshots: run the test and generate the screenshots  
${Platform.resolvedExecutable}
${Platform.script}
$packageUri
$packageRoot
''');

  var processManager = ProcessManager();
  var process = await processManager.spawn(
      flutterSdk.flutter, ['run', '-d', 'macos', '--release'],
      workingDirectory: appPath, runInShell: false);
  unawaited(process.exitCode.then(exit));
}

class FlutterSdk {
  final String root;

  FlutterSdk(String path) : root = p.canonicalize(path);

  static FlutterSdk? tryFind(String path) {
    if (FileSystemEntity.isDirectorySync(path)) {
      var dir = Directory(path);
      while (dir.existsSync()) {
        var sdk = FlutterSdk(dir.path);
        if (isValid(sdk)) {
          return sdk;
        } else {
          var parent = dir.parent;
          if (parent.path == dir.path) return null;
          dir = parent;
        }
      }
    } else if (FileSystemEntity.isFileSync(path)) {
      return tryFind(File(path).parent.path);
    }
    return null;
  }

  String get flutter =>
      p.join(root, 'bin', 'flutter${Platform.isWindows ? '.bat' : ''}');

  @override
  bool operator ==(other) => other is FlutterSdk && other.root == root;

  @override
  int get hashCode => root.hashCode;

  static bool isValid(FlutterSdk sdk) {
    return File(sdk.flutter).existsSync();
  }
}
