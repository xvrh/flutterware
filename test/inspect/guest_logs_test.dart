import 'dart:async';

import 'package:flutterware/src/inspect/guest_logs.dart';
import 'package:flutterware/src/inspect/log.dart';
import 'package:test/test.dart';

/// The capture, and the one property the whole design rests on: **it forwards**.
///
/// The guest's stdout is not decoration. The host reads the VM service URI off
/// it, and the headless check reads `FW-PROBE:` lines off it — so a zone that
/// kept a line to itself would not merely lose a log, it would stop the session
/// from starting. Every test here that looks like it is about tidiness is
/// actually about that.
void main() {
  group('GuestLogs', () {
    setUp(GuestLogs.instance.clear);

    test('records what is printed, in order, and still prints it', () {
      var printed = <String>[];
      _capturing(printed, () {
        print('first');
        print('second');
      });

      expect(printed, ['first', 'second']);
      expect(_texts(), ['first', 'second']);
    });

    test('numbers the lines so a reader can merge two sources', () {
      _capturing([], () {
        print('a');
        print('b');
        print('a');
      });

      var numbers = [
        for (var line in GuestLogs.instance.describe().lines) line.sequence,
      ];
      expect(numbers.toSet(), hasLength(3), reason: 'each line its own number');
      expect(
        numbers,
        orderedEquals([...numbers]..sort()),
        reason: 'and rising, which is what lets a reader drop an overlap',
      );
      // Two identical lines, distinguishable. Matching on text and time instead
      // would still be wrong about a demo printing the same word twice in a
      // frame — which is the case this exists for.
      expect(numbers.first, isNot(numbers.last));
    });

    test('installing inside itself does not record every line twice', () {
      _capturing([], () {
        // The hazard the guard is for. An inner zone forwards to the outer
        // one's handler, so a nested install records once on the way through
        // each — and a console showing everything twice is not a console.
        GuestLogs.instance.install(() => print('once'));
      });

      expect(_texts(), ['once']);
    });

    test('the harness talking to itself is not the demo printing', () {
      var printed = <String>[];
      _capturing(printed, () {
        print('FW-PROBE: some rendered text');
        print('mine');
      });

      // Dropped from the record and **not** from stdout: the headless check
      // reads those lines, and a console that showed them would show five a
      // second of them and nothing else.
      expect(_texts(), ['mine']);
      expect(printed, ['FW-PROBE: some rendered text', 'mine']);
    });

    test("a switch of entry forgets the previous demo's words", () {
      GuestLogs.instance.resetFor('demo.dart#one');
      _capturing([], () => print('from one'));

      GuestLogs.instance.resetFor('demo.dart#two');

      expect(_texts(), isEmpty);
      expect(GuestLogs.instance.describe().entryId, 'demo.dart#two');
    });

    test('and a rebuild of the same entry does not', () {
      GuestLogs.instance.resetFor('demo.dart#one');
      _capturing([], () => print('from one'));

      // `resetFor` runs from `didUpdateWidget`, so it fires on every rebuild —
      // turning a knob would otherwise wipe what the previous knob printed,
      // which is the one thing you turned it to see.
      GuestLogs.instance.resetFor('demo.dart#one');

      expect(_texts(), ['from one']);
    });

    test('a full buffer drops the oldest and says how many', () {
      _capturing([], () {
        for (var i = 0; i < 520; i++) {
          print('line $i');
        }
      });

      var report = GuestLogs.instance.describe();
      expect(report.lines, hasLength(500));
      expect(report.lines.first.text, 'line 20');
      expect(report.lines.last.text, 'line 519');
      // Reported rather than silently begun in the middle. A scrollback that
      // quietly starts partway reads as one that has everything.
      expect(report.dropped, 20);
    });

    test('clearing empties it without resetting the numbering', () {
      _capturing([], () => print('before'));
      var last = GuestLogs.instance.describe().lines.last.sequence;

      GuestLogs.instance.clear();
      _capturing([], () => print('after'));

      expect(_texts(), ['after']);
      // The counter has to keep going: a host that had already seen up to
      // `last` and then saw the numbering start again would discard every line
      // until the guest caught back up.
      expect(
        GuestLogs.instance.describe().lines.single.sequence,
        greaterThan(last),
      );
    });
  });

  group('the wire', () {
    test('a report survives the round trip', () {
      var report = const InspectLogs(
        entryId: 'demo.dart#one',
        dropped: 3,
        lines: [InspectLogLine(sequence: 7, text: 'hello', at: 1700)],
      );
      var back = InspectLogs.fromJson(report.toJson());

      expect(back.entryId, 'demo.dart#one');
      expect(back.dropped, 3);
      expect(back.lines.single.sequence, 7);
      expect(back.lines.single.text, 'hello');
      expect(back.lines.single.at, 1700);
    });

    test('one line survives it on its own, which is what a push is', () {
      var back = InspectLogLine.fromJson(
        const InspectLogLine(sequence: 2, text: 'x', at: 5).toJson(),
      );

      expect(back.sequence, 2);
      expect(back.text, 'x');
      expect(back.at, 5);
    });
  });

  /// What one drive step hands back, as opposed to what the buffer holds.
  ///
  /// The buffer is a scrollback and stays one. This is the reply, and a reply
  /// that costs more context than the screen it describes is a reply nobody can
  /// afford to ask for — measured driving the flutterware GUI, whose flutter
  /// daemon prints 4KB of JSON per device event.
  group('capStepLogs', () {
    InspectLogLine line(int n, String text) =>
        InspectLogLine(sequence: n, text: text, at: n);

    test('a short step is handed back whole and unchanged', () {
      var capped = capStepLogs([line(1, 'a'), line(2, 'b')]);
      expect([for (var l in capped) l.text], ['a', 'b']);
      expect([for (var l in capped) l.sequence], [1, 2]);
    });

    test('a long line keeps its head and admits its tail', () {
      var text = 'x' * (maxStepLogLineChars + 25);
      var capped = capStepLogs([line(1, text)]).single;

      expect(capped.text, startsWith('x' * maxStepLogLineChars));
      expect(capped.text, endsWith('… (+25 chars)'));
      // The identity survives: a truncated line is still that line.
      expect(capped.sequence, 1);
      expect(capped.at, 1);
    });

    test('a line exactly at the cap is left alone', () {
      var text = 'x' * maxStepLogLineChars;
      expect(capStepLogs([line(1, text)]).single.text, text);
    });

    test(
      'a flood keeps the most recent, behind a count of what it dropped',
      () {
        var lines = [
          for (var i = 1; i <= maxStepLogLines + 12; i++) line(i, 'line $i'),
        ];
        var capped = capStepLogs(lines);

        expect(capped, hasLength(maxStepLogLines + 1));
        expect(capped.first.text, '… (+12 earlier lines)');
        expect(capped[1].text, 'line 13');
        expect(capped.last.text, 'line ${maxStepLogLines + 12}');
      },
    );

    test('the marker sorts before the lines it stands in for', () {
      var lines = [
        for (var i = 10; i <= maxStepLogLines + 20; i++) line(i, 'line $i'),
      ];
      var capped = capStepLogs(lines);

      // A reader merges by sequence — see [InspectLogLine.sequence] — so the
      // marker must not collide with a real line or land after them.
      expect(capped.first.sequence, lessThan(capped[1].sequence));
    });

    test('nothing at all is nothing, not a marker', () {
      expect(capStepLogs(const []), isEmpty);
    });
  });
}

/// Runs [body] under the capture, collecting what reached the parent zone.
///
/// [GuestLogs.install] refuses to nest, so this reaches the same seam the
/// generated entrypoint does — one zone, installed once — and reads the
/// forwarded lines out of an overridden `print` above it.
void _capturing(List<String> printed, void Function() body) {
  runZoned(
    () => GuestLogs.instance.install(body),
    zoneSpecification: ZoneSpecification(
      // Collected rather than forwarded, so the test's own output stays quiet
      // while still proving the line got *out* of the capture.
      print: (self, parent, zone, line) => printed.add(line),
    ),
  );
}

List<String> _texts() => [
  for (var line in GuestLogs.instance.describe().lines) line.text,
];
