import 'dart:async';
import 'dart:io';

import 'package:flutterware/internals/constants.dart';
import 'package:flutterware_app/src/constants.dart';
import 'package:logging/logging.dart';
import 'package:io/ansi.dart';
import 'dart:io' as io;
import 'package:path/path.dart' as p;
import 'package:args/command_runner.dart';

final _logger = Logger('flutterware');

class _Context {
  final String dartExecutable;
  final String studioAppPath;
  final _FlutterSdk flutterSdk;
  final Directory projectDirectory;

  _Context({
    required this.dartExecutable,
    required this.studioAppPath,
    required this.flutterSdk,
    required this.projectDirectory,
  });
}

void main(List<String> args) async {
  var dartExecutable = Platform.environment[dartExecutableEnvironmentKey]!;
  var flutterSdk = _FlutterSdk.tryFind(dartExecutable);
  if (flutterSdk == null) {
    throw Exception('Flutter command not found. '
        'Make sure you are using the dart command from a Flutter SDK (instead of a standalone Dart SDK).\nSearched ${Platform.resolvedExecutable}');
  }

  var context = _Context(
    dartExecutable: dartExecutable,
    studioAppPath: Platform.environment[studioAppPathEnvironmentKey]!,
    flutterSdk: flutterSdk,
    projectDirectory: Directory.current,
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

  var verbose = argResults['verbose'] as bool;
  _setupLogger(verbose: verbose);

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
    _logger.fine(
        'Starting Flutter Studio App (Flutter: ${context.flutterSdk.flutter}, dir: ${context.studioAppPath})');
    _logger.fine('Current directory: ${Directory.current}');
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
      ],
      environment: {
        if (Platform.isMacOS) 'LC_ALL': 'en_US.UTF-8',
      },
      workingDirectory: context.studioAppPath,
    );

    unawaited(stdin.pipe(process.stdin));
    if (globalResults!['verbose'] as bool? ?? false) {
      unawaited(stdout.addStream(process.stdout));
      unawaited(stderr.addStream(process.stderr));
    }
    unawaited(process.exitCode.then(exit));
  }
}

void _setupLogger({bool? verbose}) {
  verbose ??= false;
  Logger.root
    ..level = verbose ? Level.ALL : Level.INFO
    ..onRecord.listen((e) {
      var foreground = {
            Level.INFO: blue,
            Level.WARNING: yellow,
            Level.SEVERE: red,
            Level.SHOUT: black,
          }[e.level] ??
          defaultForeground;
      var background = {
        Level.SHOUT: backgroundLightRed,
      }[e.level];

      var message = e.message;
      if (e.stackTrace != null) {
        message += '\n${e.stackTrace}';
      }
      io.stdout.writeln(
          wrapWith(message, [foreground, if (background != null) background]));
    });
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
