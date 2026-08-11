import 'dart:io';
import 'dart:typed_data';

import 'package:flutterware_app/src/comparison/channels.dart';
import 'package:flutterware_app/src/comparison/scenario_alignment.dart';
import 'package:flutterware_app/src/comparison/scenario_comparison.dart';
import 'package:flutterware_app/src/comparison/scenarios_runner.dart';
import 'package:flutterware_app/src/comparison/shot_cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The scenario half's orchestration — what is new, what nothing touched, and
/// what order it all ranks in.
///
/// Driven through a fake source, which is the whole reason the seam exists:
/// none of this needs a `flutter_tester` or a harness build to be wrong, and
/// while it lived inside `fw compare` none of it was tested at all.
void main() {
  late Directory root;
  late _FakeSource source;
  late ShotCache cache;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_scenarios_runner');
    source = _FakeSource();
    cache = ShotCache(p.join(root.path, 'shots'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  String checkout(String name, Map<String, String> files) {
    var dir = Directory(p.join(root.path, name))..createSync(recursive: true);
    files.forEach((relative, content) {
      File(p.join(dir.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    });
    return dir.path;
  }

  ScenariosRunner runnerFor({required String base, required String head}) =>
      ScenariosRunner(
        headRoot: head,
        baseRoot: base,
        source: source,
        cache: cache,
      );

  group('the plan', () {
    test('a scenario nothing touched is skipped, and never replayed', () async {
      source.declared = ['test/shop.dart#Checkout'];
      var files = {'test/shop.dart': 'const flow = 1;'};

      var plan = await runnerFor(
        base: checkout('base', files),
        head: checkout('head', files),
      ).plan();

      expect(plan.toRun, isEmpty);
      expect(plan.estimate, '0 of 1');
      expect(plan.settled.single.state, ComparedState.skipped);
      expect(source.replayed, isEmpty);
    });

    test('a touched scenario is the one that has to run', () async {
      source.declared = ['test/shop.dart#Checkout', 'test/cart.dart#Cart'];

      var plan = await runnerFor(
        base: checkout('base', {
          'test/shop.dart': '1',
          'test/cart.dart': 'same',
        }),
        head: checkout('head', {
          'test/shop.dart': '2',
          'test/cart.dart': 'same',
        }),
      ).plan();

      expect(plan.toRun, ['test/shop.dart#Checkout']);
      expect(plan.estimate, '1 of 2');
    });

    test('a scenario one side has is settled without a replay', () async {
      source.onBase = ['test/gone.dart#Gone'];
      source.onHead = ['test/new.dart#Fresh'];

      var plan = await runnerFor(
        base: checkout('base', {'test/gone.dart': '1'}),
        head: checkout('head', {'test/new.dart': '1'}),
      ).plan();

      expect(plan.toRun, isEmpty);
      expect(plan.settled.map((s) => '${s.scenario}:${s.state.name}'), [
        'test/new.dart#Fresh:added',
        'test/gone.dart#Gone:removed',
      ]);
    });

    test('only the named scenarios are looked at', () async {
      source.declared = ['test/shop.dart#Checkout', 'test/cart.dart#Cart'];

      var plan = await ScenariosRunner(
        headRoot: checkout('head', {
          'test/shop.dart': '2',
          'test/cart.dart': '2',
        }),
        baseRoot: checkout('base', {
          'test/shop.dart': '1',
          'test/cart.dart': '1',
        }),
        source: source,
        cache: cache,
        only: const ['test/cart.dart#Cart'],
      ).plan();

      expect(plan.total, 1);
      expect(plan.toRun, ['test/cart.dart#Cart']);
    });
  });

  group('the run', () {
    test('a plan already made is not made again', () async {
      source.declared = ['test/shop.dart#Checkout'];
      var runner = runnerFor(
        base: checkout('base', {'test/shop.dart': '1'}),
        head: checkout('head', {'test/shop.dart': '2'}),
      );

      var plan = await runner.plan();
      source.listed = 0;
      var results = await runner.run(outDir: root.path, from: plan);

      expect(source.listed, 0);
      expect(results.ran, 1);
    });

    // A scenario is a process. Replaying the whole head side and then the
    // whole base side doubles the time before the first row can be answered.
    test('one scenario runs on both sides before the next starts', () async {
      source.declared = ['test/a.dart#A', 'test/b.dart#B'];

      await runnerFor(
        base: checkout('base', {'test/a.dart': '1', 'test/b.dart': '1'}),
        head: checkout('head', {'test/a.dart': '2', 'test/b.dart': '2'}),
      ).run(outDir: root.path);

      expect(source.replayed, [
        'test/a.dart#A:base',
        'test/a.dart#A:head',
        'test/b.dart#B:base',
        'test/b.dart#B:head',
      ]);
    });

    test('rows arrive as they are decided, not all at the end', () async {
      source.declared = ['test/a.dart#A'];
      source.onHead = ['test/a.dart#A', 'test/new.dart#Fresh'];
      var seen = <String>[];

      await ScenariosRunner(
        headRoot: checkout('head', {'test/a.dart': '2'}),
        baseRoot: checkout('base', {'test/a.dart': '1'}),
        source: source,
        cache: cache,
        onScenario: (s) => seen.add(s.scenario),
      ).run(outDir: root.path);

      expect(seen, ['test/new.dart#Fresh', 'test/a.dart#A']);
    });

    test('the results rank worst first and count what ran', () async {
      source.declared = ['test/a.dart#A', 'test/same.dart#Same'];
      source.failOn = 'test/a.dart#A';

      var results = await runnerFor(
        base: checkout('base', {'test/a.dart': '1', 'test/same.dart': 'x'}),
        head: checkout('head', {'test/a.dart': '2', 'test/same.dart': 'x'}),
      ).run(outDir: root.path);

      expect(results.items.first.state, ComparedState.broke);
      expect(results.ran, 1);
      expect(results.skipped, 1);
    });
  });
}

/// Two sides of scenarios with no processes behind them.
class _FakeSource implements ScenarioSource {
  /// What both sides declare, unless one of the two below overrides it.
  List<String> declared = const [];
  List<String>? onBase;
  List<String>? onHead;

  /// The scenario whose head replay throws at its step.
  String? failOn;

  final replayed = <String>[];
  var listed = 0;

  @override
  Future<List<String>> list({required bool base}) async {
    listed++;
    return (base ? onBase : onHead) ?? declared;
  }

  @override
  String fileOf(String id) => id.split('#').first;

  @override
  Future<List<ScenarioStepShot>> shots(
    String id, {
    required bool base,
    required String outDir,
  }) async {
    replayed.add('$id:${base ? 'base' : 'head'}');
    return [
      ScenarioStepShot(
        step: const AlignableStep(index: 1, position: '#1', name: 'Open'),
        rgba: Uint8List(4 * 4 * 4),
        width: 4,
        height: 4,
        failure: !base && id == failOn ? 'nothing matches "Pay"' : null,
      ),
    ];
  }

  @override
  Future<void> dispose() async {}
}
