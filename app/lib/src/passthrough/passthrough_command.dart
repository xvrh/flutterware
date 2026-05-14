import 'package:args/command_runner.dart';

class PassthroughCommand extends Command<int> {
  @override
  final name = 'run';

  @override
  final description = 'Run a subprocess under a PTY.';

  @override
  Future<int> run() async {
    throw UnimplementedError('Implemented in a later task.');
  }
}
