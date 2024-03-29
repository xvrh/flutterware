import 'dart:convert';
import 'dart:io';
import 'dart:io' as io;
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:flutterware/src/constants.dart';
import 'package:flutterware/src/logs/io.dart';
import 'package:flutterware/src/logs/logger.dart';
import 'package:flutterware/src/logs/platform.dart' show LocalPlatform;
import 'package:flutterware/src/logs/remote_log_server.dart';
import 'package:flutterware/src/logs/terminal.dart';
import 'package:flutterware/src/utils/list_files.dart';
import 'package:path/path.dart' as p;

void main(List<String> arguments) async {
  var isVerbose = arguments.any((e) => ['-v', '--verbose'].contains(e));
  var logger = _createLogger(isVerbose: isVerbose);

  var remoteLogger = await RemoteLogServer.start(logger);

  var pubPackage =
      await Isolate.resolvePackageUri(Uri.parse('package:flutterware/lib'));
  var packageRoot = pubPackage!.resolve('..').toFilePath();
  var sourceAppPath = p.join(packageRoot, 'app');
  if (!File(p.join(packageRoot, 'pubspec.yaml')).existsSync() ||
      !File(p.join(sourceAppPath, 'pubspec.yaml')).existsSync()) {
    logger.printError('Failed to resolve flutterware (root: $packageRoot)');
    return;
  }

  logger.printTrace(
      'Platform.resolvedExecutable: ${Platform.resolvedExecutable}');
  logger.printTrace('Platform.script: ${Platform.script}');
  logger.printTrace('Flutterware Package: $pubPackage');
  logger.printTrace('PackageRoot: $packageRoot');
  logger.printTrace('App: $sourceAppPath');

  var copiedSourcePath =
      p.join(_userHomePath(), '.flutterware', _hash(packageRoot));
  var appPath = p.join(copiedSourcePath, 'app');

  var compiledCliPath = 'build/compiled_cli${Platform.isWindows ? '.exe' : ''}';
  var compiledCliFile = File(p.join(copiedSourcePath, 'app', compiledCliPath));
  //TODO(xha): we should detect if any file has changed and re-compile as needed.
  if (!compiledCliFile.existsSync() ||
      arguments.contains('--$forceCompileOption')) {
    var buildCliProgress =
        logger.startProgress('Building Flutterware executable');

    await _copyDirectory(packageRoot, copiedSourcePath);

    compiledCliFile.parent.createSync(recursive: true);
    try {
      compiledCliFile.deleteSync();
    } catch (e) {
      // Don't care if the file doesn't exist
    }

    var pubGetResult = await Process.run(
        Platform.resolvedExecutable, ['pub', 'get'],
        workingDirectory: appPath);
    if (pubGetResult.exitCode != 0) {
      throw Exception('Pub get failed ${pubGetResult.stderr}');
    }
    var compiledResult = await Process.run(Platform.resolvedExecutable,
        ['compile', 'exe', '-o', compiledCliPath, 'bin/flutterware.dart'],
        workingDirectory: appPath);
    if (compiledResult.exitCode != 0) {
      throw Exception(
          'Failed to compile flutterware CLI ${compiledResult.stderr}');
    }
    buildCliProgress.stop();
  }

  logger.printTrace('Start process ${compiledCliFile.path}');
  var process = await Process.start(
    compiledCliFile.path,
    arguments,
    environment: {
      dartExecutableEnvironmentKey: Platform.resolvedExecutable,
      appPathEnvironmentKey: p.absolute(appPath),
      remoteLoggerServerUrlKey: remoteLogger.url,
    },
  );
  logger.printTrace('Process started (pid ${process.pid})');

  logger.terminal.keystrokes.listen((e) {
    if (e.trim() == 'q') {
      logger.printStatus('Bye bye');
      process.kill();
    }
  });

  var code = await process.exitCode;
  logger.printTrace('Process exited ($code)');

  if (code > 0) {
    logger.printError('CLI terminated with error ($code).\n'
        'Stdout: ${await utf8.decodeStream(process.stdout)}\n'
        'Stderr: ${await utf8.decodeStream(process.stderr)}');
  }
  exit(code);
}

Logger _createLogger({required bool isVerbose}) {
  var stdio = Stdio();
  var terminal = AnsiTerminal(
    stdio: stdio,
    platform: LocalPlatform(),
    now: DateTime.now(),
  )..singleCharMode = true;
  var outputPreferences = OutputPreferences(showColor: true, stdio: stdio);

  Logger logger = io.Platform.isWindows
      ? WindowsStdoutLogger(
          terminal: terminal,
          stdio: stdio,
          outputPreferences: outputPreferences)
      : StdoutLogger(
          terminal: terminal,
          stdio: stdio,
          outputPreferences: outputPreferences,
        );
  if (isVerbose) {
    logger = VerboseLogger(logger);
  }

  return logger;
}

Future<void> _copyDirectory(String source, String destination) async {
  var files = listFilesInDirectory(source);
  for (var file in files) {
    var relativePath = p.relative(file.absolute.path, from: source);
    var targetFile = p.join(destination, relativePath);
    File(targetFile).createSync(recursive: true);
    await file.copy(targetFile);
  }
}

String _userHomePath() {
  var envKey = Platform.isWindows ? 'APPDATA' : 'HOME';
  return Platform.environment[envKey] ?? '.';
}

String _hash(String input) {
  return sha1
      .convert(utf8.encode(input))
      .bytes
      .map((b) => b.toRadixString(16))
      .join('');
}
