import 'dart:convert';
import 'dart:io';

import 'package:flutterware_app/src/run/logs.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// One `--machine` line, as the launcher writes them: a JSON array on its own
/// line.
String event(String name, Map<String, Object?> params) => jsonEncode([
  {'event': name, 'params': params},
]);

/// Verbatim from a real log: the engine's own stderr, on the same stdout the
/// app prints to.
const impellerLine =
    '[IMPORTANT:flutter/shell/platform/embedder/embedder_surface_metal_impeller'
    '.mm(53)] Using the Impeller rendering backend (MetalSDF).';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('run_logs_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(List<String> lines) {
    var path = p.join(dir.path, 'app-abc.log');
    File(path).writeAsStringSync(lines.join('\n'));
    return path;
  }

  test('a log that does not exist is empty rather than an error', () {
    expect(readRunLog(p.join(dir.path, 'nothing.log')), isEmpty);
  });

  test("separates the app's output from the tool's", () {
    // Verbatim from a real `flutter run --machine -d macos` log. The app's
    // print arrives as a plain `flutter: ` line between two machine events —
    // not as an `app.log`, which is what this was written against first.
    var path = write([
      'Launching lib/main.dart on macOS in debug mode...',
      '✓ Built build/macos/Build/Products/Debug/flutterware_example.app',
      'flutter: FWPROBE stdout line',
      event('app.started', {'appId': 'a'}),
      'flutter: FWPROBE tick 1',
    ]);

    expect(readRunLog(path).map((l) => '${l.source.name}: ${l.text}'), [
      'tool: Launching lib/main.dart on macOS in debug mode...',
      'tool: ✓ Built build/macos/Build/Products/Debug/flutterware_example.app',
      'app: FWPROBE stdout line',
      'app: FWPROBE tick 1',
    ]);
    // The prefix is stripped: it is the tool's framing, not the app's words.
    expect(readRunLog(path, only: RunLogSource.app).map((l) => l.text), [
      'FWPROBE stdout line',
      'FWPROBE tick 1',
    ]);
    expect(readRunLog(path, only: RunLogSource.tool), hasLength(2));
  });

  test('the engine talking about itself is not the app talking', () {
    // Also verbatim. It arrives on the same stdout as the app's output and is
    // the case the prefix exists to separate.
    var path = write([impellerLine, 'flutter: mine']);

    expect(readRunLog(path, only: RunLogSource.app).map((l) => l.text), [
      'mine',
    ]);
  });

  test('marks errors the launcher marked, and only those', () {
    var path = write([
      'flutter: no errors here',
      event('app.log', {'appId': 'a', 'log': 'RangeError', 'error': true}),
      event('daemon.logMessage', {'level': 'error', 'message': 'build failed'}),
      event('daemon.logMessage', {'level': 'warning', 'message': 'deprecated'}),
    ]);

    // The word "error" in a line is not what decides it: the first line says it
    // and is not one, the warning does not and is not one either.
    expect(readRunLog(path, errorsOnly: true).map((l) => l.text), [
      'RangeError',
      'build failed',
    ]);
    expect(readRunLog(path).map((l) => l.error), [false, true, true, false]);
  });

  test('drops the tool narrating its own progress', () {
    var path = write([
      event('daemon.logMessage', {'level': 'status', 'message': 'Resolving…'}),
      event('daemon.logMessage', {'level': 'trace', 'message': 'chatter'}),
      event('daemon.logMessage', {'level': 'warning', 'message': 'kept'}),
    ]);

    expect(readRunLog(path).map((l) => l.text), ['kept']);
  });

  test('keeps a stack trace with the message it belongs to', () {
    var path = write([
      event('daemon.logMessage', {
        'level': 'error',
        'message': 'it broke',
        'stackTrace': '#0 main',
      }),
    ]);

    expect(readRunLog(path).single.text, 'it broke\n#0 main');
  });

  test('reports the reason an app.stop carried', () {
    var path = write([
      event('app.stop', {'appId': 'a', 'error': 'the device went away'}),
    ]);

    var line = readRunLog(path).single;
    expect(line.text, 'the device went away');
    expect(line.error, isTrue);
    expect(line.source, RunLogSource.tool);
  });

  test('tail keeps the end, and the total still counts everything', () {
    var path = write([for (var i = 0; i < 10; i++) 'flutter: line $i']);

    var all = readRunLog(path);
    expect(all, hasLength(10));
    expect(readRunLog(path, tail: 3).map((l) => l.text), [
      'line 7',
      'line 8',
      'line 9',
    ]);
  });

  test('a half-written line is skipped rather than fatal', () {
    var path = write([
      'flutter: before',
      '[{"event":"app.started","params":{"appId":"a"',
      'flutter: after',
    ]);

    // The truncated line is not decodable as an event, so it survives as tool
    // output — what matters is that the lines around it are still read.
    expect(readRunLog(path, only: RunLogSource.app).map((l) => l.text), [
      'before',
      'after',
    ]);
  });

  test('an event this build does not know does not stop the read', () {
    var path = write([
      'flutter: before',
      event('app.somethingNew', {'appId': 'a', 'whatever': true}),
      'flutter: after',
    ]);

    expect(readRunLog(path, only: RunLogSource.app).map((l) => l.text), [
      'before',
      'after',
    ]);
  });

  test('blank lines are dropped', () {
    var path = write(['', '   ', 'something']);
    expect(readRunLog(path).map((l) => l.text), ['something']);
  });

  group('the engine says it threw', () {
    /// **The shape a consumer hit.** A `main` that awaited a config fetch
    /// against a dead port threw before `runApp`, and the app then sat there
    /// answering its VM service with nothing mounted. No `FlutterError`, no
    /// `app.log`, no `daemon.logMessage` — the engine writes this straight to
    /// the process's stderr, and `errors: true` used to answer `[]` for a log
    /// that plainly contained the reason.
    const unhandled =
        '[ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled '
        'Exception: ClientException with SocketException: Connection refused '
        '(OS Error: Connection refused, errno = 61), '
        'uri=http://localhost:8080/config';

    test('an unhandled exception before runApp is an error line', () {
      var path = write(['Launching lib/main.dart on macOS...', unhandled]);

      var errors = readRunLog(path, errorsOnly: true);

      expect(errors, hasLength(1));
      expect(errors.single.text, unhandled);
      expect(errors.single.source, RunLogSource.tool);
    });

    /// The guard on the rule this bends. `[IMPORTANT:…]` is the same emitter
    /// in the same format at a severity that is not a fault, and it rides
    /// every launch on macOS — matching it would make "errors" meaningless on
    /// the platform most runs happen on.
    test('the engine talking about Impeller is not an error', () {
      var path = write([impellerLine]);

      expect(readRunLog(path, errorsOnly: true), isEmpty);
      expect(readRunLog(path).single.error, isFalse);
    });

    /// The older, larger rule: [RunLogLine.error] is not inferred from prose.
    /// A fixed prefix is not prose, and neither of these has one.
    test('prose about errors is still not an error', () {
      var path = write([
        'flutter: no errors found',
        'Error: this line is the tool talking, and carries no severity',
        'building with error reporting enabled',
      ]);

      expect(readRunLog(path, errorsOnly: true), isEmpty);
    });

    test('a FATAL line counts too', () {
      const fatal =
          '[FATAL:flutter/shell/common/shell.cc(93)] Check failed: could not '
          'create the engine.';
      var path = write([fatal]);

      expect(readRunLog(path, errorsOnly: true), hasLength(1));
    });

    /// The app's own stream can carry one as well, and it stays the app's.
    test('an engine line behind the app prefix keeps its source', () {
      var path = write(['flutter: $unhandled']);

      var errors = readRunLog(path, errorsOnly: true);

      expect(errors.single.source, RunLogSource.app);
      expect(errors.single.text, unhandled);
    });
  });
}
