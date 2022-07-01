import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutterware/internals/constants.dart';
import 'package:path/path.dart' as p;

void main(List<String> arguments) async {
  var pubPackage =
      await Isolate.resolvePackageUri(Uri.parse('package:flutterware/lib'));
  var packageRoot = pubPackage!.resolve('..').toFilePath();
  var appPath = p.join(packageRoot, 'app');
  if (!File(p.join(packageRoot, 'pubspec.yaml')).existsSync() ||
      !File(p.join(appPath, 'pubspec.yaml')).existsSync()) {
    throw Exception('Failed to resolve flutterware (root: $packageRoot)');
  }

  var isVerbose = arguments.any((e) => ['-v', '--verbose'].contains(e));

  if (isVerbose) {
    print('''
Platform.resolvedExecutable: ${Platform.resolvedExecutable}
Platform.script: ${Platform.script}
Flutterware Package: $pubPackage
PackageRoot: $packageRoot
''');
  }

  var compiledCliPath = 'build/compiled_cli${Platform.isWindows ? '.exe' : ''}';
  var compiledCliFile = File(p.join(appPath, compiledCliPath));
  //TODO(xha): we should detect if any file has changed and re-compile as needed.
  if (!compiledCliFile.existsSync() ||
      arguments.contains('--$forceCompileCliOption')) {
    compiledCliFile.parent.createSync(recursive: true);
    try {
      compiledCliFile.deleteSync();
    } catch (e) {
      // Don't care if the file doesn't exist
    }

    var pubGetResult = Process.runSync(
        Platform.resolvedExecutable, ['pub', 'get'],
        workingDirectory: appPath);
    if (pubGetResult.exitCode != 0) {
      throw Exception('Pub get failed ${pubGetResult.stderr}');
    }
    var compiledResult = Process.runSync(Platform.resolvedExecutable,
        ['compile', 'exe', '-o', compiledCliPath, 'bin/flutterware.dart'],
        workingDirectory: appPath);
    if (compiledResult.exitCode != 0) {
      throw Exception(
          'Failed to compile flutterware CLI ${compiledResult.stderr}');
    }
  }

  var process = await Process.start(
    compiledCliFile.path,
    arguments,
    environment: {
      dartExecutableEnvironmentKey: Platform.resolvedExecutable,
      studioAppPathEnvironmentKey: p.absolute(appPath),
    },
    runInShell: true,
  );

  //TODO(xha): try to keep the command line colors by using a json protocol with the
  // formatting information and converting to ansi code here.
  unawaited(stdin.pipe(process.stdin));
  unawaited(stdout.addStream(process.stdout));
  unawaited(stderr.addStream(process.stderr));
}
