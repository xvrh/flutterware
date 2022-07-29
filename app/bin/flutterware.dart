import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:flutterware/internals/constants.dart';
import 'package:flutterware/internals/remote_log.dart';
import 'package:flutterware/internals/remote_log_adapter.dart';
import 'package:flutterware_app/src/constants.dart';
import 'package:flutterware_app/src/utils/daemon/events.dart';
import 'package:flutterware_app/src/utils/daemon/protocol.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';

class _Context {
  final String dartExecutable;
  final String appToolPath;
  final _FlutterSdk flutterSdk;
  final Directory projectDirectory;
  final RemoteLogClient logClient;

  _Context({
    required this.dartExecutable,
    required this.appToolPath,
    required this.flutterSdk,
    required this.projectDirectory,
    required this.logClient,
  });

  Future<String> flutterwareVersion() async {
    var pubspecContent =
        await File(p.join(appToolPath, '..', 'pubspec.yaml')).readAsString();
    var pubspec = Pubspec.parse(pubspecContent);
    return pubspec.version.toString();
  }
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
  logger.printTrace('CLI started with Flutter SDK $flutterSdk');

  var context = _Context(
    dartExecutable: dartExecutable,
    appToolPath: Platform.environment[appPathEnvironmentKey]!,
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
  final description = 'Start the Flutterware App GUI.';

  _AppCommand(this.context);

  @override
  void run() async {
    var appPubspec = Pubspec.parse(await File(
            p.join(context.projectDirectory.absolute.path, 'pubspec.yaml'))
        .readAsString());

    context.logClient.printBox('''
App: ${appPubspec.name} (${context.projectDirectory.absolute.path})
Flutter SDK: ${context.flutterSdk.root}
''', title: 'Flutterware ${await context.flutterwareVersion()}');

    var buildProgress =
        context.logClient.startProgress('Starting Flutterware GUI');

    var process = await Process.start(
      context.flutterSdk.flutter,
      [
        'run',
        '-d',
        Platform.operatingSystem,
        '--release',
        '--machine',
      ],
      environment: {
        if (Platform.isMacOS) 'LC_ALL': 'en_US.UTF-8',
        projectDefineKey: context.projectDirectory.absolute.path,
        flutterSdkDefineKey: context.flutterSdk.root,
        remoteLoggerUrlKey: '${context.logClient.uri}',
      },
      workingDirectory: context.appToolPath,
    );

    await for (var line
        in process.stdout.transform(Utf8Decoder()).transform(LineSplitter())) {
      var daemonLine = DaemonProtocol.tryReadLine(line);
      if (daemonLine != null) {
        context.logClient.printTrace('App daemon: $daemonLine');
        var event = DaemonProtocol.tryReadEvent(daemonLine);
        if (event is AppStartedEvent) {
          break;
        } else if (event is AppProgressEvent) {
          var message = event.message;
          if (message != null) {
            context.logClient.printStatus(message);
          }
        } else if (event is DaemonLogMessageEvent) {
          context.logClient.printError(event.message);
        } else if (event is DaemonLogEvent) {
          context.logClient.printWarning(event.log);
        }
      } else {
        context.logClient.printTrace('App: $line');
      }
    }
    buildProgress.stop();
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
