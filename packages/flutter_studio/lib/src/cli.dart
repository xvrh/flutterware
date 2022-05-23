import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_studio/src/server.dart';
import 'package:flutter_studio/src/test/entry_point.dart';
import 'package:flutter_studio/src/test/flutter_run_process.dart';
import 'package:logging/logging.dart';
import 'package:io/ansi.dart';
import 'dart:io' as io;

final _logger = Logger('flutter_studio');

void runCommandLine(List<String> args) async {
  var argParser = ArgParser()
    ..addOption('port', defaultsTo: '0')
    ..addFlag('verbose');

  var argResults = argParser.parse(args);
  var port = int.parse(argResults['port'] as String);
  var verbose = argResults['verbose'] as bool;

  _setupLogger(verbose: verbose);

  //TODO(xha): we drop the server part
  // This is converted to be a tool for alternate purposes:
  //   dart run flutter_studio test_ui build web (deploy Web build of test_ui)
  // Maybe move the code in app? and find a way to expose the CLI in the PATH


  var server = await Server.start(port: port);

  // 1. Start a server with a random port
  // 2. Listen on a websocket for the UI to connect (allow multiple UI)
  // 3. For each UI, create a "Client": a flutter run -d flutter-tester process
  //    pointing to an invisible .dart file with the configured entry point.
  //    In the entry point: a websocket url (which contain an id).
  // 4. The client connect in WebSocket back to the server
  // 5. The server put the UI & the client in relation (forward directly the payload)

  // => Goal get the project running

  // Next steps:
  // - Compile the app in web and serve it with the server.
  // - Find stable solution for the fonts (ie. use desktop fonts, fallback to other font, propose to download some fonts etc...).
  // - Re-add email & pdf management
  // - Allow to test with CLI (flutter test xx)?
  // - Allow to build web app (+ immediate preview).
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
