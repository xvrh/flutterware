import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutterware_app/src/wrap/install_command.dart';
import 'package:flutterware_app/src/wrap/run_command.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>(
    'wrap',
    'flutterware SDK wrap point.',
  )
    ..addCommand(RunCommand())
    ..addCommand(InstallCommand());
  try {
    final code = await runner.run(args) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}
