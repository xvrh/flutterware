import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:flutterware/src/constants.dart';
import 'package:flutterware/src/logs/remote_log_adapter.dart';
import 'package:flutterware/src/logs/remote_log_client.dart';
import 'package:flutterware_app/src/constants.dart';
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
        await File(p.join(appToolPath, 'pubspec.yaml')).readAsString();
    var pubspec = Pubspec.parse(pubspecContent);
    return pubspec.version.toString().split('+').first;
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

  await runZoned(
    () async {
      var commandRunner = CommandRunner(
          'flutterware', 'Collection of tools for Flutter development.')
        ..addCommand(_AppCommand(context))
        ..argParser.addFlag('verbose', abbr: 'v', help: 'increase logging')
        ..argParser.addFlag(forceCompileOption, hide: true);
      var argResults = commandRunner.parse(args);
      if (argResults.command == null &&
          (argResults.arguments.isEmpty ||
              argResults.arguments.first.startsWith('-'))) {
        argResults = commandRunner.parse(['app', ...args]);
      }
      logger.printTrace('Args: ${argResults.arguments}');

      Logger.root
        ..level = Level.ALL
        ..onRecord.listen(logger.printLogRecord);

      var result = await commandRunner.runCommand(argResults);
      logger.printTrace('Command ended with $result');
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, message) {
        logger.printBox(message);
      },
    ),
  );
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
    var projectPubspec = Pubspec.parse(await File(
            p.join(context.projectDirectory.absolute.path, 'pubspec.yaml'))
        .readAsString());

    context.logClient.printBox('''
Project: ${projectPubspec.name} (${context.projectDirectory.absolute.path})
Flutter SDK: ${context.flutterSdk.root}
''', title: 'Flutterware ${await context.flutterwareVersion()}');

    var exeFile = File(p.join(
        context.appToolPath, _exePathForPlatform(logger: context.logClient)));

    context.logClient.printTrace(
        'Compile GUI (exe: ${exeFile.existsSync()}, option: ${argResults!.arguments})');
    if (!exeFile.existsSync() ||
        (argResults!.arguments.contains('--$forceCompileOption'))) {
      var buildProgress =
          context.logClient.startProgress('Building Flutterware GUI');

      var buildProcess = await Process.start(
        context.flutterSdk.flutter,
        [
          'build',
          Platform.operatingSystem,
          '--release',
        ],
        workingDirectory: context.appToolPath,
      );

      await for (var line in buildProcess.stdout
          .transform(Utf8Decoder())
          .transform(LineSplitter())) {
        context.logClient.printStatus(line);
      }
      buildProgress.stop();
      var buildExitCode = await buildProcess.exitCode;
      if (buildExitCode != 0) {
        context.logClient.printError(
            'Failed to build GUI ($buildExitCode): ${await utf8.decodeStream(buildProcess.stderr)}');
        return;
      }
    }

    var process = await Process.start(
      exeFile.path,
      [],
      environment: {
        projectDefineKey: context.projectDirectory.absolute.path,
        appToolPathKey: context.appToolPath,
        flutterSdkDefineKey: context.flutterSdk.root,
        remoteLoggerUrlKey: '${context.logClient.uri}',
      },
      workingDirectory: context.appToolPath,
    );

    await process.exitCode.then(exit);
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

String _exePathForPlatform({required LogClient logger}) {
  if (Platform.isWindows) {
    return 'build/windows/runner/Release/Flutterware.exe';
  } else if (Platform.isLinux) {
    return 'build/linux/${_linuxHostPlatform(logger: logger)}/release/bundle/app';
  } else {
    return 'build/macos/Build/Products/Release/Flutterware.app/Contents/MacOS/Flutterware';
  }
}

String _linuxHostPlatform({required LogClient logger}) {
  final hostPlatformCheck = Process.runSync('uname', ['-m']);
  // On x64 stdout is "uname -m: x86_64"
  // On arm64 stdout is "uname -m: aarch64, arm64_v8a"
  if (hostPlatformCheck.exitCode != 0) {
    logger.printError(
      'Encountered an error trying to run "uname -m":\n'
      '  exit code: ${hostPlatformCheck.exitCode}\n'
      '  stdout: ${hostPlatformCheck.stdout.toString().trimRight()}\n'
      '  stderr: ${hostPlatformCheck.stderr.toString().trimRight()}\n'
      'Assuming host platform is x64.',
    );
    return 'x64';
  } else if (hostPlatformCheck.stdout.toString().trim().endsWith('x86_64')) {
    return 'x64';
  } else {
    // We default to ARM if it's not x86_64 and we did not get an error.
    return 'arm64';
  }
}
