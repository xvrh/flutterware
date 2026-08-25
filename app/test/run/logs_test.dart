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
    /// The shape a consumer hit. A `main` that awaited a config fetch
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

  group('RunLogTail', () {
    late String path;
    late File file;

    setUp(() {
      path = p.join(dir.path, 'tail.log');
      file = File(path)..writeAsStringSync('');
    });

    void append(String text) =>
        file.writeAsStringSync(text, mode: FileMode.append);

    test('reads only what is new, and the answer is the whole log', () {
      var tail = RunLogTail(path);
      append('flutter: one\n');
      tail.read();
      expect([for (var line in tail.lines) line.text], ['one']);

      append('flutter: two\nBuilding\n');
      tail.read();
      expect(
        [for (var line in tail.lines) line.text],
        ['one', 'two', 'Building'],
      );
      expect(
        [for (var line in tail.lines) line.source],
        [RunLogSource.app, RunLogSource.app, RunLogSource.tool],
      );
    });

    test('a line arriving in pieces lands once, whole', () {
      var tail = RunLogTail(path);
      // A poll between the `[` and the `]`: half a machine event.
      var whole = event('daemon.logMessage', {
        'level': 'error',
        'message': 'it broke',
      });
      append(whole.substring(0, 20));
      tail.read();
      expect(
        tail.lines,
        isEmpty,
        reason: 'half an event is held back, not shown as half an event',
      );

      append('${whole.substring(20)}\n');
      tail.read();
      expect([for (var line in tail.lines) line.text], ['it broke']);
      expect(tail.lines.single.error, isTrue);
    });

    test('a character split across two reads survives', () {
      var tail = RunLogTail(path);
      // Three bytes of one glyph, cut after the first.
      var bytes = utf8.encode('flutter: héllo ☕ world\n');
      var cut = utf8.encode('flutter: héllo ').length + 1;
      file.writeAsBytesSync(bytes.sublist(0, cut));
      tail.read();
      file.writeAsBytesSync(bytes.sublist(cut), mode: FileMode.append);
      tail.read();
      expect([for (var line in tail.lines) line.text], ['héllo ☕ world']);
    });

    test('a file that got shorter is read again from the top', () {
      var tail = RunLogTail(path);
      append('flutter: old one\nflutter: old two\n');
      tail.read();
      expect(tail.lines, hasLength(2));

      // A relaunch reusing the path.
      file.writeAsStringSync('flutter: new one\n');
      tail.read();
      expect([for (var line in tail.lines) line.text], ['new one']);
      expect(tail.dropped, 0, reason: 'starting over is not dropping');
    });

    test('the last line of a log nobody finished is still shown', () {
      var tail = RunLogTail(path);
      append('flutter: done\nflutter: killed mid-');
      tail.read();
      expect([for (var line in tail.lines) line.text], ['done', 'killed mid-']);

      // And it is not shown twice once the rest arrives.
      append('sentence\n');
      tail.read();
      expect(
        [for (var line in tail.lines) line.text],
        ['done', 'killed mid-sentence'],
      );
    });

    test('beyond what it keeps, the oldest go and are counted', () {
      var tail = RunLogTail(path, keep: 3);
      append([for (var i = 0; i < 5; i++) 'flutter: line $i\n'].join());
      tail.read();
      expect(
        [for (var line in tail.lines) line.text],
        ['line 2', 'line 3', 'line 4'],
      );
      expect(tail.dropped, 2);
    });

    test('a carriage return ends a line, as it does for readRunLog', () {
      // A build tool redrawing its progress in place, and then a machine event
      // on the end of it. Split on newlines alone this is one line, which no
      // longer starts with `[{` — so the event is never decoded and the error
      // it carried is never flagged.
      var body =
          'Building 10%\rBuilding 90%\r'
          '${event('daemon.logMessage', {'level': 'error', 'message': 'it broke'})}\n';
      file.writeAsStringSync(body);
      var tail = RunLogTail(path)..read();

      expect(
        [for (var line in tail.lines) line.text],
        [for (var line in readRunLog(path)) line.text],
        reason: 'the two readers must agree about where a line ends',
      );
      expect(
        [for (var line in tail.lines) line.text],
        ['Building 10%', 'Building 90%', 'it broke'],
      );
      expect(tail.lines.last.error, isTrue);
    });

    test(r'a \r\n cut in half by a poll does not invent a line', () {
      var tail = RunLogTail(path);
      append('flutter: one\r');
      tail.read();
      append('\nflutter: two\r\n');
      tail.read();
      expect([for (var line in tail.lines) line.text], ['one', 'two']);
    });

    test('a log that does not exist is empty rather than an error', () {
      var tail = RunLogTail(p.join(dir.path, 'nothing.log'))..read();
      expect(tail.lines, isEmpty);
      expect(tail.dropped, 0);
    });

    test('no log path at all is the early state of a run, not a failure', () {
      var tail = RunLogTail(null)..read();
      expect(tail.lines, isEmpty);
    });
  });
}
