import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutterware/internals/constants.dart';
import 'package:flutterware/internals/log.dart';
import 'package:path/path.dart' as p;
import 'package:logging/logging.dart';
import 'package:io/ansi.dart' as ansi;

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

  _printLog('''
Platform.resolvedExecutable: ${Platform.resolvedExecutable}
Platform.script: ${Platform.script}
Flutterware Package: $pubPackage
PackageRoot: $packageRoot
''', Level.INFO.value, verbose: isVerbose);

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
  process.stdout
      .transform(Utf8Decoder())
      .transform(LineSplitter())
      .listen((line) {
    var log = Log.tryParse(line);
    if (log != null) {
      _printLog(log.message, log.level, verbose: isVerbose);
    }
  });
  unawaited(stderr.addStream(process.stderr));
}

void _printLog(String message, int level, {required bool verbose}) {
  if (!verbose && level < Level.INFO.value) {
    return;
  }

  var color = <int, ansi.AnsiCode> {
        Level.SHOUT.value: ansi.red,
        Level.SEVERE.value: ansi.red,
        Level.WARNING.value: ansi.yellow,
        Level.INFO.value: ansi.blue,
      }[level] ??
      ansi.black;

  print(ansi.wrapWith(message, [color]));
}
