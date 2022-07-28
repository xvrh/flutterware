import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutterware/internals/constants.dart';
import 'package:flutterware/internals/remote_log.dart';
import 'package:flutterware/internals/remote_log_adapter.dart';
import 'package:flutterware_app/src/constants.dart';
import 'package:flutterware_app/src/utils/daemon/events.dart';
import 'package:flutterware_app/src/utils/daemon/protocol.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:args/command_runner.dart';

class _Context {
  final String dartExecutable;
  final String studioAppPath;
  final _FlutterSdk flutterSdk;
  final Directory projectDirectory;
  final RemoteLogClient logClient;

  _Context({
    required this.dartExecutable,
    required this.studioAppPath,
    required this.flutterSdk,
    required this.projectDirectory,
    required this.logClient,
  });
}

void main(List<String> args) async {
  var dartExecutable = Platform.environment[dartExecutableEnvironmentKey]!;
  var flutterSdk = _FlutterSdk.tryFind(dartExecutable);
  if (flutterSdk == null) {
    throw Exception('Flutter command not found. '
        'Make sure you are using the dart command from a Flutter SDK (instead of a standalone Dart SDK).\nSearched ${Platform.resolvedExecutable}');
  }

  var loggerUrl = Platform.environment[remoteLoggerServerUrlKey]!;
  var logger = RemoteLogClient(Uri.parse(loggerUrl));

  logger.printWarning("message");
  await Future.delayed(const Duration(seconds: 3));

  var context = _Context(
    dartExecutable: dartExecutable,
    studioAppPath: Platform.environment[appPathEnvironmentKey]!,
    flutterSdk: flutterSdk,
    projectDirectory: Directory.current,
    logClient: logger,
  );

  var commandRunner = CommandRunner(
      'flutterware', 'Collection of tools for Flutter development.')
    ..addCommand(_AppCommand(context))
    ..argParser.addFlag('verbose', abbr: 'v', help: 'increase logging')
    ..argParser.addFlag(forceCompileCliOption, hide: true);
  var argResults = commandRunner.parse(args);
  if (argResults.command == null &&
      (argResults.arguments.isEmpty ||
          argResults.arguments.first.startsWith('-'))) {
    argResults = commandRunner.parse(['app', ...args]);
  }

  Logger.root
    ..level = Level.ALL
    ..onRecord.listen(logger.printLogRecord);

  await commandRunner.runCommand(argResults);
}

class _AppCommand extends Command {
  final _Context context;

  @override
  final name = 'app';

  @override
  final description = 'Start the Flutter Studio App GUI.';

  _AppCommand(this.context);

  @override
  void run() async {
    var buildProgress = context.logClient.startProgress(
        'Starting Flutter Studio App (Flutter: ${context.flutterSdk.flutter}, dir: ${context.studioAppPath})');

    var process = await Process.start(
      context.flutterSdk.flutter,
      [
        'run',
        '-d',
        'macos',
        '--release',
        '--dart-define',
        '$projectDefineKey=${context.projectDirectory.absolute.path}',
        '--dart-define',
        '$flutterSdkDefineKey=${context.flutterSdk.root}',
        '--dart-define',
        '$flutterSdkDefineKey=${context.logClient.uri}',
      ],
      environment: {
        if (Platform.isMacOS) 'LC_ALL': 'en_US.UTF-8',
      },
      workingDirectory: context.studioAppPath,
    );

    await for (var line in process.stdout.transform(Utf8Decoder()).transform(LineSplitter())) {
      context.logClient.printTrace('App: $line');
      var daemonLine = DaemonProtocol.tryReadLine(line);
      if (daemonLine != null) {
        var event = DaemonProtocol.tryReadEvent(daemonLine);
        if (event is AppProgressEvent && event.finished) {
          buildProgress.stop();
        }
      }
    }

    unawaited(process.exitCode.then(exit));
  }
}

class _FlutterSdk {
  final String root;

  _FlutterSdk(String path) : root = p.canonicalize(path);

  static _FlutterSdk? tryFind(String path) {
    if (FileSystemEntity.isDirectorySync(path)) {
      var dir = Directory(path);
      while (dir.existsSync()) {
        var sdk = _FlutterSdk(dir.path);
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

  static bool isValid(_FlutterSdk sdk) {
    return File(sdk.flutter).existsSync();
  }
}
