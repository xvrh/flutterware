import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('hello world runs end to end through the engine embedder', () async {
    // `dart test` runs with the package root as the current directory.
    var runScript = p.join(Directory.current.path, 'tool', 'run.dart');

    var result =
        await Process.run(Platform.resolvedExecutable, ['run', runScript]);

    printOnFailure('exit code: ${result.exitCode}');
    printOnFailure('stdout:\n${result.stdout}');
    printOnFailure('stderr:\n${result.stderr}');

    expect(result.stdout, contains('Hello, World!'));
    expect(result.exitCode, 0);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
