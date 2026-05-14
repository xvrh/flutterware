import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutterware_app/src/passthrough/passthrough_command.dart';

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<int>('passthrough', 'Run a subprocess under a PTY.')
        ..addCommand(PassthroughCommand());
  try {
    final code = await runner.run(args) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}
