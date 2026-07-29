import 'package:flutterware/src/launch_plan.dart';
import 'package:flutterware/src/live_region.dart';
import 'package:test/test.dart';

/// Two properties, and everything below is one of them.
///
/// A region must always know how far up to go — get that wrong and it either
/// eats the user's scrollback or leaves a dead copy of itself in it. And a
/// plan must print no escape sequence at all when nobody is watching, which is
/// the same rule `build_output_test.dart` protects for `Step`.
void main() {
  group('LiveRegion', () {
    test('the first paint writes the rows and nothing else', () {
      var out = StringBuffer();
      LiveRegion(out: out, rows: () => ['one', 'two']).start();

      expect(out.toString(), '\x1b[2Kone\n\x1b[2Ktwo\n');
      // Nothing to go back over yet.
      expect(out.toString(), isNot(contains('F')));
    });

    test('a repaint goes back exactly as far as it came', () {
      var rows = ['one', 'two', 'three'];
      var out = StringBuffer();
      var region = LiveRegion(out: out, rows: () => rows);
      region.start();
      out.clear();

      region.printAbove(const []);
      // Erase three, then paint three.
      expect(out.toString(), startsWith('\x1b[3F\x1b[0J'));
      expect(out.toString(), contains('\x1b[2Kthree\n'));
    });

    test('a shrinking region clears what it no longer covers', () async {
      var rows = ['one', 'two', 'three'];
      var out = StringBuffer();
      var region = LiveRegion(out: out, rows: () => rows);
      region.start(every: const Duration(milliseconds: 5));
      addTearDown(region.stop);

      rows = ['one'];
      out.clear();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // A plain repaint, with no erase before it: the two rows below the new
      // last one are still showing the previous frame without the trailing
      // `0J`. Every repaint after this one goes back one row, not three.
      expect(out.toString(), startsWith('\x1b[3F\x1b[2Kone\n\x1b[0J'));
      expect(out.toString(), isNot(contains('\x1b[3F\x1b[2Kone\n\x1b[2K')));
    });

    test('printAbove puts the line above, and the region back below', () {
      var out = StringBuffer();
      var region = LiveRegion(out: out, rows: () => ['status'])..start();
      out.clear();

      region.printAbove(['a log line']);

      var written = out.toString();
      expect(written, startsWith('\x1b[1F\x1b[0J'));
      expect(
        written.indexOf('a log line'),
        lessThan(written.indexOf('status')),
      );
    });

    test('printing above nothing does not paint a region that is gone', () {
      var out = StringBuffer();
      var region = LiveRegion(out: out, rows: () => ['status'])..start();
      region.stop();
      out.clear();

      region.printAbove(['after']);

      // No region to erase and none to restore: the line is just a line.
      expect(out.toString(), 'after\n');
    });

    test('stop erases the region and keeps the closing lines', () {
      var out = StringBuffer();
      var region = LiveRegion(out: out, rows: () => ['status'])..start();
      out.clear();

      region.stop(closing: ['done']);

      expect(out.toString(), '\x1b[1F\x1b[0Jdone\n');
    });

    test('settle keeps the last frame instead of erasing it', () {
      var out = StringBuffer();
      var region = LiveRegion(out: out, rows: () => ['status'])..start();
      out.clear();

      region.settle(trailing: ['after']);

      // Repainted in place, then released — so `after` lands below it rather
      // than on top of it.
      expect(out.toString(), '\x1b[1F\x1b[2Kstatus\nafter\n');
    });

    test('a stopped region stops painting', () async {
      var out = StringBuffer();
      var region = LiveRegion(out: out, rows: () => ['status']);
      region.start(every: const Duration(milliseconds: 5));
      region.stop();
      out.clear();

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(out.toString(), isEmpty);
    });
  });

  group('LaunchPlan', () {
    LaunchStage stage(String label, [int seconds = 1]) =>
        LaunchStage(label, budget: Duration(seconds: seconds));

    test('off a terminal it is one plain line per stage', () async {
      var out = StringBuffer();
      var first = stage('unpack flutterware', 3);
      var second = stage('build the CLI', 10);
      var plan = LaunchPlan(
        [first, second],
        out: out,
        interactive: false,
        title: 'flutterware · example',
      )..start();

      await plan.run(first, () async => 0);
      await plan.run(second, () async => 0);
      plan.finish(closing: 'ready');

      expect(
        out.toString(),
        'unpack flutterware… (~3s)\nbuild the CLI… (~10s)\n',
      );
      // The rule `Step` follows, for the same reason: a CI log must never
      // receive an escape sequence.
      expect(out.toString(), isNot(contains('\x1b')));
    });

    test(
      'on a terminal every stage is listed before any of them runs',
      () async {
        var out = StringBuffer();
        var first = stage('build the CLI');
        var second = stage('build the GUI');
        LaunchPlan([first, second], out: out, interactive: true).start();

        // The whole feature: the second stage is on screen before the first one
        // has started, which is what answers "how much is left".
        expect(out.toString(), contains('build the CLI'));
        expect(out.toString(), contains('build the GUI'));
      },
    );

    test(
      'the projection is dropped once there is nothing left to project',
      () async {
        var out = StringBuffer();
        var only = stage('build the GUI', 30);
        var plan = LaunchPlan([only], out: out, interactive: true)..start();
        await plan.run(only, () async => 0);

        out.clear();
        plan.finish(closing: 'ready in 1s');

        // "about 29s left" above a line saying it is over is worse than no
        // footer at all.
        expect(out.toString(), isNot(contains('left')));
        expect(out.toString(), contains('ready in 1s'));
      },
    );

    test('a stage that fails is drawn as failed, and kept', () async {
      var out = StringBuffer();
      var only = stage('build the GUI');
      var plan = LaunchPlan([only], out: out, interactive: true)..start();

      await plan.run(only, () async => 1, ok: (code) => code == 0);
      plan.finish();

      expect(only.state, LaunchStageState.failed);
      // Kept rather than erased: the ✗ is what says which stage the error
      // printed below it came from.
      expect(out.toString(), contains('✗'));
      expect(out.toString(), contains('build the GUI'));
    });

    test('a throwing body still ends the stage', () async {
      var out = StringBuffer();
      var only = stage('build the CLI');
      var plan = LaunchPlan([only], out: out, interactive: true)..start();

      await expectLater(
        plan.run(only, () async => throw StateError('boom')),
        throwsStateError,
      );
      plan.finish();

      expect(only.state, LaunchStageState.failed);
    });

    test('two stages can run at once, and time separately', () async {
      var out = StringBuffer();
      var first = stage('build the CLI');
      var second = stage('build the GUI');
      var plan = LaunchPlan([first, second], out: out, interactive: true)
        ..start();

      await Future.wait([
        plan.run(first, () => Future<void>.delayed(Duration.zero)),
        plan.run(
          second,
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        ),
      ]);
      plan.finish();

      expect(first.state, LaunchStageState.done);
      expect(second.state, LaunchStageState.done);
      expect(second.elapsed, greaterThan(first.elapsed));
    });
  });
}
