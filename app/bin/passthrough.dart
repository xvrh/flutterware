import 'dart:async';
import 'package:args/command_runner.dart';
import 'package:flutterware_app/src/passthrough/passthrough_command.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>('passthrough', 'Run a subprocess under a PTY.')
    ..addCommand(PassthroughCommand());
  final exitCode = await runner.run(args) ?? 0;
  // ignore: avoid_print
  // exit via process exit code
  await Future<void>.delayed(Duration.zero);
  // Use dart:io exit in next task once command is implemented end-to-end.
  // For now, just propagate.
  // (Will be replaced with `exit(exitCode);` once command body lands.)
  if (exitCode != 0) {
    throw StateError('passthrough exited with $exitCode');
  }
}
